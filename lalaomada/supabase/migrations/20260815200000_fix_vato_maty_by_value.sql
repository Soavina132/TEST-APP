-- Fix vato maty: store dead tiles by VALUE not index
-- When tiles are played, indices shift and the dead tile check breaks

-- 1. Fix _domino_playable_tiles: check dead by tile value
CREATE OR REPLACE FUNCTION public._domino_playable_tiles(_state jsonb, _slot integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $func$
DECLARE
  hand jsonb; board jsonb; left_end INT; right_end INT;
  i INT; j INT; tile jsonb; a INT; b INT;
  result jsonb := '[]'::jsonb;
  first_move_double INT; first_tile_rule TEXT; board_len INT;
  dead_tiles jsonb; is_dead boolean;
BEGIN
  hand := _state->'hands'->_slot::text;
  board := _state->'board';
  IF hand IS NULL THEN RETURN '[]'::jsonb; END IF;
  dead_tiles := COALESCE(_state->'dead_tiles'->_slot::text, '[]'::jsonb);
  board_len := COALESCE(jsonb_array_length(board), 0);
  left_end := NULLIF(_state->>'left_end','')::INT;
  right_end := NULLIF(_state->>'right_end','')::INT;
  first_move_double := NULLIF(_state->>'first_move_double','null')::INT;
  first_tile_rule := COALESCE(_state->>'first_tile_rule', 'libre');
  FOR i IN 0..jsonb_array_length(hand)-1 LOOP
    tile := hand->i;
    is_dead := false;
    FOR j IN 0..jsonb_array_length(dead_tiles)-1 LOOP
      IF (dead_tiles->j->>0)::INT = (tile->>0)::INT AND (dead_tiles->j->>1)::INT = (tile->>1)::INT THEN
        is_dead := true; EXIT;
      END IF;
    END LOOP;
    IF is_dead THEN CONTINUE; END IF;
    a := (tile->>0)::INT; b := (tile->>1)::INT;
    IF board_len = 0 THEN
      IF first_move_double IS NOT NULL THEN
        IF a = first_move_double AND b = first_move_double THEN result := result || to_jsonb(i); END IF;
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
END;
$func$;

-- 2. Fix _domino_required_starter_slot: skip dead tiles
CREATE OR REPLACE FUNCTION public._domino_required_starter_slot(_game_id uuid, _state jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $func$
DECLARE
  first_dbl integer; p record; t jsonb; dead_tiles jsonb; is_dead boolean; j INT;
BEGIN
  IF jsonb_array_length(COALESCE(_state->'board', '[]'::jsonb)) > 0 THEN RETURN NULL; END IF;
  first_dbl := NULLIF(_state->>'first_move_double', 'null')::integer;
  IF first_dbl IS NULL THEN RETURN NULL; END IF;
  FOR p IN SELECT slot FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
    dead_tiles := COALESCE(_state->'dead_tiles'->p.slot::text, '[]'::jsonb);
    FOR t IN SELECT * FROM jsonb_array_elements(COALESCE(_state->'hands'->p.slot::text, '[]'::jsonb)) LOOP
      IF (t->>0)::integer = first_dbl AND (t->>1)::integer = first_dbl THEN
        is_dead := false;
        FOR j IN 0..jsonb_array_length(dead_tiles)-1 LOOP
          IF (dead_tiles->j->>0)::integer = (t->>0)::integer AND (dead_tiles->j->>1)::integer = (t->>1)::integer THEN
            is_dead := true; EXIT;
          END IF;
        END LOOP;
        IF NOT is_dead THEN RETURN p.slot; END IF;
      END IF;
    END LOOP;
  END LOOP;
  RETURN NULL;
END;
$func$;

-- 3. New function: find next highest double excluding dead tiles
CREATE OR REPLACE FUNCTION public._domino_find_next_double(_game_id uuid, _state jsonb, _exclude_dbl integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $func$
DECLARE
  p record; t jsonb; a INT; b INT; dead_tiles jsonb; is_dead boolean; j INT;
  best_dbl INT := -1; best_slot INT;
BEGIN
  FOR p IN SELECT slot FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
    dead_tiles := COALESCE(_state->'dead_tiles'->p.slot::text, '[]'::jsonb);
    FOR t IN SELECT * FROM jsonb_array_elements(COALESCE(_state->'hands'->p.slot::text, '[]'::jsonb)) LOOP
      a := (t->>0)::integer; b := (t->>1)::integer;
      IF a = b AND a > best_dbl AND a < _exclude_dbl THEN
        is_dead := false;
        FOR j IN 0..jsonb_array_length(dead_tiles)-1 LOOP
          IF (dead_tiles->j->>0)::integer = a AND (dead_tiles->j->>1)::integer = b THEN is_dead := true; EXIT; END IF;
        END LOOP;
        IF NOT is_dead THEN best_dbl := a; best_slot := p.slot; END IF;
      END IF;
    END LOOP;
  END LOOP;
  IF best_dbl >= 0 THEN RETURN jsonb_build_object('double', best_dbl, 'slot', best_slot); END IF;
  RETURN NULL;
END;
$func$;

-- 4. Fix domino_tick: store dead tiles by VALUE, handle first move specially
CREATE OR REPLACE FUNCTION public.domino_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $func$
DECLARE
  g record; cur_uid uuid; _cfg record; _skips int; _next int;
  remaining int; last_slot int;
  _break_until timestamptz; _reveal_until timestamptz; _deal_until timestamptz;
  required_slot int; board_empty boolean;
  _bot_think timestamptz; v_is_bot boolean := false;
  v_playable jsonb; v_dead_tiles jsonb; v_dead_obj jsonb;
  v_tile_idx int; v_tile_val jsonb; i int; j int;
  v_next_dbl jsonb; first_dbl int; is_dead boolean;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;
  IF (g.state->>'phase') = 'dealing' THEN
    _deal_until := NULLIF(g.state->>'deal_until','')::timestamptz;
    IF _deal_until IS NOT NULL AND _deal_until <= now() THEN PERFORM public._domino_deal_hands(_game_id); END IF;
    RETURN;
  END IF;
  IF (g.state->>'phase') = 'reveal' THEN
    _reveal_until := NULLIF(g.state->>'reveal_until','')::timestamptz;
    IF _reveal_until IS NOT NULL AND _reveal_until <= now() THEN PERFORM public._domino_start_play(_game_id); END IF;
    RETURN;
  END IF;
  IF (g.state->>'phase') = 'break' THEN
    _break_until := NULLIF(g.state->>'break_until','')::timestamptz;
    IF _break_until IS NOT NULL AND _break_until <= now() THEN PERFORM public._domino_start_round(_game_id); END IF;
    RETURN;
  END IF;
  SELECT * INTO _cfg FROM public._game_cfg('domino');
  board_empty := jsonb_array_length(COALESCE(g.state->'board', '[]'::jsonb)) = 0;
  required_slot := public._domino_required_starter_slot(_game_id, g.state);
  IF board_empty AND required_slot IS NOT NULL AND required_slot <> g.current_turn THEN
    UPDATE public.domino_games SET current_turn = required_slot,
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
    RETURN;
  END IF;
  _bot_think := NULLIF(g.state->>'bot_think_until', '')::timestamptz;
  IF _bot_think IS NOT NULL AND _bot_think <= now() THEN PERFORM public._domino_bot_step(_game_id); RETURN; END IF;
  IF _bot_think IS NULL THEN
    SELECT COALESCE(dp.is_bot, false) INTO v_is_bot FROM public.domino_participants dp
     WHERE dp.game_id = _game_id AND dp.slot = g.current_turn AND dp.forfeited = false;
    IF v_is_bot THEN PERFORM public._domino_bot_step(_game_id); RETURN; END IF;
  END IF;
  IF g.turn_deadline IS NULL OR g.turn_deadline > now() THEN RETURN; END IF;
  SELECT COALESCE(dp.is_bot, false), dp.user_id INTO v_is_bot, cur_uid
    FROM public.domino_participants dp WHERE dp.game_id = _game_id AND dp.slot = g.current_turn AND dp.forfeited = false;
  IF NOT FOUND THEN
    _next := public._domino_next_playable_slot(_game_id, g.current_turn, g.state);
    IF _next IS NULL THEN PERFORM public._domino_end_round(_game_id, NULL);
    ELSE UPDATE public.domino_games SET current_turn = _next, turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id; END IF;
    RETURN;
  END IF;
  IF v_is_bot THEN PERFORM public._domino_bot_step(_game_id); RETURN; END IF;
  -- VATO MATY
  IF COALESCE(g.vato_maty, false) THEN
    first_dbl := NULLIF(g.state->>'first_move_double', 'null')::int;
    IF board_empty AND first_dbl IS NOT NULL THEN
      -- First move with required double: only mark THAT tile as dead
      v_dead_tiles := COALESCE(g.state->'dead_tiles'->g.current_turn::text, '[]'::jsonb);
      FOR i IN 0..jsonb_array_length(COALESCE(g.state->'hands'->g.current_turn::text, '[]'::jsonb))-1 LOOP
        v_tile_val := g.state->'hands'->g.current_turn::text->i;
        IF (v_tile_val->>0)::int = first_dbl AND (v_tile_val->>1)::int = first_dbl THEN
          is_dead := false;
          FOR j IN 0..jsonb_array_length(v_dead_tiles)-1 LOOP
            IF (v_dead_tiles->j->>0)::int = (v_tile_val->>0)::int AND (v_dead_tiles->j->>1)::int = (v_tile_val->>1)::int THEN is_dead := true; END IF;
          END LOOP;
          IF NOT is_dead THEN v_dead_tiles := v_dead_tiles || jsonb_build_array(v_tile_val); END IF;
        END IF;
      END LOOP;
      v_dead_obj := COALESCE(g.state->'dead_tiles', '{}'::jsonb);
      v_dead_obj := jsonb_set(v_dead_obj, ARRAY[g.current_turn::text], v_dead_tiles, true);
      g.state := jsonb_set(g.state, ARRAY['dead_tiles'], v_dead_obj, true);
      v_next_dbl := public._domino_find_next_double(_game_id, g.state, first_dbl);
      IF v_next_dbl IS NOT NULL THEN
        g.state := jsonb_set(g.state, '{first_move_double}', to_jsonb((v_next_dbl->>'double')::int), true);
        required_slot := (v_next_dbl->>'slot')::int;
      ELSE
        g.state := jsonb_set(g.state, '{first_move_double}', 'null'::jsonb, true);
        required_slot := NULL;
      END IF;
    ELSE
      -- Normal: mark ALL playable tiles as dead
      v_playable := public._domino_playable_tiles(g.state, g.current_turn);
      IF jsonb_array_length(v_playable) > 0 THEN
        v_dead_tiles := COALESCE(g.state->'dead_tiles'->g.current_turn::text, '[]'::jsonb);
        FOR i IN 0..jsonb_array_length(v_playable)-1 LOOP
          v_tile_idx := (v_playable->i)::int;
          v_tile_val := g.state->'hands'->g.current_turn::text->v_tile_idx;
          is_dead := false;
          FOR j IN 0..jsonb_array_length(v_dead_tiles)-1 LOOP
            IF (v_dead_tiles->j->>0)::int = (v_tile_val->>0)::int AND (v_dead_tiles->j->>1)::int = (v_tile_val->>1)::int THEN is_dead := true; END IF;
          END LOOP;
          IF NOT is_dead THEN v_dead_tiles := v_dead_tiles || jsonb_build_array(v_tile_val); END IF;
        END LOOP;
        v_dead_obj := COALESCE(g.state->'dead_tiles', '{}'::jsonb);
        v_dead_obj := jsonb_set(v_dead_obj, ARRAY[g.current_turn::text], v_dead_tiles, true);
        g.state := jsonb_set(g.state, ARRAY['dead_tiles'], v_dead_obj, true);
      END IF;
    END IF;
  END IF;
  -- Skip/forfeit
  _skips := COALESCE((g.turn_skips->>cur_uid::text)::int, 0) + 1;
  IF _skips >= COALESCE(_cfg.max_turn_skips, 3) THEN
    UPDATE public.domino_participants SET forfeited = true WHERE game_id = _game_id AND user_id = cur_uid;
    SELECT count(*) INTO remaining FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
    IF remaining <= 1 THEN
      SELECT slot INTO last_slot FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false LIMIT 1;
      IF last_slot IS NOT NULL THEN PERFORM public._domino_finalize(_game_id, last_slot);
      ELSE UPDATE public.domino_games SET status = 'cancelled', finished_at = now() WHERE id = _game_id; END IF;
      RETURN;
    END IF;
    g.turn_skips := jsonb_set(COALESCE(g.turn_skips,'{}'::jsonb), ARRAY[cur_uid::text], to_jsonb(_skips), true);
    g.state := jsonb_set(g.state, ARRAY['hands', g.current_turn::text], '[]'::jsonb, true);
    required_slot := public._domino_required_starter_slot(_game_id, g.state);
    IF board_empty AND required_slot IS NOT NULL THEN
      UPDATE public.domino_games SET state = g.state, turn_skips = g.turn_skips, current_turn = required_slot,
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id; RETURN;
    END IF;
  ELSE
    g.turn_skips := jsonb_set(COALESCE(g.turn_skips,'{}'::jsonb), ARRAY[cur_uid::text], to_jsonb(_skips), true);
    IF board_empty AND required_slot IS NOT NULL THEN
      UPDATE public.domino_games SET state = g.state, turn_skips = g.turn_skips, current_turn = required_slot,
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id; RETURN;
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
$func$;

-- 5. Fix domino_play: check dead tiles by VALUE
CREATE OR REPLACE FUNCTION public.domino_play(_game_id uuid, _move jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $func$
DECLARE
  v_uid uuid := auth.uid();
  g record; my_slot int; st jsonb; hand jsonb; tile jsonb;
  a int; b int; le int; re int; side text;
  new_left int; new_right int; action text; next_turn int;
  drawn jsonb; stock jsonb; found boolean := false; new_hand jsonb; i int;
  _cfg record; has_playable boolean := false; draw_mode text;
  is_first_move boolean; first_dbl int;
  matches_left boolean; matches_right boolean; winner_slot int;
  v_rule text; _fti int; v_dead_tiles jsonb; is_dead boolean;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  IF (g.state->>'phase') IN ('break','reveal') THEN RAISE EXCEPTION 'round break'; END IF;
  SELECT slot INTO my_slot FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid AND forfeited = false;
  IF my_slot IS NULL OR my_slot <> g.current_turn THEN RAISE EXCEPTION 'not your turn'; END IF;
  st := g.state; action := _move->>'action';
  hand := COALESCE(st -> 'hands' -> my_slot::text, '[]'::jsonb);
  stock := COALESCE(st -> 'stock','[]'::jsonb);
  le := NULLIF(st->>'left_end','null')::int; re := NULLIF(st->>'right_end','null')::int;
  draw_mode := COALESCE(st->>'draw_mode','with'); v_rule := COALESCE(st->>'first_tile_rule','libre');
  _fti := COALESCE((st->>'first_tile_idx')::int, 0);
  SELECT * INTO _cfg FROM public._game_cfg('domino');
  is_first_move := jsonb_array_length(COALESCE(st->'board','[]'::jsonb)) = 0;
  has_playable := public._domino_slot_has_playable(st, my_slot);
  IF action = 'draw' THEN
    IF draw_mode = 'without' THEN RAISE EXCEPTION 'draw disabled'; END IF;
    IF has_playable THEN RAISE EXCEPTION 'you have a playable tile'; END IF;
    IF jsonb_array_length(stock) = 0 THEN RAISE EXCEPTION 'stock empty'; END IF;
    drawn := stock -> 0; stock := stock - 0; hand := hand || jsonb_build_array(drawn);
    st := jsonb_set(st, ARRAY['hands', my_slot::text], hand); st := jsonb_set(st, '{stock}', stock);
    UPDATE public.domino_games SET state = st WHERE id = _game_id; RETURN;
  END IF;
  IF action = 'pass' THEN
    IF has_playable THEN RAISE EXCEPTION 'you must play'; END IF;
    IF draw_mode = 'with' AND jsonb_array_length(stock) > 0 THEN RAISE EXCEPTION 'you must draw first'; END IF;
    st := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1));
    next_turn := public._domino_next_playable_slot(_game_id, my_slot, st);
    IF next_turn IS NULL THEN
      winner_slot := public._domino_lowest_pip_slot(_game_id, st);
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
      IF winner_slot IS NOT NULL THEN PERFORM public._domino_end_round(_game_id, winner_slot); END IF;
      RETURN;
    END IF;
    UPDATE public.domino_games SET state = st, current_turn = next_turn,
      turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id; RETURN;
  END IF;
  tile := _move -> 'tile'; side := _move->>'side'; a := (tile->>0)::int; b := (tile->>1)::int;
  -- VATO MATY: check dead by VALUE
  v_dead_tiles := COALESCE(st->'dead_tiles'->my_slot::text, '[]'::jsonb);
  is_dead := false;
  IF jsonb_array_length(v_dead_tiles) > 0 THEN
    FOR i IN 0..jsonb_array_length(v_dead_tiles)-1 LOOP
      IF (v_dead_tiles->i->>0)::int = a AND (v_dead_tiles->i->>1)::int = b THEN is_dead := true; EXIT; END IF;
    END LOOP;
  END IF;
  IF is_dead THEN RAISE EXCEPTION 'Vato maty: ce domino est mort'; END IF;
  new_hand := '[]'::jsonb;
  FOR i IN 0..jsonb_array_length(hand)-1 LOOP
    IF NOT found AND ((hand->i->>0)::int = a AND (hand->i->>1)::int = b) THEN found := true;
    ELSE new_hand := new_hand || jsonb_build_array(hand->i); END IF;
  END LOOP;
  IF NOT found THEN RAISE EXCEPTION 'tile not in hand'; END IF;
  IF is_first_move THEN
    first_dbl := NULLIF(st->>'first_move_double','null')::int;
    IF first_dbl IS NOT NULL THEN
      IF NOT (a = first_dbl AND b = first_dbl) THEN RAISE EXCEPTION 'first move must be the highest double (%-%)', first_dbl, first_dbl; END IF;
    ELSIF v_rule = 'under6' THEN
      IF (a + b) >= 6 THEN RAISE EXCEPTION '1er domino doit avoir un total < 6'; END IF;
    END IF;
    st := jsonb_set(st, '{board}', jsonb_build_array(jsonb_build_object('tile', tile, 'flipped', false)));
    new_left := a; new_right := b; _fti := 0;
  ELSE
    matches_left := (a = le OR b = le); matches_right := (a = re OR b = re);
    IF side IS NULL OR side NOT IN ('left','right') OR (side = 'left' AND NOT matches_left) OR (side = 'right' AND NOT matches_right) THEN
      IF matches_right THEN side := 'right'; ELSIF matches_left THEN side := 'left';
      ELSE RAISE EXCEPTION 'tile does not match either end'; END IF;
    END IF;
    IF side = 'left' THEN
      IF a = le THEN new_left := b; ELSE new_left := a; END IF;
      st := jsonb_set(st, '{board}', jsonb_build_array(jsonb_build_object('tile', tile, 'flipped', a<>le)) || (st->'board'));
      new_right := re; _fti := _fti + 1;
    ELSE
      IF a = re THEN new_right := b; ELSE new_right := a; END IF;
      st := jsonb_set(st, '{board}', (st->'board') || jsonb_build_array(jsonb_build_object('tile', tile, 'flipped', a=re AND a<>b)));
      new_left := le;
    END IF;
  END IF;
  st := jsonb_set(st, ARRAY['hands', my_slot::text], new_hand);
  st := jsonb_set(st, '{left_end}', to_jsonb(new_left));
  st := jsonb_set(st, '{right_end}', to_jsonb(new_right));
  st := jsonb_set(st, '{passes}', to_jsonb(0));
  st := jsonb_set(st, '{first_move_double}', 'null'::jsonb);
  st := jsonb_set(st, '{first_tile_idx}', to_jsonb(_fti));
  IF jsonb_array_length(new_hand) = 0 THEN
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_end_round(_game_id, my_slot); RETURN;
  END IF;
  next_turn := public._domino_next_playable_slot(_game_id, my_slot, st);
  IF next_turn IS NULL THEN
    winner_slot := public._domino_lowest_pip_slot(_game_id, st);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    IF winner_slot IS NOT NULL THEN PERFORM public._domino_end_round(_game_id, winner_slot); END IF;
    RETURN;
  END IF;
  UPDATE public.domino_games SET state = st, current_turn = next_turn,
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
END;
$func$;
