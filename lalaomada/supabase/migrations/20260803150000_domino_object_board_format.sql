-- ─────────────────────────────────────────────────────────────────────────────
-- Migration : passer TOUTES les fonctions domino au format objet {tile, flipped}
--
-- Le frontend utilise BoardEntry = { tile: [number, number], flipped: boolean }
-- comme type canonique. readBoardTile() gère les deux formats (tuple et objet),
-- mais pour la cohérence, on standardise sur le format objet.
--
-- Fonctions modifiées :
--   1. domino_play         — stored_tile et premier tile -> {tile:[a,b], flipped:false}
--   2. _domino_bot_step    — placed -> {tile:[a,b], flipped:false}
--   3. _domino_autoplay_bots — placed -> {tile:[a,b], flipped:false}
--   4. _domino_place_first — premier tile -> {tile:[a,a], flipped:false}
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. domino_play : format objet pour le board ─────────────────────────────
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
    UPDATE public.domino_games
       SET state = st,
           turn_deadline = now() + interval '30 seconds'
     WHERE id = _game_id;
    RETURN;
  END IF;

  IF action = 'pass' THEN
    IF draw_mode = 'with' AND stock_len > 0 THEN RAISE EXCEPTION 'you must draw first'; END IF;
    st := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1));
    st := jsonb_set(st, '{last_pass_by}', to_jsonb(my_slot));
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
    st := public._domino_arm_bot_think(_game_id, next_turn, st);
    st := jsonb_set(st, '{current_turn}', to_jsonb(next_turn));
    UPDATE public.domino_games
       SET state = st, current_turn = next_turn,
           turn_deadline = now() + interval '30 seconds'
     WHERE id = _game_id;
    RETURN;
  END IF;

  IF action <> 'play' THEN RAISE EXCEPTION 'unknown action'; END IF;

  tile := _move -> 'tile';
  IF tile IS NULL THEN RAISE EXCEPTION 'tile required'; END IF;
  a := (tile->>0)::int; b := (tile->>1)::int;
  side := _move->>'side';

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
    st := jsonb_set(st, '{board}', jsonb_build_array(
      jsonb_build_object('tile', jsonb_build_array(a, b), 'flipped', false)
    ));
  ELSE
    DECLARE
      touch int; expose int;
      matches_left  boolean := (a = le OR b = le);
      matches_right boolean := (a = re OR b = re);
    BEGIN
      IF side IS NULL THEN
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
        stored_tile := jsonb_build_object('tile', jsonb_build_array(expose, touch), 'flipped', false);
        st := jsonb_set(st, '{board}', jsonb_build_array(stored_tile) || (st->'board'));
      ELSE
        IF a = re THEN touch := a; expose := b;
        ELSIF b = re THEN touch := b; expose := a;
        ELSE RAISE EXCEPTION 'tile does not fit right'; END IF;
        new_left  := le;
        new_right := expose;
        stored_tile := jsonb_build_object('tile', jsonb_build_array(touch, expose), 'flipped', false);
        st := jsonb_set(st, '{board}', (st->'board') || jsonb_build_array(stored_tile));
      END IF;
    END;
  END IF;

  st := jsonb_set(st, ARRAY['hands', my_slot::text], new_hand);
  st := jsonb_set(st, '{left_end}',  to_jsonb(new_left));
  st := jsonb_set(st, '{right_end}', to_jsonb(new_right));
  st := jsonb_set(st, '{passes}',    to_jsonb(0));
  st := jsonb_set(st, '{first_move_double}', 'null'::jsonb);
  st := st - 'last_pass_by';

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

  st := public._domino_arm_bot_think(_game_id, next_turn, st);
  st := jsonb_set(st, '{current_turn}', to_jsonb(next_turn));
  UPDATE public.domino_games
    SET state = st, current_turn = next_turn,
        turn_deadline = now() + interval '30 seconds'
    WHERE id = _game_id;
END;
$$;

