-- ─────────────────────────────────────────────────────────────────────────────
-- Fix: Domino blocked game with equal pip counts → match nul instead of
-- declaring the first-slot player as winner.
--
-- Root cause: _domino_lowest_pip_slot used strict `< best_sum`, so when
-- multiple players have the same pip total it returned the player at the
-- lowest slot number. Now it returns NULL on a tie.
--
-- Chain of fixes:
--   1. _domino_lowest_pip_slot  → return NULL when ≥2 players tie
--   2. _domino_finalize         → handle NULL winner_slot (draw / refund)
--   3. _domino_end_round        → handle NULL winner_slot (blocked draw)
--   4. domino_play              → handle NULL from _domino_lowest_pip_slot
-- ─────────────────────────────────────────────────────────────────────────────

-- ① Fix _domino_lowest_pip_slot: return NULL on tie
CREATE OR REPLACE FUNCTION public._domino_lowest_pip_slot(_game_id uuid, _state jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  p record;
  cur_sum integer;
  best_sum integer := 2147483647;
  best_slot integer := NULL;
  tie_count integer := 0;
BEGIN
  FOR p IN
    SELECT slot FROM public.domino_participants
    WHERE game_id = _game_id AND forfeited = false
    ORDER BY slot
  LOOP
    cur_sum := public._domino_hand_pips(
      COALESCE(_state -> 'hands' -> p.slot::text, '[]'::jsonb)
    );
    IF cur_sum < best_sum THEN
      best_sum  := cur_sum;
      best_slot := p.slot;
      tie_count := 1;
    ELSIF cur_sum = best_sum THEN
      tie_count := tie_count + 1;   -- tie detected
    END IF;
  END LOOP;

  -- If multiple players share the minimum, it's a draw → return NULL
  IF tie_count > 1 THEN
    RETURN NULL;
  END IF;
  RETURN best_slot;
END;
$$;

-- ② Fix _domino_finalize: handle NULL winner (draw → refund pot equally)
CREATE OR REPLACE FUNCTION public._domino_finalize(_game_id uuid, _winner_slot int)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  g            record;
  winner_uid   uuid;
  payout       numeric;
  p            record;
  n_active     integer;
  refund_each  numeric;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status = 'finished' THEN RETURN; END IF;

  -- ── Draw: no winner ───────────────────────────────────────────────────────
  IF _winner_slot IS NULL THEN
    SELECT count(*) INTO n_active
    FROM public.domino_participants
    WHERE game_id = _game_id AND forfeited = false;

    IF n_active > 0 AND g.pot > 0 THEN
      refund_each := floor(g.pot / n_active);
      FOR p IN
        SELECT user_id FROM public.domino_participants
        WHERE game_id = _game_id AND forfeited = false
      LOOP
        UPDATE public.profiles
          SET balance_ar = balance_ar + refund_each
          WHERE id = p.user_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (p.user_id, 'domino_draw', refund_each, _game_id, 'Domino match nul – remboursement');
      END LOOP;
    END IF;

    UPDATE public.domino_games
      SET status = 'finished', winner_id = NULL, finished_at = now()
      WHERE id = _game_id;
    RETURN;
  END IF;

  -- ── Normal win ────────────────────────────────────────────────────────────
  SELECT user_id INTO winner_uid
  FROM public.domino_participants
  WHERE game_id = _game_id AND slot = _winner_slot;

  payout := g.pot * (100 - g.commission_pct) / 100;
  IF winner_uid IS NOT NULL THEN
    UPDATE public.profiles SET balance_ar = balance_ar + payout WHERE id = winner_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (winner_uid, 'domino_win', payout, _game_id, 'Domino win');
  END IF;
  UPDATE public.domino_games
    SET status = 'finished', winner_id = winner_uid, finished_at = now()
    WHERE id = _game_id;
END;
$$;

-- ③ Fix _domino_end_round: handle NULL winner (blocked draw in multi-round)
CREATE OR REPLACE FUNCTION public._domino_end_round(_game_id uuid, _winner_slot integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  g              record;
  st             jsonb;
  winner_uid     uuid;
  round_score    int  := 0;
  hand_pips      jsonb := '{}'::jsonb;
  v_final_hands  jsonb := '{}'::jsonb;
  p              record;
  pips           int;
  v_scores       jsonb;
  new_total      int;
  v_blocked      boolean := false;
  winner_hand    jsonb;
  v_reveal       interval := interval '3 seconds';
  v_break_total  interval := interval '13 seconds';
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN; END IF;

  -- ── Blocked draw: no single winner ───────────────────────────────────────
  IF _winner_slot IS NULL THEN
    st := g.state;
    FOR p IN SELECT slot, user_id FROM public.domino_participants WHERE game_id = _game_id LOOP
      pips := public._domino_hand_pips(st->'hands'->p.slot::text);
      hand_pips     := hand_pips     || jsonb_build_object(p.user_id::text, pips);
      v_final_hands := v_final_hands || jsonb_build_object(p.user_id::text, COALESCE(st->'hands'->p.slot::text, '[]'::jsonb));
    END LOOP;
    st := jsonb_set(st, '{last_round}', jsonb_build_object(
      'winner_uid', NULL::text, 'round_score', 0, 'hand_pips', hand_pips,
      'final_hands', v_final_hands, 'blocked', true, 'draw', true, 'final', true
    ));
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_finalize(_game_id, NULL);
    RETURN;
  END IF;

  -- ── Normal round win ─────────────────────────────────────────────────────
  SELECT user_id INTO winner_uid FROM public.domino_participants WHERE game_id = _game_id AND slot = _winner_slot;
  st := g.state;

  winner_hand := st->'hands'->_winner_slot::text;
  v_blocked   := COALESCE(jsonb_array_length(winner_hand), 0) > 0;

  FOR p IN SELECT slot, user_id FROM public.domino_participants WHERE game_id = _game_id LOOP
    pips := public._domino_hand_pips(st->'hands'->p.slot::text);
    hand_pips     := hand_pips     || jsonb_build_object(p.user_id::text, pips);
    v_final_hands := v_final_hands || jsonb_build_object(p.user_id::text, COALESCE(st->'hands'->p.slot::text, '[]'::jsonb));
    IF p.slot <> _winner_slot THEN round_score := round_score + pips; END IF;
  END LOOP;

  IF COALESCE(g.target_score, 0) <= 0 THEN
    PERFORM public._domino_finalize(_game_id, _winner_slot);
    RETURN;
  END IF;

  v_scores  := COALESCE(g.scores, '{}'::jsonb);
  new_total := COALESCE((v_scores->>winner_uid::text)::int, 0) + round_score;
  v_scores  := jsonb_set(v_scores, ARRAY[winner_uid::text], to_jsonb(new_total), true);
  UPDATE public.domino_games SET scores = v_scores WHERE id = _game_id;

  IF new_total >= g.target_score THEN
    st := jsonb_set(st, '{last_round}', jsonb_build_object(
      'winner_uid', winner_uid, 'round_score', round_score, 'hand_pips', hand_pips,
      'final_hands', v_final_hands, 'blocked', v_blocked, 'final', true
    ));
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_finalize(_game_id, _winner_slot);
    RETURN;
  END IF;

  st := jsonb_set(st, '{phase}', '"reveal"'::jsonb);
  st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text));
  st := jsonb_set(st, '{break_until}',  to_jsonb((now() + v_break_total)::text));
  st := jsonb_set(st, '{last_round}', jsonb_build_object(
    'winner_uid', winner_uid, 'round_score', round_score, 'hand_pips', hand_pips,
    'final_hands', v_final_hands, 'blocked', v_blocked, 'final', false
  ));
  st := jsonb_set(st, '{scores}', v_scores);
  UPDATE public.domino_games SET state = st, turn_deadline = NULL WHERE id = _game_id;
