-- ============================================================
-- 1. LUDO: Auto-move at 4 seconds remaining (random pawn)
-- ============================================================

-- New function: pick a RANDOM playable pawn (not smartest)
CREATE OR REPLACE FUNCTION public._ludo_auto_move_random(_game_id uuid, _slot int)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  g public.ludo_games%ROWTYPE;
  v_dice int;
  v_playable jsonb;
  v_count int;
  v_pawn int;
  v_idx int;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id = _game_id;
  IF g.id IS NULL OR g.status <> 'playing' THEN RETURN false; END IF;
  IF NOT COALESCE(g.auto_move, false) THEN RETURN false; END IF;
  IF NOT COALESCE((g.state->>'must_move')::boolean, false) THEN RETURN false; END IF;
  v_dice := NULLIF(g.state->>'dice', 'null')::int;
  IF v_dice IS NULL THEN RETURN false; END IF;

  v_playable := public._ludo_playable_pawns(g.state->'pawns', _slot, v_dice);
  v_count := jsonb_array_length(COALESCE(v_playable, '[]'::jsonb));
  IF v_count = 0 THEN RETURN false; END IF;

  -- Pick a random playable pawn
  v_idx := floor(random() * v_count)::int;
  v_pawn := (v_playable->v_idx)::int;

  PERFORM set_config('app.ludo_auto', 'on', true);
  PERFORM public.ludo_move(_game_id, v_pawn);
  PERFORM set_config('app.ludo_auto', 'off', true);
  RETURN true;
END
$function$;
REVOKE ALL ON FUNCTION public._ludo_auto_move_random(uuid, int) FROM PUBLIC;

-- Update ludo_tick_all to auto-move at 4 seconds remaining
CREATE OR REPLACE FUNCTION public.ludo_tick_all()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  g_id UUID;
  v_slot INT;
  v_isbot BOOLEAN;
  st JSONB;
  v_turn_started TIMESTAMPTZ;
  v_elapsed FLOAT;
  v_delay_until TIMESTAMPTZ;
  v_bot_delay FLOAT;
  v_secs INT;
  v_auto_move BOOLEAN;
  v_uid UUID;
BEGIN
  -- Cleanup stale open games (older than 2 minutes)
  PERFORM public.cleanup_stale_open_games();

  FOR g_id IN SELECT id FROM public.ludo_games WHERE status='playing' LOOP
    BEGIN
      -- ── Pre-timeout auto-move (4 seconds before timeout) ──
      SELECT state, auto_move INTO st, v_auto_move FROM public.ludo_games WHERE id = g_id;
      IF st IS NOT NULL AND COALESCE(v_auto_move, false) THEN
        v_slot := (st->>'turn_slot')::INT;
        SELECT is_bot, user_id INTO v_isbot, v_uid
          FROM public.ludo_participants
          WHERE game_id = g_id AND slot = v_slot AND NOT forfeited;
        IF FOUND AND NOT v_isbot AND COALESCE((st->>'must_move')::boolean, false) THEN
          SELECT COALESCE(turn_seconds, 30) INTO v_secs FROM public.app_settings WHERE id = 1;
          v_turn_started := (st->>'turn_started_at')::timestamptz;
          v_elapsed := EXTRACT(EPOCH FROM (now() - v_turn_started));
          -- Auto-move when 4 seconds remaining
          IF v_elapsed >= (v_secs - 4) THEN
            -- Try to auto-move a random playable pawn
            IF public._ludo_auto_move_random(g_id, v_slot) THEN
              -- Auto-move succeeded, skip the rest for this game
              PERFORM public._ludo_check_stalemate(g_id);
              CONTINUE;
            END IF;
            -- No playable pawn — let ludo_check_timeout handle the skip
          END IF;
        END IF;
      END IF;

      -- ── Normal timeout check ──
      PERFORM public.ludo_check_timeout(g_id);

      SELECT state INTO st FROM public.ludo_games WHERE id=g_id;
      IF st IS NULL THEN CONTINUE; END IF;
      v_slot := (st->>'turn_slot')::INT;
      SELECT is_bot INTO v_isbot FROM public.ludo_participants
        WHERE game_id=g_id AND slot=v_slot;

      IF v_isbot THEN
        v_turn_started := (st->>'turn_started_at')::timestamptz;
        v_elapsed := EXTRACT(EPOCH FROM (now() - v_turn_started));

        IF NOT (st->>'must_move')::BOOLEAN THEN
          IF v_elapsed >= 3.0 + (random() * 2.0) THEN
            PERFORM public.ludo_bot_play(g_id);
          END IF;
        ELSE
          SELECT bot_delay_until INTO v_delay_until FROM public.ludo_games WHERE id=g_id;
          IF v_delay_until IS NULL OR v_delay_until < v_turn_started THEN
            v_bot_delay := 2.0 + (random() * 2.0);
            UPDATE public.ludo_games
              SET bot_delay_until = now() + make_interval(secs => v_bot_delay)
              WHERE id=g_id;
          ELSIF now() >= v_delay_until THEN
            PERFORM public.ludo_bot_move(g_id);
            UPDATE public.ludo_games SET bot_delay_until = NULL WHERE id=g_id;
          END IF;
        END IF;
      END IF;

      PERFORM public._ludo_check_stalemate(g_id);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
