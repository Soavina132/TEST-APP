-- Fix: domino_play appended every played tile to the end of `board` regardless
-- of the side it was actually played on. The client walks `board` left→right
-- and assumes tile[i][1] touches tile[i+1][0]. When a tile was played on the
-- LEFT end of the chain, this assumption breaks and the board visually shows
-- adjacent tiles with mismatched pips (e.g. 6|4 next to 3|1).
--
-- Fix: prepend to `board` when playing on the left, append when playing on the
-- right, and store the tile with pips ordered so that the touching pip faces
-- the neighbour (left play → [exposed, touching]; right play → [touching, exposed]).
CREATE OR REPLACE FUNCTION public.domino_play(_game_id uuid, _move jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  g           record;
  my_slot     int;
  st          jsonb;
  hand        jsonb;
  tile        jsonb;
  a int; b int;
  le int; re int;
  side        text;
  new_left    int; new_right int;
  action      text;
  n_players   int;
  next_turn   int;
  drawn       jsonb;
  stock       jsonb;
  found       boolean := false;
  new_hand    jsonb;
  i           int;
  winner_slot int;
  draw_mode   text;
  first_dbl   int;
  stock_len   int;
  stored_tile jsonb;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  SELECT slot INTO my_slot FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid;
  IF my_slot IS NULL OR my_slot <> g.current_turn THEN RAISE EXCEPTION 'not your turn'; END IF;

  st        := g.state;
  action    := _move->>'action';
  hand      := st -> 'hands' -> my_slot::text;
  stock     := st -> 'stock';
  le        := NULLIF(st->>'left_end',  'null')::int;
  re        := NULLIF(st->>'right_end', 'null')::int;
  draw_mode := COALESCE(st->>'draw_mode', 'with');
  stock_len := jsonb_array_length(COALESCE(stock, '[]'::jsonb));
  SELECT count(*) INTO n_players FROM public.domino_participants WHERE game_id = _game_id;

  IF action = 'draw' THEN
    IF draw_mode = 'without' THEN RAISE EXCEPTION 'draw disabled in this game'; END IF;
    IF stock_len = 0 THEN RAISE EXCEPTION 'stock empty'; END IF;
    drawn := stock -> 0; stock := stock - 0;
    hand  := hand || jsonb_build_array(drawn);
    st := jsonb_set(st, ARRAY['hands', my_slot::text], hand);
    st := jsonb_set(st, '{stock}', stock);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    RETURN;
  END IF;

  IF action = 'pass' THEN
    IF draw_mode = 'with' AND stock_len > 0 THEN RAISE EXCEPTION 'you must draw first'; END IF;
    st        := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1));
    next_turn := public._domino_next_playable_slot(_game_id, my_slot, st);
    IF (st->>'passes')::int >= n_players THEN
      winner_slot := public._domino_lowest_pip_slot(_game_id, st);
      PERFORM public._domino_end_round(_game_id, winner_slot);
      RETURN;
    END IF;
    IF next_turn IS NULL THEN
      winner_slot := public._domino_lowest_pip_slot(_game_id, st);
      PERFORM public._domino_end_round(_game_id, winner_slot);
      RETURN;
    END IF;
    st := jsonb_set(st, '{current_turn}', to_jsonb(next_turn));
    UPDATE public.domino_games SET state = st, current_turn = next_turn, turn_deadline = now() + interval '30 seconds' WHERE id = _game_id;
    RETURN;
  END IF;

  IF action <> 'play' THEN RAISE EXCEPTION 'unknown action'; END IF;

  tile := _move -> 'tile';
  IF tile IS NULL THEN RAISE EXCEPTION 'tile required'; END IF;
  a := (tile->>0)::int; b := (tile->>1)::int;
  side := _move->>'side';

  found := false;
  FOR i IN 0 .. jsonb_array_length(hand) - 1 LOOP
    IF (hand->i->>0)::int = a AND (hand->i->>1)::int = b THEN
      found := true;
      new_hand := hand - i;
      EXIT;
    END IF;
    IF (hand->i->>0)::int = b AND (hand->i->>1)::int = a THEN
      found := true;
      a := b; b := (hand->i->>0)::int;
      new_hand := hand - i;
      EXIT;
    END IF;
  END LOOP;
  IF NOT found THEN RAISE EXCEPTION 'tile not in hand'; END IF;

  first_dbl := NULLIF(st->>'first_move_double', 'null')::int;
  IF le IS NULL THEN
    IF first_dbl IS NOT NULL AND a <> b THEN RAISE EXCEPTION 'first move must be the highest double'; END IF;
    IF first_dbl IS NOT NULL AND a <> first_dbl THEN RAISE EXCEPTION 'first move must be the highest double'; END IF;
    new_left  := a; new_right := b;
    -- First tile: store as [left_end, right_end] so orientation is canonical.
    st := jsonb_set(st, '{board}', jsonb_build_array(jsonb_build_array(a, b)));
  ELSE
    -- Determine the side and which pip touches the chain (`touch`) vs is exposed (`expose`).
    -- After normalisation above, (a, b) is the tile as held; we recompute here.
    DECLARE
      touch int; expose int;
      matches_left  boolean := (a = le OR b = le);
      matches_right boolean := (a = re OR b = re);
    BEGIN
      IF side IS NULL THEN
        -- Auto: prefer left if it fits, else right.
        IF matches_left THEN side := 'left';
        ELSIF matches_right THEN side := 'right';
        ELSE RAISE EXCEPTION 'tile does not fit'; END IF;
      END IF;

      IF side = 'left' THEN
        IF a = le THEN touch := a; expose := b;
        ELSIF b = le THEN touch := b; expose := a;
        ELSE RAISE EXCEPTION 'tile does not fit left'; END IF;
        new_left  := expose;
        new_right := re;
        -- Store as [expose, touch] so board[0][1] = old left_end, matching the
        -- neighbour's [old_le, ...] on its left side.
        stored_tile := jsonb_build_array(expose, touch);
        st := jsonb_set(st, '{board}', jsonb_build_array(stored_tile) || (st->'board'));
      ELSE
        IF a = re THEN touch := a; expose := b;
        ELSIF b = re THEN touch := b; expose := a;
        ELSE RAISE EXCEPTION 'tile does not fit right'; END IF;
        new_left  := le;
        new_right := expose;
        -- Store as [touch, expose] so board[i][1] matches board[i+1][0].
        stored_tile := jsonb_build_array(touch, expose);
        st := jsonb_set(st, '{board}', (st->'board') || jsonb_build_array(stored_tile));
      END IF;
    END;
  END IF;

  st := jsonb_set(st, ARRAY['hands', my_slot::text], new_hand);
  st := jsonb_set(st, '{left_end}',  to_jsonb(new_left));
  st := jsonb_set(st, '{right_end}', to_jsonb(new_right));
  st := jsonb_set(st, '{passes}',    to_jsonb(0));
  st := jsonb_set(st, '{first_move_double}', 'null'::jsonb);

  IF jsonb_array_length(new_hand) = 0 THEN
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_end_round(_game_id, my_slot);
    RETURN;
  END IF;

  next_turn := public._domino_next_playable_slot(_game_id, my_slot, st);
  IF next_turn IS NULL THEN
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    winner_slot := public._domino_lowest_pip_slot(_game_id, st);
    PERFORM public._domino_end_round(_game_id, winner_slot);
    RETURN;
  END IF;

  st := jsonb_set(st, '{current_turn}', to_jsonb(next_turn));
  UPDATE public.domino_games
    SET state = st, current_turn = next_turn,
        turn_deadline = now() + interval '30 seconds'
    WHERE id = _game_id;
END;
$$;
