
-- 1) Columns -------------------------------------------------------------
ALTER TABLE public.fanorona_games  ADD COLUMN IF NOT EXISTS turn_skips jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.domino_games    ADD COLUMN IF NOT EXISTS turn_skips jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.rami_games      ADD COLUMN IF NOT EXISTS turn_skips jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.chess_games     ADD COLUMN IF NOT EXISTS turn_skips jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.chess_games     ADD COLUMN IF NOT EXISTS turn_deadline timestamptz;
ALTER TABLE public.fanorona_games  ADD COLUMN IF NOT EXISTS turn_deadline timestamptz;

-- 2) Helper to read game config ----------------------------------------
CREATE OR REPLACE FUNCTION public._game_cfg(_slug text)
RETURNS TABLE(turn_timer_seconds integer, max_turn_skips integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT
    COALESCE((SELECT gc.turn_timer_seconds FROM public.game_configs gc WHERE gc.slug=_slug), 30)::int,
    COALESCE((SELECT gc.max_turn_skips     FROM public.game_configs gc WHERE gc.slug=_slug), 5)::int;
$$;

-- 3) FANORONA tick: skip turn, forfeit at max --------------------------
CREATE OR REPLACE FUNCTION public.fanorona_tick(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  g record; cur_uid uuid; _cfg record; _skips int; _next int;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' OR g.turn_deadline IS NULL OR g.turn_deadline > now() THEN
    RETURN;
  END IF;
  SELECT * INTO _cfg FROM public._game_cfg('fanorona');
  SELECT user_id INTO cur_uid FROM public.fanorona_participants WHERE game_id = _game_id AND slot = g.current_turn;
  _skips := COALESCE((g.turn_skips->>cur_uid::text)::int, 0) + 1;
  IF _skips >= _cfg.max_turn_skips THEN
    UPDATE public.fanorona_participants SET forfeited = true WHERE game_id = _game_id AND user_id = cur_uid;
    PERFORM public._fanorona_finalize(_game_id, 1 - g.current_turn);
    RETURN;
  END IF;
  _next := 1 - g.current_turn;
  UPDATE public.fanorona_games SET
    current_turn = _next,
    turn_skips = jsonb_set(g.turn_skips, ARRAY[cur_uid::text], to_jsonb(_skips)),
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
  WHERE id = _game_id;
END $$;

-- 4) DOMINO tick: skip turn, forfeit at max ----------------------------
CREATE OR REPLACE FUNCTION public.domino_tick(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  g record; cur_uid uuid; _cfg record; _skips int; _next int; remaining int; last_slot int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' OR g.turn_deadline IS NULL OR g.turn_deadline > now() THEN
    RETURN;
  END IF;
  SELECT * INTO _cfg FROM public._game_cfg('domino');
  SELECT user_id INTO cur_uid FROM public.domino_participants WHERE game_id = _game_id AND slot = g.current_turn;
  _skips := COALESCE((g.turn_skips->>cur_uid::text)::int, 0) + 1;

  IF _skips >= _cfg.max_turn_skips THEN
    UPDATE public.domino_participants SET forfeited = true WHERE game_id = _game_id AND user_id = cur_uid;
    SELECT count(*) INTO remaining FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
    IF remaining <= 1 THEN
      SELECT slot INTO last_slot FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false LIMIT 1;
      IF last_slot IS NOT NULL THEN
        PERFORM public._domino_finalize(_game_id, last_slot);
      ELSE
        UPDATE public.domino_games SET status='cancelled', finished_at=now() WHERE id = _game_id;
      END IF;
      RETURN;
    END IF;
  ELSE
    UPDATE public.domino_games
       SET turn_skips = jsonb_set(g.turn_skips, ARRAY[cur_uid::text], to_jsonb(_skips))
     WHERE id = _game_id;
  END IF;

  -- advance turn to next non-forfeited
  SELECT slot INTO _next
    FROM public.domino_participants
   WHERE game_id = _game_id AND forfeited = false AND slot > g.current_turn
   ORDER BY slot LIMIT 1;
  IF _next IS NULL THEN
    SELECT slot INTO _next FROM public.domino_participants
     WHERE game_id = _game_id AND forfeited = false ORDER BY slot LIMIT 1;
  END IF;
  IF _next IS NOT NULL THEN
    UPDATE public.domino_games
       SET current_turn = _next,
           turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
     WHERE id = _game_id;
  END IF;
END $$;

-- 5) RAMI tick: count skip, auto-play, forfeit at max -------------------
CREATE OR REPLACE FUNCTION public.rami_tick(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  _g rami_games; _state jsonb; _uid uuid; _hand int[]; _new_hand int[];
  _deck int[]; _discard int[]; _card int; _next int; _cfg record; _skips int;
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' OR _g.turn_deadline IS NULL OR _g.turn_deadline > now() THEN RETURN; END IF;
  SELECT * INTO _cfg FROM public._game_cfg('rami');
  SELECT user_id INTO _uid FROM rami_participants WHERE game_id=_game_id AND slot=_g.current_turn;
  _skips := COALESCE((_g.turn_skips->>_uid::text)::int, 0) + 1;

  IF _skips >= _cfg.max_turn_skips THEN
    UPDATE rami_participants SET forfeited = true WHERE game_id=_game_id AND user_id=_uid;
    -- advance to next non-forfeited, finalize if only one left
    IF (SELECT count(*) FROM rami_participants WHERE game_id=_game_id AND NOT forfeited) <= 1 THEN
      DECLARE _win uuid;
      BEGIN
        SELECT user_id INTO _win FROM rami_participants WHERE game_id=_game_id AND NOT forfeited LIMIT 1;
        UPDATE rami_games SET status='finished', winner_id=_win, finished_at=now() WHERE id=_game_id;
        IF _win IS NOT NULL THEN
          UPDATE profiles SET balance_ar = balance_ar + (_g.pot * (100 - _g.commission_pct) / 100) WHERE id=_win;
          INSERT INTO transactions(user_id,type,amount,ref_id,note)
            VALUES (_win,'rami_win', _g.pot * (100 - _g.commission_pct) / 100, _game_id, 'Rami win (forfait)');
        END IF;
        RETURN;
      END;
    END IF;
  END IF;

  _state := _g.state;
  _deck := ARRAY(SELECT jsonb_array_elements_text(_state->'deck'))::int[];
  _discard := ARRAY(SELECT jsonb_array_elements_text(_state->'discard'))::int[];
  _hand := ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[];

  IF _g.turn_phase = 'draw' THEN
    IF array_length(_deck,1) IS NULL THEN
      _deck := _discard[1:array_length(_discard,1)-1];
      _discard := ARRAY[_discard[array_length(_discard,1)]];
      _deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_deck) c);
    END IF;
    _card := _deck[1]; _deck := _deck[2:array_length(_deck,1)];
    _hand := array_append(_hand, _card);
  END IF;

  _card := _hand[1 + floor(random()*array_length(_hand,1))::int];
  _new_hand := _rami_remove_one(_hand, _card);
  _discard := array_append(_discard, _card);
  _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard));
  _state := jsonb_set(_state, ARRAY['hands',_uid::text], to_jsonb(_new_hand));
  UPDATE rami_participants SET hand_count=array_length(_new_hand,1) WHERE game_id=_game_id AND user_id=_uid;

  _next := _g.current_turn;
  LOOP
    _next := (_next + 1) % _g.max_players;
    EXIT WHEN _next IN (SELECT slot FROM rami_participants WHERE game_id=_game_id AND NOT forfeited);
  END LOOP;

  UPDATE rami_games SET state=_state, current_turn=_next, turn_phase='draw',
    turn_skips = jsonb_set(_g.turn_skips, ARRAY[_uid::text], to_jsonb(_skips)),
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
    updated_at=now()
    WHERE id=_game_id;
