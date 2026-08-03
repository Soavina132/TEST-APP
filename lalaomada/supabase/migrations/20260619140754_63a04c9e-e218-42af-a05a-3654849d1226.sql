
CREATE OR REPLACE FUNCTION public._domino_start(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  g record; n int; tiles jsonb; hands jsonb := '{}'::jsonb; stock jsonb;
  per_hand int := 7; p record; idx int := 0; hand jsonb;
  starter int := 0; best int := -1; cur_dbl int; t jsonb;
  starter_double int := -1;
  prev_draw_mode text;
  new_state jsonb;
  board jsonb := '[]'::jsonb;
  left_end_v jsonb := 'null'::jsonb;
  right_end_v jsonb := 'null'::jsonb;
  starter_hand jsonb; filtered jsonb;
  next_slot int;
  current_slot int;
  _cfg record;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'open' THEN RETURN; END IF;
  SELECT count(*) INTO n FROM public.domino_participants WHERE game_id = _game_id;
  IF n < g.max_players THEN RETURN; END IF;

  tiles := public._domino_deal(n);

  FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id ORDER BY slot LOOP
    SELECT jsonb_agg(value) INTO hand FROM jsonb_array_elements(tiles) WITH ORDINALITY t(value, ord)
      WHERE ord > idx*per_hand AND ord <= (idx+1)*per_hand;
    hands := hands || jsonb_build_object(p.slot::text, COALESCE(hand,'[]'::jsonb));
    idx := idx + 1;
  END LOOP;

  SELECT jsonb_agg(value) INTO stock FROM jsonb_array_elements(tiles) WITH ORDINALITY t(value, ord)
    WHERE ord > n*per_hand;
  stock := COALESCE(stock, '[]'::jsonb);

  FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id ORDER BY slot LOOP
    cur_dbl := -1;
    FOR t IN SELECT * FROM jsonb_array_elements(hands -> p.slot::text) LOOP
      IF (t->>0)::int = (t->>1)::int AND (t->>0)::int > cur_dbl THEN cur_dbl := (t->>0)::int; END IF;
    END LOOP;
    IF cur_dbl > best THEN best := cur_dbl; starter := p.slot; starter_double := cur_dbl; END IF;
  END LOOP;

  prev_draw_mode := COALESCE(g.state->>'draw_mode','with');
  IF jsonb_array_length(stock) = 0 THEN prev_draw_mode := 'without'; END IF;

  current_slot := starter;
  -- Auto-play the starter's highest double
  IF starter_double >= 0 THEN
    starter_hand := hands -> starter::text;
    SELECT COALESCE(jsonb_agg(value), '[]'::jsonb) INTO filtered
      FROM jsonb_array_elements(starter_hand) value
      WHERE NOT ((value->>0)::int = starter_double AND (value->>1)::int = starter_double);
    hands := jsonb_set(hands, ARRAY[starter::text], filtered);
    board := jsonb_build_array(jsonb_build_object('tile', jsonb_build_array(starter_double, starter_double), 'flipped', false));
    left_end_v := to_jsonb(starter_double);
    right_end_v := to_jsonb(starter_double);
    SELECT slot INTO next_slot FROM public.domino_participants WHERE game_id=_game_id AND slot > starter ORDER BY slot LIMIT 1;
    IF next_slot IS NULL THEN SELECT slot INTO next_slot FROM public.domino_participants WHERE game_id=_game_id ORDER BY slot LIMIT 1; END IF;
    current_slot := COALESCE(next_slot, starter);
  END IF;

  SELECT * INTO _cfg FROM public._game_cfg('domino');

  new_state := jsonb_build_object(
    'phase','playing',
    'hands', hands,
    'stock', stock,
    'board', board,
    'left_end', left_end_v,
    'right_end', right_end_v,
    'passes', 0,
    'scores', '{}'::jsonb,
    'draw_mode', prev_draw_mode,
    'first_move_double', 'null'::jsonb
  );

  UPDATE public.domino_games SET
    status = 'playing',
    started_at = now(),
    current_turn = current_slot,
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
    state = new_state
  WHERE id = _game_id;
END $function$;

CREATE OR REPLACE FUNCTION public._domino_next_round(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  g record; n int; tiles jsonb; hands jsonb := '{}'::jsonb;
  stock jsonb; per_hand int := 7; p record; idx int := 0; hand jsonb;
  starter int := 0; best int := -1; cur_dbl int; t jsonb;
  starter_double int := -1;
  board jsonb := '[]'::jsonb;
  left_end_v jsonb := 'null'::jsonb;
  right_end_v jsonb := 'null'::jsonb;
  starter_hand jsonb; filtered jsonb;
  current_slot int; next_slot int;
  _cfg record;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN; END IF;
  SELECT count(*) INTO n FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  IF n < 2 THEN RETURN; END IF;

  tiles := public._domino_deal(n);

  FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
    SELECT jsonb_agg(value) INTO hand FROM jsonb_array_elements(tiles) WITH ORDINALITY t(value, ord)
      WHERE ord > idx*per_hand AND ord <= (idx+1)*per_hand;
    hands := hands || jsonb_build_object(p.slot::text, COALESCE(hand,'[]'::jsonb));
    idx := idx + 1;
  END LOOP;
  SELECT jsonb_agg(value) INTO stock FROM jsonb_array_elements(tiles) WITH ORDINALITY t(value, ord)
    WHERE ord > n*per_hand;
  stock := COALESCE(stock, '[]'::jsonb);

  FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
    cur_dbl := -1;
    FOR t IN SELECT * FROM jsonb_array_elements(hands -> p.slot::text) LOOP
      IF (t->>0)::int = (t->>1)::int AND (t->>0)::int > cur_dbl THEN cur_dbl := (t->>0)::int; END IF;
    END LOOP;
    IF cur_dbl > best THEN best := cur_dbl; starter := p.slot; starter_double := cur_dbl; END IF;
  END LOOP;

  current_slot := starter;
  IF starter_double >= 0 THEN
    starter_hand := hands -> starter::text;
    SELECT COALESCE(jsonb_agg(value), '[]'::jsonb) INTO filtered
      FROM jsonb_array_elements(starter_hand) value
      WHERE NOT ((value->>0)::int = starter_double AND (value->>1)::int = starter_double);
    hands := jsonb_set(hands, ARRAY[starter::text], filtered);
    board := jsonb_build_array(jsonb_build_object('tile', jsonb_build_array(starter_double, starter_double), 'flipped', false));
    left_end_v := to_jsonb(starter_double);
    right_end_v := to_jsonb(starter_double);
    SELECT slot INTO next_slot FROM public.domino_participants WHERE game_id=_game_id AND forfeited=false AND slot > starter ORDER BY slot LIMIT 1;
    IF next_slot IS NULL THEN SELECT slot INTO next_slot FROM public.domino_participants WHERE game_id=_game_id AND forfeited=false ORDER BY slot LIMIT 1; END IF;
    current_slot := COALESCE(next_slot, starter);
  END IF;

  SELECT * INTO _cfg FROM public._game_cfg('domino');

  UPDATE public.domino_games SET
    current_turn = current_slot,
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
    state = jsonb_build_object(
      'phase','playing',
      'hands', hands,
      'stock', stock,
      'board', board,
      'left_end', left_end_v,
      'right_end', right_end_v,
      'passes', 0,
      'scores', COALESCE(g.state->'scores','{}'::jsonb),
      'round', COALESCE((g.state->>'round')::int,1) + 1,
      'last_round', g.state->'last_round',
      'draw_mode', COALESCE(g.state->>'draw_mode','with'),
      'first_move_double', 'null'::jsonb
    )
  WHERE id = _game_id;
END $function$;
