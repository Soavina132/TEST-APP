-- ============================================================
-- Migration: Fix Ludo — NULL guards + restore _ludo_start_for
-- Date: 2026-08-01
-- Bugs corrigés:
--   1. ludo_check_timeout: guard NULL sur g.status/g.max_players
--   2. ludo_pass: guard NULL sur g.status
--   3. ludo_bot_play: guard NULL sur g.status
--   4. ludo_move: restaurer _ludo_start_for (color-based) au lieu de _ludo_start_idx (slot-based)
--   5. ludo_bot_play: restaurer _ludo_start_for pour le calcul des captures
-- ============================================================

-- 1. ludo_check_timeout — guard NULL complet
CREATE OR REPLACE FUNCTION public.ludo_check_timeout(_game_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $function$
DECLARE
  g public.ludo_games%ROWTYPE; st jsonb; v_slot INT;
  v_started TIMESTAMPTZ; v_uid UUID; v_isbot BOOLEAN;
  v_missed INT; v_winner UUID; v_status TEXT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.id IS NULL OR g.status IS NULL OR g.status <> 'playing' THEN RETURN g.state; END IF;
  st := g.state;
  IF st IS NULL THEN RETURN st; END IF;
  v_started := (st->>'turn_started_at')::TIMESTAMPTZ;
  IF v_started > now() + interval '1 minute' THEN
    v_started := now() - interval '60 seconds';
  END IF;
  IF now() - v_started < interval '30 seconds' THEN RETURN st; END IF;
  v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot, missed_turns INTO v_uid, v_isbot, v_missed
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  v_missed := COALESCE(v_missed,0) + 1;
  UPDATE public.ludo_participants SET missed_turns=v_missed WHERE game_id=_game_id AND slot=v_slot;
  IF v_missed >= 3 AND NOT v_isbot THEN
    UPDATE public.ludo_participants SET forfeited=TRUE WHERE game_id=_game_id AND slot=v_slot;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_uid,'forfeit',0,_game_id,'Forfait (3 timeouts)');
    SELECT status INTO v_status FROM public.ludo_games WHERE id=_game_id;
    IF v_status = 'finished' THEN
      RETURN (SELECT state FROM public.ludo_games WHERE id=_game_id);
    END IF;
    v_winner := public._ludo_check_last_standing(_game_id);
    IF v_winner IS NOT NULL THEN
      PERFORM public.finish_game(_game_id, v_winner);
      RETURN (SELECT state FROM public.ludo_games WHERE id=_game_id);
    END IF;
  END IF;
  st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
  st := jsonb_set(st,'{dice}','null'::jsonb);
  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := jsonb_set(st,'{consecutive_sixes}','0'::jsonb);
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('timeout'::text));
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  RETURN st;
END; $function$;

