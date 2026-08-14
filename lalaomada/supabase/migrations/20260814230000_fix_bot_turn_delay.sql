-- Migration: Fix bot turn delay — bot should play in 1-2s, not wait 30s for turn_deadline
--
-- Root cause chain:
-- 1. _domino_arm_bot_think was turned into a NO-OP (just clears bot_think_until)
-- 2. _domino_bot_step sets turn_deadline = now + turn_timer_seconds (30s) for ALL
--    next players, even bots — bots should get 3-5s via _domino_turn_delay
-- 3. domino_tick doesn't trigger _domino_bot_step when bot_think_until is NULL
--    and turn_deadline hasn't expired → bot waits full 30s before anything happens
-- 4. domino_tick_all doesn't detect un-armed bots (bot_think_until IS NULL + slot is bot)
--
-- Fix:
-- A. Re-enable _domino_arm_bot_think to set bot_think_until = now + 1-2s for bots
-- B. _domino_bot_step: use _domino_turn_delay for turn_deadline (3-5s for bots)
-- C. domino_tick: when bot_think_until is NULL and current slot is bot, arm it
-- D. domino_tick_all: detect un-armed bots and trigger tick

-- ═══════════════════════════════════════════════════════════════════
-- A. Re-enable _domino_arm_bot_think
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._domino_arm_bot_think(_game_id uuid, _slot integer, _state jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_is_bot boolean := false;
  v_delay_ms int;
BEGIN
  SELECT COALESCE(dp.is_bot, false) INTO v_is_bot
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id AND dp.slot = _slot AND dp.forfeited = false;

  IF v_is_bot THEN
    -- Arm the bot: set think delay of 1-2 seconds
    v_delay_ms := 1000 + (floor(random() * 1000))::int;
    _state := jsonb_set(_state, '{bot_locked_slot}', to_jsonb(_slot), true);
    _state := jsonb_set(_state, '{bot_think_until}',
                    to_jsonb((now() + make_interval(secs => v_delay_ms / 1000.0))::text), true);
  ELSE
    -- Human player: clear bot think state
    _state := _state - 'bot_think_until' - 'bot_locked_slot';
  END IF;

  RETURN _state;
END;
$function$;

-- ═══════════════════════════════════════════════════════════════════
-- B. Fix _domino_bot_step: use _domino_turn_delay for turn_deadline
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._domino_bot_step(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  g record; st jsonb; v_slot int; hand jsonb; le int; re int;
  draw_mode text; is_first_move boolean; first_dbl int; v_rule text;
  i int; j int; a int; b int; tile jsonb; placed jsonb;
  found boolean; found_i int; new_hand jsonb; new_left int; new_right int;
  next_turn int; winner_slot int; stock jsonb; drawn jsonb;
  _cfg record; v_is_bot boolean; phase text; v_think_until timestamptz;
  v_locked_slot int; v_delay_ms int; v_name text;
  v_playable jsonb;
  v_next_delay interval;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

  st := g.state;
  phase := COALESCE(st->>'phase', 'play');
  IF phase NOT IN ('play','playing') THEN RETURN; END IF;

  v_slot := g.current_turn;
  SELECT COALESCE(dp.is_bot, false), COALESCE(dp.display_name, 'Bot') INTO v_is_bot, v_name
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id AND dp.slot = v_slot AND dp.forfeited = false;

  IF NOT COALESCE(v_is_bot, false) THEN RETURN; END IF;

  v_think_until := NULLIF(st->>'bot_think_until','')::timestamptz;

  -- If bot_think_until is set and in the future, wait
  IF v_think_until IS NOT NULL AND v_think_until > now() THEN
    RETURN;
  END IF;

  -- If bot_think_until is NULL, arm it with a short delay then return
  IF v_think_until IS NULL THEN
    v_delay_ms := 1000 + (floor(random() * 1000))::int;
    st := jsonb_set(st, '{bot_locked_slot}', to_jsonb(v_slot), true);
    st := jsonb_set(st, '{bot_think_until}',
                    to_jsonb((now() + make_interval(secs => v_delay_ms / 1000.0))::text), true);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    RETURN;
  END IF;

  -- bot_think_until is in the past → play the bot
  st := st - 'bot_think_until' - 'bot_locked_slot';

  hand := COALESCE(st->'hands'->v_slot::text, '[]'::jsonb);
  le := NULLIF(st->>'left_end', 'null')::int;
  re := NULLIF(st->>'right_end', 'null')::int;
  draw_mode := COALESCE(st->>'draw_mode', 'with');
  v_rule := COALESCE(st->>'first_tile_rule', 'libre');
  is_first_move := jsonb_array_length(COALESCE(st->'board', '[]'::jsonb)) = 0;
  first_dbl := NULLIF(st->>'first_move_double', 'null')::int;
  SELECT * INTO _cfg FROM public._game_cfg('domino');

  found := false; found_i := -1;

  IF jsonb_array_length(hand) > 0 THEN
    FOR i IN 0..jsonb_array_length(hand)-1 LOOP
      a := (hand->i->>0)::int; b := (hand->i->>1)::int;
      IF is_first_move THEN
        IF first_dbl IS NOT NULL THEN
          IF a = first_dbl AND b = first_dbl THEN found := true; found_i := i; EXIT; END IF;
        ELSIF v_rule = 'under6' THEN
          IF (a + b) < 6 THEN found := true; found_i := i; EXIT; END IF;
        ELSE
          found := true; found_i := i; EXIT;
        END IF;
      ELSE
        IF a = le OR b = le OR a = re OR b = re THEN found := true; found_i := i; EXIT; END IF;
      END IF;
    END LOOP;
  END IF;

  IF found THEN
    tile := hand->found_i; a := (tile->>0)::int; b := (tile->>1)::int;
    new_hand := '[]'::jsonb;
    FOR j IN 0..jsonb_array_length(hand)-1 LOOP
      IF j <> found_i THEN new_hand := new_hand || jsonb_build_array(hand->j); END IF;
    END LOOP;

    IF is_first_move THEN
      placed := jsonb_build_object('tile', jsonb_build_array(a, b), 'flipped', false);
      st := jsonb_set(st, '{board}', jsonb_build_array(placed), true);
      new_left := a; new_right := b;
    ELSE
      IF a = re OR b = re THEN
        IF a = re THEN
          placed := jsonb_build_object('tile', jsonb_build_array(a, b), 'flipped', false); new_right := b;
        ELSE
          placed := jsonb_build_object('tile', jsonb_build_array(b, a), 'flipped', false); new_right := a;
        END IF;
        new_left := le;
        st := jsonb_set(st, '{board}', COALESCE(st->'board','[]'::jsonb) || jsonb_build_array(placed), true);
      ELSE
        IF a = le THEN
          placed := jsonb_build_object('tile', jsonb_build_array(b, a), 'flipped', false); new_left := b;
        ELSE
          placed := jsonb_build_object('tile', jsonb_build_array(a, b), 'flipped', false); new_left := a;
        END IF;
        new_right := re;
        st := jsonb_set(st, '{board}', jsonb_build_array(placed) || COALESCE(st->'board','[]'::jsonb), true);
      END IF;
    END IF;

    st := jsonb_set(st, ARRAY['hands', v_slot::text], new_hand, true);
    st := jsonb_set(st, '{left_end}', to_jsonb(new_left), true);
    st := jsonb_set(st, '{right_end}', to_jsonb(new_right), true);
    st := jsonb_set(st, '{passes}', to_jsonb(0), true);
    st := jsonb_set(st, '{first_move_double}', 'null'::jsonb, true);
    st := jsonb_set(st, '{phase}', '"play"'::jsonb, true);
    st := st - 'last_pass_by';

    IF jsonb_array_length(new_hand) = 0 THEN
      st := jsonb_set(st, ARRAY['turn_slot'], to_jsonb(v_slot), true);
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
      PERFORM public._domino_end_round(_game_id, v_slot);
      RETURN;
    END IF;

    next_turn := public._domino_next_playable_slot(_game_id, v_slot, st);
    IF next_turn IS NULL THEN
      winner_slot := public._domino_lowest_pip_slot(_game_id, st);
      st := jsonb_set(st, ARRAY['turn_slot'], to_jsonb(winner_slot), true);
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
      PERFORM public._domino_end_round(_game_id, winner_slot);
      RETURN;
    END IF;

    -- FIX: Use _domino_turn_delay for turn_deadline (3-5s for bots, 30s for humans)
    v_next_delay := public._domino_turn_delay(_game_id, next_turn);
    -- FIX: Arm the next bot's think delay if next player is a bot
    st := public._domino_arm_bot_think(_game_id, next_turn, st);
    v_playable := public._domino_playable_tiles(st, next_turn);
    st := jsonb_set(st, ARRAY['playable_tiles'], v_playable, true);
    st := jsonb_set(st, ARRAY['turn_slot'], to_jsonb(next_turn), true);
    UPDATE public.domino_games SET state = st, current_turn = next_turn,
           turn_deadline = now() + v_next_delay
     WHERE id = _game_id;
    RETURN;
  END IF;

  -- Bot has no playable tile → draw from stock
  stock := COALESCE(st->'stock', '[]'::jsonb);
  IF draw_mode = 'with' AND jsonb_array_length(stock) > 0 THEN
    drawn := stock -> 0; stock := stock - 0;
    hand := hand || jsonb_build_array(drawn);
    st := jsonb_set(st, ARRAY['hands', v_slot::text], hand, true);
    st := jsonb_set(st, '{stock}', stock, true);
    -- Re-arm think delay so bot tries the drawn tile quickly
    v_delay_ms := 500 + (floor(random() * 500))::int;
    st := jsonb_set(st, '{bot_locked_slot}', to_jsonb(v_slot), true);
    st := jsonb_set(st, '{bot_think_until}',
                    to_jsonb((now() + make_interval(secs => v_delay_ms / 1000.0))::text), true);
    v_playable := public._domino_playable_tiles(st, v_slot);
    st := jsonb_set(st, ARRAY['playable_tiles'], v_playable, true);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    RETURN;
  END IF;

  -- Bot must pass
  st := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1), true);
  st := jsonb_set(st, '{last_pass_by}', to_jsonb(v_slot), true);

  next_turn := public._domino_next_playable_slot(_game_id, v_slot, st);
  IF next_turn IS NULL THEN
    winner_slot := public._domino_lowest_pip_slot(_game_id, st);
    st := jsonb_set(st, ARRAY['turn_slot'], to_jsonb(winner_slot), true);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_end_round(_game_id, winner_slot);
    RETURN;
  END IF;

  -- FIX: Use _domino_turn_delay + arm next bot
  v_next_delay := public._domino_turn_delay(_game_id, next_turn);
  st := public._domino_arm_bot_think(_game_id, next_turn, st);
  v_playable := public._domino_playable_tiles(st, next_turn);
  st := jsonb_set(st, ARRAY['playable_tiles'], v_playable, true);
  st := jsonb_set(st, ARRAY['turn_slot'], to_jsonb(next_turn), true);
  UPDATE public.domino_games SET state = st, current_turn = next_turn,
         turn_deadline = now() + v_next_delay
   WHERE id = _game_id;
