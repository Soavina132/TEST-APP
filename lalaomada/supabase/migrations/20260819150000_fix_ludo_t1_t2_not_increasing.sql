-- ════════════════════════════════════════════════════════════
-- FIX: ludo_check_timeout n'incrémente plus afk_t1/afk_t2 (T1/T2)
-- Cause: la migration 20260819090000_restore_ludo_from_ludo1.sql a
--        écrasé ludo_check_timeout avec une vieille version qui utilise
--        missed_turns au lieu de afk_t1/afk_t2.
-- Solution: restaurer la logique T1/T2 dans ludo_check_timeout et
--           _ludo_check_afk.
-- ════════════════════════════════════════════════════════════

-- ── 1. Fix ludo_check_timeout: increment afk_t1 (no roll) / afk_t2 (no move) ──
CREATE OR REPLACE FUNCTION public.ludo_check_timeout(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  g public.ludo_games%ROWTYPE;
  st jsonb;
  v_slot INT;
  v_started TIMESTAMPTZ;
  v_uid UUID;
  v_isbot BOOLEAN;
  v_turn_seconds INT;
  v_new_slot INT;
  v_missed INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := g.state;

  -- Skip if game is paused
  IF COALESCE(g.paused, false) THEN RETURN st; END IF;

  SELECT turn_seconds INTO v_turn_seconds FROM public.app_settings WHERE id = 1;
  v_turn_seconds := COALESCE(v_turn_seconds, 30);

  v_started := (st->>'turn_started_at')::TIMESTAMPTZ;
  IF now() - v_started < (v_turn_seconds || ' seconds')::interval THEN RETURN st; END IF;

  v_slot := (st->>'turn_slot')::INT;

  -- Get current player info
  SELECT user_id, is_bot, missed_turns INTO v_uid, v_isbot, v_missed
    FROM public.ludo_participants
    WHERE game_id=_game_id AND slot=v_slot AND NOT forfeited;

  -- If current player forfeited or not found, advance turn
  IF NOT FOUND THEN
    st := jsonb_set(st, '{must_move}', 'false'::jsonb);
    st := jsonb_set(st, '{dice}', 'null'::jsonb);
    v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
    st := public._ludo_clear_shield(st, v_new_slot);
    st := jsonb_set(st, '{turn_slot}', to_jsonb(v_new_slot));
    st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st, '{last_event}', to_jsonb('skip_forfeit'::text));
    st := st - 'no_move_display' - 'movable_pawns' - 'power_event';
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
    RETURN st;
  END IF;

  -- Skip bots — they're auto-played by ludo_tick_all
  IF v_isbot THEN RETURN st; END IF;

  -- ── T1/T2 logic ──
  -- T1: player didn't roll the dice (must_move = false) → increment afk_t1
  -- T2: player rolled but didn't move (must_move = true) → increment afk_t2

  -- Try auto_move if enabled before counting T2
  IF COALESCE((st->>'must_move')::boolean, false) AND COALESCE(g.auto_move, false) THEN
    IF public._ludo_auto_move(_game_id, v_slot) THEN
      SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
      RETURN st;
    END IF;
  END IF;

  -- Increment T1 or T2
  IF NOT COALESCE((st->>'must_move')::boolean, false) THEN
    -- Player didn't roll → T1
    UPDATE public.ludo_participants
      SET afk_t1 = COALESCE(afk_t1, 0) + 1, consecutive_sixes = 0
      WHERE game_id=_game_id AND slot=v_slot;
  ELSE
    -- Player rolled but didn't move → T2
    UPDATE public.ludo_participants
      SET afk_t2 = COALESCE(afk_t2, 0) + 1, consecutive_sixes = 0
      WHERE game_id=_game_id AND slot=v_slot;
  END IF;

  -- Clear double_roll_pending if applicable
  IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
    st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
  END IF;

  -- Advance turn
  v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
  st := public._ludo_clear_shield(st, v_new_slot);
  st := jsonb_set(st, '{turn_slot}', to_jsonb(v_new_slot));
  st := jsonb_set(st, '{dice}', 'null'::jsonb);
  st := jsonb_set(st, '{must_move}', 'false'::jsonb);
  st := public._ludo_decrement_cooldowns(st);
  st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  st := jsonb_set(st, '{last_event}', to_jsonb('timeout'::text));
  st := st - 'no_move_display' - 'movable_pawns' - 'power_event';

  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;

  -- Check AFK thresholds (T1/T2 → warning or forfeit)
  PERFORM public._ludo_check_afk(_game_id, v_slot);

  PERFORM public._ludo_check_game_over(_game_id);
  RETURN st;
END $function$;
REVOKE ALL ON FUNCTION public.ludo_check_timeout(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ludo_check_timeout(uuid) TO authenticated;

-- ── 2. Fix _ludo_check_afk: full logic (forfeit, pawn-to-yard, warning, solo) ──
CREATE OR REPLACE FUNCTION public._ludo_check_afk(_game_id uuid, _slot integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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

    -- Check if solo game
    SELECT COALESCE(is_solo, false) OR COALESCE(match_type, 'groupe') = 'solo'
      INTO v_is_solo FROM public.ludo_games WHERE id = _game_id;

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
       AND COALESCE(paused, false) = FALSE
       AND (afk_warning IS NULL
            OR (afk_warning->>'uid')::uuid IS DISTINCT FROM v_uid);
  END IF;
END $$;
REVOKE ALL ON FUNCTION public._ludo_check_afk(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._ludo_check_afk(uuid, integer) TO authenticated;
