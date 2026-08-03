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

  -- Accept both 'play' and 'playing' phases (fix: was only 'playing')
  IF COALESCE(st->>'phase', 'play') NOT IN ('play', 'playing') THEN RETURN; END IF;

  -- Check bot thinking delay
  _bot_think := NULLIF(st->>'bot_think_until', '')::timestamptz;
  IF _bot_think IS NOT NULL AND _bot_think > now() THEN
    RETURN;
  END IF;
  IF _bot_think IS NOT NULL AND _bot_think <= now() THEN
    st := st - 'bot_think_until';
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
  END IF;

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
