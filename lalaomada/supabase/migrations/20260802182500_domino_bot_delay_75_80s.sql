-- Bot plays between 75-80 seconds (near end of 80s turn timer)
-- Replace 20 + floor(random() * 56) with 75 + floor(random() * 6)

-- ================================================================
-- _domino_play_as: 75-80s delay after human move
-- ================================================================
CREATE OR REPLACE FUNCTION public._domino_play_as(_game_id uuid, _slot integer, _move jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  g             record;
  st            jsonb;
  hand          jsonb;
  tile          jsonb;
  placed_tile   jsonb;
  a int; b int;
  ha int; hb int;
  le int; re int;
  side          text;
  new_left      int;
  new_right     int;
  action        text;
  n_players     int;
  next_turn     int;
  drawn         jsonb;
  stock         jsonb;
  found         boolean := false;
  new_hand      jsonb;
  i             int;
  winner_slot   int;
  draw_mode     text;
  first_dbl     int;
  first_rule    text;
  stock_len     int;
  actor_is_bot  boolean;
  norm          jsonb;
  turn_secs     int;
  next_is_bot   boolean;
  think_secs    int;
BEGIN
  PERFORM public._domino_lock_game(_game_id);

  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  IF _slot <> g.current_turn THEN RAISE EXCEPTION 'not your turn (slot %, expected %)', _slot, g.current_turn; END IF;

  SELECT COALESCE(turn_timer_seconds, 80) INTO turn_secs
    FROM public.game_configs WHERE slug = 'domino';
  IF turn_secs IS NULL THEN turn_secs := 80; END IF;

  st := g.state;
  IF COALESCE(st->>'phase', 'play') NOT IN ('play', 'playing') THEN
    RAISE EXCEPTION 'round transition in progress';
  END IF;

  norm      := public._domino_normalize_board(COALESCE(st->'board', '[]'::jsonb));
  st        := jsonb_set(st, '{board}', COALESCE(norm->'board', '[]'::jsonb), true);
  st        := jsonb_set(st, '{left_end}', COALESCE(norm->'left_end', 'null'::jsonb), true);
  st        := jsonb_set(st, '{right_end}', COALESCE(norm->'right_end', 'null'::jsonb), true);

  action    := _move->>'action';
  hand      := COALESCE(st -> 'hands' -> _slot::text, '[]'::jsonb);
  stock     := COALESCE(st -> 'stock', '[]'::jsonb);
  le        := NULLIF(st->>'left_end',  'null')::int;
  re        := NULLIF(st->>'right_end', 'null')::int;
  draw_mode := COALESCE(st->>'draw_mode', 'with');
  first_rule := COALESCE(st->>'first_tile_rule', 'libre');
  stock_len := jsonb_array_length(stock);

  SELECT count(*) INTO n_players FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  SELECT is_bot INTO actor_is_bot
    FROM public.domino_participants WHERE game_id = _game_id AND slot = _slot;

  st := st - 'bot_think_until' - 'bot_locked_slot';

  IF COALESCE(actor_is_bot,false) AND action IN ('play','pass') THEN
    st := jsonb_set(st, '{bot_last_play_at}', to_jsonb(now()::text), true);
  END IF;

  IF action = 'draw' THEN
    IF draw_mode = 'without' THEN RAISE EXCEPTION 'draw disabled in this game'; END IF;
    IF public._domino_slot_has_playable(st, _slot) THEN RAISE EXCEPTION 'play your playable domino first'; END IF;
    IF stock_len = 0 THEN RAISE EXCEPTION 'stock empty'; END IF;
    drawn := stock -> 0;
    stock := stock - 0;
    hand  := hand || jsonb_build_array(drawn);
    st := jsonb_set(st, ARRAY['hands', _slot::text], hand, true);
    st := jsonb_set(st, '{stock}', stock, true);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    RETURN;
  END IF;

  IF action = 'pass' THEN
    IF public._domino_slot_has_playable(st, _slot) THEN RAISE EXCEPTION 'you have a playable domino'; END IF;
    IF draw_mode = 'with' AND stock_len > 0 THEN RAISE EXCEPTION 'you must draw first'; END IF;
    st        := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1), true);
    st        := jsonb_set(st, '{last_pass_by}', to_jsonb(_slot), true);
    next_turn := public._domino_next_playable_slot(_game_id, _slot, st);
    IF (st->>'passes')::int >= n_players THEN
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
      winner_slot := public._domino_lowest_pip_slot(_game_id, st);
      PERFORM public._domino_end_round(_game_id, winner_slot);
      RETURN;
    END IF;
    IF next_turn IS NULL THEN
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
      winner_slot := public._domino_lowest_pip_slot(_game_id, st);
      PERFORM public._domino_end_round(_game_id, winner_slot);
      RETURN;
    END IF;
    st := jsonb_set(st, '{current_turn}', to_jsonb(next_turn), true);
    st := public._domino_turn_state(st, turn_secs);
    SELECT COALESCE(dp.is_bot, false) INTO next_is_bot
      FROM public.domino_participants dp WHERE dp.game_id = _game_id AND dp.slot = next_turn;
    IF next_is_bot THEN
      think_secs := 75 + floor(random() * 6)::int;  -- 75-80 seconds
      st := jsonb_set(st, '{bot_think_until}', to_jsonb((now() + make_interval(secs => think_secs))::text), true);
    END IF;
    UPDATE public.domino_games
       SET state = st,
           current_turn = next_turn,
           turn_deadline = now() + (turn_secs || ' seconds')::interval
     WHERE id = _game_id;
    RETURN;
  END IF;

  IF action <> 'play' THEN RAISE EXCEPTION 'unknown action %', action; END IF;

  tile := _move -> 'tile';
  IF tile IS NULL OR jsonb_typeof(tile) <> 'array' OR jsonb_array_length(tile) <> 2 THEN
    RAISE EXCEPTION 'tile required';
  END IF;
  a := (tile->>0)::int;
  b := (tile->>1)::int;
  side := NULLIF(_move->>'side', 'auto');

  found := false;
  FOR i IN 0 .. jsonb_array_length(hand) - 1 LOOP
    ha := (hand->i->>0)::int;
    hb := (hand->i->>1)::int;
    IF (ha = a AND hb = b) OR (ha = b AND hb = a) THEN
      found := true;
      a := ha;
      b := hb;
      new_hand := hand - i;
      EXIT;
    END IF;
  END LOOP;
  IF NOT found THEN RAISE EXCEPTION 'tile [% %] not in hand of slot %', a, b, _slot; END IF;

  first_dbl := NULLIF(st->>'first_move_double', 'null')::int;
  IF le IS NULL THEN
    IF first_dbl IS NOT NULL AND (a <> first_dbl OR b <> first_dbl) THEN
      RAISE EXCEPTION 'first move must be the highest double';
    END IF;
    IF first_dbl IS NULL AND first_rule = 'under6' AND (a + b) >= 6 THEN
      RAISE EXCEPTION 'first domino must be under 6 points';
    END IF;
    new_left := a;
    new_right := b;
    placed_tile := jsonb_build_array(a, b);
    st := jsonb_set(st, '{board}', jsonb_build_array(jsonb_build_object('tile', placed_tile, 'flipped', false)), true);
  ELSE
    IF side IS NULL THEN
      IF a = re OR b = re THEN side := 'right';
      ELSIF a = le OR b = le THEN side := 'left';
      ELSE RAISE EXCEPTION 'tile does not fit';
      END IF;
    END IF;

    IF side = 'right' THEN
      IF a = re THEN placed_tile := jsonb_build_array(a, b); new_right := b;
      ELSIF b = re THEN placed_tile := jsonb_build_array(b, a); new_right := a;
      ELSE RAISE EXCEPTION 'tile does not fit right';
      END IF;
      new_left := le;
      st := jsonb_set(st, '{board}', COALESCE(st->'board', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('tile', placed_tile, 'flipped', false)), true);
    ELSIF side = 'left' THEN
      IF a = le THEN placed_tile := jsonb_build_array(b, a); new_left := b;
      ELSIF b = le Then placed_tile := jsonb_build_array(a, b); new_left := a;
      ELSE RAISE EXCEPTION 'tile does not fit left';
      END IF;
      new_right := re;
      st := jsonb_set(st, '{board}', jsonb_build_array(jsonb_build_object('tile', placed_tile, 'flipped', false)) || COALESCE(st->'board', '[]'::jsonb), true);
    ELSE
      RAISE EXCEPTION 'invalid side';
    END IF;
  END IF;

  st := jsonb_set(st, ARRAY['hands', _slot::text], new_hand, true);
  st := jsonb_set(st, '{left_end}',  to_jsonb(new_left), true);
  st := jsonb_set(st, '{right_end}', to_jsonb(new_right), true);
  st := jsonb_set(st, '{passes}',    to_jsonb(0), true);
  st := jsonb_set(st, '{first_move_double}', 'null'::jsonb, true);
  st := st - 'last_pass_by';

  IF jsonb_array_length(new_hand) = 0 THEN
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_end_round(_game_id, _slot);
    RETURN;
  END IF;

  next_turn := public._domino_next_playable_slot(_game_id, _slot, st);
  IF next_turn IS NULL THEN
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    winner_slot := public._domino_lowest_pip_slot(_game_id, st);
    PERFORM public._domino_end_round(_game_id, winner_slot);
    RETURN;
  END IF;

  st := jsonb_set(st, '{current_turn}', to_jsonb(next_turn), true);
  st := public._domino_turn_state(st, turn_secs);
  SELECT COALESCE(dp.is_bot, false) INTO next_is_bot
    FROM public.domino_participants dp WHERE dp.game_id = _game_id AND dp.slot = next_turn;
  IF next_is_bot THEN
    think_secs := 75 + floor(random() * 6)::int;  -- 75-80 seconds
    st := jsonb_set(st, '{bot_think_until}', to_jsonb((now() + make_interval(secs => think_secs))::text), true);
  END IF;
  UPDATE public.domino_games
     SET state = st,
         current_turn = next_turn,
         turn_deadline = now() + (turn_secs || ' seconds')::interval
   WHERE id = _game_id;
