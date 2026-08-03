
-- 1) domino_create: restrict max players to 2 or 3
CREATE OR REPLACE FUNCTION public.domino_create(
  _stake numeric, _max integer, _private boolean,
  _mode text DEFAULT 'classic', _commission numeric DEFAULT 10,
  _target_score integer DEFAULT 0, _draw_mode text DEFAULT 'with'
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_balance numeric; v_code text; v_id uuid; v_name text; v_state jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _max NOT BETWEEN 2 AND 3 THEN RAISE EXCEPTION 'invalid max_players (2-3)'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'invalid stake'; END IF;
  IF _target_score < 0 OR _target_score > 1000 THEN RAISE EXCEPTION 'invalid target_score'; END IF;
  IF _draw_mode NOT IN ('with','without') THEN RAISE EXCEPTION 'invalid draw_mode'; END IF;

  SELECT balance_ar, pseudo INTO v_balance, v_name FROM public.profiles WHERE id = v_uid;
  IF v_balance IS NULL OR v_balance < _stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;

  IF _private THEN
    v_code := upper(substring(md5(random()::text||clock_timestamp()::text) from 1 for 6));
  END IF;

  v_state := public._domino_init_state();
  v_state := jsonb_set(v_state, '{draw_mode}', to_jsonb(_draw_mode), true);

  INSERT INTO public.domino_games(host_id, max_players, stake, pot, commission_pct, is_private, room_code, mode, target_score, state)
  VALUES (v_uid, _max, _stake, _stake, _commission, _private, v_code, _mode, _target_score, v_state)
  RETURNING id INTO v_id;

  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
    VALUES (v_uid, 'domino_stake', -_stake, v_id, 'Create domino game');
  INSERT INTO public.domino_participants(game_id, user_id, slot, display_name)
    VALUES (v_id, v_uid, 0, COALESCE(v_name,'Player'));
  RETURN v_id;
END $function$;

-- 2) domino_play: auto-select side when missing/ambiguous; place tile correctly
CREATE OR REPLACE FUNCTION public.domino_play(_game_id uuid, _move jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  g record; my_slot int; st jsonb; hand jsonb; tile jsonb;
  a int; b int; le int; re int; side text;
  new_left int; new_right int; action text; n_players int; next_turn int;
  drawn jsonb; stock jsonb; found boolean := false; new_hand jsonb; i int;
  _cfg record;
  has_playable boolean := false;
  ht jsonb; ha int; hb int;
  draw_mode text;
  is_first_move boolean;
  first_dbl int;
  matches_left boolean;
  matches_right boolean;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  IF (g.state->>'phase') = 'break' THEN RAISE EXCEPTION 'round break'; END IF;
  SELECT slot INTO my_slot FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid;
  IF my_slot IS NULL OR my_slot <> g.current_turn THEN RAISE EXCEPTION 'not your turn'; END IF;

  st := g.state;
  action := _move->>'action';
  hand := st -> 'hands' -> my_slot::text;
  stock := COALESCE(st -> 'stock','[]'::jsonb);
  le := NULLIF(st->>'left_end','null')::int;
  re := NULLIF(st->>'right_end','null')::int;
  draw_mode := COALESCE(st->>'draw_mode','with');
  SELECT count(*) INTO n_players FROM public.domino_participants WHERE game_id = _game_id;
  SELECT * INTO _cfg FROM public._game_cfg('domino');
  is_first_move := jsonb_array_length(COALESCE(st->'board','[]'::jsonb)) = 0;

  IF NOT is_first_move THEN
    FOR ht IN SELECT * FROM jsonb_array_elements(hand) LOOP
      ha := (ht->>0)::int; hb := (ht->>1)::int;
      IF ha = le OR hb = le OR ha = re OR hb = re THEN has_playable := true; EXIT; END IF;
    END LOOP;
  ELSE
    has_playable := jsonb_array_length(hand) > 0;
  END IF;

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
  side := _move->>'side';
  a := (tile->>0)::int; b := (tile->>1)::int;

  -- enforce: tile must come from hand
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
    -- Auto-pick side when caller didn't specify, or specified an invalid side that the tile doesn't match.
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

  IF jsonb_array_length(new_hand) = 0 THEN
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_end_round(_game_id, my_slot);
    RETURN;
  END IF;

  next_turn := (my_slot + 1) % n_players;
  UPDATE public.domino_games SET state = st, current_turn = next_turn,
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
END $function$;
