-- Fix: bot plays first domino instantly (no think delay on dealing→playing transition and next_round)
-- Fix 1: domino_tick dealing→playing: set bot_think_until if current player is bot
-- Fix 2: _domino_next_round: set bot_think_until if starter is bot

-- ================================================================
-- Fix 1: domino_tick — set bot_think on dealing→playing transition
-- ================================================================
CREATE OR REPLACE FUNCTION public.domino_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  g record; st jsonb; _cfg record;
  _deal_until timestamptz; _reveal_until timestamptz; _break_until timestamptz;
  _bot_think timestamptz;
  v_is_bot boolean; v_hand jsonb;
  v_left int; v_right int; v_draw_mode text; v_stock jsonb;
  v_next int; v_n int; v_a int; v_b int;
  v_can_play boolean; v_new_tile jsonb;
  ps record; anyone boolean;
  _starter_is_bot boolean;
  think_secs int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;
  st := g.state;

  IF st->>'phase' = 'dealing' THEN
    _deal_until := NULLIF(st->>'deal_until', '')::timestamptz;
    IF _deal_until IS NOT NULL AND _deal_until <= now() THEN
      st := jsonb_set(st, '{phase}', '"playing"'::jsonb);
      SELECT * INTO _cfg FROM public._game_cfg('domino');
      -- Check if the current player is a bot → set think delay instead of playing immediately
      SELECT COALESCE(dp.is_bot, false) INTO _starter_is_bot
        FROM public.domino_participants dp
       WHERE dp.game_id = _game_id AND dp.slot = g.current_turn AND dp.forfeited = false;
      IF _starter_is_bot THEN
        think_secs := 1 + floor(random() * 5)::int;  -- 1-5 seconds
        st := jsonb_set(st, '{bot_think_until}', to_jsonb((now() + make_interval(secs => think_secs))::text), true);
        UPDATE public.domino_games SET state = st, turn_deadline = now() + make_interval(secs => COALESCE(_cfg.turn_timer_seconds, 80)) WHERE id = _game_id;
      ELSE
        UPDATE public.domino_games SET state = st, turn_deadline = now() + make_interval(secs => COALESCE(_cfg.turn_timer_seconds, 80)) WHERE id = _game_id;
        PERFORM public._domino_autoplay_bots();
      END IF;
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

  IF COALESCE(st->>'phase', 'play') NOT IN ('play', 'playing') THEN RETURN; END IF;

  _bot_think := NULLIF(st->>'bot_think_until', '')::timestamptz;
  IF _bot_think IS NOT NULL AND _bot_think > now() THEN RETURN; END IF;
  IF _bot_think IS NOT NULL AND _bot_think <= now() THEN
    st := st - 'bot_think_until';
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
  END IF;

  IF g.turn_deadline IS NULL OR g.turn_deadline > now() THEN
    PERFORM public._domino_autoplay_bots();
    RETURN;
  END IF;

  SELECT is_bot INTO v_is_bot FROM public.domino_participants WHERE game_id = _game_id AND slot = g.current_turn;
  IF v_is_bot THEN
    PERFORM public._domino_bot_step(_game_id);
    RETURN;
  END IF;

  v_hand := st->'hands'->(g.current_turn::text);
  v_left := (st->>'left_end')::int;
  v_right := (st->>'right_end')::int;
  v_draw_mode := COALESCE(st->>'draw_mode', g.draw_mode, 'with');
  v_stock := st->'stock';
  v_can_play := public._domino_slot_has_playable(v_hand, v_left, v_right);

  IF NOT v_can_play AND v_draw_mode = 'with' AND jsonb_array_length(v_stock) > 0 THEN
    WHILE jsonb_array_length(v_stock) > 0 LOOP
      v_new_tile := v_stock->0; v_stock := v_stock - 0;
      v_hand := v_hand || jsonb_build_array(v_new_tile);
      v_a := (v_new_tile->>0)::int; v_b := (v_new_tile->>1)::int;
      IF v_a = v_left OR v_b = v_left OR v_a = v_right OR v_b = v_right THEN v_can_play := true; EXIT; END IF;
    END LOOP;
    st := st || jsonb_build_object('hands', jsonb_set(st->'hands', ARRAY[g.current_turn::text], v_hand), 'stock', v_stock);
  END IF;

  v_n := g.max_players;
  v_next := (g.current_turn + 1) % v_n;

  IF NOT v_can_play THEN
    st := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1));
    IF (st->>'passes')::int >= v_n THEN
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
      PERFORM public._domino_end_round(_game_id, NULL); RETURN;
    END IF;
    IF v_draw_mode = 'without' OR jsonb_array_length(v_stock) = 0 THEN
      anyone := false;
      FOR ps IN SELECT * FROM public.domino_participants WHERE game_id = _game_id LOOP
        IF public._domino_slot_has_playable(st->'hands'->(ps.slot::text), v_left, v_right) THEN anyone := true; EXIT; END IF;
      END LOOP;
      IF NOT anyone THEN
        UPDATE public.domino_games SET state = st WHERE id = _game_id;
        PERFORM public._domino_end_round(_game_id, NULL); RETURN;
      END IF;
    END IF;
  END IF;

  SELECT * INTO _cfg FROM public._game_cfg('domino');
  UPDATE public.domino_games SET state = st, current_turn = v_next, turn_deadline = now() + make_interval(secs => COALESCE(_cfg.turn_timer_seconds, 80)) WHERE id = _game_id;
  PERFORM public._domino_autoplay_bots();
