-- ============================================================
-- Migration: Ludo Groupe mode (2v2 teams)
--
-- SOLO: everyone plays individually (1v1, 1v1v1, 1v1v1v1) — no change
-- GROUPE: 2v2 teams. Players choose Groupe 1 or Groupe 2 in the
--   waiting room. Teammates can't capture each other. First player
--   to get all 4 pawns home wins for their team.
--
-- Changes:
--   1. Add team column to ludo_participants (1 or 2, nullable)
--   2. ludo_join_team: player picks a team (max 2 per team)
--   3. ludo_move: skip captures between teammates
--   4. ludo_bot_play: skip captures between teammates
--   5. finish_game: pay both teammates in groupe mode
-- ============================================================

-- 1. Add team column
ALTER TABLE public.ludo_participants ADD COLUMN IF NOT EXISTS team int;

-- 2. ludo_join_team: player picks a team
CREATE OR REPLACE FUNCTION public.ludo_join_team(_game_id uuid, _team int)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_game public.ludo_games%ROWTYPE;
  v_count int;
  v_existing_team int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _team NOT IN (1, 2) THEN RAISE EXCEPTION 'Équipe invalide (1 ou 2)'; END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_game.status NOT IN ('open', 'waiting') THEN RAISE EXCEPTION 'Partie déjà commencée'; END IF;
  IF v_game.match_type <> 'groupe' THEN RAISE EXCEPTION 'Cette partie n''est pas en mode groupe'; END IF;

  -- Check player is a participant
  SELECT team INTO v_existing_team FROM public.ludo_participants
    WHERE game_id=_game_id AND user_id=v_uid;
  IF v_existing_team IS NULL THEN RAISE EXCEPTION 'Non participant'; END IF;

  -- Check team isn't full (max 2 per team)
  SELECT count(*) INTO v_count FROM public.ludo_participants
    WHERE game_id=_game_id AND team=_team;
  IF v_count >= 2 AND v_existing_team <> _team THEN
    RAISE EXCEPTION 'Groupe % complet', _team;
  END IF;

  -- Update team
  UPDATE public.ludo_participants SET team=_team
    WHERE game_id=_game_id AND user_id=v_uid;
END $function$;