-- 2. ludo_pass — guard NULL + _ludo_start_for pour vérification
CREATE OR REPLACE FUNCTION public.ludo_pass(_game_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $function$
DECLARE
  g public.ludo_games%ROWTYPE; st jsonb; v_slot INT; v_dice INT;
  v_uid UUID := auth.uid(); v_user UUID; v_isbot BOOLEAN;
  arr jsonb; pawn jsonb; i INT; pstate TEXT; pstep INT; has_move BOOLEAN := FALSE;
  start_idx INT; v_next_slot INT; v_isbot_next BOOLEAN;
  v_now TEXT; v_seq INT; v_consec_six INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.id IS NULL OR g.status IS NULL OR g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := g.state;
  IF st IS NULL THEN RAISE EXCEPTION 'État de partie manquant'; END IF;
  v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot INTO v_user, v_isbot FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF NOT (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Lancez le d''abord'; END IF;
  v_dice := (st->>'dice')::INT;
  start_idx := public._ludo_start_for(_game_id, v_slot);
  arr := st->'pawns'->v_slot::text;
  FOR i IN 0..3 LOOP
    pawn := arr->i; pstate := pawn->>'s'; pstep := (pawn->>'k')::INT;
    IF pstate='finished' THEN CONTINUE; END IF;
    IF pstate='yard' THEN IF v_dice = 6 THEN has_move := TRUE; EXIT; END IF;
    ELSE IF pstep + v_dice <= 56 THEN has_move := TRUE; EXIT; END IF; END IF;
  END LOOP;
  IF has_move THEN RAISE EXCEPTION 'Vous avez un coup possible'; END IF;
  v_now := to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"');
  v_seq := COALESCE((st->>'turn_seq')::int, 0) + 1;
  v_next_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
  v_consec_six := COALESCE((st->>'consecutive_sixes')::INT, 0);
  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := jsonb_set(st,'{dice}','null'::jsonb);
  IF v_dice = 6 THEN st := jsonb_set(st,'{consecutive_sixes}', to_jsonb(v_consec_six + 1));
  ELSE st := jsonb_set(st,'{consecutive_sixes}','0'::jsonb); END IF;
  st := jsonb_set(st,'{turn_slot}', to_jsonb(v_next_slot));
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(v_now));
  st := jsonb_set(st,'{last_event}', to_jsonb('pass'::text));
  st := jsonb_set(st,'{turn_seq}', to_jsonb(v_seq));
  st := jsonb_set(st,'{phase}', to_jsonb('spinning'::text));
  st := jsonb_set(st,'{phase_started_at}', to_jsonb(v_now));
  SELECT is_bot INTO v_isbot_next FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_next_slot;
  st := jsonb_set(st,'{spin_ms}', to_jsonb(CASE WHEN COALESCE(v_isbot_next, FALSE) THEN 2500 ELSE 0 END));
  UPDATE public.ludo_games SET state=st, current_turn=v_next_slot WHERE id=_game_id;
  RETURN st;
END; $function$;

-- 3. ludo_move — guard NULL + _ludo_start_for (color-based) pour captures
CREATE OR REPLACE FUNCTION public.ludo_move(_game_id uuid, _pawn_idx integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $function$
DECLARE
  st jsonb; g public.ludo_games%ROWTYPE; v_uid UUID := auth.uid();
  v_slot INT; v_dice INT; v_user UUID; v_isbot BOOLEAN; v_max INT;
  pawn jsonb; pawn_state TEXT; pawn_step INT; new_step INT; new_state TEXT;
  start_idx INT; abs_cell INT; captured BOOLEAN := FALSE; bonus BOOLEAN := FALSE;
  finished BOOLEAN := FALSE; all_done BOOLEAN; winner_uid UUID;
  rec RECORD; other_pawns jsonb; op jsonb; op_step INT; op_start INT;
  i INT; j INT; arr jsonb; same_slot_count INT;
  v_next_slot INT; v_isbot_next BOOLEAN; v_now TEXT; v_seq INT;
  v_consec_six INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.id IS NULL OR g.status IS NULL OR g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := g.state;
  IF st IS NULL THEN RAISE EXCEPTION 'État de partie manquant'; END IF;
  v_slot := (st->>'turn_slot')::INT; v_max := g.max_players;
  SELECT user_id, is_bot INTO v_user, v_isbot FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF NOT (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Lancez le d''abord'; END IF;
  v_dice := (st->>'dice')::INT;

  -- Compteur de 6 consécutifs
  v_consec_six := COALESCE((st->>'consecutive_sixes')::INT, 0);
  IF v_dice = 6 THEN
    v_consec_six := v_consec_six + 1;
    IF v_consec_six >= 3 THEN
      v_now := to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"');
      v_seq := COALESCE((st->>'turn_seq')::int, 0) + 1;
      v_next_slot := public._ludo_next_slot(_game_id, v_slot, v_max);
      st := jsonb_set(st,'{must_move}','false'::jsonb);
      st := jsonb_set(st,'{dice}','null'::jsonb);
      st := jsonb_set(st,'{consecutive_sixes}','0'::jsonb);
      st := jsonb_set(st,'{turn_slot}', to_jsonb(v_next_slot));
      st := jsonb_set(st,'{last_event}', to_jsonb('three_sixes:skip'::text));
      st := jsonb_set(st,'{turn_started_at}', to_jsonb(v_now));
      st := jsonb_set(st,'{turn_seq}', to_jsonb(v_seq));
      st := jsonb_set(st,'{phase}', to_jsonb('spinning'::text));
      st := jsonb_set(st,'{phase_started_at}', to_jsonb(v_now));
      SELECT is_bot INTO v_isbot_next FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_next_slot;
      st := jsonb_set(st,'{spin_ms}', to_jsonb(CASE WHEN COALESCE(v_isbot_next, FALSE) THEN 2500 ELSE 0 END));
      UPDATE public.ludo_games SET state=st, current_turn=v_next_slot WHERE id=_game_id;
      RETURN st;
    END IF;
  ELSE
    v_consec_six := 0;
  END IF;
  st := jsonb_set(st,'{consecutive_sixes}', to_jsonb(v_consec_six));

  pawn := st->'pawns'->v_slot::text->_pawn_idx;
  IF pawn IS NULL THEN RAISE EXCEPTION 'Pion inconnu'; END IF;
  pawn_state := pawn->>'s'; pawn_step := (pawn->>'k')::INT;
  IF pawn_state = 'finished' THEN RAISE EXCEPTION 'Pion deja arrive'; END IF;
  IF pawn_state = 'yard' THEN
    IF v_dice <> 6 THEN RAISE EXCEPTION 'Sortie possible avec un 6'; END IF;
    new_state := 'track'; new_step := 0;
  ELSE
    new_step := pawn_step + v_dice;
    IF new_step > 56 THEN RAISE EXCEPTION 'Depassement'; END IF;
    IF new_step = 56 THEN new_state := 'finished'; finished := TRUE;
    ELSE new_state := 'track'; END IF;
  END IF;

  arr := st->'pawns'->v_slot::text;
  arr := jsonb_set(arr, ARRAY[_pawn_idx::text], jsonb_build_object('s', new_state, 'k', new_step));
  st := jsonb_set(st, ARRAY['pawns', v_slot::text], arr);

  -- CAPTURE: utiliser _ludo_start_for (basé sur la couleur réelle du participant)
  IF new_state = 'track' AND new_step <= 50 THEN
    start_idx := public._ludo_start_for(_game_id, v_slot);
    abs_cell := (start_idx + new_step) % 52;
    IF NOT public._ludo_is_safe(abs_cell) THEN
      FOR rec IN SELECT slot FROM public.ludo_participants WHERE game_id=_game_id AND slot <> v_slot LOOP
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
        -- Capturer seulement si 1 pion adverse sur la case (pas un mur de 2+)
        IF same_slot_count = 1 THEN
          FOR j IN 0..3 LOOP
            op := other_pawns->j;
            IF op->>'s' = 'track' THEN
              op_step := (op->>'k')::INT;
              IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
                other_pawns := jsonb_set(other_pawns, ARRAY[j::text], jsonb_build_object('s','yard','k',-1));
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
    PERFORM public.finish_game(_game_id, winner_uid);
    RETURN st;
  END IF;

  bonus := (v_dice = 6) OR captured OR finished;
  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := jsonb_set(st,'{dice}','null'::jsonb);
  v_now := to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"');
  v_seq := COALESCE((st->>'turn_seq')::int, 0) + 1;
  IF bonus THEN
    st := jsonb_set(st,'{last_event}', to_jsonb(
      CASE WHEN captured THEN 'capture'::text WHEN finished THEN 'home'::text ELSE 'six'::text END || ':rejoue'));
    st := jsonb_set(st,'{phase}', to_jsonb('spinning'::text));
    st := jsonb_set(st,'{spin_ms}', to_jsonb(CASE WHEN v_isbot THEN 2500 ELSE 0 END));
  ELSE
    v_next_slot := public._ludo_next_slot(_game_id, v_slot, v_max);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(v_next_slot));
    st := jsonb_set(st,'{last_event}', to_jsonb('move'::text));
    st := jsonb_set(st,'{phase}', to_jsonb('spinning'::text));
    SELECT is_bot INTO v_isbot_next FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_next_slot;
    st := jsonb_set(st,'{spin_ms}', to_jsonb(CASE WHEN COALESCE(v_isbot_next, FALSE) THEN 2500 ELSE 0 END));
  END IF;
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(v_now));
  st := jsonb_set(st,'{turn_seq}', to_jsonb(v_seq));
  st := jsonb_set(st,'{phase_started_at}', to_jsonb(v_now));
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  RETURN st;
END; $function$;

-- 4. ludo_bot_play — guard NULL + _ludo_start_for pour le calcul des scores de capture
CREATE OR REPLACE FUNCTION public.ludo_bot_play(_game_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $function$
DECLARE
  g public.ludo_games%ROWTYPE; st jsonb; v_slot INT; v_isbot BOOLEAN;
  v_intel INT; v_bias INT; v_dice INT; arr jsonb; pawn jsonb;
  i INT; k INT; best INT := -1; best_score INT := -1; sc INT;
  pstate TEXT; pstep INT; abs_cell INT; start_idx INT;
  rec RECORD; op jsonb; op_step INT; op_start INT;
  would_capture BOOLEAN; would_be_captured BOOLEAN;
  candidates INT[] := ARRAY[]::INT[]; scores INT[] := ARRAY[]::INT[];
  v_rand FLOAT; v_mistake FLOAT; v_idx INT; v_count INT;
  v_yard_count INT := 0; v_finished INT := 0; v_on_track INT := 0;
  v_phase TEXT; v_near_danger BOOLEAN; v_dist_to_enemy INT;
  v_next_slot INT; v_isbot_next BOOLEAN; v_now TEXT; v_seq INT; v_consec_six INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.id IS NULL OR g.status IS NULL OR g.status <> 'playing' THEN RETURN g.state; END IF;
  st := public._ludo_ensure_state(_game_id);
  IF st IS NULL THEN RETURN st; END IF;
  v_slot := (st->>'turn_slot')::INT;
  SELECT is_bot, bot_intelligence, bot_win_bias INTO v_isbot, v_intel, v_bias FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot THEN RETURN st; END IF;

  IF NOT (st->>'must_move')::BOOLEAN THEN
    v_dice := 1 + (floor(random()*6))::INT;
    IF COALESCE(v_bias,0) > 0 AND (random()*100) < v_bias AND v_dice < 4 THEN v_dice := 3 + (floor(random()*4))::INT; END IF;
    v_now := to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"');
    st := jsonb_set(st,'{dice}', to_jsonb(v_dice));
    st := jsonb_set(st,'{must_move}','true'::jsonb);
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(v_now));
    st := jsonb_set(st,'{last_event}', to_jsonb('bot_roll:'||v_dice));
    st := jsonb_set(st,'{phase}', to_jsonb('rolling'::text));
    st := jsonb_set(st,'{phase_started_at}', to_jsonb(v_now));
    UPDATE public.ludo_games SET state=st WHERE id=_game_id;
  ELSE v_dice := (st->>'dice')::INT; END IF;

  v_consec_six := COALESCE((st->>'consecutive_sixes')::INT, 0);
  IF v_dice = 6 AND v_consec_six >= 2 THEN
    v_now := to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"');
    v_seq := COALESCE((st->>'turn_seq')::int, 0) + 1;
    v_next_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := jsonb_set(st,'{consecutive_sixes}','0'::jsonb);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(v_next_slot));
    st := jsonb_set(st,'{last_event}', to_jsonb('three_sixes:skip'::text));
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(v_now));
    st := jsonb_set(st,'{turn_seq}', to_jsonb(v_seq));
    st := jsonb_set(st,'{phase}', to_jsonb('spinning'::text));
    st := jsonb_set(st,'{phase_started_at}', to_jsonb(v_now));
    SELECT is_bot INTO v_isbot_next FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_next_slot;
    st := jsonb_set(st,'{spin_ms}', to_jsonb(CASE WHEN COALESCE(v_isbot_next, FALSE) THEN 2500 ELSE 0 END));
    UPDATE public.ludo_games SET state=st, current_turn=v_next_slot WHERE id=_game_id;
    RETURN st;
  END IF;

  arr := st->'pawns'->v_slot::text;
  start_idx := public._ludo_start_for(_game_id, v_slot);
  FOR i IN 0..3 LOOP
    pawn := arr->i; pstate := pawn->>'s';
    IF pstate = 'yard' THEN v_yard_count := v_yard_count + 1;
    ELSIF pstate = 'finished' THEN v_finished := v_finished + 1;
    ELSIF pstate = 'track' THEN v_on_track := v_on_track + 1; END IF;
  END LOOP;
  IF v_yard_count >= 3 THEN v_phase := 'early';
  ELSIF v_finished >= 2 THEN v_phase := 'late';
  ELSE v_phase := 'mid'; END IF;

  FOR i IN 0..3 LOOP
    pawn := arr->i; pstate := pawn->>'s'; pstep := (pawn->>'k')::INT;
    IF pstate='finished' THEN CONTINUE; END IF;
    IF pstate='yard' THEN IF v_dice = 6 THEN candidates := candidates || i; END IF;
    ELSE IF pstep + v_dice <= 56 THEN candidates := candidates || i; END IF; END IF;
  END LOOP;

  IF array_length(candidates,1) IS NULL THEN
    v_now := to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"');
    v_seq := COALESCE((st->>'turn_seq')::int, 0) + 1;
    v_next_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{dice}','null'::jsonb);
    IF v_dice = 6 THEN st := jsonb_set(st,'{consecutive_sixes}', to_jsonb(v_consec_six + 1));
    ELSE st := jsonb_set(st,'{consecutive_sixes}','0'::jsonb); END IF;
    st := jsonb_set(st,'{turn_slot}', to_jsonb(v_next_slot));
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(v_now));
    st := jsonb_set(st,'{last_event}', to_jsonb('bot:pass'::text));
    st := jsonb_set(st,'{turn_seq}', to_jsonb(v_seq));
    st := jsonb_set(st,'{phase}', to_jsonb('spinning'::text));
    st := jsonb_set(st,'{phase_started_at}', to_jsonb(v_now));
    SELECT is_bot INTO v_isbot_next FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_next_slot;
    st := jsonb_set(st,'{spin_ms}', to_jsonb(CASE WHEN COALESCE(v_isbot_next, FALSE) THEN 2500 ELSE 0 END));
    UPDATE public.ludo_games SET state=st, current_turn=v_next_slot WHERE id=_game_id;
    RETURN st;
  END IF;

  v_rand := random() * 100;
  IF v_rand < COALESCE(v_intel, 70) THEN
    FOREACH i IN ARRAY candidates LOOP
      pawn := arr->i; pstate := pawn->>'s'; pstep := (pawn->>'k')::INT; sc := 0;
      IF pstate = 'yard' THEN
        IF v_phase = 'early' THEN sc := 70; ELSIF v_phase = 'mid' THEN sc := 55; ELSE sc := 40; END IF;
        IF v_yard_count = 1 THEN sc := sc + 15; END IF;
      ELSIF pstep + v_dice = 56 THEN sc := 90;
      ELSE
        sc := pstep + v_dice;
        would_capture := FALSE;
        IF pstep + v_dice <= 50 THEN
          abs_cell := (start_idx + pstep + v_dice) % 52;
          IF NOT public._ludo_is_safe(abs_cell) THEN
            FOR rec IN SELECT slot FROM public.ludo_participants WHERE game_id=_game_id AND slot <> v_slot LOOP
              op_start := public._ludo_start_for(_game_id, rec.slot);
              FOR k IN 0..3 LOOP
                op := st->'pawns'->rec.slot::text->k;
                IF op->>'s' = 'track' THEN
                  op_step := (op->>'k')::INT;
                  IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN would_capture := TRUE; END IF;
                END IF;
              END LOOP;
            END LOOP;
          END IF;
        END IF;
        IF would_capture THEN sc := sc + 120; END IF;
        sc := sc + (pstep * 2);
        IF v_phase = 'late' THEN sc := sc + (pstep * 3); END IF;
        would_be_captured := FALSE;
        IF pstep + v_dice <= 50 THEN
          abs_cell := (start_idx + pstep + v_dice) % 52;
          IF NOT public._ludo_is_safe(abs_cell) THEN
            FOR rec IN SELECT slot FROM public.ludo_participants WHERE game_id=_game_id AND slot <> v_slot LOOP
              op_start := public._ludo_start_for(_game_id, rec.slot);
              FOR k IN 0..3 LOOP
                op := st->'pawns'->rec.slot::text->k;
                IF op->>'s' = 'track' THEN
                  op_step := (op->>'k')::INT;
                  v_dist_to_enemy := ((start_idx + pstep + v_dice) - (op_start + op_step) + 52) % 52;
                  IF v_dist_to_enemy >= 1 AND v_dist_to_enemy <= 6 THEN would_be_captured := TRUE; END IF;
                END IF;
              END LOOP;
            END LOOP;
          END IF;
        END IF;
        IF would_be_captured THEN sc := sc - 40; END IF;
        IF pstep + v_dice <= 50 THEN
          abs_cell := (start_idx + pstep + v_dice) % 52;
          IF public._ludo_is_safe(abs_cell) THEN sc := sc + 15; END IF;
        END IF;
      END IF;
      scores := scores || sc;
      IF sc > best_score THEN best_score := sc; best := i; END IF;
    END LOOP;
    v_mistake := random() * 100;
    IF v_mistake > COALESCE(v_intel, 70) AND array_length(candidates,1) >= 2 THEN
      v_count := array_length(candidates,1);
      IF v_count = 2 THEN best := candidates[CASE WHEN candidates[1] = best THEN 2 ELSE 1 END];
      ELSE v_idx := 1 + (floor(random() * (v_count - 1)))::INT; best := candidates[v_idx]; END IF;
    END IF;
  ELSE best := candidates[1 + (floor(random()*array_length(candidates,1)))::INT]; END IF;

  PERFORM public.ludo_move(_game_id, best);
  SELECT status, state INTO g.status, st FROM public.ludo_games WHERE id=_game_id;
  RETURN st;
END; $function$;
