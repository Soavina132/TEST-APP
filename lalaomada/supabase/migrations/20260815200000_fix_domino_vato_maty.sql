-- Fix: _domino_slot_has_playable reads dead_tiles as INDICES but all other
-- functions (domino_tick, domino_play, _domino_playable_tiles, etc.) store
-- dead_tiles as TILE VALUES like [[3,5],[2,4]].
-- This causes a crash when dead_tiles is non-empty, blocking all player actions.

CREATE OR REPLACE FUNCTION public._domino_slot_has_playable(_state jsonb, _slot integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = 'public'
AS $function$
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

  -- Get dead tiles for this slot (stored as TILE VALUES, e.g. [[3,5],[2,4]])
  dead_tiles := COALESCE(_state->'dead_tiles'->_slot::text, '[]'::jsonb);

  IF board_len = 0 THEN
    first_dbl := NULLIF(_state->>'first_move_double', 'null')::integer;
    IF first_dbl IS NOT NULL THEN
      FOR i IN 0..jsonb_array_length(hand)-1 LOOP
        -- Check if tile i is dead (compare by VALUE)
        is_dead := false;
        t := hand->i;
        FOR j IN 0..jsonb_array_length(dead_tiles)-1 LOOP
          IF (dead_tiles->j->>0)::int = (t->>0)::int AND (dead_tiles->j->>1)::int = (t->>1)::int THEN is_dead := true; EXIT; END IF;
        END LOOP;
        IF is_dead THEN CONTINUE; END IF;
        IF (t->>0)::int = first_dbl AND (t->>1)::int = first_dbl THEN RETURN true; END IF;
      END LOOP;
      RETURN false;
    END IF;
    v_rule := COALESCE(_state->>'first_tile_rule','libre');
    IF v_rule = 'under6' THEN
      FOR i IN 0..jsonb_array_length(hand)-1 LOOP
        is_dead := false;
        t := hand->i;
        FOR j IN 0..jsonb_array_length(dead_tiles)-1 LOOP
          IF (dead_tiles->j->>0)::int = (t->>0)::int AND (dead_tiles->j->>1)::int = (t->>1)::int THEN is_dead := true; EXIT; END IF;
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
      t := hand->i;
      FOR j IN 0..jsonb_array_length(dead_tiles)-1 LOOP
        IF (dead_tiles->j->>0)::int = (t->>0)::int AND (dead_tiles->j->>1)::int = (t->>1)::int THEN is_dead := true; EXIT; END IF;
      END LOOP;
      IF NOT is_dead THEN RETURN true; END IF;
    END LOOP;
    RETURN false;
  END IF;

  le := NULLIF(_state->>'left_end', 'null')::integer;
  re := NULLIF(_state->>'right_end', 'null')::integer;
  FOR i IN 0..jsonb_array_length(hand)-1 LOOP
    -- Check if tile i is dead (compare by VALUE)
    is_dead := false;
    t := hand->i;
    FOR j IN 0..jsonb_array_length(dead_tiles)-1 LOOP
      IF (dead_tiles->j->>0)::int = (t->>0)::int AND (dead_tiles->j->>1)::int = (t->>1)::int THEN is_dead := true; EXIT; END IF;
    END LOOP;
    IF is_dead THEN CONTINUE; END IF;
    a := (t->>0)::integer; b := (t->>1)::integer;
    IF a = le OR b = le OR a = re OR b = re THEN RETURN true; END IF;
  END LOOP;
  RETURN false;
END
$function$;

-- Also fix domino_play: the dead tile check only compares [a,b] but tiles
-- can be stored as [b,a]. Add reverse comparison.
CREATE OR REPLACE FUNCTION public.domino_play(_game_id uuid, _move jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = 'public'
AS $function$
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
  -- VATO MATY: check dead by VALUE (handle both [a,b] and [b,a] orientations)
  v_dead_tiles := COALESCE(st->'dead_tiles'->my_slot::text, '[]'::jsonb);
  is_dead := false;
  IF jsonb_array_length(v_dead_tiles) > 0 THEN
    FOR i IN 0..jsonb_array_length(v_dead_tiles)-1 LOOP
      IF ((v_dead_tiles->i->>0)::int = a AND (v_dead_tiles->i->>1)::int = b)
      OR ((v_dead_tiles->i->>0)::int = b AND (v_dead_tiles->i->>1)::int = a) THEN is_dead := true; EXIT; END IF;
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
$function$;
