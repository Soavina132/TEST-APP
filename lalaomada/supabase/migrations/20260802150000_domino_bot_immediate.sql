-- Domino bot fix: apply reference repo (Lalao-MADA) approach
-- Bot plays immediately, no think timer. domino_tick calls _domino_autoplay_bots.

CREATE OR REPLACE FUNCTION public._domino_hand_pips(_hand jsonb)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  t jsonb; total int := 0;
BEGIN
  IF _hand IS NULL THEN RETURN 0; END IF;
  FOR t IN SELECT * FROM jsonb_array_elements(_hand) LOOP
    total := total + (t->>0)::int + (t->>1)::int;
  END LOOP;
  RETURN total;
END $function$;

CREATE OR REPLACE FUNCTION public._domino_remove_tile(_hand jsonb, _a integer, _b integer)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  new_hand jsonb;
BEGIN
  IF _hand IS NULL THEN RETURN '[]'::jsonb; END IF;
  WITH items AS (
    SELECT value, row_number() OVER () as rnum
    FROM jsonb_array_elements(_hand)
  ),
  match AS (
    SELECT rnum FROM items 
    WHERE ((value->>0)::int = _a AND (value->>1)::int = _b)
       OR ((value->>0)::int = _b AND (value->>1)::int = _a)
    LIMIT 1
  )
  SELECT COALESCE(jsonb_agg(value), '[]'::jsonb) INTO new_hand
  FROM items WHERE rnum NOT IN (SELECT rnum FROM match);
  RETURN new_hand;
END $function$;

CREATE OR REPLACE FUNCTION public._domino_slot_has_playable(_hand jsonb, _left_end integer, _right_end integer)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  t jsonb; a int; b int;
BEGIN
  IF _hand IS NULL THEN RETURN false; END IF;
  IF _left_end IS NULL OR _right_end IS NULL THEN RETURN true; END IF;
  FOR t IN SELECT * FROM jsonb_array_elements(_hand) LOOP
    a := (t->>0)::int; b := (t->>1)::int;
    IF a = _left_end OR b = _left_end OR a = _right_end OR b = _right_end THEN
      RETURN true;
    END IF;
  END LOOP;
  RETURN false;
END $function$;

