CREATE OR REPLACE FUNCTION public._domino_bot_step(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $$
DECLARE
  g record; st jsonb; v_slot int; hand jsonb; le int; re int;
  draw_mode text; is_first_move boolean; first_dbl int; v_rule text;
  i int; j int; a int; b int; tile jsonb; placed jsonb;
  found boolean; found_i int; new_hand jsonb; new_left int; new_right int;
  next_turn int; winner_slot int; stock jsonb; drawn jsonb;
  _cfg record; v_is_bot boolean; phase text; v_think_until timestamptz;
  v_locked_slot int; v_delay_ms int; v_name text;
  v_playable jsonb;
  v_next_delay interval;
  _fti int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

  st := g.state;
  IF st IS NULL THEN RETURN; END IF;

  phase := COALESCE(st->>'phase', 'play');

  -- FIX: Si la phase n'est pas 'play' et bot_think_until est présent, nettoyer
  IF phase NOT IN ('play','playing') THEN
    IF st ? 'bot_think_until' THEN
      st := st - 'bot_think_until' - 'bot_locked_slot';
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;

  v_slot := g.current_turn;
  SELECT COALESCE(dp.is_bot, false), COALESCE(dp.display_name, 'Bot') INTO v_is_bot, v_name
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id AND dp.slot = v_slot AND dp.forfeited = false;

  v_think_until := NULLIF(st->>'bot_think_until','')::timestamptz;

  -- Si bot_think_until est dans le futur, attendre
  IF v_think_until IS NOT NULL AND v_think_until > now() THEN
    RETURN;
  END IF;

  -- FIX: Si bot_think_until est dans le passé mais le joueur n'est pas un bot,
  -- nettoyer bot_think_until en base pour éviter les appels répétés
  IF v_think_until IS NOT NULL AND v_think_until <= now() THEN
    st := st - 'bot_think_until' - 'bot_locked_slot';
    IF NOT COALESCE(v_is_bot, false) THEN
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
      RETURN;
    END IF;
  END IF;

  -- Si bot_think_until est NULL, l'armer avec un délai court
  IF v_think_until IS NULL THEN
    IF NOT COALESCE(v_is_bot, false) THEN RETURN; END IF;
    v_delay_ms := 1000 + (floor(random() * 1000))::int;
    st := jsonb_set(st, '{bot_locked_slot}', to_jsonb(v_slot), true);
    st := jsonb_set(st, '{bot_think_until}',
                    to_jsonb((now() + make_interval(secs => v_delay_ms / 1000.0))::text), true);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    RETURN;
  END IF;

  -- bot_think_until est dans le passé → jouer le bot

  hand := COALESCE(st->'hands'->v_slot::text, '[]'::jsonb);
  le := NULLIF(st->>'left_end', 'null')::int;
  re := NULLIF(st->>'right_end', 'null')::int;
  draw_mode := COALESCE(st->>'draw_mode', 'with');
  v_rule := COALESCE(st->>'first_tile_rule', 'libre');
  is_first_move := jsonb_array_length(COALESCE(st->'board', '[]'::jsonb)) = 0;
  first_dbl := NULLIF(st->>'first_move_double', 'null')::int;
  _fti := COALESCE((st->>'first_tile_idx')::int, 0);
  SELECT * INTO _cfg FROM public._game_cfg('domino');

  found := false; found_i := -1;

  IF jsonb_array_length(hand) > 0 THEN
    FOR i IN 0..jsonb_array_length(hand)-1 LOOP
      a := (hand->i->>0)::int; b := (hand->i->>1)::int;
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
    tile := hand->found_i; a := (tile->>0)::int; b := (tile->>1)::int;
    new_hand := '[]'::jsonb;
    FOR j IN 0..jsonb_array_length(hand)-1 LOOP
      IF j <> found_i THEN new_hand := new_hand || jsonb_build_array(hand->j); END IF;
    END LOOP;

    IF is_first_move THEN
      placed := jsonb_build_object('tile', jsonb_build_array(a, b), 'flipped', false);
      st := jsonb_set(st, '{board}', jsonb_build_array(placed), true);
      new_left := a; new_right := b;
      _fti := 0;
    ELSE
      IF a = re OR b = re THEN
        IF a = re THEN
          placed := jsonb_build_object('tile', jsonb_build_array(a, b), 'flipped', false); new_right := b;
        ELSE
          placed := jsonb_build_object('tile', jsonb_build_array(b, a), 'flipped', false); new_right := a;
        END IF;
        new_left := le;
        st := jsonb_set(st, '{board}', COALESCE(st->'board','[]'::jsonb) || jsonb_build_array(placed), true);
      ELSE
        IF a = le THEN
          placed := jsonb_build_object('tile', jsonb_build_array(b, a), 'flipped', false); new_left := b;
        ELSE
          placed := jsonb_build_object('tile', jsonb_build_array(a, b), 'flipped', false); new_left := a;
        END IF;
        new_right := re;
        st := jsonb_set(st, '{board}', jsonb_build_array(placed) || COALESCE(st->'board','[]'::jsonb), true);
        _fti := _fti + 1;
      END IF;
    END IF;

    st := jsonb_set(st, ARRAY['hands', v_slot::text], new_hand, true);
    st := jsonb_set(st, '{left_end}', to_jsonb(new_left), true);
    st := jsonb_set(st, '{right_end}', to_jsonb(new_right), true);
    st := jsonb_set(st, '{passes}', to_jsonb(0), true);
    st := jsonb_set(st, '{first_move_double}', 'null'::jsonb, true);
    st := jsonb_set(st, '{phase}', '"play"'::jsonb, true);
    st := jsonb_set(st, '{first_tile_idx}', to_jsonb(_fti), true);
    st := st - 'last_pass_by';

    IF jsonb_array_length(new_hand) = 0 THEN
      st := jsonb_set(st, ARRAY['turn_slot'], to_jsonb(v_slot), true);
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
      PERFORM public._domino_end_round(_game_id, v_slot);
      RETURN;
    END IF;

    next_turn := public._domino_next_playable_slot(_game_id, v_slot, st);
    IF next_turn IS NULL THEN
      winner_slot := public._domino_lowest_pip_slot(_game_id, st);
      -- FIX: COALESCE winner_slot pour éviter to_jsonb(NULL) → jsonb_set NULL
      st := jsonb_set(st, ARRAY['turn_slot'], to_jsonb(COALESCE(winner_slot, v_slot)), true);
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
      PERFORM public._domino_end_round(_game_id, winner_slot);
      RETURN;
    END IF;

    v_next_delay := public._domino_turn_delay(_game_id, next_turn);
    st := public._domino_arm_bot_think(_game_id, next_turn, st);
    v_playable := public._domino_playable_tiles(st, next_turn);
    st := jsonb_set(st, ARRAY['playable_tiles'], COALESCE(v_playable, '[]'::jsonb), true);
    st := jsonb_set(st, ARRAY['turn_slot'], to_jsonb(next_turn), true);
    UPDATE public.domino_games SET state = st, current_turn = next_turn,
           turn_deadline = now() + v_next_delay
     WHERE id = _game_id;
    RETURN;
  END IF;

  -- Bot n'a pas de tuile jouable → piocher
  stock := COALESCE(st->'stock', '[]'::jsonb);
  IF draw_mode = 'with' AND jsonb_array_length(stock) > 0 THEN
    drawn := stock -> 0; stock := stock - 0;
    hand := hand || jsonb_build_array(drawn);
    st := jsonb_set(st, ARRAY['hands', v_slot::text], hand, true);
    st := jsonb_set(st, '{stock}', stock, true);
    v_delay_ms := 500 + (floor(random() * 500))::int;
    st := jsonb_set(st, '{bot_locked_slot}', to_jsonb(v_slot), true);
    st := jsonb_set(st, '{bot_think_until}',
                    to_jsonb((now() + make_interval(secs => v_delay_ms / 1000.0))::text), true);
    v_playable := public._domino_playable_tiles(st, v_slot);
    st := jsonb_set(st, ARRAY['playable_tiles'], COALESCE(v_playable, '[]'::jsonb), true);
    UPDATE public.domino_games SET state = st,
           turn_deadline = now() + public._domino_turn_delay(_game_id, v_slot)
     WHERE id = _game_id;
    RETURN;
  END IF;

  -- Bot doit passer
  st := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1), true);
  st := jsonb_set(st, '{last_pass_by}', to_jsonb(v_slot), true);

  next_turn := public._domino_next_playable_slot(_game_id, v_slot, st);
  IF next_turn IS NULL THEN
    winner_slot := public._domino_lowest_pip_slot(_game_id, st);
    -- FIX: COALESCE winner_slot
    st := jsonb_set(st, ARRAY['turn_slot'], to_jsonb(COALESCE(winner_slot, v_slot)), true);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_end_round(_game_id, winner_slot);
    RETURN;
  END IF;

  v_next_delay := public._domino_turn_delay(_game_id, next_turn);
  st := public._domino_arm_bot_think(_game_id, next_turn, st);
  v_playable := public._domino_playable_tiles(st, next_turn);
  st := jsonb_set(st, ARRAY['playable_tiles'], COALESCE(v_playable, '[]'::jsonb), true);
  st := jsonb_set(st, ARRAY['turn_slot'], to_jsonb(next_turn), true);
  UPDATE public.domino_games SET state = st, current_turn = next_turn,
         turn_deadline = now() + v_next_delay
   WHERE id = _game_id;
END $$;

REVOKE ALL ON FUNCTION public._domino_bot_step(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public._domino_bot_step(uuid) TO service_role;
