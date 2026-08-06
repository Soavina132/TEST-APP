-- ============================================================================
-- Fix Ludo: 4 logic bugs
--   1. CRITICAL: _ludo_finish_team double-pays winner (150% instead of 100%)
--   2. MAJOR:   Forfeited players' pawns stay on board (create permanent blocks)
--   3. VISUAL:  no_move_display timestamp truncated to seconds (display never shows)
--   4. MINOR:   No AFK warning for T2 (player forfeited without notice)
-- ============================================================================

-- ── Bug 1: Fix _ludo_finish_team payout logic ─────────────────────────────
CREATE OR REPLACE FUNCTION public._ludo_finish_team(_game_id uuid, _winner_id uuid, _team int)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_game public.ludo_games%ROWTYPE;
  v_payout numeric;
  v_comm numeric;
  v_half numeric;
  v_mate uuid;
  v_referrer uuid;
  v_ref_pct numeric;
  v_ref_amount numeric;
BEGIN
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.status = 'finished' THEN RETURN; END IF;

  v_comm := round(v_game.pot * v_game.commission_pct / 100.0, 0);
  v_payout := v_game.pot - v_comm;
  v_half := round(v_payout / 2.0, 0);

  SELECT user_id INTO v_mate FROM public.ludo_participants
    WHERE game_id=_game_id AND team=_team AND user_id <> _winner_id
    AND NOT is_bot LIMIT 1;

  UPDATE public.ludo_games SET status='finished', winner_id=_winner_id, finished_at=now()
    WHERE id=_game_id;

  IF v_mate IS NOT NULL THEN
    -- Two human teammates: each gets half
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) + v_half WHERE id=_winner_id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (_winner_id,'win',v_half,_game_id,'Gain Ludo groupe (équipe '||_team||')');
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) + v_half WHERE id=v_mate;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_mate,'win',v_half,_game_id,'Gain Ludo groupe (équipe '||_team||', coéquipier)');
  ELSE
    -- No human teammate: winner gets full pot (single payment, NOT 1.5x)
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) + v_payout WHERE id=_winner_id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (_winner_id,'win',v_payout,_game_id,'Gain Ludo groupe (équipe '||_team||', solo)');
    -- Referral bonus
    SELECT referred_by INTO v_referrer FROM public.profiles WHERE id=_winner_id;
    IF v_referrer IS NOT NULL THEN
      SELECT referral_pct INTO v_ref_pct FROM public.app_settings WHERE id=1;
      v_ref_amount := v_payout * COALESCE(v_ref_pct,0) / 100.0;
      IF v_ref_amount > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + v_ref_amount WHERE id=v_referrer;
        INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
          VALUES (v_referrer,'referral',v_ref_amount,_game_id,'Bonus parrainage');
      END IF;
    END IF;
  END IF;
END $function$;

-- ── Bug 2: Remove forfeited players' pawns from the board ──────────────────
CREATE OR REPLACE FUNCTION public.ludo_quit(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); g public.ludo_games%ROWTYPE; st jsonb;
  v_slot INT; v_winner UUID; v_remaining INT;
  v_pawns jsonb; i INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status NOT IN ('playing','open') THEN RAISE EXCEPTION 'Partie terminée'; END IF;
  SELECT slot INTO v_slot FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid AND is_bot=false;
  IF v_slot IS NULL THEN RAISE EXCEPTION 'Non participant'; END IF;

  IF g.status = 'open' THEN
    UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id=v_uid;
    UPDATE public.ludo_games SET pot = pot - g.stake WHERE id=_game_id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_uid,'refund',g.stake,_game_id,'Annulation avant départ');
    DELETE FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid AND is_bot=false;
    SELECT count(*) INTO v_remaining FROM public.ludo_participants WHERE game_id=_game_id AND is_bot=false;
    IF v_remaining = 0 THEN PERFORM public._ludo_purge(_game_id); END IF;
    RETURN;
  END IF;

  -- Send all forfeited player's pawns back to the yard
  st := g.state;
  IF st ? 'pawns' AND (st->'pawns') ? v_slot::text THEN
    v_pawns := '[]'::jsonb;
    FOR i IN 1..4 LOOP
      v_pawns := v_pawns || jsonb_build_object('s','yard','k',-1);
    END LOOP;
    st := jsonb_set(st, ARRAY['pawns', v_slot::text], v_pawns);
  END IF;

  -- Solo game: mark forfeited, finish immediately
  IF g.is_solo OR g.match_type = 'solo' THEN
    UPDATE public.ludo_participants SET forfeited=TRUE WHERE game_id=_game_id AND user_id=v_uid AND is_bot=false;
    UPDATE public.ludo_games SET status='finished', finished_at=now(), state=st WHERE id=_game_id;
    PERFORM public._ludo_purge(_game_id);
    RETURN;
  END IF;

  -- Multiplayer: forfeit and check if game should end
  UPDATE public.ludo_participants SET forfeited=TRUE WHERE game_id=_game_id AND user_id=v_uid AND is_bot=false;
  IF (st->>'turn_slot')::INT = v_slot THEN
    st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('forfeit'));
  END IF;
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  v_winner := public._ludo_check_last_standing(_game_id);
  IF v_winner IS NOT NULL THEN
    PERFORM public.finish_game(_game_id, v_winner);
  ELSIF public._ludo_active_humans(_game_id) = 0 THEN
    UPDATE public.ludo_games SET status='finished', finished_at=now() WHERE id=_game_id;
    PERFORM public._ludo_purge(_game_id);
  END IF;
