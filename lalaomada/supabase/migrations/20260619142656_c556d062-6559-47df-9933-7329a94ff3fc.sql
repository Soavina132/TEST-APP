
-- Helper: place the starter's highest double after the dealing animation
CREATE OR REPLACE FUNCTION public._domino_place_first(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  g record; st jsonb; starter int; starter_double int;
  hands jsonb; starter_hand jsonb; filtered jsonb;
  board jsonb; next_slot int; _cfg record;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;
  st := g.state;
  IF (st->>'phase') <> 'dealing' THEN RETURN; END IF;

  starter := COALESCE((st->>'starter_slot')::int, g.current_turn);
  starter_double := COALESCE((st->>'starter_double')::int, -1);
  hands := st->'hands';

  IF starter_double >= 0 THEN
    starter_hand := hands -> starter::text;
    SELECT COALESCE(jsonb_agg(value), '[]'::jsonb) INTO filtered
      FROM jsonb_array_elements(starter_hand) value
      WHERE NOT ((value->>0)::int = starter_double AND (value->>1)::int = starter_double);
    hands := jsonb_set(hands, ARRAY[starter::text], filtered);
    board := jsonb_build_array(jsonb_build_object('tile', jsonb_build_array(starter_double, starter_double), 'flipped', false));
    st := jsonb_set(st, '{hands}', hands);
    st := jsonb_set(st, '{board}', board);
    st := jsonb_set(st, '{left_end}', to_jsonb(starter_double));
    st := jsonb_set(st, '{right_end}', to_jsonb(starter_double));

    SELECT slot INTO next_slot FROM public.domino_participants
      WHERE game_id=_game_id AND forfeited=false AND slot > starter ORDER BY slot LIMIT 1;
    IF next_slot IS NULL THEN
      SELECT slot INTO next_slot FROM public.domino_participants
        WHERE game_id=_game_id AND forfeited=false ORDER BY slot LIMIT 1;
    END IF;
  ELSE
    next_slot := starter;
  END IF;

  st := jsonb_set(st, '{phase}', '"play"'::jsonb);
  st := st - 'deal_until';

  SELECT * INTO _cfg FROM public._game_cfg('domino');

  UPDATE public.domino_games
     SET state = st,
         current_turn = COALESCE(next_slot, starter),
         turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
   WHERE id = _game_id;
END $function$;

-- Update _domino_start to enter 'dealing' phase for 3s instead of auto-placing
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
  _cfg record;
  deal_until timestamptz;
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

  SELECT * INTO _cfg FROM public._game_cfg('domino');
  deal_until := now() + interval '3 seconds';

  new_state := jsonb_build_object(
    'hands', hands,
    'stock', stock,
    'board', '[]'::jsonb,
    'left_end', null,
    'right_end', null,
    'draw_mode', prev_draw_mode,
    'phase', 'dealing',
    'deal_until', deal_until::text,
    'starter_slot', starter,
    'starter_double', starter_double
  );

  UPDATE public.domino_games
     SET status='playing',
         state=new_state,
         current_turn=starter,
         turn_deadline=deal_until,
         started_at=now(),
         turn_skips='{}'::jsonb,
         scores=COALESCE(scores,'{}'::jsonb)
   WHERE id = _game_id;
END $function$;

-- Update _domino_next_round similarly
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
  _cfg record;
  deal_until timestamptz;
  new_state jsonb;
  prev_scores jsonb;
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

  SELECT * INTO _cfg FROM public._game_cfg('domino');
  deal_until := now() + interval '3 seconds';
  prev_scores := COALESCE(g.scores, '{}'::jsonb);

  new_state := jsonb_build_object(
    'hands', hands,
    'stock', stock,
    'board', '[]'::jsonb,
    'left_end', null,
    'right_end', null,
    'draw_mode', COALESCE(g.state->>'draw_mode','with'),
    'phase', 'dealing',
    'deal_until', deal_until::text,
    'starter_slot', starter,
    'starter_double', starter_double,
    'scores', prev_scores
  );

  UPDATE public.domino_games
     SET state=new_state,
         current_turn=starter,
         turn_deadline=deal_until,
         turn_skips='{}'::jsonb
   WHERE id = _game_id;
END $function$;

-- Update domino_tick to handle the dealing phase
CREATE OR REPLACE FUNCTION public.domino_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  g record; cur_uid uuid; _cfg record; _skips int; _next int; remaining int; last_slot int;
  _break_until timestamptz; _deal_until timestamptz;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

  -- Dealing phase: place the first tile when the 3s animation is done
  IF (g.state->>'phase') = 'dealing' THEN
    _deal_until := NULLIF(g.state->>'deal_until','')::timestamptz;
    IF _deal_until IS NOT NULL AND _deal_until <= now() THEN
      PERFORM public._domino_place_first(_game_id);
    END IF;
    RETURN;
  END IF;

  -- Break phase: start next round when expired
  IF (g.state->>'phase') = 'break' THEN
    _break_until := NULLIF(g.state->>'break_until','')::timestamptz;
    IF _break_until IS NOT NULL AND _break_until <= now() THEN
      PERFORM public._domino_next_round(_game_id);
    END IF;
    RETURN;
  END IF;

  IF g.turn_deadline IS NULL OR g.turn_deadline > now() THEN RETURN; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('domino');
  SELECT user_id INTO cur_uid FROM public.domino_participants WHERE game_id = _game_id AND slot = g.current_turn;
  _skips := COALESCE((g.turn_skips->>cur_uid::text)::int, 0) + 1;

  IF _skips >= _cfg.max_turn_skips THEN
    UPDATE public.domino_participants SET forfeited = true WHERE game_id = _game_id AND user_id = cur_uid;
    SELECT count(*) INTO remaining FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
    IF remaining <= 1 THEN
      SELECT slot INTO last_slot FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false LIMIT 1;
      IF last_slot IS NOT NULL THEN PERFORM public._domino_finalize(_game_id, last_slot);
      ELSE UPDATE public.domino_games SET status='cancelled', finished_at=now() WHERE id = _game_id; END IF;
      RETURN;
    END IF;
  ELSE
    UPDATE public.domino_games
       SET turn_skips = jsonb_set(COALESCE(g.turn_skips,'{}'::jsonb), ARRAY[cur_uid::text], to_jsonb(_skips))
     WHERE id = _game_id;
  END IF;

  SELECT slot INTO _next FROM public.domino_participants
   WHERE game_id = _game_id AND forfeited = false AND slot > g.current_turn ORDER BY slot LIMIT 1;
  IF _next IS NULL THEN
    SELECT slot INTO _next FROM public.domino_participants
     WHERE game_id = _game_id AND forfeited = false ORDER BY slot LIMIT 1;
  END IF;
  IF _next IS NOT NULL THEN
    UPDATE public.domino_games
       SET current_turn = _next, turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
     WHERE id = _game_id;
  END IF;
END $function$;