END;
$$;

-- ④ Fix domino_play: add ELSE draw branch after _domino_lowest_pip_slot calls
--    (Replaces the latest full version that has the two winner_slot IS NOT NULL checks)
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

  -- ── Draw tile ──────────────────────────────────────────────────────────────
  IF action = 'draw' THEN
    IF draw_mode = 'without' THEN RAISE EXCEPTION 'draw disabled in this game'; END IF;
    IF stock_len = 0 THEN RAISE EXCEPTION 'stock empty'; END IF;
    drawn := stock -> 0; stock := stock - 0;
    hand  := hand || jsonb_build_array(drawn);
    st := jsonb_set(st, ARRAY['hands', my_slot::text], hand);
    st := jsonb_set(st, '{stock}', stock);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    RETURN;
  END IF;

  -- ── Pass ───────────────────────────────────────────────────────────────────
  IF action = 'pass' THEN
    IF draw_mode = 'with' AND stock_len > 0 THEN RAISE EXCEPTION 'you must draw first'; END IF;
    st        := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1));
    next_turn := public._domino_next_playable_slot(_game_id, my_slot, st);
    IF (st->>'passes')::int >= n_players THEN
      -- All passed → blocked game
      winner_slot := public._domino_lowest_pip_slot(_game_id, st);
      -- winner_slot IS NULL means equal pips → draw
      PERFORM public._domino_end_round(_game_id, winner_slot);
      RETURN;
    END IF;
    IF next_turn IS NULL THEN
      -- No one can play → blocked
      winner_slot := public._domino_lowest_pip_slot(_game_id, st);
      PERFORM public._domino_end_round(_game_id, winner_slot);
      RETURN;
    END IF;
    st := jsonb_set(st, '{current_turn}', to_jsonb(next_turn));
    UPDATE public.domino_games SET state = st, current_turn = next_turn, turn_deadline = now() + interval '30 seconds' WHERE id = _game_id;
    RETURN;
  END IF;

  -- ── Play tile ──────────────────────────────────────────────────────────────
  IF action <> 'play' THEN RAISE EXCEPTION 'unknown action'; END IF;

  tile := _move -> 'tile';
  IF tile IS NULL THEN RAISE EXCEPTION 'tile required'; END IF;
  a := (tile->>0)::int; b := (tile->>1)::int;
  side := _move->>'side';

  -- Validate the player has this tile
  found := false;
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

  -- First move: must be on empty board
  first_dbl := NULLIF(st->>'first_move_double', 'null')::int;
  IF le IS NULL THEN
    IF first_dbl IS NOT NULL AND a <> b THEN RAISE EXCEPTION 'first move must be the highest double'; END IF;
    IF first_dbl IS NOT NULL AND a <> first_dbl THEN RAISE EXCEPTION 'first move must be the highest double'; END IF;
    new_left  := b; new_right := a;
    st := jsonb_set(st, '{board}', jsonb_build_array(tile));
  ELSE
    -- Determine side
    IF side = 'left' OR side IS NULL THEN
      IF a = le THEN new_left := b;
      ELSIF b = le THEN new_left := a; a := b; b := (tile->>0)::int;
      ELSIF side = 'left' THEN RAISE EXCEPTION 'tile does not fit left';
      ELSE side := 'right'; END IF;
    END IF;
    IF side = 'right' THEN
      IF a = re THEN new_right := b;
      ELSIF b = re THEN new_right := a;
      ELSE RAISE EXCEPTION 'tile does not fit'; END IF;
    END IF;
    new_left  := CASE WHEN side = 'left'  THEN new_left  ELSE le END;
    new_right := CASE WHEN side = 'right' THEN new_right ELSE re END;
    st := jsonb_set(st, '{board}', (st->'board') || jsonb_build_array(tile));
  END IF;

  st := jsonb_set(st, ARRAY['hands', my_slot::text], new_hand);
  st := jsonb_set(st, '{left_end}',  to_jsonb(new_left));
  st := jsonb_set(st, '{right_end}', to_jsonb(new_right));
  st := jsonb_set(st, '{passes}',    to_jsonb(0));
  st := jsonb_set(st, '{first_move_double}', 'null'::jsonb);

  -- Win: player emptied their hand
  IF jsonb_array_length(new_hand) = 0 THEN
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_end_round(_game_id, my_slot);
    RETURN;
  END IF;

  -- Advance turn
  next_turn := public._domino_next_playable_slot(_game_id, my_slot, st);
  IF next_turn IS NULL THEN
    -- Board is blocked
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    winner_slot := public._domino_lowest_pip_slot(_game_id, st);
    -- winner_slot IS NULL → equal pips → draw
    PERFORM public._domino_end_round(_game_id, winner_slot);
    RETURN;
  END IF;

  st := jsonb_set(st, '{current_turn}', to_jsonb(next_turn));
  UPDATE public.domino_games
    SET state = st, current_turn = next_turn,
        turn_deadline = now() + interval '30 seconds'
    WHERE id = _game_id;
END;
$$;