-- ── 2. _domino_bot_step : format objet pour le board ─────────────────────────
CREATE OR REPLACE FUNCTION public._domino_bot_step(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','extensions'
AS $$
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
  v_think_until timestamptz;
  v_locked_slot int;
  v_delay_ms int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

  st := g.state;
  phase := COALESCE(st->>'phase', 'play');
  IF phase NOT IN ('play','playing') THEN RETURN; END IF;

  v_slot := g.current_turn;
  SELECT COALESCE(dp.is_bot, false) INTO v_is_bot
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id
     AND dp.slot = v_slot
     AND dp.forfeited = false;

  IF NOT COALESCE(v_is_bot, false) THEN RETURN; END IF;

  v_think_until := NULLIF(st->>'bot_think_until','')::timestamptz;
  v_locked_slot := NULLIF(st->>'bot_locked_slot','null')::int;

  IF v_think_until IS NULL OR v_locked_slot IS DISTINCT FROM v_slot THEN
    v_delay_ms := 1500 + (floor(random() * 2000))::int;
    st := jsonb_set(st, '{bot_locked_slot}', to_jsonb(v_slot), true);
    st := jsonb_set(st, '{bot_think_until}',
                    to_jsonb((now() + make_interval(secs => v_delay_ms / 1000.0))::text), true);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    RETURN;
  END IF;

  IF v_think_until > now() THEN RETURN; END IF;

  st := st - 'bot_think_until' - 'bot_locked_slot';

  hand := COALESCE(st->'hands'->v_slot::text, '[]'::jsonb);
  le := NULLIF(st->>'left_end', 'null')::int;
  re := NULLIF(st->>'right_end', 'null')::int;
  draw_mode := COALESCE(st->>'draw_mode', 'with');
  v_rule := COALESCE(st->>'first_tile_rule', 'libre');
  is_first_move := jsonb_array_length(COALESCE(st->'board', '[]'::jsonb)) = 0;
  first_dbl := NULLIF(st->>'first_move_double', 'null')::int;
  SELECT * INTO _cfg FROM public._game_cfg('domino');

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
      placed := jsonb_build_object('tile', jsonb_build_array(a, b), 'flipped', false);
      st := jsonb_set(st, '{board}', jsonb_build_array(placed), true);
      new_left := a;
      new_right := b;
    ELSE
      IF a = re OR b = re THEN
        IF a = re THEN
          placed := jsonb_build_object('tile', jsonb_build_array(a, b), 'flipped', false);
          new_right := b;
        ELSE
          placed := jsonb_build_object('tile', jsonb_build_array(b, a), 'flipped', false);
          new_right := a;
        END IF;
        new_left := le;
        st := jsonb_set(st, '{board}', COALESCE(st->'board','[]'::jsonb) || jsonb_build_array(placed), true);
      ELSE
        IF a = le THEN
          placed := jsonb_build_object('tile', jsonb_build_array(b, a), 'flipped', false);
          new_left := b;
        ELSE
          placed := jsonb_build_object('tile', jsonb_build_array(a, b), 'flipped', false);
          new_left := a;
        END IF;
        new_right := re;
        st := jsonb_set(st, '{board}', jsonb_build_array(placed) || COALESCE(st->'board','[]'::jsonb), true);
      END IF;
    END IF;

    st := jsonb_set(st, ARRAY['hands', v_slot::text], new_hand, true);
    st := jsonb_set(st, '{left_end}', to_jsonb(new_left), true);
    st := jsonb_set(st, '{right_end}', to_jsonb(new_right), true);
    st := jsonb_set(st, '{passes}', to_jsonb(0), true);
    st := jsonb_set(st, '{first_move_double}', 'null'::jsonb, true);
    st := jsonb_set(st, '{phase}', '"play"'::jsonb, true);
    st := st - 'last_pass_by';

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

    st := public._domino_arm_bot_think(_game_id, next_turn, st);

    UPDATE public.domino_games
       SET state = st,
           current_turn = next_turn,
           turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
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
    v_delay_ms := 800 + (floor(random() * 1200))::int;
    st := jsonb_set(st, '{bot_locked_slot}', to_jsonb(v_slot), true);
    st := jsonb_set(st, '{bot_think_until}',
                    to_jsonb((now() + make_interval(secs => v_delay_ms / 1000.0))::text), true);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    RETURN;
  END IF;

  st := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1), true);
  st := jsonb_set(st, '{last_pass_by}', to_jsonb(v_slot), true);

  next_turn := public._domino_next_playable_slot(_game_id, v_slot, st);
  IF next_turn IS NULL THEN
    winner_slot := public._domino_lowest_pip_slot(_game_id, st);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_end_round(_game_id, winner_slot);
    RETURN;
  END IF;

  st := public._domino_arm_bot_think(_game_id, next_turn, st);
  UPDATE public.domino_games
     SET state = st,
         current_turn = next_turn,
         turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
   WHERE id = _game_id;
END;
$$;

