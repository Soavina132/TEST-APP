-- Helper: compute pip sum for a hand
CREATE OR REPLACE FUNCTION public._domino_hand_pips(_hand jsonb)
RETURNS int LANGUAGE sql IMMUTABLE AS $$
  SELECT COALESCE(SUM(((t->>0)::int + (t->>1)::int)), 0)::int
  FROM jsonb_array_elements(COALESCE(_hand,'[]'::jsonb)) t
$$;

-- Re-deal a new round, preserving scores
CREATE OR REPLACE FUNCTION public._domino_next_round(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  g record; n int; tiles jsonb; hands jsonb := '{}'::jsonb;
  stock jsonb; per_hand int := 7; p record; idx int := 0; hand jsonb;
  starter int := 0; best int := -1; cur int; t jsonb;
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
    cur := -1;
    FOR t IN SELECT * FROM jsonb_array_elements(hands -> p.slot::text) LOOP
      IF (t->>0)::int = (t->>1)::int AND (t->>0)::int > cur THEN cur := (t->>0)::int * 10 + 100; END IF;
    END LOOP;
    IF cur > best THEN best := cur; starter := p.slot; END IF;
  END LOOP;

  SELECT * INTO _cfg FROM public._game_cfg('domino');

  UPDATE public.domino_games SET
    current_turn = starter,
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
    state = jsonb_build_object(
      'phase','playing',
      'hands', hands,
      'stock', stock,
      'board', '[]'::jsonb,
      'left_end', null,
      'right_end', null,
      'passes', 0,
      'scores', COALESCE(g.state->'scores','{}'::jsonb),
      'round', COALESCE((g.state->>'round')::int,1) + 1,
      'last_round', g.state->'last_round'
    )
  WHERE id = _game_id;
END $$;

-- End-of-round handler: pays out (direct) or accumulates score / starts break (points)
CREATE OR REPLACE FUNCTION public._domino_end_round(_game_id uuid, _winner_slot int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  g record; st jsonb; winner_uid uuid; round_score int := 0;
  hand_pips jsonb := '{}'::jsonb; p record; pips int; total int;
  scores jsonb; new_total int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN; END IF;

  SELECT user_id INTO winner_uid FROM public.domino_participants WHERE game_id = _game_id AND slot = _winner_slot;
  st := g.state;

  -- Compute round score = sum of pips remaining in losers' hands
  FOR p IN SELECT slot, user_id FROM public.domino_participants WHERE game_id = _game_id LOOP
    pips := public._domino_hand_pips(st->'hands'->p.slot::text);
    hand_pips := hand_pips || jsonb_build_object(p.user_id::text, pips);
    IF p.slot <> _winner_slot THEN round_score := round_score + pips; END IF;
  END LOOP;

  -- Direct mode (no target) -> finalize game now
  IF COALESCE(g.target_score,0) <= 0 THEN
    PERFORM public._domino_finalize(_game_id, _winner_slot);
    RETURN;
  END IF;

  -- Points mode
  scores := COALESCE(g.scores, '{}'::jsonb);
  new_total := COALESCE((scores->>winner_uid::text)::int, 0) + round_score;
  scores := jsonb_set(scores, ARRAY[winner_uid::text], to_jsonb(new_total), true);

  UPDATE public.domino_games SET scores = scores WHERE id = _game_id;

  IF new_total >= g.target_score THEN
    -- Game over: pay out and store final recap
    st := jsonb_set(st, '{last_round}', jsonb_build_object(
      'winner_uid', winner_uid, 'round_score', round_score, 'hand_pips', hand_pips, 'final', true
    ));
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_finalize(_game_id, _winner_slot);
    RETURN;
  END IF;

  -- Start break before next round
  st := jsonb_set(st, '{phase}', '"break"'::jsonb);
  st := jsonb_set(st, '{break_until}', to_jsonb((now() + interval '10 seconds')::text));
  st := jsonb_set(st, '{last_round}', jsonb_build_object(
    'winner_uid', winner_uid, 'round_score', round_score, 'hand_pips', hand_pips, 'final', false
  ));
  st := jsonb_set(st, '{scores}', scores);
  UPDATE public.domino_games SET state = st, turn_deadline = NULL WHERE id = _game_id;
END $$;

-- Replace round-winning sites in domino_play to use end_round
CREATE OR REPLACE FUNCTION public.domino_play(_game_id uuid, _move jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  g record; my_slot int; st jsonb; hand jsonb; tile jsonb;
  a int; b int; le int; re int; side text;
  new_left int; new_right int; action text; n_players int; next_turn int;
  drawn jsonb; stock jsonb; found boolean := false; new_hand jsonb; i int;
  _cfg record;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  IF (g.state->>'phase') = 'break' THEN RAISE EXCEPTION 'round break'; END IF;
  SELECT slot INTO my_slot FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid;
  IF my_slot IS NULL OR my_slot <> g.current_turn THEN RAISE EXCEPTION 'not your turn'; END IF;

  st := g.state;
  action := _move->>'action';
  hand := st -> 'hands' -> my_slot::text;
  stock := st -> 'stock';
  le := NULLIF(st->>'left_end','null')::int;
  re := NULLIF(st->>'right_end','null')::int;
  SELECT count(*) INTO n_players FROM public.domino_participants WHERE game_id = _game_id;
  SELECT * INTO _cfg FROM public._game_cfg('domino');

  IF action = 'draw' THEN
    IF jsonb_array_length(stock) = 0 THEN RAISE EXCEPTION 'stock empty'; END IF;
    drawn := stock -> 0; stock := stock - 0;
    hand := hand || jsonb_build_array(drawn);
    st := jsonb_set(st, ARRAY['hands', my_slot::text], hand);
    st := jsonb_set(st, '{stock}', stock);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    RETURN;
  END IF;

  IF action = 'pass' THEN
    st := jsonb_set(st, '{passes}', to_jsonb( COALESCE((st->>'passes')::int,0) + 1 ));
    next_turn := (my_slot + 1) % n_players;
    IF (st->>'passes')::int >= n_players THEN
      DECLARE p record; best_slot int := 0; best_sum int := 9999; cur_sum int; t jsonb;
      BEGIN
        FOR p IN SELECT slot FROM public.domino_participants WHERE game_id = _game_id LOOP
          cur_sum := 0;
          FOR t IN SELECT * FROM jsonb_array_elements(st->'hands'->p.slot::text) LOOP
            cur_sum := cur_sum + (t->>0)::int + (t->>1)::int;
          END LOOP;
          IF cur_sum < best_sum THEN best_sum := cur_sum; best_slot := p.slot; END IF;
        END LOOP;
        UPDATE public.domino_games SET state = st, current_turn = next_turn WHERE id = _game_id;
        PERFORM public._domino_end_round(_game_id, best_slot);
        RETURN;
      END;
    END IF;
    UPDATE public.domino_games SET state = st, current_turn = next_turn,
      turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
    RETURN;
  END IF;

  tile := _move -> 'tile';
  side := COALESCE(_move->>'side','right');
  a := (tile->>0)::int; b := (tile->>1)::int;

  new_hand := '[]'::jsonb;
  FOR i IN 0..jsonb_array_length(hand)-1 LOOP
    IF NOT found AND ((hand->i->>0)::int = a AND (hand->i->>1)::int = b) THEN found := true;
    ELSE new_hand := new_hand || jsonb_build_array(hand->i); END IF;
  END LOOP;
  IF NOT found THEN RAISE EXCEPTION 'tile not in hand'; END IF;

  IF jsonb_array_length(st->'board') = 0 THEN
    st := jsonb_set(st, '{board}', jsonb_build_array(jsonb_build_object('tile', tile, 'flipped', false)));
    new_left := a; new_right := b;
  ELSIF side = 'left' THEN
    IF a = le THEN new_left := b;
    ELSIF b = le THEN new_left := a;
    ELSE RAISE EXCEPTION 'tile does not match left end'; END IF;
    st := jsonb_set(st, '{board}', jsonb_build_array(jsonb_build_object('tile', tile, 'flipped', a<>le)) || (st->'board'));
    new_right := re;
  ELSE
    IF a = re THEN new_right := b;
    ELSIF b = re THEN new_right := a;
    ELSE RAISE EXCEPTION 'tile does not match right end'; END IF;
    st := jsonb_set(st, '{board}', (st->'board') || jsonb_build_array(jsonb_build_object('tile', tile, 'flipped', a=re AND a<>b)));
    new_left := le;
  END IF;

  st := jsonb_set(st, ARRAY['hands', my_slot::text], new_hand);
  st := jsonb_set(st, '{left_end}', to_jsonb(new_left));
  st := jsonb_set(st, '{right_end}', to_jsonb(new_right));
  st := jsonb_set(st, '{passes}', to_jsonb(0));

  IF jsonb_array_length(new_hand) = 0 THEN
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_end_round(_game_id, my_slot);
    RETURN;
  END IF;

  next_turn := (my_slot + 1) % n_players;
  UPDATE public.domino_games SET state = st, current_turn = next_turn,
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
END $$;

-- Extend tick: advance past break to next round
CREATE OR REPLACE FUNCTION public.domino_tick(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  g record; cur_uid uuid; _cfg record; _skips int; _next int; remaining int; last_slot int;
  _break_until timestamptz;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

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
END $$;