CREATE OR REPLACE FUNCTION public._domino_slot_has_playable(_state jsonb, _slot integer)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  hand jsonb := COALESCE(_state -> 'hands' -> _slot::text, '[]'::jsonb);
  board_len integer := jsonb_array_length(COALESCE(_state -> 'board', '[]'::jsonb));
  first_dbl integer;
  le integer;
  re integer;
  t jsonb;
  a integer;
  b integer;
BEGIN
  IF jsonb_array_length(hand) = 0 THEN
    RETURN false;
  END IF;

  IF board_len = 0 THEN
    first_dbl := NULLIF(_state->>'first_move_double', 'null')::integer;
    IF first_dbl IS NULL THEN
      RETURN true;
    END IF;

    FOR t IN SELECT * FROM jsonb_array_elements(hand) LOOP
      a := (t->>0)::integer;
      b := (t->>1)::integer;
      IF a = first_dbl AND b = first_dbl THEN
        RETURN true;
      END IF;
    END LOOP;
    RETURN false;
  END IF;

  le := NULLIF(_state->>'left_end', 'null')::integer;
  re := NULLIF(_state->>'right_end', 'null')::integer;

  FOR t IN SELECT * FROM jsonb_array_elements(hand) LOOP
    a := (t->>0)::integer;
    b := (t->>1)::integer;
    IF a = le OR b = le OR a = re OR b = re THEN
      RETURN true;
    END IF;
  END LOOP;

  RETURN false;
END;
$function$;

CREATE OR REPLACE FUNCTION public._domino_lowest_pip_slot(_game_id uuid, _state jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  p record;
  cur_sum integer;
  best_sum integer := 2147483647;
  best_slot integer := NULL;
BEGIN
  FOR p IN SELECT slot FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
    cur_sum := public._domino_hand_pips(COALESCE(_state -> 'hands' -> p.slot::text, '[]'::jsonb));
    IF cur_sum < best_sum THEN
      best_sum := cur_sum;
      best_slot := p.slot;
    END IF;
  END LOOP;

  RETURN best_slot;
END;
$function$;

CREATE OR REPLACE FUNCTION public._domino_next_playable_slot(_game_id uuid, _from_slot integer, _state jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  slots integer[];
  total integer;
  start_idx integer := 1;
  step integer;
  idx integer;
  candidate integer;
  draw_mode text := COALESCE(_state->>'draw_mode', 'with');
  stock_len integer := jsonb_array_length(COALESCE(_state -> 'stock', '[]'::jsonb));
BEGIN
  SELECT array_agg(slot ORDER BY slot)
    INTO slots
    FROM public.domino_participants
   WHERE game_id = _game_id AND forfeited = false;

  total := COALESCE(array_length(slots, 1), 0);
  IF total = 0 THEN
    RETURN NULL;
  END IF;

  FOR idx IN 1..total LOOP
    IF slots[idx] = _from_slot THEN
      start_idx := idx;
      EXIT;
    END IF;
  END LOOP;

  FOR step IN 1..total LOOP
    idx := ((start_idx - 1 + step) % total) + 1;
    candidate := slots[idx];

    IF public._domino_slot_has_playable(_state, candidate)
       OR (draw_mode = 'with' AND stock_len > 0) THEN
      RETURN candidate;
    END IF;
  END LOOP;

  RETURN NULL;
END;
$function$;

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

DO $function$
DECLARE
  g record;
  next_slot integer;
  winner_slot integer;
  _cfg record;
BEGIN
  SELECT * INTO _cfg FROM public._game_cfg('domino');

  FOR g IN
    SELECT * FROM public.domino_games
     WHERE status = 'playing'
       AND COALESCE(state->>'phase', '') = 'playing'
       AND jsonb_array_length(COALESCE(state->'board', '[]'::jsonb)) > 0
  LOOP
    IF NOT public._domino_slot_has_playable(g.state, g.current_turn)
       AND (COALESCE(g.state->>'draw_mode', 'with') = 'without'
            OR jsonb_array_length(COALESCE(g.state->'stock', '[]'::jsonb)) = 0) THEN
      next_slot := public._domino_next_playable_slot(g.id, g.current_turn, g.state);

      IF next_slot IS NULL THEN
        winner_slot := public._domino_lowest_pip_slot(g.id, g.state);
        IF winner_slot IS NOT NULL THEN
          PERFORM public._domino_end_round(g.id, winner_slot);
        END IF;
      ELSE
        UPDATE public.domino_games
           SET current_turn = next_slot,
               turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
         WHERE id = g.id;
      END IF;
    END IF;
  END LOOP;
END;
$function$;