-- ═══ Fix 1: Bot delay reduced from 1500-3500ms to 800-2000ms ═══
-- The bot was too slow, especially on the first domino of a round.
-- _domino_arm_bot_think and _domino_bot_step now use 800-2000ms.
CREATE OR REPLACE FUNCTION public._domino_arm_bot_think(_game_id uuid, _slot integer, _state jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_is_bot boolean := false; v_delay_ms int;
BEGIN
  SELECT COALESCE(dp.is_bot, false) INTO v_is_bot
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id AND dp.slot = _slot AND dp.forfeited = false;
  IF v_is_bot THEN
    v_delay_ms := 800 + (floor(random() * 1200))::int;
    _state := jsonb_set(_state, '{bot_locked_slot}', to_jsonb(_slot), true);
    _state := jsonb_set(_state, '{bot_think_until}',
             to_jsonb((now() + make_interval(secs => v_delay_ms / 1000.0))::text), true);
  ELSE
    _state := _state - 'bot_think_until' - 'bot_locked_slot';
  END IF;
  RETURN _state;
END;
$$;

-- ═══ Fix 2: Bot notifies when it has no playable domino ═══
-- _domino_bot_step now calls _domino_notify_all before passing,
-- so all players see the "no playable domino" message.
CREATE OR REPLACE FUNCTION public._domino_bot_step(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  g record; st jsonb; v_slot int; hand jsonb; le int; re int;
  draw_mode text; is_first_move boolean; first_dbl int; v_rule text;
  i int; j int; a int; b int; tile jsonb; placed jsonb;
  found boolean; found_i int; new_hand jsonb; new_left int; new_right int;
  next_turn int; winner_slot int; stock jsonb; drawn jsonb;
  _cfg record; v_is_bot boolean; phase text; v_think_until timestamptz;
  v_locked_slot int; v_delay_ms int; v_name text;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;
  st := g.state; phase := COALESCE(st->>'phase', 'play');
  IF phase NOT IN ('play','playing') THEN RETURN; END IF;
  v_slot := g.current_turn;
  SELECT COALESCE(dp.is_bot, false), COALESCE(dp.display_name, 'Bot') INTO v_is_bot, v_name
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id AND dp.slot = v_slot AND dp.forfeited = false;
  IF NOT COALESCE(v_is_bot, false) THEN RETURN; END IF;
  v_think_until := NULLIF(st->>'bot_think_until','')::timestamptz;
  v_locked_slot := NULLIF(st->>'bot_locked_slot','null')::int;
  IF v_think_until IS NULL OR v_locked_slot IS DISTINCT FROM v_slot THEN
    v_delay_ms := 800 + (floor(random() * 1200))::int;
    st := jsonb_set(st, '{bot_locked_slot}', to_jsonb(v_slot), true);
    st := jsonb_set(st, '{bot_think_until}', to_jsonb((now() + make_interval(secs => v_delay_ms / 1000.0))::text), true);
    UPDATE public.domino_games SET state = st WHERE id = _game_id; RETURN;
  END IF;
  IF v_think_until > now() THEN RETURN; END IF;
  st := st - 'bot_think_until' - 'bot_locked_slot';
  hand := COALESCE(st->'hands'->v_slot::text, '[]'::jsonb);
  le := NULLIF(st->>'left_end', 'null')::int; re := NULLIF(st->>'right_end', 'null')::int;
  draw_mode := COALESCE(st->>'draw_mode', 'with');
  v_rule := COALESCE(st->>'first_tile_rule', 'libre');
  is_first_move := jsonb_array_length(COALESCE(st->'board', '[]'::jsonb)) = 0;
  first_dbl := NULLIF(st->>'first_move_double', 'null')::int;
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
        ELSE found := true; found_i := i; EXIT; END IF;
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
      st := jsonb_set(st, '{board}', jsonb_build_array(placed), true); new_left := a; new_right := b;
    ELSE
      IF a = re OR b = re THEN
        IF a = re THEN placed := jsonb_build_object('tile', jsonb_build_array(a, b), 'flipped', false); new_right := b;
        ELSE placed := jsonb_build_object('tile', jsonb_build_array(b, a), 'flipped', false); new_right := a; END IF;
        new_left := le;
        st := jsonb_set(st, '{board}', COALESCE(st->'board','[]'::jsonb) || jsonb_build_array(placed), true);
      ELSE
        IF a = le THEN placed := jsonb_build_object('tile', jsonb_build_array(b, a), 'flipped', false); new_left := b;
        ELSE placed := jsonb_build_object('tile', jsonb_build_array(a, b), 'flipped', false); new_left := a; END IF;
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
      PERFORM public._domino_end_round(_game_id, v_slot); RETURN;
    END IF;
    next_turn := public._domino_next_playable_slot(_game_id, v_slot, st);
    IF next_turn IS NULL THEN
      winner_slot := public._domino_lowest_pip_slot(_game_id, st);
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
      PERFORM public._domino_end_round(_game_id, winner_slot); RETURN;
    END IF;
    st := public._domino_arm_bot_think(_game_id, next_turn, st);
    UPDATE public.domino_games SET state = st, current_turn = next_turn,
           turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
     WHERE id = _game_id; RETURN;
  END IF;
  -- Bot has no playable tile: notify all players
  PERFORM public._domino_notify_all(_game_id, v_slot, 'domino_pass',
    v_name || ' n''a pas de domino jouable',
    v_name || ' passe son tour', '{"reason": "no_playable"}'::jsonb);
  stock := COALESCE(st->'stock', '[]'::jsonb);
  IF draw_mode = 'with' AND jsonb_array_length(stock) > 0 THEN
    drawn := stock -> 0; stock := stock - 0;
    hand := hand || jsonb_build_array(drawn);
    st := jsonb_set(st, ARRAY['hands', v_slot::text], hand, true);
    st := jsonb_set(st, '{stock}', stock, true);
    v_delay_ms := 800 + (floor(random() * 1200))::int;
    st := jsonb_set(st, '{bot_locked_slot}', to_jsonb(v_slot), true);
    st := jsonb_set(st, '{bot_think_until}', to_jsonb((now() + make_interval(secs => v_delay_ms / 1000.0))::text), true);
    UPDATE public.domino_games SET state = st WHERE id = _game_id; RETURN;
  END IF;
  st := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1), true);
  st := jsonb_set(st, '{last_pass_by}', to_jsonb(v_slot), true);
  next_turn := public._domino_next_playable_slot(_game_id, v_slot, st);
  IF next_turn IS NULL THEN
    winner_slot := public._domino_lowest_pip_slot(_game_id, st);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_end_round(_game_id, winner_slot); RETURN;
  END IF;
  st := public._domino_arm_bot_think(_game_id, next_turn, st);
  UPDATE public.domino_games SET state = st, current_turn = next_turn,
         turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
   WHERE id = _game_id;
