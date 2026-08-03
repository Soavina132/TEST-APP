-- Fix domino bot: immediate play (no think timer), correct first-move handling
-- DROP duplicate functions, replace with clean versions

-- 1. Drop the 2-param version (wrong board format, no first-move handling)
DROP FUNCTION IF EXISTS public._domino_bot_step(uuid, integer);

-- 2. Drop the old 1-param _domino_autoplay_bots (was replaced by no-arg version)
DROP FUNCTION IF EXISTS public._domino_autoplay_bots(uuid);

-- 3. Drop old _domino_arm_bot_think (no longer needed — no think timer)
DROP FUNCTION IF EXISTS public._domino_arm_bot_think(uuid, integer, jsonb);

-- 4. Replace _domino_bot_step(uuid) with immediate-play logic
--    Keeps the same board format (objects with tile+flipped) and first-move rules
CREATE OR REPLACE FUNCTION public._domino_bot_step(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  g record;
  st jsonb;
  v_slot int;
  hand jsonb;
  le int;
  re int;
  draw_mode text;
  is_first_move boolean;
  first_dbl int;
  v_rule text;
  i int;
  j int;
  a int;
  b int;
  tile jsonb;
  placed jsonb;
  found boolean;
  found_i int;
  new_hand jsonb;
  new_left int;
  new_right int;
  next_turn int;
  winner_slot int;
  stock jsonb;
  drawn jsonb;
  _cfg record;
  v_is_bot boolean;
  phase text;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

  st := g.state;
  phase := COALESCE(st->>'phase', 'play');
  IF phase NOT IN ('play','playing') THEN RETURN; END IF;

  v_slot := g.current_turn;
  SELECT COALESCE(dp.is_bot, false) INTO v_is_bot
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id
     AND dp.slot = v_slot
     AND dp.forfeited = false;

  IF NOT COALESCE(v_is_bot, false) THEN RETURN; END IF;

  -- No think timer — play immediately

  hand := COALESCE(st->'hands'->v_slot::text, '[]'::jsonb);
  le := NULLIF(st->>'left_end', 'null')::int;
  re := NULLIF(st->>'right_end', 'null')::int;
  draw_mode := COALESCE(st->>'draw_mode', 'with');
  v_rule := COALESCE(st->>'first_tile_rule', 'libre');
  is_first_move := jsonb_array_length(COALESCE(st->'board', '[]'::jsonb)) = 0;
  first_dbl := NULLIF(st->>'first_move_double', 'null')::int;
  SELECT * INTO _cfg FROM public._game_cfg('domino');

  -- Find a playable tile
  found := false;
  found_i := -1;

  IF jsonb_array_length(hand) > 0 THEN
    FOR i IN 0..jsonb_array_length(hand)-1 LOOP
      a := (hand->i->>0)::int;
      b := (hand->i->>1)::int;
      IF is_first_move THEN
        -- First move: handle special rules
        IF first_dbl IS NOT NULL THEN
          IF a = first_dbl AND b = first_dbl THEN found := true; found_i := i; EXIT; END IF;
        ELSIF v_rule = 'under6' THEN
          IF (a + b) < 6 THEN found := true; found_i := i; EXIT; END IF;
        ELSE
          -- Libre: any tile is playable
          found := true; found_i := i; EXIT;
        END IF;
      ELSE
        -- Normal move: match left or right end
        IF a = le OR b = le OR a = re OR b = re THEN found := true; found_i := i; EXIT; END IF;
      END IF;
    END LOOP;
  END IF;

  IF found THEN
    tile := hand->found_i;
    a := (tile->>0)::int;
    b := (tile->>1)::int;

    -- Remove tile from hand
    new_hand := '[]'::jsonb;
    FOR j IN 0..jsonb_array_length(hand)-1 LOOP
      IF j <> found_i THEN new_hand := new_hand || jsonb_build_array(hand->j); END IF;
    END LOOP;

    IF is_first_move THEN
      placed := jsonb_build_array(a, b);
      st := jsonb_set(st, '{board}', jsonb_build_array(jsonb_build_object('tile', placed, 'flipped', false)), true);
      new_left := a;
      new_right := b;
    ELSE
      IF a = re OR b = re THEN
        -- Place on right side
        IF a = re THEN
          placed := jsonb_build_array(a, b);
          new_right := b;
        ELSE
          placed := jsonb_build_array(b, a);
          new_right := a;
        END IF;
        new_left := le;
        st := jsonb_set(st, '{board}', COALESCE(st->'board','[]'::jsonb) || jsonb_build_array(jsonb_build_object('tile', placed, 'flipped', false)), true);
      ELSE
        -- Place on left side
        IF a = le THEN
          placed := jsonb_build_array(b, a);
          new_left := b;
        ELSE
          placed := jsonb_build_array(a, b);
          new_left := a;
        END IF;
        new_right := re;
        st := jsonb_set(st, '{board}', jsonb_build_array(jsonb_build_object('tile', placed, 'flipped', false)) || COALESCE(st->'board','[]'::jsonb), true);
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
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
      PERFORM public._domino_end_round(_game_id, v_slot);
      RETURN;
    END IF;

    next_turn := public._domino_next_playable_slot(_game_id, v_slot, st);
    IF next_turn IS NULL THEN
      winner_slot := public._domino_lowest_pip_slot(_game_id, st);
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
      PERFORM public._domino_end_round(_game_id, winner_slot);
      RETURN;
    END IF;

    st := st - 'bot_think_until' - 'bot_locked_slot';

    UPDATE public.domino_games
       SET state = st,
           current_turn = next_turn,
           turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
     WHERE id = _game_id;

    -- Chain to next bot if needed
    PERFORM public._domino_autoplay_bots();
    RETURN;
  END IF;

  -- No playable tile: draw from stock if allowed
  stock := COALESCE(st->'stock', '[]'::jsonb);
  IF draw_mode = 'with' AND jsonb_array_length(stock) > 0 THEN
    drawn := stock -> 0;
    hand := hand || jsonb_build_array(drawn);
    stock := stock - 0;
    st := jsonb_set(st, ARRAY['hands', v_slot::text], hand, true);
    st := jsonb_set(st, '{stock}', stock, true);
    st := st - 'bot_think_until' - 'bot_locked_slot';
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    -- Re-check if drawn tile is playable (recursive call)
    PERFORM public._domino_bot_step(_game_id);
    RETURN;
  END IF;

  -- Pass
  st := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1), true);
  st := jsonb_set(st, '{last_pass_by}', to_jsonb(v_slot), true);
  st := st - 'bot_think_until' - 'bot_locked_slot';
  next_turn := public._domino_next_playable_slot(_game_id, v_slot, st);

  IF next_turn IS NULL THEN
    winner_slot := public._domino_lowest_pip_slot(_game_id, st);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_end_round(_game_id, winner_slot);
    RETURN;
  END IF;

  UPDATE public.domino_games
     SET state = st,
         current_turn = next_turn,
         turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
   WHERE id = _game_id;

  -- Chain to next bot if needed
  PERFORM public._domino_autoplay_bots();
