-- Restore clean domino_tick (remove debug logging)
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
  i int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

  -- Phase checks
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

  -- Bot think delay
  _bot_think := NULLIF(g.state->>'bot_think_until', '')::timestamptz;
  IF _bot_think IS NOT NULL AND _bot_think <= now() THEN
    PERFORM public._domino_bot_step(_game_id);
    RETURN;
  END IF;

  -- If no bot_think, check if current slot is a bot (arm the think delay)
  IF _bot_think IS NULL THEN
    SELECT COALESCE(dp.is_bot, false) INTO v_is_bot
      FROM public.domino_participants dp
     WHERE dp.game_id = _game_id AND dp.slot = g.current_turn AND dp.forfeited = false;
    IF v_is_bot THEN
      PERFORM public._domino_bot_step(_game_id);
      RETURN;
    END IF;
  END IF;

  -- For human players, wait for turn_deadline
  IF g.turn_deadline IS NULL OR g.turn_deadline > now() THEN RETURN; END IF;

  SELECT COALESCE(dp.is_bot, false), dp.user_id
    INTO v_is_bot, cur_uid
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id
     AND dp.slot = g.current_turn
     AND dp.forfeited = false;

  -- Case 1: No non-forfeited player at this slot
  IF NOT FOUND THEN
    _next := public._domino_next_playable_slot(_game_id, g.current_turn, g.state);
    IF _next IS NULL THEN
      UPDATE public.domino_games SET current_turn = _next WHERE id = _game_id;
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

  -- VATO MATY: Mark playable tiles as dead for the timed-out player
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
      g.state := jsonb_set(g.state, ARRAY['dead_tiles', g.current_turn::text], v_dead_tiles, true);
    END IF;
  END IF;

  -- Case 3: Human player — apply skip/forfeit logic
  _skips := COALESCE((g.turn_skips->>cur_uid::text)::int, 0) + 1;

  IF _skips >= COALESCE(_cfg.max_turn_skips, 3) THEN
    -- Forfeit the player
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

    -- FIX: was missing state = g.state, losing dead_tiles on vato_maty
    required_slot := public._domino_required_starter_slot(_game_id, g.state);
    IF board_empty AND required_slot IS NOT NULL THEN
      UPDATE public.domino_games SET state = g.state, turn_skips = g.turn_skips,
        current_turn = required_slot,
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
      RETURN;
    END IF;
  ELSE
    g.turn_skips := jsonb_set(COALESCE(g.turn_skips,'{}'::jsonb), ARRAY[cur_uid::text], to_jsonb(_skips), true);

    -- FIX: was missing state = g.state, losing dead_tiles on vato_maty
    IF board_empty AND required_slot IS NOT NULL THEN
      UPDATE public.domino_games SET state = g.state, turn_skips = g.turn_skips,
        current_turn = required_slot,
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
      RETURN;
    END IF;
  END IF;

  -- Advance to next player
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