CREATE OR REPLACE FUNCTION public._domino_bot_step(_game_id uuid, _bot_slot integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  g record; st jsonb; hand jsonb;
  left_end int; right_end int;
  t jsonb; a int; b int;
  best_tile jsonb; best_score int := -1; score_val int;
  stock jsonb; draw_mode text;
  next_slot int; n int;
  new_board jsonb; new_left int; new_right int;
  new_hand jsonb; new_tile jsonb;
  _cfg record;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN; END IF;
  IF g.current_turn <> _bot_slot THEN RETURN; END IF;

  st := g.state;
  hand := st->'hands'->(_bot_slot::text);
  left_end := (st->>'left_end')::int; right_end := (st->>'right_end')::int;
  draw_mode := COALESCE(st->>'draw_mode', g.draw_mode, 'with');
  n := g.max_players;

  IF jsonb_array_length(st->'board') > 0 THEN
    FOR t IN SELECT * FROM jsonb_array_elements(hand) LOOP
      a := (t->>0)::int; b := (t->>1)::int;
      score_val := 0;
      IF a = left_end OR b = left_end THEN score_val := a + b + 1; END IF;
      IF a = right_end OR b = right_end THEN
        IF (a + b + 2) > score_val THEN score_val := a + b + 2; END IF;
      END IF;
      IF score_val > best_score THEN best_score := score_val; best_tile := t; END IF;
    END LOOP;
  END IF;

  IF best_tile IS NULL THEN
    stock := st->'stock';
    IF draw_mode = 'without' OR jsonb_array_length(stock) = 0 THEN
      next_slot := (_bot_slot + 1) % n;
      SELECT * INTO _cfg FROM public._game_cfg('domino');
      UPDATE public.domino_games
         SET current_turn = next_slot,
             turn_deadline = now() + make_interval(secs => COALESCE(_cfg.turn_timer_seconds, 60))
       WHERE id = _game_id;
      RETURN;
    END IF;

    new_tile := stock->0;
    stock := stock - 0;
    hand := hand || jsonb_build_array(new_tile);
    st := st || jsonb_build_object(
      'hands', jsonb_set(st->'hands', ARRAY[_bot_slot::text], hand), 'stock', stock
    );

    a := (new_tile->>0)::int; b := (new_tile->>1)::int;
    IF a = left_end OR b = left_end OR a = right_end OR b = right_end THEN
      best_tile := new_tile;
    ELSE
      next_slot := (_bot_slot + 1) % n;
      SELECT * INTO _cfg FROM public._game_cfg('domino');
      UPDATE public.domino_games
         SET state = st, current_turn = next_slot,
             turn_deadline = now() + make_interval(secs => COALESCE(_cfg.turn_timer_seconds, 60))
       WHERE id = _game_id;
      RETURN;
    END IF;
  END IF;

  a := (best_tile->>0)::int; b := (best_tile->>1)::int;

  IF jsonb_array_length(st->'board') = 0 THEN
    new_board := jsonb_build_array(jsonb_build_array(a, b));
    new_left := a; new_right := b;
  ELSIF a = left_end OR b = left_end THEN
    IF b = left_end THEN new_board := jsonb_build_array(jsonb_build_array(b, a)) || st->'board';
    ELSE new_board := jsonb_build_array(jsonb_build_array(a, b)) || st->'board'; END IF;
    new_left := CASE WHEN a = left_end THEN b ELSE a END;
    new_right := right_end;
  ELSIF a = right_end OR b = right_end THEN
    IF a = right_end THEN new_board := st->'board' || jsonb_build_array(jsonb_build_array(a, b));
    ELSE new_board := st->'board' || jsonb_build_array(jsonb_build_array(b, a)); END IF;
    new_left := left_end;
    new_right := CASE WHEN a = right_end THEN b ELSE a END;
  ELSE
    RAISE EXCEPTION 'bot: cannot place [%,%] on [%,%]', a, b, left_end, right_end;
  END IF;

  new_hand := public._domino_remove_tile(hand, a, b);
  hand := new_hand;

  st := st || jsonb_build_object(
    'hands', jsonb_set(st->'hands', ARRAY[_bot_slot::text], hand),
    'board', new_board, 'left_end', to_jsonb(new_left),
    'right_end', to_jsonb(new_right), 'phase', 'playing', 'passes', 0
  );

  IF jsonb_array_length(hand) = 0 THEN
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_end_round(_game_id, _bot_slot);
    RETURN;
  END IF;

  next_slot := (_bot_slot + 1) % n;
  SELECT * INTO _cfg FROM public._game_cfg('domino');
  UPDATE public.domino_games
     SET state = st, current_turn = next_slot,
         turn_deadline = now() + make_interval(secs => COALESCE(_cfg.turn_timer_seconds, 60))
   WHERE id = _game_id;

  PERFORM public._domino_autoplay_bots();
END $function$;

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
    SELECT dg.id, dp.slot INTO g
      FROM public.domino_games dg
      JOIN public.domino_participants dp ON dp.game_id = dg.id
     WHERE dg.status = 'playing' AND dp.is_bot = true AND dg.current_turn = dp.slot
     LIMIT 1;
    EXIT WHEN g.id IS NULL;
    BEGIN
      PERFORM public._domino_bot_step(g.id, g.slot);
    EXCEPTION WHEN OTHERS THEN
      EXIT;
    END;
    attempts := attempts + 1;
  END LOOP;
END $function$;

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

  IF g.turn_deadline IS NULL OR g.turn_deadline > now() THEN
    PERFORM public._domino_autoplay_bots();
    RETURN;
  END IF;

  SELECT is_bot INTO v_is_bot
    FROM public.domino_participants
   WHERE game_id = _game_id AND slot = g.current_turn;

  IF v_is_bot THEN
    PERFORM public._domino_bot_step(_game_id, g.current_turn);
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
END $function$;

CREATE OR REPLACE FUNCTION public.domino_tick_all()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  g record;
BEGIN
  FOR g IN SELECT id FROM public.domino_games WHERE status = 'playing' LOOP
    BEGIN
      PERFORM public.domino_tick(g.id);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
END $function$;