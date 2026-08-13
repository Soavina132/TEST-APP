-- Track the index of the first tile played (the "center" tile)
-- When a tile is played on the left (prepended to board), first_tile_idx increments
-- When a tile is played on the right (appended), first_tile_idx stays the same

CREATE OR REPLACE FUNCTION public.domino_play(_game_id uuid, _move jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
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
  v_first_tile_idx int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  IF (g.state->>'phase') = 'break' THEN RAISE EXCEPTION 'round break'; END IF;

  SELECT slot INTO my_slot FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid AND forfeited = false;
  IF my_slot IS NULL OR my_slot <> g.current_turn THEN RAISE EXCEPTION 'not your turn'; END IF;

  st := g.state;
  action := _move->>'action';
  hand := COALESCE(st -> 'hands' -> my_slot::text, '[]'::jsonb);
  stock := COALESCE(st -> 'stock','[]'::jsonb);
  le := NULLIF(st->>'left_end','null')::int;
  re := NULLIF(st->>'right_end','null')::int;
  draw_mode := COALESCE(st->>'draw_mode','with');
  SELECT * INTO _cfg FROM public._game_cfg('domino');
  is_first_move := jsonb_array_length(COALESCE(st->'board','[]'::jsonb)) = 0;
  has_playable := public._domino_slot_has_playable(st, my_slot);
  v_first_tile_idx := COALESCE((st->>'first_tile_idx')::int, 0);

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

  new_hand := '[]'::jsonb;
  FOR i IN 0..jsonb_array_length(hand)-1 LOOP
    IF NOT found AND ((hand->i->>0)::int = a AND (hand->i->>1)::int = b) THEN found := true;
    ELSE new_hand := new_hand || jsonb_build_array(hand->i); END IF;
  END LOOP;
  IF NOT found THEN RAISE EXCEPTION 'tile not in hand'; END IF;

  IF is_first_move THEN
    first_dbl := NULLIF(st->>'first_move_double','null')::int;
    IF first_dbl IS NOT NULL THEN
      IF NOT (a = first_dbl AND b = first_dbl) THEN
        RAISE EXCEPTION 'first move must be the highest double (%-%)', first_dbl, first_dbl;
      END IF;
    END IF;
    st := jsonb_set(st, '{board}', jsonb_build_array(jsonb_build_object('tile', tile, 'flipped', false)));
    st := jsonb_set(st, '{first_tile_idx}', '0'::jsonb);
    new_left := a; new_right := b;
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
      IF a = le THEN new_left := b;
      ELSE new_left := a; END IF;
      st := jsonb_set(st, '{board}', jsonb_build_array(jsonb_build_object('tile', tile, 'flipped', a<>le)) || (st->'board'));
      v_first_tile_idx := v_first_tile_idx + 1;
      st := jsonb_set(st, '{first_tile_idx}', to_jsonb(v_first_tile_idx));
      new_right := re;
    ELSE
      IF a = re THEN new_right := b;
      ELSE new_right := a; END IF;
      st := jsonb_set(st, '{board}', (st->'board') || jsonb_build_array(jsonb_build_object('tile', tile, 'flipped', a=re AND a<>b)));
      new_left := le;
    END IF;
  END IF;

  st := jsonb_set(st, ARRAY['hands', my_slot::text], new_hand);
  st := jsonb_set(st, '{left_end}', to_jsonb(new_left));
  st := jsonb_set(st, '{right_end}', to_jsonb(new_right));
  st := jsonb_set(st, '{passes}', to_jsonb(0));
  st := jsonb_set(st, '{first_move_double}', 'null'::jsonb);

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
END $function$;