END;
$function$;
REVOKE ALL ON FUNCTION public.ludo_tick_all() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ludo_tick_all() TO authenticated;

-- Also update ludo_check_timeout to use random auto-move
CREATE OR REPLACE FUNCTION public.ludo_check_timeout(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_slot int; v_started timestamptz;
  v_uid uuid; v_isbot boolean; v_secs int; v_new_slot INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  IF COALESCE(g.paused, false) THEN RETURN g.state; END IF;

  st := g.state;

  -- Handle power_pending
  IF st ? 'power_pending' THEN
    DECLARE v_choice text;
    BEGIN
      IF (st->'power_pending'->>'tile_type') = 'boost' THEN
        v_choice := 'skip';
      ELSE
        v_choice := (st->'power_pending'->'options'->>0);
      END IF;
      PERFORM public.ludo_choose_power(_game_id, v_choice);
      SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
      RETURN st;
    END;
  END IF;

  SELECT COALESCE(turn_seconds,30) INTO v_secs FROM public.app_settings WHERE id=1;
  v_started := (st->>'turn_started_at')::timestamptz;
  IF now() - v_started < (v_secs || ' seconds')::interval THEN RETURN st; END IF;

  v_slot := (st->>'turn_slot')::INT;

  SELECT user_id, is_bot INTO v_uid, v_isbot
    FROM public.ludo_participants
    WHERE game_id=_game_id AND slot=v_slot AND NOT forfeited;

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

  IF v_isbot THEN RETURN st; END IF;

  -- Try auto-move (random) before counting T2
  IF COALESCE((st->>'must_move')::boolean, false) AND COALESCE(g.auto_move, false) THEN
    IF public._ludo_auto_move_random(_game_id, v_slot) THEN
      SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
      RETURN st;
    END IF;
  END IF;

  -- Increment T1 (no roll) or T2 (no move)
  IF NOT COALESCE((st->>'must_move')::boolean, false) THEN
    UPDATE public.ludo_participants SET afk_t1 = afk_t1 + 1, consecutive_sixes = 0
      WHERE game_id=_game_id AND slot=v_slot;
  ELSE
    UPDATE public.ludo_participants SET afk_t2 = afk_t2 + 1, consecutive_sixes = 0
      WHERE game_id=_game_id AND slot=v_slot;
  END IF;

  IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
    st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
  END IF;

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

  PERFORM public._ludo_check_afk(_game_id, v_slot);
  RETURN st;
END
$function$;
REVOKE ALL ON FUNCTION public.ludo_check_timeout(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ludo_check_timeout(uuid) TO authenticated;

-- ============================================================
-- 2. DOMINO: Vato maty (dead tile on timeout)
-- ============================================================

-- Add vato_maty column to domino_games
ALTER TABLE public.domino_games ADD COLUMN IF NOT EXISTS vato_maty boolean DEFAULT false;

-- Update _domino_playable_tiles to exclude dead tiles
CREATE OR REPLACE FUNCTION public._domino_playable_tiles(_state jsonb, _slot int)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  hand jsonb;
  board jsonb;
  left_end INT;
  right_end INT;
  i INT;
  tile jsonb;
  a INT; b INT;
  result jsonb := '[]'::jsonb;
  first_move_double INT;
  first_tile_rule TEXT;
  board_len INT;
  dead_tiles jsonb;
  is_dead boolean;
BEGIN
  hand := _state->'hands'->_slot::text;
  board := _state->'board';
  IF hand IS NULL THEN RETURN '[]'::jsonb; END IF;

  -- Get dead tiles for this slot
  dead_tiles := COALESCE(_state->'dead_tiles'->_slot::text, '[]'::jsonb);

  board_len := COALESCE(jsonb_array_length(board), 0);
  left_end := NULLIF(_state->>'left_end','')::INT;
  right_end := NULLIF(_state->>'right_end','')::INT;
  first_move_double := NULLIF(_state->>'first_move_double','')::INT;
  first_tile_rule := COALESCE(_state->>'first_tile_rule', 'libre');

  FOR i IN 0..jsonb_array_length(hand)-1 LOOP
    -- Skip dead tiles
    is_dead := false;
    FOR j IN 0..jsonb_array_length(dead_tiles)-1 LOOP
      IF (dead_tiles->j)::int = i THEN is_dead := true; EXIT; END IF;
    END LOOP;
    IF is_dead THEN CONTINUE; END IF;

    tile := hand->i;
    a := (tile->>0)::INT;
    b := (tile->>1)::INT;

    IF board_len = 0 THEN
      IF first_move_double IS NOT NULL THEN
        IF a = first_move_double AND b = first_move_double THEN
          result := result || to_jsonb(i);
        END IF;
      ELSIF first_tile_rule = 'under6' THEN
        IF a + b < 6 THEN result := result || to_jsonb(i); END IF;
      ELSE
        result := result || to_jsonb(i);
      END IF;
    ELSE
      IF a = left_end OR b = left_end OR a = right_end OR b = right_end THEN
        result := result || to_jsonb(i);
      END IF;
    END IF;
  END LOOP;

  RETURN result;
END
$$;
REVOKE ALL ON FUNCTION public._domino_playable_tiles(jsonb, int) FROM PUBLIC;

-- Update _domino_slot_has_playable to respect dead tiles
CREATE OR REPLACE FUNCTION public._domino_slot_has_playable(_state jsonb, _slot int)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  hand jsonb := COALESCE(_state -> 'hands' -> _slot::text, '[]'::jsonb);
  board_len integer := jsonb_array_length(COALESCE(_state -> 'board', '[]'::jsonb));
  first_dbl integer;
  le integer; re integer;
  t jsonb; a integer; b integer;
  v_rule text;
  dead_tiles jsonb;
  is_dead boolean;
  i int;
  j int;
BEGIN
  IF jsonb_array_length(hand) = 0 THEN RETURN false; END IF;

  -- Get dead tiles for this slot
  dead_tiles := COALESCE(_state->'dead_tiles'->_slot::text, '[]'::jsonb);

  IF board_len = 0 THEN
    first_dbl := NULLIF(_state->>'first_move_double', 'null')::integer;
    IF first_dbl IS NOT NULL THEN
      FOR i IN 0..jsonb_array_length(hand)-1 LOOP
        -- Check if tile i is dead
        is_dead := false;
        FOR j IN 0..jsonb_array_length(dead_tiles)-1 LOOP
          IF (dead_tiles->j)::int = i THEN is_dead := true; EXIT; END IF;
        END LOOP;
        IF is_dead THEN CONTINUE; END IF;
        t := hand->i;
        IF (t->>0)::int = first_dbl AND (t->>1)::int = first_dbl THEN RETURN true; END IF;
      END LOOP;
      RETURN false;
    END IF;
    v_rule := COALESCE(_state->>'first_tile_rule','libre');
    IF v_rule = 'under6' THEN
      FOR i IN 0..jsonb_array_length(hand)-1 LOOP
        is_dead := false;
        FOR j IN 0..jsonb_array_length(dead_tiles)-1 LOOP
          IF (dead_tiles->j)::int = i THEN is_dead := true; EXIT; END IF;
        END LOOP;
        IF is_dead THEN CONTINUE; END IF;
        t := hand->i;
        IF ((t->>0)::int + (t->>1)::int) < 6 THEN RETURN true; END IF;
      END LOOP;
      RETURN false;
    END IF;
    -- Libre: check if any non-dead tile exists
    FOR i IN 0..jsonb_array_length(hand)-1 LOOP
      is_dead := false;
      FOR j IN 0..jsonb_array_length(dead_tiles)-1 LOOP
        IF (dead_tiles->j)::int = i THEN is_dead := true; EXIT; END IF;
      END LOOP;
      IF NOT is_dead THEN RETURN true; END IF;
    END LOOP;
    RETURN false;
  END IF;

  le := NULLIF(_state->>'left_end', 'null')::integer;
  re := NULLIF(_state->>'right_end', 'null')::integer;
  FOR i IN 0..jsonb_array_length(hand)-1 LOOP
    -- Check if tile i is dead
    is_dead := false;
    FOR j IN 0..jsonb_array_length(dead_tiles)-1 LOOP
      IF (dead_tiles->j)::int = i THEN is_dead := true; EXIT; END IF;
    END LOOP;
    IF is_dead THEN CONTINUE; END IF;
    t := hand->i;
    a := (t->>0)::integer; b := (t->>1)::integer;
    IF a = le OR b = le OR a = re OR b = re THEN RETURN true; END IF;
  END LOOP;
  RETURN false;
END
$$;
REVOKE ALL ON FUNCTION public._domino_slot_has_playable(jsonb, int) FROM PUBLIC;

-- Update domino_tick to mark dead tiles on timeout (vato maty)
CREATE OR REPLACE FUNCTION public.domino_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  g record; cur_uid uuid; _cfg record; _skips int; _next int;
  remaining int; last_slot int;
  _break_until timestamptz; _reveal_until timestamptz; _deal_until timestamptz;
  required_slot int; board_empty boolean;
  _bot_think timestamptz;
  v_is_bot boolean := false;
  v_playable jsonb;
  v_dead_tiles jsonb;
  v_tile_idx int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

  -- Phase: dealing
  IF (g.state->>'phase') = 'dealing' THEN
    _deal_until := NULLIF(g.state->>'deal_until','')::timestamptz;
    IF _deal_until IS NOT NULL AND _deal_until <= now() THEN
      PERFORM public._domino_place_first(_game_id);
    END IF;
    RETURN;
  END IF;

  -- Phase: reveal
  IF (g.state->>'phase') = 'reveal' THEN
    _reveal_until := NULLIF(g.state->>'reveal_until','')::timestamptz;
    IF _reveal_until IS NOT NULL AND _reveal_until <= now() THEN
      UPDATE public.domino_games
         SET state = jsonb_set(g.state, '{phase}', '"break"'::jsonb)
       WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;

  -- Phase: break
  IF (g.state->>'phase') = 'break' THEN
    _break_until := NULLIF(g.state->>'break_until','')::timestamptz;
    IF _break_until IS NOT NULL AND _break_until <= now() THEN
      PERFORM public._domino_next_round(_game_id);
    END IF;
    RETURN;
  END IF;

  SELECT * INTO _cfg FROM public._game_cfg('domino');
  board_empty := jsonb_array_length(COALESCE(g.state->'board', '[]'::jsonb)) = 0;
  required_slot := public._domino_required_starter_slot(_game_id, g.state);

  IF board_empty AND required_slot IS NOT NULL AND required_slot <> g.current_turn THEN
    UPDATE public.domino_games
       SET current_turn = required_slot,
           turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
     WHERE id = _game_id;
    RETURN;
  END IF;

  -- Bot think delay expired → trigger bot play
  _bot_think := NULLIF(g.state->>'bot_think_until', '')::timestamptz;
  IF _bot_think IS NOT NULL AND _bot_think <= now() THEN
    PERFORM public._domino_bot_step(_game_id);
    RETURN;
  END IF;

  -- If bot_think_until is NULL, check if current slot is a bot
  IF _bot_think IS NULL THEN
    SELECT COALESCE(dp.is_bot, false) INTO v_is_bot
      FROM public.domino_participants dp
     WHERE dp.game_id = _game_id
       AND dp.slot = g.current_turn
       AND dp.forfeited = false;

    IF v_is_bot THEN
      PERFORM public._domino_bot_step(_game_id);
      RETURN;
    END IF;
  END IF;

  -- For human players, wait for turn_deadline
  IF g.turn_deadline IS NULL OR g.turn_deadline > now() THEN RETURN; END IF;

  -- Check who is at the current slot
  SELECT COALESCE(dp.is_bot, false), dp.user_id
    INTO v_is_bot, cur_uid
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id
     AND dp.slot = g.current_turn
     AND dp.forfeited = false;

  -- Case 1: No non-forfeited player at this slot
  IF NOT FOUND THEN
    _next := public._domino_next_playable_slot(_game_id, g.current_turn, g.state);
    IF _next IS NOT NULL THEN
      UPDATE public.domino_games
         SET current_turn = _next,
             turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
       WHERE id = _game_id;
    ELSE
      _next := public._domino_lowest_pip_slot(_game_id, g.state);
      IF _next IS NOT NULL THEN
        PERFORM public._domino_end_round(_game_id, _next);
      ELSE
        PERFORM public._domino_end_round(_game_id, NULL);
      END IF;
    END IF;
    RETURN;
  END IF;

  -- Case 2: Bot's turn and deadline expired
  IF v_is_bot THEN
    PERFORM public._domino_bot_step(_game_id);
    RETURN;
  END IF;

  -- ── VATO MATY: Mark playable tiles as dead on timeout ──
  IF COALESCE(g.vato_maty, false) THEN
    v_playable := public._domino_playable_tiles(g.state, g.current_turn);
    IF jsonb_array_length(v_playable) > 0 THEN
      -- Get existing dead tiles for this slot
      v_dead_tiles := COALESCE(g.state->'dead_tiles'->g.current_turn::text, '[]'::jsonb);
      -- Add all playable tile indices to dead tiles
      FOR i IN 0..jsonb_array_length(v_playable)-1 LOOP
        v_tile_idx := (v_playable->i)::int;
        -- Check if already dead
        IF NOT EXISTS (
          SELECT 1 FROM jsonb_array_elements(v_dead_tiles) AS dt
          WHERE dt::int = v_tile_idx
        ) THEN
          v_dead_tiles := v_dead_tiles || to_jsonb(v_tile_idx);
        END IF;
      END LOOP;
      -- Save dead tiles to state
      g.state := jsonb_set(g.state, ARRAY['dead_tiles', g.current_turn::text], v_dead_tiles, true);
    END IF;
  END IF;

  -- Case 3: Human player — apply skip/forfeit logic
  _skips := COALESCE((g.turn_skips->>cur_uid::text)::int, 0) + 1;

  IF _skips >= _cfg.max_turn_skips THEN
    UPDATE public.domino_participants SET forfeited = true WHERE game_id = _game_id AND user_id = cur_uid;
    SELECT count(*) INTO remaining FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
    IF remaining <= 1 THEN
      SELECT slot INTO last_slot FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false LIMIT 1;
      IF last_slot IS NOT NULL THEN
        PERFORM public._domino_finalize(_game_id, last_slot);
      ELSE
        UPDATE public.domino_games SET status='cancelled', finished_at=now() WHERE id = _game_id;
      END IF;
      RETURN;
    END IF;
    g.turn_skips := jsonb_set(COALESCE(g.turn_skips,'{}'::jsonb), ARRAY[cur_uid::text], to_jsonb(_skips), true);
    g.state := jsonb_set(g.state, ARRAY['hands', g.current_turn::text], '[]'::jsonb, true);
    required_slot := public._domino_required_starter_slot(_game_id, g.state);
    IF board_empty AND required_slot IS NOT NULL THEN
      UPDATE public.domino_games SET state = g.state, turn_skips = g.turn_skips,
        current_turn = required_slot,
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
      RETURN;
    END IF;
  ELSE
    g.turn_skips := jsonb_set(COALESCE(g.turn_skips,'{}'::jsonb), ARRAY[cur_uid::text], to_jsonb(_skips), true);
    IF board_empty AND required_slot IS NOT NULL THEN
      UPDATE public.domino_games SET turn_skips = g.turn_skips,
        current_turn = required_slot,
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
      RETURN;
    END IF;
  END IF;

  -- Save state (with dead tiles if vato maty) and advance turn
  _next := public._domino_next_playable_slot(_game_id, g.current_turn, g.state);
  IF _next IS NULL THEN
    _next := public._domino_lowest_pip_slot(_game_id, g.state);
    IF _next IS NOT NULL THEN
      UPDATE public.domino_games SET state = g.state, turn_skips = g.turn_skips WHERE id = _game_id;
      PERFORM public._domino_end_round(_game_id, _next);
    ELSE
      UPDATE public.domino_games SET state = g.state, turn_skips = g.turn_skips WHERE id = _game_id;
      PERFORM public._domino_end_round(_game_id, NULL);
    END IF;
    RETURN;
  END IF;

  UPDATE public.domino_games SET state = g.state, turn_skips = g.turn_skips, current_turn = _next,
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
END;
$$;
REVOKE ALL ON FUNCTION public.domino_tick(uuid) FROM PUBLIC;

-- Update domino_create to accept _vato_maty parameter
DROP FUNCTION IF EXISTS public.domino_create(numeric, integer, boolean, text, numeric, integer, text, text);
CREATE OR REPLACE FUNCTION public.domino_create(
  _stake numeric,
  _max integer,
  _private boolean,
  _mode text DEFAULT 'classic',
  _commission numeric DEFAULT 10,
  _target_score integer DEFAULT 0,
  _draw_mode text DEFAULT 'with',
  _first_tile_rule text DEFAULT 'libre',
  _vato_maty boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_balance numeric; v_code text; v_id uuid; v_name text; v_state jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _max NOT BETWEEN 2 AND 3 THEN RAISE EXCEPTION 'invalid max_players (2-3)'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'invalid stake'; END IF;
  IF _target_score < 0 OR _target_score > 1000 THEN RAISE EXCEPTION 'invalid target_score'; END IF;
  IF _draw_mode NOT IN ('with','without') THEN RAISE EXCEPTION 'invalid draw_mode'; END IF;
  IF _first_tile_rule NOT IN ('libre','under6') THEN RAISE EXCEPTION 'invalid first_tile_rule'; END IF;

  SELECT balance_ar, pseudo INTO v_balance, v_name FROM public.profiles WHERE id = v_uid;
  IF v_balance IS NULL OR v_balance < _stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;

  IF _private THEN
    v_code := upper(substring(md5(random()::text||clock_timestamp()::text) from 1 for 6));
  END IF;

  v_state := public._domino_init_state();
  v_state := jsonb_set(v_state, '{draw_mode}', to_jsonb(_draw_mode), true);
  v_state := jsonb_set(v_state, '{first_tile_rule}', to_jsonb(_first_tile_rule), true);

  INSERT INTO public.domino_games(host_id, max_players, stake, pot, commission_pct, is_private, room_code, mode, target_score, state, first_tile_rule, vato_maty)
  VALUES (v_uid, _max, _stake, _stake, _commission, _private, v_code, _mode, _target_score, v_state, _first_tile_rule, _vato_maty)
  RETURNING id INTO v_id;

  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
    VALUES (v_uid, 'domino_stake', -_stake, v_id, 'Create domino game');
  INSERT INTO public.domino_participants(game_id, user_id, slot, display_name)
    VALUES (v_id, v_uid, 0, COALESCE(v_name,'Player'));
  RETURN v_id;
END
$$;
REVOKE ALL ON FUNCTION public.domino_create(numeric, integer, boolean, text, numeric, integer, text, text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.domino_create(numeric, integer, boolean, text, numeric, integer, text, text, boolean) TO authenticated;

-- Keep the old overloads working (they delegate without vato_maty)
-- The 3-arg, 6-arg, and 7-arg overloads still exist from previous migrations.
-- The new 9-arg overload is the canonical one used by the frontend.