END;
$$;

-- ═══ Fix 3: Break between rounds = 10 seconds (was 13) ═══
CREATE OR REPLACE FUNCTION public._domino_end_round(_game_id uuid, _winner_slot integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  g record; st jsonb; winner_uid uuid; winner_key text; round_score int := 0;
  hand_pips jsonb := '{}'::jsonb; p record; pips int; v_scores jsonb; new_total int;
  v_final_hands jsonb := '{}'::jsonb; v_blocked boolean := false; winner_hand jsonb;
  v_reveal interval := interval '3 seconds';
  v_break_total interval := interval '10 seconds';
  p_key text;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN; END IF;
  SELECT user_id INTO winner_uid FROM public.domino_participants WHERE game_id = _game_id AND slot = _winner_slot;
  winner_key := COALESCE(winner_uid::text, 'bot_' || _winner_slot::text);
  st := g.state;
  winner_hand := st->'hands'->_winner_slot::text;
  v_blocked := COALESCE(jsonb_array_length(winner_hand), 0) > 0;
  FOR p IN SELECT slot, user_id FROM public.domino_participants WHERE game_id = _game_id LOOP
    p_key := COALESCE(p.user_id::text, 'bot_' || p.slot::text);
    pips := public._domino_hand_pips(st->'hands'->p.slot::text);
    hand_pips := hand_pips || jsonb_build_object(p_key, pips);
    v_final_hands := v_final_hands || jsonb_build_object(p_key, COALESCE(st->'hands'->p.slot::text, '[]'::jsonb));
    IF p.slot <> _winner_slot THEN round_score := round_score + pips; END IF;
  END LOOP;
  IF COALESCE(g.target_score,0) <= 0 THEN
    PERFORM public._domino_finalize(_game_id, _winner_slot); RETURN;
  END IF;
  v_scores := COALESCE(g.scores, '{}'::jsonb);
  new_total := COALESCE((v_scores->>winner_key)::int, 0) + round_score;
  v_scores := jsonb_set(v_scores, ARRAY[winner_key], to_jsonb(new_total), true);
  UPDATE public.domino_games SET scores = v_scores WHERE id = _game_id;
  IF new_total >= g.target_score THEN
    st := jsonb_set(st, '{last_round}', jsonb_build_object('winner_uid', winner_uid, 'winner_slot', _winner_slot,
      'round_score', round_score, 'hand_pips', hand_pips, 'final_hands', v_final_hands, 'blocked', v_blocked, 'final', true));
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_finalize(_game_id, _winner_slot); RETURN;
  END IF;
  st := jsonb_set(st, '{phase}', '"reveal"'::jsonb);
  st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text));
  st := jsonb_set(st, '{break_until}', to_jsonb((now() + v_break_total)::text));
  st := jsonb_set(st, '{last_round}', jsonb_build_object('winner_uid', winner_uid, 'winner_slot', _winner_slot,
    'round_score', round_score, 'hand_pips', hand_pips, 'final_hands', v_final_hands, 'blocked', v_blocked, 'final', false));
  st := jsonb_set(st, '{scores}', v_scores);
  UPDATE public.domino_games SET state = st, turn_deadline = NULL WHERE id = _game_id;
END;
$$;