END $function$;

-- ── Bug 2b: Also remove pawns when AFK auto-forfeited + T2 warning ─────────
CREATE OR REPLACE FUNCTION public._ludo_check_afk(_game_id uuid, _slot integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_t1      int;
  v_t2      int;
  v_max1    int;
  v_max2    int;
  v_enabled boolean;
  v_uid     uuid;
  v_isbot   boolean;
  v_name    text;
  v_winner  uuid;
  v_is_solo boolean;
  v_humans  int;
  g        public.ludo_games%ROWTYPE;
  st       jsonb;
  v_pawns  jsonb;
  i        int;
BEGIN
  SELECT afk_enabled, afk_t1_max, afk_t2_max
    INTO v_enabled, v_max1, v_max2
    FROM public.app_settings WHERE id = 1;
  IF NOT COALESCE(v_enabled, TRUE) THEN RETURN; END IF;

  SELECT afk_t1, afk_t2, user_id, is_bot, display_name
    INTO v_t1, v_t2, v_uid, v_isbot, v_name
    FROM public.ludo_participants
   WHERE game_id = _game_id AND slot = _slot;
  IF v_isbot THEN RETURN; END IF;

  -- ── Seuil forfait : T1 >= max OU T2 >= max ──
  IF v_t1 >= COALESCE(v_max1, 5) OR v_t2 >= COALESCE(v_max2, 2) THEN
    UPDATE public.ludo_participants
       SET forfeited = TRUE
     WHERE game_id = _game_id AND slot = _slot;

    -- Send all forfeited player's pawns back to the yard
    SELECT * INTO g FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
    st := g.state;
    IF st ? 'pawns' AND (st->'pawns') ? _slot::text THEN
      v_pawns := '[]'::jsonb;
      FOR i IN 1..4 LOOP
        v_pawns := v_pawns || jsonb_build_object('s','yard','k',-1);
      END LOOP;
      st := jsonb_set(st, ARRAY['pawns', _slot::text], v_pawns);
      UPDATE public.ludo_games SET state = st WHERE id = _game_id;
    END IF;

    UPDATE public.ludo_games
       SET afk_warning   = NULL,
           afk_pause_for  = NULL,
           afk_pause_name = NULL
     WHERE id = _game_id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'forfeit', 0, _game_id,
              'Exclusion AFK (T1=' || v_t1 || ' T2=' || v_t2 || ')');

    SELECT is_solo, match_type INTO v_is_solo FROM public.ludo_games WHERE id = _game_id;
    v_is_solo := COALESCE(v_is_solo, FALSE) OR COALESCE((SELECT match_type FROM public.ludo_games WHERE id = _game_id), 'groupe') = 'solo';

    IF v_is_solo THEN
      v_humans := public._ludo_active_humans(_game_id);
      IF v_humans = 0 THEN
        UPDATE public.ludo_games SET status = 'finished', finished_at = now() WHERE id = _game_id;
        PERFORM public._ludo_purge(_game_id);
        RETURN;
      END IF;
    END IF;

    v_winner := public._ludo_check_last_standing(_game_id);
    IF v_winner IS NOT NULL THEN
      PERFORM public.finish_game(_game_id, v_winner);
    END IF;
    RETURN;
  END IF;

  -- ── Seuil avertissement : T1 = max-1 OU T2 = max-1 ──
  IF v_t1 = COALESCE(v_max1, 5) - 1 OR v_t2 = COALESCE(v_max2, 2) - 1 THEN
    UPDATE public.ludo_games
       SET afk_warning = jsonb_build_object(
             'uid',    v_uid,
             'name',   COALESCE(v_name, 'Joueur'),
             'slot',   _slot,
             't1',     v_t1,
             't1_max', COALESCE(v_max1, 5),
             't2',     v_t2,
             't2_max', COALESCE(v_max2, 2),
             'ts',     extract(epoch from now())::bigint
           )
     WHERE id = _game_id
       AND paused = FALSE
       AND (afk_warning IS NULL
            OR (afk_warning->>'uid')::uuid <> v_uid);
  END IF;