END;
$function$;

-- ═══════════════════════════════════════════════════════════════════
-- C. Fix domino_tick: arm un-armed bots immediately
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.domino_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  g record; cur_uid uuid; _cfg record; _skips int; _next int;
  remaining int; last_slot int;
  _break_until timestamptz; _reveal_until timestamptz; _deal_until timestamptz;
  required_slot int; board_empty boolean;
  _bot_think timestamptz;
  v_is_bot boolean := false;
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

  -- ── Bot think delay expired → trigger bot play ──
  _bot_think := NULLIF(g.state->>'bot_think_until', '')::timestamptz;
  IF _bot_think IS NOT NULL AND _bot_think <= now() THEN
    PERFORM public._domino_bot_step(_game_id);
    RETURN;
  END IF;

  -- ── NEW: If bot_think_until is NULL, check if current slot is a bot ──
  -- If so, arm the bot immediately (don't wait for turn_deadline to expire)
  IF _bot_think IS NULL THEN
    SELECT COALESCE(dp.is_bot, false) INTO v_is_bot
      FROM public.domino_participants dp
     WHERE dp.game_id = _game_id
       AND dp.slot = g.current_turn
       AND dp.forfeited = false;

    IF v_is_bot THEN
      -- Arm the bot's think delay right now
      PERFORM public._domino_bot_step(_game_id);
      RETURN;
    END IF;
  END IF;

  -- ── For human players, wait for turn_deadline ──
  IF g.turn_deadline IS NULL OR g.turn_deadline > now() THEN RETURN; END IF;

  -- ── Check who is at the current slot ──
  SELECT COALESCE(dp.is_bot, false), dp.user_id
    INTO v_is_bot, cur_uid
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id
     AND dp.slot = g.current_turn
     AND dp.forfeited = false;

  -- Case 1: No non-forfeited player at this slot (forfeited/empty)
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

  -- Case 2: Bot's turn and deadline expired (shouldn't happen with new logic,
  -- but kept as safety net)
  IF v_is_bot THEN
    PERFORM public._domino_bot_step(_game_id);
    RETURN;
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
    UPDATE public.domino_games SET turn_skips = g.turn_skips WHERE id = _game_id;
  END IF;

  _next := public._domino_next_playable_slot(_game_id, g.current_turn, g.state);
  IF _next IS NULL THEN
    _next := public._domino_lowest_pip_slot(_game_id, g.state);
    IF _next IS NOT NULL THEN
      PERFORM public._domino_end_round(_game_id, _next);
    ELSE
      PERFORM public._domino_end_round(_game_id, NULL);
    END IF;
    RETURN;
  END IF;

  UPDATE public.domino_games SET current_turn = _next,
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
END;
$function$;