-- Add dead tile check to domino_play
CREATE OR REPLACE FUNCTION public.domino_play(_game_id uuid, _move jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  g record; my_slot int; st jsonb; hand jsonb; tile jsonb;
  a int; b int; le int; re int; side text;
  new_left int; new_right int; action text; next_turn int;
  drawn jsonb; stock jsonb; found boolean := false; new_hand jsonb; i int;
  _cfg record;
  has_playable boolean := false;
  draw_mode text;
  is_first_move boolean;
  first_dbl int;
  matches_left boolean;
  matches_right boolean;
  winner_slot int;
  v_rule text;
  _fti int;
  found_i int := -1;
  v_dead_tiles jsonb;
  is_dead boolean;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  IF (g.state->>'phase') IN ('break','reveal') THEN RAISE EXCEPTION 'round break'; END IF;

  SELECT slot INTO my_slot FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid AND forfeited = false;
  IF my_slot IS NULL OR my_slot <> g.current_turn THEN RAISE EXCEPTION 'not your turn'; END IF;

  st := g.state;
  action := _move->>'action';
  hand := COALESCE(st -> 'hands' -> my_slot::text, '[]'::jsonb);
  stock := COALESCE(st -> 'stock','[]'::jsonb);
  le := NULLIF(st->>'left_end','null')::int;
  re := NULLIF(st->>'right_end','null')::int;
  draw_mode := COALESCE(st->>'draw_mode','with');
  v_rule := COALESCE(st->>'first_tile_rule','libre');
  _fti := COALESCE((st->>'first_tile_idx')::int, 0);
  SELECT * INTO _cfg FROM public._game_cfg('domino');
  is_first_move := jsonb_array_length(COALESCE(st->'board','[]'::jsonb)) = 0;
  has_playable := public._domino_slot_has_playable(st, my_slot);

  IF action = 'draw' THEN
    IF draw_mode = 'without' THEN RAISE EXCEPTION 'draw disabled in this game'; END IF;
    IF has_playable THEN RAISE EXCEPTION 'you have a playable tile'; END IF;
    IF jsonb_array_length(stock) = 0 THEN RAISE EXCEPTION 'stock empty'; END IF;
    drawn := stock -> 0; stock := stock - 0;
    hand := hand || jsonb_build_array(drawn);
    st := jsonb_set(st, ARRAY['hands', my_slot::text], hand);
    st := jsonb_set(st, '{stock}', stock);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    RETURN;
  END IF;

  IF action = 'pass' THEN
    IF has_playable THEN RAISE EXCEPTION 'you must play'; END IF;
    IF draw_mode = 'with' AND jsonb_array_length(stock) > 0 THEN RAISE EXCEPTION 'you must draw first'; END IF;

    st := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1));
    next_turn := public._domino_next_playable_slot(_game_id, my_slot, st);

    IF next_turn IS NULL THEN
      winner_slot := public._domino_lowest_pip_slot(_game_id, st);
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
      IF winner_slot IS NOT NULL THEN
        PERFORM public._domino_end_round(_game_id, winner_slot);
      END IF;
      RETURN;
    END IF;

    UPDATE public.domino_games SET state = st, current_turn = next_turn,
      turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
    RETURN;
  END IF;

  tile := _move -> 'tile';
  side := _move->>'side';
  a := (tile->>0)::int; b := (tile->>1)::int;

  -- Find the tile in hand, tracking the index
  new_hand := '[]'::jsonb;
  FOR i IN 0..jsonb_array_length(hand)-1 LOOP
    IF NOT found AND ((hand->i->>0)::int = a AND (hand->i->>1)::int = b) THEN
      found := true;
      found_i := i;
    ELSE
      new_hand := new_hand || jsonb_build_array(hand->i);
    END IF;
  END LOOP;
  IF NOT found THEN RAISE EXCEPTION 'tile not in hand'; END IF;

  -- VATO MATY: Check if this tile is dead (vato maty)
  v_dead_tiles := COALESCE(st->'dead_tiles'->my_slot::text, '[]'::jsonb);
  is_dead := false;
  IF jsonb_array_length(v_dead_tiles) > 0 THEN
    FOR i IN 0..jsonb_array_length(v_dead_tiles)-1 LOOP
      IF (v_dead_tiles->i)::int = found_i THEN
        is_dead := true;
        EXIT;
      END IF;
    END LOOP;
  END IF;
  IF is_dead THEN
    RAISE EXCEPTION 'Vato maty: ce domino est mort et ne peut plus etre joue';
  END IF;

  IF is_first_move THEN
    first_dbl := NULLIF(st->>'first_move_double','null')::int;
    IF first_dbl IS NOT NULL THEN
      IF NOT (a = first_dbl AND b = first_dbl) THEN
        RAISE EXCEPTION 'first move must be the highest double (%-%)', first_dbl, first_dbl;
      END IF;
    ELSIF v_rule = 'under6' THEN
      IF (a + b) >= 6 THEN
        RAISE EXCEPTION '1er domino doit avoir un total < 6';
      END IF;
    END IF;
    st := jsonb_set(st, '{board}', jsonb_build_array(jsonb_build_object('tile', tile, 'flipped', false)));
    new_left := a; new_right := b;
    _fti := 0;
  ELSE
    matches_left := (a = le OR b = le);
    matches_right := (a = re OR b = re);
    IF side IS NULL OR side NOT IN ('left','right')
       OR (side = 'left' AND NOT matches_left)
       OR (side = 'right' AND NOT matches_right) THEN
      IF matches_right THEN side := 'right';
      ELSIF matches_left THEN side := 'left';
      ELSE RAISE EXCEPTION 'tile does not match either end'; END IF;
    END IF;

    IF side = 'left' THEN
      IF a = le THEN new_left := b; ELSE new_left := a; END IF;
      st := jsonb_set(st, '{board}', jsonb_build_array(jsonb_build_object('tile', tile, 'flipped', a<>le)) || (st->'board'));
      new_right := re;
      _fti := _fti + 1;
    ELSE
      IF a = re THEN new_right := b; ELSE new_right := a; END IF;
      st := jsonb_set(st, '{board}', (st->'board') || jsonb_build_array(jsonb_build_object('tile', tile, 'flipped', a=re AND a<>b)));
      new_left := le;
    END IF;
  END IF;

  st := jsonb_set(st, ARRAY['hands', my_slot::text], new_hand);
  st := jsonb_set(st, '{left_end}', to_jsonb(new_left));
  st := jsonb_set(st, '{right_end}', to_jsonb::jsonb);
  st := jsonb_set(st, '{passes}', to_jsonb(0));
  st := jsonb_set(st, '{first_move_double}', 'null'::jsonb);
  st := jsonb_set(st, '{first_tile_idx}', to_jsonb(_fti));

  IF jsonb_array_length(new_hand) = 0 THEN
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_end_round(_game_id, my_slot);
    RETURN;
  END IF;

  next_turn := public._domino_next_playable_slot(_game_id, my_slot, st);
  IF next_turn IS NULL THEN
    winner_slot := public._domino_lowest_pip_slot(_game_id, st);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    IF winner_slot IS NOT NULL THEN
      PERFORM public._domino_end_round(_game_id, winner_slot);
    END IF;
    RETURN;
  END IF;

  UPDATE public.domino_games SET state = st, current_turn = next_turn,
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
  RETURN;
END;
$$;

-- Cleanup
DROP TABLE IF EXISTS _debug_vato;
DELETE FROM public.domino_participants WHERE game_id = 'aaaaaaaa-0000-0000-0000-000000000001';
DELETE FROM public.domino_games WHERE id = 'aaaaaaaa-0000-0000-0000-000000000001';