END;
$function$;

-- ================================================================
-- Fix 2: _domino_next_round — set bot_think_until if starter is bot
-- ================================================================
CREATE OR REPLACE FUNCTION public._domino_next_round(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  g record; n int; tiles jsonb; hands jsonb := '{}'::jsonb;
  stock jsonb; per_hand int := 7; p record; idx int := 0; hand jsonb;
  starter int := 0; best int := -1; cur_best int; t jsonb;
  starter_double int := -1;
  _cfg record;
  v_round int;
  v_rule text;
  v_prev_starter int;
  slots int[];
  i int;
  a int; b int; sum2 int;
  v_starter_is_bot boolean;
  v_state jsonb;
  think_secs int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN; END IF;
  SELECT count(*) INTO n FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  IF n < 2 THEN RETURN; END IF;

  tiles := public._domino_deal(n);
  SELECT array_agg(slot ORDER BY slot) INTO slots FROM public.domino_participants WHERE game_id=_game_id AND forfeited=false;

  FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
    SELECT jsonb_agg(value) INTO hand FROM jsonb_array_elements(tiles) WITH ORDINALITY t(value, ord) WHERE ord > idx*per_hand AND ord <= (idx+1)*per_hand;
    hands := hands || jsonb_build_object(p.slot::text, COALESCE(hand,'[]'::jsonb));
    idx := idx + 1;
  END LOOP;
  SELECT jsonb_agg(value) INTO stock FROM jsonb_array_elements(tiles) WITH ORDINALITY t(value, ord) WHERE ord > n*per_hand;
  stock := COALESCE(stock, '[]'::jsonb);

  v_round := COALESCE((g.state->>'round')::int, 1) + 1;
  v_rule := COALESCE(g.state->>'first_tile_rule', g.first_tile_rule, 'libre');
  v_prev_starter := NULLIF(g.state->>'starter_slot','null')::int;

  IF v_prev_starter IS NOT NULL THEN
    starter := slots[1];
    FOR i IN 1..array_length(slots,1) LOOP
      IF slots[i] = v_prev_starter THEN starter := slots[ ((i) % array_length(slots,1)) + 1 ]; EXIT; END IF;
    END LOOP;
    starter_double := -1;
  ELSIF v_rule = 'under6' THEN
    best := -1; starter := slots[1]; starter_double := -1;
    FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
      cur_best := -1;
      FOR t IN SELECT * FROM jsonb_array_elements(hands -> p.slot::text) LOOP
        a := (t->>0)::int; b := (t->>1)::int; sum2 := a + b;
        IF a = b AND sum2 < 6 AND sum2 > cur_best THEN cur_best := sum2; END IF;
      END LOOP;
      IF cur_best > best THEN best := cur_best; starter := p.slot; END IF;
    END LOOP;
    IF best < 0 THEN
      FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
        cur_best := -1;
        FOR t IN SELECT * FROM jsonb_array_elements(hands -> p.slot::text) LOOP
          a := (t->>0)::int; b := (t->>1)::int; sum2 := a + b;
          IF sum2 < 6 AND sum2 > cur_best THEN cur_best := sum2; END IF;
        END LOOP;
        IF cur_best > best THEN best := cur_best; starter := p.slot; END IF;
      END LOOP;
    END IF;
  ELSE
    FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
      cur_best := -1;
      FOR t IN SELECT * FROM jsonb_array_elements(hands -> p.slot::text) LOOP
        IF (t->>0)::int = (t->>1)::int AND (t->>0)::int > cur_best THEN cur_best := (t->>0)::int; END IF;
      END LOOP;
      IF cur_best > best THEN best := cur_best; starter := p.slot; starter_double := cur_best; END IF;
    END LOOP;
  END IF;

  SELECT * INTO _cfg FROM public._game_cfg('domino');

  -- Check if starter is a bot
  SELECT COALESCE(dp.is_bot, false) INTO v_starter_is_bot
    FROM public.domino_participants dp WHERE dp.game_id = _game_id AND dp.slot = starter;

  v_state := jsonb_build_object(
    'phase','playing',
    'hands', hands,
    'stock', stock,
    'board', '[]'::jsonb,
    'left_end', 'null'::jsonb,
    'right_end', 'null'::jsonb,
    'passes', 0,
    'scores', COALESCE(g.scores, g.state->'scores', '{}'::jsonb),
    'round', v_round,
    'last_round', NULL,
    'reveal_until', NULL,
    'break_until', NULL,
    'draw_mode', COALESCE(g.state->>'draw_mode','with'),
    'first_tile_rule', v_rule,
    'starter_slot', to_jsonb(starter),
    'first_move_double', CASE WHEN starter_double >= 0 THEN to_jsonb(starter_double) ELSE 'null'::jsonb END
  );

  -- Set bot_think_until if starter is a bot
  IF v_starter_is_bot THEN
    think_secs := 1 + floor(random() * 5)::int;  -- 1-5 seconds
    v_state := jsonb_set(v_state, '{bot_think_until}', to_jsonb((now() + make_interval(secs => think_secs))::text), true);
  END IF;

  UPDATE public.domino_participants SET ready = false WHERE game_id = _game_id;
  UPDATE public.domino_games SET
    current_turn = starter,
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
    turn_skips = '{}'::jsonb,
    state = v_state
  WHERE id = _game_id;
END;
$function$;