END;
$function$;

-- 5. Replace _domino_autoplay_bots() (no args) to call 1-param version
CREATE OR REPLACE FUNCTION public._domino_autoplay_bots()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  g record; attempts int := 0;
BEGIN
  WHILE attempts < 10 LOOP
    SELECT dg.id INTO g
      FROM public.domino_games dg
      JOIN public.domino_participants dp ON dp.game_id = dg.id
     WHERE dg.status = 'playing' AND dp.is_bot = true AND dg.current_turn = dp.slot
       AND dp.forfeited = false
     LIMIT 1;
    EXIT WHEN g.id IS NULL;
    BEGIN
      PERFORM public._domino_bot_step(g.id);
    EXCEPTION WHEN OTHERS THEN
      EXIT;
    END;
    attempts := attempts + 1;
  END LOOP;
END;
$function$;

-- 6. Update domino_tick to call 1-param _domino_bot_step
CREATE OR REPLACE FUNCTION public.domino_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  g record; st jsonb; _cfg record;
  _deal_until timestamptz; _reveal_until timestamptz; _break_until timestamptz;
  v_is_bot boolean; v_hand jsonb;
  v_left int; v_right int; v_draw_mode text; v_stock jsonb;
  v_next int; v_n int; v_a int; v_b int;
  v_can_play boolean; v_new_tile jsonb;
  ps record; anyone boolean;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;
  st := g.state;

  IF st->>'phase' = 'dealing' THEN
    _deal_until := NULLIF(st->>'deal_until', '')::timestamptz;
    IF _deal_until IS NOT NULL AND _deal_until <= now() THEN
      st := jsonb_set(st, '{phase}', '"playing"'::jsonb);
      SELECT * INTO _cfg FROM public._game_cfg('domino');
      UPDATE public.domino_games
         SET state = st,
             turn_deadline = now() + make_interval(secs => COALESCE(_cfg.turn_timer_seconds, 60))
       WHERE id = _game_id;
      PERFORM public._domino_autoplay_bots();
    END IF;
    RETURN;
  END IF;

  IF st->>'phase' = 'reveal' THEN
    _reveal_until := NULLIF(st->>'reveal_until', '')::timestamptz;
    IF _reveal_until IS NOT NULL AND _reveal_until <= now() THEN
      st := jsonb_set(st, '{phase}', '"break"'::jsonb);
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;

  IF st->>'phase' = 'break' THEN
    _break_until := NULLIF(st->>'break_until', '')::timestamptz;
    IF _break_until IS NOT NULL AND _break_until <= now() THEN
      PERFORM public._domino_next_round(_game_id);
    END IF;
    RETURN;
  END IF;

  IF st->>'phase' <> 'playing' THEN RETURN; END IF;

  -- Bot plays immediately (no think timer)
  IF g.turn_deadline IS NULL OR g.turn_deadline > now() THEN
    PERFORM public._domino_autoplay_bots();
    RETURN;
  END IF;

  SELECT is_bot INTO v_is_bot
    FROM public.domino_participants
   WHERE game_id = _game_id AND slot = g.current_turn;

  IF v_is_bot THEN
    PERFORM public._domino_bot_step(_game_id);
    RETURN;
  END IF;

  -- Human timeout: auto-draw or auto-pass
  v_hand := st->'hands'->(g.current_turn::text);
  v_left := (st->>'left_end')::int;
  v_right := (st->>'right_end')::int;
  v_draw_mode := COALESCE(st->>'draw_mode', g.draw_mode, 'with');
  v_stock := st->'stock';
  v_can_play := public._domino_slot_has_playable(v_hand, v_left, v_right);

  IF NOT v_can_play AND v_draw_mode = 'with' AND jsonb_array_length(v_stock) > 0 THEN
    WHILE jsonb_array_length(v_stock) > 0 LOOP
      v_new_tile := v_stock->0;
      v_stock := v_stock - 0;
      v_hand := v_hand || jsonb_build_array(v_new_tile);
      v_a := (v_new_tile->>0)::int; v_b := (v_new_tile->>1)::int;
      IF v_a = v_left OR v_b = v_left OR v_a = v_right OR v_b = v_right THEN
        v_can_play := true; EXIT;
      END IF;
    END LOOP;
    st := st || jsonb_build_object(
      'hands', jsonb_set(st->'hands', ARRAY[g.current_turn::text], v_hand), 'stock', v_stock
    );
  END IF;

  v_n := g.max_players;
  v_next := (g.current_turn + 1) % v_n;

  IF NOT v_can_play THEN
    st := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1));
    IF (st->>'passes')::int >= v_n THEN
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
      PERFORM public._domino_end_round(_game_id, NULL);
      RETURN;
    END IF;
    IF v_draw_mode = 'without' OR jsonb_array_length(v_stock) = 0 THEN
      anyone := false;
      FOR ps IN SELECT * FROM public.domino_participants WHERE game_id = _game_id LOOP
        IF public._domino_slot_has_playable(st->'hands'->(ps.slot::text), v_left, v_right) THEN
          anyone := true; EXIT;
        END IF;
      END LOOP;
      IF NOT anyone THEN
        UPDATE public.domino_games SET state = st WHERE id = _game_id;
        PERFORM public._domino_end_round(_game_id, NULL);
        RETURN;
      END IF;
    END IF;
  END IF;

  SELECT * INTO _cfg FROM public._game_cfg('domino');
  UPDATE public.domino_games
     SET state = st, current_turn = v_next,
         turn_deadline = now() + make_interval(secs => COALESCE(_cfg.turn_timer_seconds, 60))
   WHERE id = _game_id;

  PERFORM public._domino_autoplay_bots();
END;
$function$;
