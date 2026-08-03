-- ============================================================
-- Migration: Fix all Ludo bugs
--   1. Create missing player_add_bot function (non-admin bot add)
--   2. Fix ludo_pass: reset consecutive_sixes
--   3. Fix ludo_check_timeout: reset consecutive_sixes
--   4. Fix ludo_bot_play: reset consecutive_sixes on bot pass
-- ============================================================

-- ============================================================
-- BUG 1 (CRITICAL): player_add_bot function is missing.
-- Frontend calls supabase.rpc("player_add_bot", { _game_id, _bot_name })
-- but no such function exists in the database.
-- Non-admin players get an error when trying to add bots.
-- ============================================================
CREATE OR REPLACE FUNCTION public.player_add_bot(_game_id UUID, _bot_name TEXT DEFAULT 'Bot')
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_game public.ludo_games%ROWTYPE;
  v_count INT;
  v_slot INT;
  v_color TEXT;
  v_colors TEXT[] := ARRAY['red','green','yellow','blue'];
  v_uid UUID := auth.uid();
  v_is_participant BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;

  SELECT * INTO v_game FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF v_game.id IS NULL OR v_game.status <> 'open' THEN
    RAISE EXCEPTION 'Partie non ouverte';
  END IF;

  -- Only participants can add bots
  SELECT EXISTS(
    SELECT 1 FROM public.ludo_participants
    WHERE game_id = _game_id AND user_id = v_uid
  ) INTO v_is_participant;

  IF NOT v_is_participant THEN
    RAISE EXCEPTION 'Seuls les participants peuvent ajouter un bot';
  END IF;

  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = _game_id;
  IF v_count >= v_game.max_players THEN
    RAISE EXCEPTION 'Partie pleine';
  END IF;

  -- Only allow bots on free games (stake = 0) or private games
  IF v_game.stake > 0 AND NOT v_game.is_private THEN
    RAISE EXCEPTION 'Bots réservés aux parties amicales (mise 0) ou privées';
  END IF;

  v_slot := v_count;
  v_color := v_colors[v_slot + 1];

  INSERT INTO public.ludo_participants(
    game_id, user_id, slot, color, is_bot, bot_name, display_name,
    bot_intelligence, bot_win_bias, ready
  ) VALUES (
    _game_id, NULL, v_slot, v_color, TRUE, _bot_name, _bot_name,
    70, 0, TRUE
  );

  -- Auto-start if full
  IF v_count + 1 = v_game.max_players THEN
    UPDATE public.ludo_games
      SET status = 'playing', started_at = now(),
          state = public._ludo_init_state(v_game.max_players)
      WHERE id = _game_id;
  END IF;
END $$;

-- Revoke anon access (authenticated only)
REVOKE EXECUTE ON FUNCTION public.player_add_bot(UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.player_add_bot(UUID, TEXT) TO authenticated;

-- ============================================================
-- BUG 2: ludo_pass does not reset consecutive_sixes.
-- ============================================================
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

  -- FIX: reset consecutive_sixes when passing
  UPDATE public.ludo_participants SET consecutive_sixes = 0
    WHERE game_id = _game_id AND slot = v_slot;

  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := jsonb_set(st,'{dice}','null'::jsonb);
  st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('pass'));
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  RETURN st;
END $function$;

-- ============================================================
-- BUG 3: ludo_check_timeout does not reset consecutive_sixes.
-- ============================================================
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

  -- FIX: reset consecutive_sixes on timeout
  UPDATE public.ludo_participants SET consecutive_sixes = 0
    WHERE game_id = _game_id AND slot = v_slot;

  st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
  st := jsonb_set(st,'{dice}','null'::jsonb);
  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('timeout'::text));
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  IF NOT v_isbot THEN PERFORM public._ludo_check_afk(_game_id, v_slot); END IF;
  RETURN st;
END $$;

-- ============================================================
-- BUG 4: ludo_bot_play does not reset consecutive_sixes on pass.
-- ============================================================
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
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;
  SELECT is_bot, bot_intelligence, bot_win_bias INTO v_isbot, v_intel, v_bias
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
    -- FIX: reset consecutive_sixes on bot pass
    UPDATE public.ludo_participants SET consecutive_sixes = 0
      WHERE game_id = _game_id AND slot = v_slot;

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
            FOR rec IN SELECT slot FROM public.ludo_participants
                        WHERE game_id=_game_id AND slot <> v_slot LOOP
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
        sc := pstep + v_dice + CASE WHEN would_capture THEN 100 ELSE 0 END;
      END IF;
      IF sc > best_score THEN best_score := sc; best := i; END IF;
    END LOOP;
  ELSE
    best := candidates[1 + (floor(random()*array_length(candidates,1)))::INT];
  END IF;

  RETURN public.ludo_move(_game_id, best);
END $function$;