END $$;

-- 6) CHESS tick: skip move, forfeit at max -----------------------------
CREATE OR REPLACE FUNCTION public.chess_tick(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_g chess_games%ROWTYPE; cur_uid uuid; opp_uid uuid; _cfg record; _skips int;
BEGIN
  SELECT * INTO v_g FROM chess_games WHERE id=_game_id FOR UPDATE;
  IF v_g.status <> 'playing' OR v_g.turn_deadline IS NULL OR v_g.turn_deadline > now() THEN RETURN; END IF;
  SELECT * INTO _cfg FROM public._game_cfg('chess');
  IF v_g.turn = 'w' THEN cur_uid := v_g.white_id; opp_uid := v_g.black_id;
  ELSE cur_uid := v_g.black_id; opp_uid := v_g.white_id; END IF;
  _skips := COALESCE((v_g.turn_skips->>cur_uid::text)::int, 0) + 1;
  IF _skips >= _cfg.max_turn_skips THEN
    PERFORM public._chess_payout(_game_id, opp_uid, false);
    RETURN;
  END IF;
  UPDATE chess_games SET
    turn = CASE WHEN turn='w' THEN 'b' ELSE 'w' END,
    turn_skips = jsonb_set(v_g.turn_skips, ARRAY[cur_uid::text], to_jsonb(_skips)),
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
  WHERE id=_game_id;
END $$;

-- 7) chess_move: refresh deadline ---------------------------------------
CREATE OR REPLACE FUNCTION public.chess_move(_game_id uuid, _san text, _uci text, _fen_after text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_g chess_games%ROWTYPE; v_my text; _cfg record;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  v_my := CASE WHEN v_g.white_id = v_uid THEN 'w' WHEN v_g.black_id = v_uid THEN 'b' ELSE NULL END;
  IF v_my IS NULL THEN RAISE EXCEPTION 'not a player'; END IF;
  IF v_my <> v_g.turn THEN RAISE EXCEPTION 'not your turn'; END IF;
  SELECT * INTO _cfg FROM public._game_cfg('chess');
  INSERT INTO chess_moves(game_id, ply, san, uci, fen_after, by_user)
    VALUES (_game_id, v_g.ply + 1, _san, _uci, _fen_after, v_uid);
  UPDATE chess_games SET
    fen = _fen_after,
    turn = CASE WHEN v_g.turn='w' THEN 'b' ELSE 'w' END,
    ply = v_g.ply + 1,
    last_move_at = now(),
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
  WHERE id = _game_id;
END $$;

-- 8) chess_join_code: set first deadline when game starts ---------------
CREATE OR REPLACE FUNCTION public.chess_join_code(_code text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_g chess_games%ROWTYPE; v_bal numeric; v_flip boolean; _cfg record;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE room_code = upper(_code) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status <> 'open' THEN RAISE EXCEPTION 'game not open'; END IF;
  IF v_g.host_id = v_uid THEN RAISE EXCEPTION 'cannot join own game'; END IF;
  SELECT balance_ar INTO v_bal FROM profiles WHERE id = v_uid;
  IF v_bal < v_g.stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;
  SELECT * INTO _cfg FROM public._game_cfg('chess');
  v_flip := (random() < 0.5);
  IF v_flip THEN
    UPDATE chess_games SET black_id = v_uid, status='playing', started_at=now(),
      pot = pot + v_g.stake, turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
      WHERE id = v_g.id;
  ELSE
    UPDATE chess_games SET white_id = v_uid, black_id = v_g.host_id, status='playing', started_at=now(),
      pot = pot + v_g.stake, turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
      WHERE id = v_g.id;
  END IF;
  UPDATE profiles SET balance_ar = balance_ar - v_g.stake WHERE id = v_uid;
  INSERT INTO transactions(user_id, type, amount, ref_id, note) VALUES (v_uid, 'chess_stake', -v_g.stake, v_g.id, 'Join chess');
  RETURN v_g.id;
END $$;