-- ═══════════════════════════════════════════════════════════════════
-- D. Fix domino_tick_all: detect un-armed bots
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.domino_tick_all()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  g_id uuid;
BEGIN
  FOR g_id IN
    SELECT id
    FROM public.domino_games
    WHERE status = 'playing'
      AND (
        -- turn_deadline expired
        (turn_deadline IS NOT NULL AND turn_deadline <= now())
        -- phase transitions
        OR (state->>'phase' = 'reveal' AND NULLIF(state->>'reveal_until', '')::timestamptz <= now())
        OR (state->>'phase' = 'break' AND NULLIF(state->>'break_until', '')::timestamptz <= now())
        OR (state->>'phase' = 'dealing' AND NULLIF(state->>'deal_until', '')::timestamptz <= now())
        -- bot_think_until expired
        OR (state->>'bot_think_until' IS NOT NULL AND NULLIF(state->>'bot_think_until', '')::timestamptz <= now())
        -- NEW: un-armed bot (phase=play, bot_think_until IS NULL, current player is a bot)
        OR (
          COALESCE(state->>'phase', 'play') IN ('play', 'playing')
          AND state->>'bot_think_until' IS NULL
          AND EXISTS (
            SELECT 1 FROM public.domino_participants dp
            WHERE dp.game_id = domino_games.id
              AND dp.slot = domino_games.current_turn
              AND dp.is_bot = true
              AND dp.forfeited = false
          )
        )
      )
  LOOP
    BEGIN
      PERFORM public.domino_tick(g_id);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END LOOP;
  END LOOP;
END;
$function$;