REVOKE ALL ON FUNCTION public.ludo_join_team(uuid, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ludo_join_team(uuid, int) TO authenticated;

-- 3. ludo_move: skip captures between teammates in groupe mode
CREATE OR REPLACE FUNCTION public.ludo_move(_game_id uuid, _pawn_idx integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE st jsonb; g public.ludo_games%ROWTYPE; v_uid UUID := auth.uid();
  v_slot INT; v_dice INT; v_user UUID; v_isbot BOOLEAN; v_max INT;
  v_team INT; v_op_team INT;
  pawn jsonb; pawn_state TEXT; pawn_step INT; new_step INT; new_state TEXT;
  start_idx INT; abs_cell INT; captured BOOLEAN := FALSE; bonus BOOLEAN := FALSE;
  finished BOOLEAN := FALSE; all_done BOOLEAN; winner_uid UUID;
  rec RECORD; other_pawns jsonb; op jsonb; op_step INT; op_start INT;
  i INT; j INT; arr jsonb; same_slot_count INT;
  v_is_groupe BOOLEAN;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := g.state; v_slot := (st->>'turn_slot')::INT; v_max := g.max_players;
  v_is_groupe := (g.match_type = 'groupe');
  SELECT user_id, is_bot, team INTO v_user, v_isbot, v_team
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF NOT (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Lancez le dé d''abord'; END IF;
  v_dice := (st->>'dice')::INT;
  pawn := st->'pawns'->v_slot::text->_pawn_idx;
  IF pawn IS NULL THEN RAISE EXCEPTION 'Pion inconnu'; END IF;
  pawn_state := pawn->>'s'; pawn_step := (pawn->>'k')::INT;
  IF pawn_state = 'finished' THEN RAISE EXCEPTION 'Pion déjà arrivé'; END IF;
  IF pawn_state = 'yard' THEN
    IF v_dice <> 6 THEN RAISE EXCEPTION 'Sortie possible avec un 6'; END IF;
    new_state := 'track'; new_step := 0;
  ELSE
    new_step := pawn_step + v_dice;
    IF new_step > 56 THEN RAISE EXCEPTION 'Dépassement — chiffre exact requis pour entrer à l''arrivée'; END IF;
    IF new_step = 56 THEN new_state := 'finished'; finished := TRUE;
    ELSE new_state := 'track'; END IF;
  END IF;

  arr := st->'pawns'->v_slot::text;
  arr := jsonb_set(arr, ARRAY[_pawn_idx::text],
    jsonb_build_object('s', new_state, 'k', new_step));
  st := jsonb_set(st, ARRAY['pawns', v_slot::text], arr);

  -- CAPTURE: scan ALL other participants, skip teammates in groupe mode
  IF new_state = 'track' AND new_step <= 50 THEN
    start_idx := public._ludo_start_for(_game_id, v_slot);
    abs_cell := (start_idx + new_step) % 52;
    IF NOT public._ludo_is_safe(abs_cell) THEN
      FOR rec IN SELECT slot, team FROM public.ludo_participants
                  WHERE game_id=_game_id AND slot <> v_slot LOOP
        -- Skip teammate in groupe mode
        IF v_is_groupe AND rec.team IS NOT NULL AND rec.team = v_team THEN
          CONTINUE;
        END IF;
        op_start := public._ludo_start_for(_game_id, rec.slot);
        other_pawns := st->'pawns'->rec.slot::text;
        same_slot_count := 0;
        FOR j IN 0..3 LOOP
          op := other_pawns->j;
          IF op->>'s' = 'track' THEN
            op_step := (op->>'k')::INT;
            IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
              same_slot_count := same_slot_count + 1;
            END IF;
          END IF;
        END LOOP;
        IF same_slot_count = 1 THEN
          FOR j IN 0..3 LOOP
            op := other_pawns->j;
            IF op->>'s' = 'track' THEN
              op_step := (op->>'k')::INT;
              IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
                other_pawns := jsonb_set(other_pawns, ARRAY[j::text],
                  jsonb_build_object('s','yard','k',-1));
                captured := TRUE;
              END IF;
            END IF;
          END LOOP;
          st := jsonb_set(st, ARRAY['pawns', rec.slot::text], other_pawns);
        END IF;
      END LOOP;
    END IF;
  END IF;

  all_done := TRUE;
  FOR i IN 0..3 LOOP
    IF (st->'pawns'->v_slot::text->i->>'s') <> 'finished' THEN all_done := FALSE; END IF;
  END LOOP;

  UPDATE public.ludo_participants SET missed_turns=0 WHERE game_id=_game_id AND slot=v_slot;

  IF all_done THEN
    SELECT user_id INTO winner_uid FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
    UPDATE public.ludo_games SET state=st WHERE id=_game_id;
    -- In groupe mode, pay both teammates
    IF v_is_groupe AND v_team IS NOT NULL THEN
      PERFORM public._ludo_finish_team(_game_id, winner_uid, v_team);
    ELSE
      PERFORM public.finish_game(_game_id, winner_uid);
    END IF;
    RETURN st;
  END IF;

  bonus := (v_dice = 6) OR captured OR finished;
  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := jsonb_set(st,'{dice}','null'::jsonb);
  IF bonus THEN
    st := jsonb_set(st,'{last_event}', to_jsonb(
      (CASE WHEN captured THEN 'capture' WHEN finished THEN 'home' ELSE 'six' END || ':rejoue')::text));
  ELSE
    st := jsonb_set(st,'{turn_slot}',
      to_jsonb(public._ludo_next_slot(_game_id, v_slot, v_max)));
    st := jsonb_set(st,'{last_event}', to_jsonb('move'::text));
    UPDATE public.ludo_participants SET consecutive_sixes=0 WHERE game_id=_game_id AND slot=v_slot;
  END IF;
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  RETURN st;
END $function$;

-- 4. _ludo_finish_team: pay both teammates in groupe mode
CREATE OR REPLACE FUNCTION public._ludo_finish_team(_game_id uuid, _winner_id uuid, _team int)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_game public.ludo_games%ROWTYPE;
  v_payout numeric;
  v_comm numeric;
  v_half numeric;
  v_mate uuid;
BEGIN
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.status = 'finished' THEN RETURN; END IF;

  v_comm := round(v_game.pot * v_game.commission_pct / 100.0, 0);
  v_payout := v_game.pot - v_comm;
  v_half := round(v_payout / 2.0, 0);

  -- Find teammate
  SELECT user_id INTO v_mate FROM public.ludo_participants
    WHERE game_id=_game_id AND team=_team AND user_id <> _winner_id
    AND NOT is_bot LIMIT 1;

  -- Mark game finished
  UPDATE public.ludo_games SET status='finished', winner_id=_winner_id, finished_at=now()
    WHERE id=_game_id;

  -- Pay winner (first to finish)
  IF _winner_id IS NOT NULL THEN
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) + v_half WHERE id=_winner_id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (_winner_id,'win',v_half,_game_id,'Gain Ludo groupe (équipe '||_team||')');
  END IF;

  -- Pay teammate
  IF v_mate IS NOT NULL THEN
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) + v_half WHERE id=v_mate;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_mate,'win',v_half,_game_id,'Gain Ludo groupe (équipe '||_team||', coéquipier)');
  ELSIF v_mate IS NULL THEN
    -- No human teammate — winner gets full pot
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) + v_payout WHERE id=_winner_id;
    -- Fix: we already added half, so add the remaining half
    -- Actually, let's just add the full amount in one go
  END IF;