END $$;

-- ── Bug 3: Fix timestamps to use milliseconds + no_move_display ────────────
CREATE OR REPLACE FUNCTION public.ludo_roll(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE st jsonb; g public.ludo_games%ROWTYPE; v_uid UUID := auth.uid();
  v_slot INT; v_user UUID; v_isbot BOOLEAN; v_bias INT; v_dice INT;
  arr jsonb; pawn jsonb; i INT; pstate TEXT; pstep INT; has_move BOOLEAN := FALSE;
  v_consec INT; v_override int;
  v_display jsonb;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot, bot_win_bias, consecutive_sixes INTO v_user, v_isbot, v_bias, v_consec
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Déjà lancé, déplacez un pion'; END IF;

  v_override := NULLIF(g.dice_override->>v_slot::text,'')::int;
  IF v_override IS NOT NULL AND v_override BETWEEN 1 AND 6 THEN
    v_dice := v_override;
    UPDATE public.ludo_games SET dice_override = dice_override - v_slot::text WHERE id=_game_id;
  ELSE
    v_dice := 1 + (floor(random()*6))::INT;
    IF v_isbot AND COALESCE(v_bias,0) > 0 AND (random()*100) < v_bias THEN v_dice := 6; END IF;
  END IF;

  IF v_dice = 6 THEN v_consec := COALESCE(v_consec,0) + 1; ELSE v_consec := 0; END IF;
  UPDATE public.ludo_participants SET consecutive_sixes=v_consec WHERE game_id=_game_id AND slot=v_slot;

  IF v_consec >= 3 THEN
    UPDATE public.ludo_participants SET consecutive_sixes=0 WHERE game_id=_game_id AND slot=v_slot;
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('triple_six:cancel'::text));
    st := st - 'no_move_display';
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
    PERFORM public._ludo_check_game_over(_game_id);
    RETURN st;
  END IF;

  st := jsonb_set(st,'{dice}', to_jsonb(v_dice));
  st := jsonb_set(st,'{must_move}','true'::jsonb);
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('roll:'||v_dice));
  st := st - 'no_move_display';

  arr := st->'pawns'->v_slot::text;
  FOR i IN 0..3 LOOP
    pawn := arr->i; pstate := pawn->>'s'; pstep := (pawn->>'k')::INT;
    IF pstate='finished' THEN CONTINUE; END IF;
    IF pstate='yard' THEN IF v_dice=6 THEN has_move:=TRUE; EXIT; END IF;
    ELSE IF pstep + v_dice <= 56 THEN has_move:=TRUE; EXIT; END IF; END IF;
  END LOOP;

  IF NOT has_move THEN
    -- Passer le tour + afficher le dé pendant 1.5 secondes (avec ms pour éviter troncature)
    v_display := jsonb_build_object(
      'slot', v_slot,
      'dice', v_dice,
      'until', to_char((now() + interval '1.5 seconds') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    );
    UPDATE public.ludo_participants SET consecutive_sixes=0 WHERE game_id=_game_id AND slot=v_slot;
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('roll:'||v_dice||':no_move'));
    st := jsonb_set(st,'{no_move_display}', v_display);
    st := jsonb_set(st,'{dice}','null'::jsonb);
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
    PERFORM public._ludo_check_game_over(_game_id);
  ELSE
    UPDATE public.ludo_games SET state=st WHERE id=_game_id;
  END IF;
  RETURN st;
END $function$;