END;
$function$;

-- ================================================================
-- _domino_bot_step: 75-80s delay for bot-to-bot chains too
-- ================================================================
CREATE OR REPLACE FUNCTION public._domino_bot_step(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  g record;
  st jsonb;
  v_slot int;
  hand jsonb;
  le int;
  re int;
  draw_mode text;
  is_first_move boolean;
  first_dbl int;
  v_rule text;
  i int;
  j int;
  a int;
  b int;
  tile jsonb;
  placed jsonb;
  found boolean;
  found_i int;
  new_hand jsonb;
  new_left int;
  new_right int;
  next_turn int;
  winner_slot int;
  stock jsonb;
  drawn jsonb;
  _cfg record;
  v_is_bot boolean;
  phase text;
  next_is_bot boolean;
  turn_secs int;
  _bot_think timestamptz;
  think_secs int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

  st := g.state;
  phase := COALESCE(st->>'phase', 'play');
  IF phase NOT IN ('play','playing') THEN RETURN; END IF;

  _bot_think := NULLIF(st->>'bot_think_until', '')::timestamptz;
  IF _bot_think IS NOT NULL AND _bot_think > now() THEN
    RETURN;
  END IF;

  v_slot := g.current_turn;
  SELECT COALESCE(dp.is_bot, false) INTO v_is_bot
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id
     AND dp.slot = v_slot
     AND dp.forfeited = false;

  IF NOT COALESCE(v_is_bot, false) THEN RETURN; END IF;

  SELECT COALESCE(turn_timer_seconds, 80) INTO turn_secs
    FROM public.game_configs WHERE slug = 'domino';
  IF turn_secs IS NULL THEN turn_secs := 80; END IF;

  hand := COALESCE(st->'hands'->v_slot::text, '[]'::jsonb);
  le := NULLIF(st->>'left_end', 'null')::int;
  re := NULLIF(st->>'right_end', 'null')::int;
  draw_mode := COALESCE(st->>'draw_mode', 'with');
  v_rule := COALESCE(st->>'first_tile_rule', 'libre');
  is_first_move := jsonb_array_length(COALESCE(st->'board', '[]'::jsonb)) = 0;
  first_dbl := NULLIF(st->>'first_move_double', 'null')::int;

  found := false;
  found_i := -1;

  IF jsonb_array_length(hand) > 0 THEN
    FOR i IN 0..jsonb_array_length(hand)-1 LOOP
      a := (hand->i->>0)::int;
      b := (hand->i->>1)::int;
      IF is_first_move THEN
        IF first_dbl IS NOT NULL THEN
          IF a = first_dbl AND b = first_dbl THEN found := true; found_i := i; EXIT; END IF;
        ELSIF v_rule = 'under6' THEN
          IF (a + b) < 6 THEN found := true; found_i := i; EXIT; END IF;
        ELSE
          found := true; found_i := i; EXIT;
        END IF;
      ELSE
        IF a = le OR b = le OR a = re OR b = re THEN found := true; found_i := i; EXIT; END IF;
      END IF;
    END LOOP;
  END IF;

  IF found THEN
    tile := hand->found_i;
    a := (tile->>0)::int;
    b := (tile->>1)::int;

    new_hand := '[]'::jsonb;
    FOR j IN 0..jsonb_array_length(hand)-1 LOOP
      IF j <> found_i THEN new_hand := new_hand || jsonb_build_array(hand->j); END IF;
    END LOOP;

    IF is_first_move THEN
      placed := jsonb_build_array(a, b);
      st := jsonb_set(st, '{board}', jsonb_build_array(jsonb_build_object('tile', placed, 'flipped', false)), true);
      new_left := a;
      new_right := b;
    ELSE
      IF a = re OR b = re THEN
        IF a = re THEN
          placed := jsonb_build_array(a, b);
          new_right := b;
        ELSE
          placed := jsonb_build_array(b, a);
          new_right := a;
        END IF;
        new_left := le;
        st := jsonb_set(st, '{board}', COALESCE(st->'board','[]'::jsonb) || jsonb_build_array(jsonb_build_object('tile', placed, 'flipped', false)), true);
      ELSE
        IF a = le THEN
          placed := jsonb_build_array(b, a);
          new_left := b;
        ELSE
          placed := jsonb_build_array(a, b);
          new_left := a;
        END IF;
        new_right := re;
        st := jsonb_set(st, '{board}', jsonb_build_array(jsonb_build_object('tile', placed, 'flipped', false)) || COALESCE(st->'board','[]'::jsonb), true);
      END IF;
    END IF;

    st := jsonb_set(st, ARRAY['hands', v_slot::text], new_hand, true);
    st := jsonb_set(st, '{left_end}', to_jsonb(new_left), true);
    st := jsonb_set(st, '{right_end}', to_jsonb(new_right), true);
    st := jsonb_set(st, '{passes}', to_jsonb(0), true);
    st := jsonb_set(st, '{first_move_double}', 'null'::jsonb, true);
    st := jsonb_set(st, '{phase}', '"play"'::jsonb, true);
    st := st - 'last_pass_by' - 'bot_think_until' - 'bot_locked_slot';

    IF jsonb_array_length(new_hand) = 0 THEN
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
      PERFORM public._domino_end_round(_game_id, v_slot);
      RETURN;
    END IF;

    next_turn := public._domino_next_playable_slot(_game_id, v_slot, st);
    IF next_turn IS NULL THEN
      winner_slot := public._domino_lowest_pip_slot(_game_id, st);
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
      PERFORM public._domino_end_round(_game_id, winner_slot);
      RETURN;
    END IF;

    SELECT COALESCE(dp.is_bot, false) INTO next_is_bot
      FROM public.domino_participants dp WHERE dp.game_id = _game_id AND dp.slot = next_turn;
    IF next_is_bot THEN
      think_secs := 75 + floor(random() * 6)::int;  -- 75-80 seconds
      st := jsonb_set(st, '{bot_think_until}', to_jsonb((now() + make_interval(secs => think_secs))::text), true);
    END IF;

    UPDATE public.domino_games
       SET state = st,
           current_turn = next_turn,
           turn_deadline = now() + (turn_secs || ' seconds')::interval
     WHERE id = _game_id;
    RETURN;
  END IF;

  stock := COALESCE(st->'stock', '[]'::jsonb);
  IF draw_mode = 'with' AND jsonb_array_length(stock) > 0 THEN
    drawn := stock -> 0;
    hand := hand || jsonb_build_array(drawn);
    stock := stock - 0;
    st := jsonb_set(st, ARRAY['hands', v_slot::text], hand, true);
    st := jsonb_set(st, '{stock}', stock, true);
    st := st - 'bot_think_until' - 'bot_locked_slot';
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_bot_step(_game_id);
    RETURN;
  END IF;

  st := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1), true);
  st := jsonb_set(st, '{last_pass_by}', to_jsonb(v_slot), true);
  st := st - 'bot_think_until' - 'bot_locked_slot';
  next_turn := public._domino_next_playable_slot(_game_id, v_slot, st);

  IF next_turn IS NULL THEN
    winner_slot := public._domino_lowest_pip_slot(_game_id, st);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_end_round(_game_id, winner_slot);
    RETURN;
  END IF;

  SELECT COALESCE(dp.is_bot, false) INTO next_is_bot
    FROM public.domino_participants dp WHERE dp.game_id = _game_id AND dp.slot = next_turn;
  IF next_is_bot THEN
    think_secs := 75 + floor(random() * 6)::int;  -- 75-80 seconds
    st := jsonb_set(st, '{bot_think_until}', to_jsonb((now() + make_interval(secs => think_secs))::text), true);
  END IF;

  UPDATE public.domino_games
     SET state = st,
         current_turn = next_turn,
         turn_deadline = now() + (turn_secs || ' seconds')::interval
   WHERE id = _game_id;
END;
$function$;
