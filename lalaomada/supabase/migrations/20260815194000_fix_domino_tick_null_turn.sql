-- Fix: domino_tick crashes when current_turn = NULL in the "no player found" branch
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
  v_dead_obj jsonb;
  v_tile_idx int;
  i int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

  IF (g.state->>'phase') = 'dealing' THEN
    _deal_until := NULLIF(g.state->>'deal_until','')::timestamptz;
    IF _deal_until IS NOT NULL AND _deal_until <= now() THEN
      PERFORM public._domino_deal_hands(_game_id);
    END IF;
    RETURN;
  END IF;
  IF (g.state->>'phase') = 'reveal' THEN
    _reveal_until := NULLIF(g.state->>'reveal_until','')::timestamptz;
    IF _reveal_until IS NOT NULL AND _reveal_until <= now() THEN
      PERFORM public._domino_start_play(_game_id);
    END IF;
    RETURN;
  END IF;
  IF (g.state->>'phase') = 'break' THEN
    _break_until := NULLIF(g.state->>'break_until','')::timestamptz;
    IF _break_until IS NOT NULL AND _break_until <= now() THEN
      PERFORM public._domino_start_round(_game_id);
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

  _bot_think := NULLIF(g.state->>'bot_think_until', '')::timestamptz;
  IF _bot_think IS NOT NULL AND _bot_think <= now() THEN
    PERFORM public._domino_bot_step(_game_id);
    RETURN;
  END IF;

  IF _bot_think IS NULL THEN
    SELECT COALESCE(dp.is_bot, false) INTO v_is_bot
      FROM public.domino_participants dp
     WHERE dp.game_id = _game_id AND dp.slot = g.current_turn AND dp.forfeited = false;
    IF v_is_bot THEN
      PERFORM public._domino_bot_step(_game_id);
      RETURN;
    END IF;
  END IF;

  IF g.turn_deadline IS NULL OR g.turn_deadline > now() THEN RETURN; END IF;

  SELECT COALESCE(dp.is_bot, false), dp.user_id
    INTO v_is_bot, cur_uid
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id
     AND dp.slot = g.current_turn
     AND dp.forfeited = false;

  -- Case 1: No non-forfeited player at this slot — skip to next or end round
  IF NOT FOUND THEN
    _next := public._domino_next_playable_slot(_game_id, g.current_turn, g.state);
    IF _next IS NULL THEN
      -- FIX: Don't set current_turn = NULL (NOT NULL constraint)
      -- Just end the round directly
      PERFORM public._domino_end_round(_game_id, NULL);
    ELSE
      UPDATE public.domino_games SET current_turn = _next,
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
      WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;

  -- Case 2: Bot's turn and deadline expired
  IF v_is_bot THEN
    PERFORM public._domino_bot_step(_game_id);
    RETURN;
  END IF;

  -- VATO MATY: Mark playable tiles as dead
  IF COALESCE(g.vato_maty, false) THEN
    v_playable := public._domino_playable_tiles(g.state, g.current_turn);
    IF jsonb_array_length(v_playable) > 0 THEN
      v_dead_tiles := COALESCE(g.state->'dead_tiles'->g.current_turn::text, '[]'::jsonb);
      FOR i IN 0..jsonb_array_length(v_playable)-1 LOOP
        v_tile_idx := (v_playable->i)::int;
        IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_dead_tiles) AS dt WHERE dt::int = v_tile_idx) THEN
          v_dead_tiles := v_dead_tiles || to_jsonb(v_tile_idx);
        END IF;
      END LOOP;
      -- FIX: Build dead_tiles object separately (jsonb_set with nested path doesn't work)
      v_dead_obj := COALESCE(g.state->'dead_tiles', '{}'::jsonb);
      v_dead_obj := jsonb_set(v_dead_obj, ARRAY[g.current_turn::text], v_dead_tiles, true);
      g.state := jsonb_set(g.state, ARRAY['dead_tiles'], v_dead_obj, true);
    END IF;
  END IF;

  -- Case 3: Human player — apply skip/forfeit logic
  _skips := COALESCE((g.turn_skips->>cur_uid::text)::int, 0) + 1;

  IF _skips >= COALESCE(_cfg.max_turn_skips, 3) THEN
    UPDATE public.domino_participants SET forfeited = true
     WHERE game_id = _game_id AND user_id = cur_uid;
    SELECT count(*) INTO remaining FROM public.domino_participants
     WHERE game_id = _game_id AND forfeited = false;
    IF remaining <= 1 THEN
      SELECT slot INTO last_slot FROM public.domino_participants
       WHERE game_id = _game_id AND forfeited = false LIMIT 1;
      IF last_slot IS NOT NULL THEN
        PERFORM public._domino_finalize(_game_id, last_slot);
      ELSE
        UPDATE public.domino_games SET status = 'cancelled', finished_at = now() WHERE id = _game_id;
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
      UPDATE public.domino_games SET state = g.state, turn_skips = g.turn_skips,
        current_turn = required_slot,
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
      RETURN;
    END IF;
  END IF;

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