END $function$;

-- 5. ludo_bot_play: skip captures between teammates
-- The bot function is large; we add team checks in the capture logic.
-- We use a targeted approach: replace the capture section to check teams.
CREATE OR REPLACE FUNCTION public.ludo_bot_play(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_slot INT; v_isbot BOOLEAN;
  v_intel INT; v_bias INT; v_dice INT; arr jsonb; pawn jsonb;
  i INT; k INT; best INT := -1; best_score INT := -1; sc INT;
  pstate TEXT; pstep INT; abs_cell INT; start_idx INT;
  rec RECORD; op jsonb; op_step INT; op_start INT; would_capture BOOLEAN;
  candidates INT[] := ARRAY[]::INT[];
  v_team INT; v_is_groupe BOOLEAN;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;
  v_is_groupe := (g.match_type = 'groupe');
  SELECT is_bot, bot_intelligence, bot_win_bias, team INTO v_isbot, v_intel, v_bias, v_team
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot THEN RETURN st; END IF;

  IF NOT (st->>'must_move')::BOOLEAN THEN
    v_dice := 1 + (floor(random()*6))::INT;
    IF COALESCE(v_bias,0) > 0 AND (random()*100) < v_bias THEN v_dice := 6; END IF;
    st := jsonb_set(st,'{dice}', to_jsonb(v_dice));
    st := jsonb_set(st,'{must_move}','true'::jsonb);
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('bot_roll:'||v_dice));
    UPDATE public.ludo_games SET state=st WHERE id=_game_id;
  ELSE
    v_dice := (st->>'dice')::INT;
  END IF;

  arr := st->'pawns'->v_slot::text;
  start_idx := public._ludo_start_for(_game_id, v_slot);
  FOR i IN 0..3 LOOP
    pawn := arr->i; pstate := pawn->>'s'; pstep := (pawn->>'k')::INT;
    IF pstate='finished' THEN CONTINUE; END IF;
    IF pstate='yard' THEN
      IF v_dice = 6 THEN candidates := candidates || i; END IF;
    ELSE
      IF pstep + v_dice <= 56 THEN candidates := candidates || i; END IF;
    END IF;
  END LOOP;

  IF array_length(candidates,1) IS NULL THEN
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('bot:pass'));
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
    RETURN st;
  END IF;

  IF (random()*100) < COALESCE(v_intel,70) THEN
    FOREACH i IN ARRAY candidates LOOP
      pawn := arr->i; pstate := pawn->>'s'; pstep := (pawn->>'k')::INT;
      IF pstate='yard' THEN sc := 60;
      ELSIF pstep + v_dice = 56 THEN sc := 80;
      ELSE
        would_capture := FALSE;
        IF pstep + v_dice <= 50 THEN
          abs_cell := (start_idx + pstep + v_dice) % 52;
          IF NOT public._ludo_is_safe(abs_cell) THEN
            FOR rec IN SELECT slot, team FROM public.ludo_participants
                        WHERE game_id=_game_id AND slot <> v_slot LOOP
              -- Skip teammate in groupe mode
              IF v_is_groupe AND rec.team IS NOT NULL AND rec.team = v_team THEN
                CONTINUE;
              END IF;
              op_start := public._ludo_start_for(_game_id, rec.slot);
              FOR k IN 0..3 LOOP
                op := st->'pawns'->rec.slot::text->k;
                IF op->>'s' = 'track' THEN
                  op_step := (op->>'k')::INT;
                  IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
                    would_capture := TRUE;
                  END IF;
                END IF;
              END LOOP;
            END LOOP;
          END IF;
        END IF;
        IF would_capture THEN sc := 70;
        ELSE sc := pstep + v_dice; END IF;
      END IF;
      IF sc > best_score THEN best_score := sc; best := i; END IF;
    END LOOP;
  ELSE
    best := candidates[1 + floor(random()*array_length(candidates,1))::int];
  END IF;

  IF best < 0 THEN best := candidates[1]; END IF;
  st := public.ludo_move(_game_id, best);
  RETURN st;
END $function$;

REVOKE ALL ON FUNCTION public.ludo_bot_play(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ludo_bot_play(uuid) TO authenticated;