-- ── 3. _domino_autoplay_bots : format objet pour le board ────────────────────
CREATE OR REPLACE FUNCTION public._domino_autoplay_bots(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','extensions'
AS $$
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
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

  st := g.state;
  phase := COALESCE(st->>'phase', 'play');
  IF phase NOT IN ('play','playing') THEN RETURN; END IF;

  v_slot := g.current_turn;
  SELECT COALESCE(dp.is_bot, false) INTO v_is_bot
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id
     AND dp.slot = v_slot
     AND dp.forfeited = false;
  IF NOT COALESCE(v_is_bot, false) THEN RETURN; END IF;

  st := st - 'bot_think_until' - 'bot_locked_slot';

  hand := COALESCE(st->'hands'->v_slot::text, '[]'::jsonb);
  le := NULLIF(st->>'left_end', 'null')::int;
  re := NULLIF(st->>'right_end', 'null')::int;
  draw_mode := COALESCE(st->>'draw_mode', 'with');
  v_rule := COALESCE(st->>'first_tile_rule', 'libre');
  is_first_move := jsonb_array_length(COALESCE(st->'board', '[]'::jsonb)) = 0;
  first_dbl := NULLIF(st->>'first_move_double', 'null')::int;
  SELECT * INTO _cfg FROM public._game_cfg('domino');

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
      placed := jsonb_build_object('tile', jsonb_build_array(a, b), 'flipped', false);
      st := jsonb_set(st, '{board}', jsonb_build_array(placed), true);
      new_left := a;
      new_right := b;
    ELSE
      IF a = re OR b = re THEN
        IF a = re THEN
          placed := jsonb_build_object('tile', jsonb_build_array(a, b), 'flipped', false);
          new_right := b;
        ELSE
          placed := jsonb_build_object('tile', jsonb_build_array(b, a), 'flipped', false);
          new_right := a;
        END IF;
        new_left := le;
        st := jsonb_set(st, '{board}', COALESCE(st->'board','[]'::jsonb) || jsonb_build_array(placed), true);
      ELSE
        IF a = le THEN
          placed := jsonb_build_object('tile', jsonb_build_array(b, a), 'flipped', false);
          new_left := b;
        ELSE
          placed := jsonb_build_object('tile', jsonb_build_array(a, b), 'flipped', false);
          new_left := a;
        END IF;
        new_right := re;
        st := jsonb_set(st, '{board}', jsonb_build_array(placed) || COALESCE(st->'board','[]'::jsonb), true);
      END IF;
    END IF;

    st := jsonb_set(st, ARRAY['hands', v_slot::text], new_hand, true);
    st := jsonb_set(st, '{left_end}', to_jsonb(new_left), true);
    st := jsonb_set(st, '{right_end}', to_jsonb(new_right), true);
    st := jsonb_set(st, '{passes}', to_jsonb(0), true);
    st := jsonb_set(st, '{first_move_double}', 'null'::jsonb, true);
    st := jsonb_set(st, '{phase}', '"play"'::jsonb, true);
    st := st - 'last_pass_by';

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

    st := public._domino_arm_bot_think(_game_id, next_turn, st);
    UPDATE public.domino_games
       SET state = st,
           current_turn = next_turn,
           turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
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
    st := jsonb_set(st, '{bot_locked_slot}', to_jsonb(v_slot), true);
    st := jsonb_set(st, '{bot_think_until}',
                    to_jsonb((now() + make_interval(secs => 1.0))::text), true);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    RETURN;
  END IF;

  st := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1), true);
  st := jsonb_set(st, '{last_pass_by}', to_jsonb(v_slot), true);

  next_turn := public._domino_next_playable_slot(_game_id, v_slot, st);
  IF next_turn IS NULL THEN
    winner_slot := public._domino_lowest_pip_slot(_game_id, st);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_end_round(_game_id, winner_slot);
    RETURN;
  END IF;

  st := public._domino_arm_bot_think(_game_id, next_turn, st);
  UPDATE public.domino_games
     SET state = st,
         current_turn = next_turn,
         turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
   WHERE id = _game_id;
END;
$$;

-- ── 4. _domino_place_first : format objet pour le board ──────────────────────
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
    board := jsonb_build_array(
      jsonb_build_object('tile', jsonb_build_array(starter_double, starter_double), 'flipped', false)
    );
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

  next_slot := COALESCE(next_slot, starter);
  st := public._domino_arm_bot_think(_game_id, next_slot, st);

  UPDATE public.domino_games
     SET state = st,
         current_turn = next_slot,
         turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
   WHERE id = _game_id;
END $function$;