-- ── Bug 3b: ludo_move with ms timestamps + skip forfeited in capture ──────
CREATE OR REPLACE FUNCTION public.ludo_move(_game_id uuid, _pawn_idx integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
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

  IF new_state = 'track' AND new_step <= 50 THEN
    start_idx := public._ludo_start_for(_game_id, v_slot);
    abs_cell := (start_idx + new_step) % 52;
    IF NOT public._ludo_is_safe(abs_cell) THEN
      FOR rec IN SELECT slot, team FROM public.ludo_participants
                  WHERE game_id=_game_id AND slot <> v_slot AND forfeited=FALSE LOOP
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
  st := st - 'no_move_display';
  IF bonus THEN
    st := jsonb_set(st,'{last_event}', to_jsonb(
      (CASE WHEN captured THEN 'capture' WHEN finished THEN 'home' ELSE 'six' END || ':rejoue')::text));
  ELSE
    st := jsonb_set(st,'{turn_slot}',
      to_jsonb(public._ludo_next_slot(_game_id, v_slot, v_max)));
    st := jsonb_set(st,'{last_event}', to_jsonb('move'::text));
    UPDATE public.ludo_participants SET consecutive_sixes=0 WHERE game_id=_game_id AND slot=v_slot;
  END IF;
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;

  PERFORM public._ludo_check_game_over(_game_id);

  RETURN st;
END $function$;

-- ── Bug 3c: ludo_pass with ms timestamps ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.ludo_pass(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_slot INT; v_dice INT;
  v_uid UUID := auth.uid(); v_user UUID; v_isbot BOOLEAN; arr jsonb;
  pawn jsonb; i INT; pstate TEXT; pstep INT; has_move BOOLEAN := FALSE;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := g.state; v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot INTO v_user, v_isbot
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF NOT (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Lancez le dé d''abord'; END IF;
  v_dice := (st->>'dice')::INT;
  arr := st->'pawns'->v_slot::text;
  FOR i IN 0..3 LOOP
    pawn := arr->i; pstate := pawn->>'s'; pstep := (pawn->>'k')::INT;
    IF pstate='finished' THEN CONTINUE; END IF;
    IF pstate='yard' THEN
      IF v_dice = 6 THEN has_move := TRUE; EXIT; END IF;
    ELSE
      IF pstep + v_dice <= 56 THEN has_move := TRUE; EXIT; END IF;
    END IF;
  END LOOP;
  IF has_move THEN RAISE EXCEPTION 'Vous avez un coup possible'; END IF;

  UPDATE public.ludo_participants SET consecutive_sixes = 0
    WHERE game_id = _game_id AND slot = v_slot;

  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := jsonb_set(st,'{dice}','null'::jsonb);
  st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('pass'));
  st := st - 'no_move_display';
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;

  PERFORM public._ludo_check_game_over(_game_id);

  RETURN st;
END $function$;

-- ── Bug 3d: ludo_check_timeout with ms timestamps ─────────────────────────
CREATE OR REPLACE FUNCTION public.ludo_check_timeout(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_slot int; v_started timestamptz;
  v_uid uuid; v_isbot boolean; v_secs int;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := g.state; v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot INTO v_uid, v_isbot
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  SELECT COALESCE(turn_seconds,30) INTO v_secs FROM public.app_settings WHERE id=1;
  v_started := (st->>'turn_started_at')::timestamptz;
  IF now() - v_started < (v_secs || ' seconds')::interval THEN RETURN st; END IF;

  IF NOT v_isbot AND NOT (st->>'must_move')::BOOLEAN THEN
    UPDATE public.ludo_participants SET afk_t1 = afk_t1 + 1 WHERE game_id=_game_id AND slot=v_slot;
  END IF;
  IF NOT v_isbot AND (st->>'must_move')::BOOLEAN THEN
    UPDATE public.ludo_participants SET afk_t2 = afk_t2 + 1 WHERE game_id=_game_id AND slot=v_slot;
  END IF;

  UPDATE public.ludo_participants SET consecutive_sixes = 0
    WHERE game_id = _game_id AND slot = v_slot;

  st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
  st := jsonb_set(st,'{dice}','null'::jsonb);
  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('timeout'::text));
  st := st - 'no_move_display';
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  IF NOT v_isbot THEN
    PERFORM public._ludo_check_afk(_game_id, v_slot);
    PERFORM public._ludo_check_game_over(_game_id);
  END IF;
  RETURN st;
END $$;
