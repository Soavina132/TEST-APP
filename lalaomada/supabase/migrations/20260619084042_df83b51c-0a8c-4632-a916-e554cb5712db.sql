CREATE OR REPLACE FUNCTION public.rami_create(_stake numeric, _max integer, _private boolean, _commission integer)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _uid uuid := auth.uid();
  _id uuid;
  _code text;
  _bal numeric;
  _name text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _max < 2 OR _max > 4 THEN RAISE EXCEPTION 'players 2-4'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'stake invalid'; END IF;

  SELECT balance_ar, COALESCE(pseudo, 'Joueur') INTO _bal, _name
    FROM public.profiles
   WHERE id = _uid
   FOR UPDATE;

  IF _bal IS NULL OR _bal < _stake THEN RAISE EXCEPTION 'solde insuffisant'; END IF;
  _code := public._rami_gen_code();

  INSERT INTO public.rami_games (room_code, is_private, stake, max_players, commission_pct, created_by, pot)
  VALUES (_code, COALESCE(_private, true), _stake, _max, COALESCE(_commission, 10), _uid, _stake)
  RETURNING id INTO _id;

  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = _uid;
    INSERT INTO public.transactions (user_id, type, amount, ref_id, note)
    VALUES (_uid, 'rami_stake', -_stake, _id, 'Create rami');
  END IF;

  INSERT INTO public.rami_participants (game_id, user_id, slot, display_name)
  VALUES (_id, _uid, 0, _name);

  RETURN _id;
END;
$$;

CREATE OR REPLACE FUNCTION public.rami_join_code(_code text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _uid uuid := auth.uid();
  _g public.rami_games;
  _slot int;
  _bal numeric;
  _name text;
  _count int;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;

  SELECT * INTO _g FROM public.rami_games WHERE room_code = upper(_code) FOR UPDATE;
  IF _g.id IS NULL THEN RAISE EXCEPTION 'partie introuvable'; END IF;
  IF _g.status <> 'waiting' THEN RAISE EXCEPTION 'partie déjà commencée'; END IF;
  IF EXISTS (SELECT 1 FROM public.rami_participants WHERE game_id = _g.id AND user_id = _uid) THEN RETURN _g.id; END IF;

  SELECT count(*) INTO _count FROM public.rami_participants WHERE game_id = _g.id;
  IF _count >= _g.max_players THEN RAISE EXCEPTION 'partie pleine'; END IF;

  SELECT balance_ar, COALESCE(pseudo, 'Joueur') INTO _bal, _name
    FROM public.profiles
   WHERE id = _uid
   FOR UPDATE;

  IF _bal IS NULL OR _bal < _g.stake THEN RAISE EXCEPTION 'solde insuffisant'; END IF;
  _slot := _count;

  IF _g.stake > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar - _g.stake WHERE id = _uid;
    UPDATE public.rami_games SET pot = pot + _g.stake WHERE id = _g.id;
    INSERT INTO public.transactions (user_id, type, amount, ref_id, note)
    VALUES (_uid, 'rami_stake', -_g.stake, _g.id, 'Join rami');
  END IF;

  INSERT INTO public.rami_participants (game_id, user_id, slot, display_name)
  VALUES (_g.id, _uid, _slot, _name);

  RETURN _g.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.rami_discard(_game_id uuid, _card integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _uid uuid := auth.uid();
  _g public.rami_games;
  _slot int;
  _state jsonb;
  _hand int[];
  _new_hand int[];
  _discard int[];
  _hands jsonb;
  _parts int[];
  _next int;
  _payout numeric;
  _comm numeric;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id = _game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;

  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id = _game_id AND user_id = _uid;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  _state := _g.state;
  _hand := ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[];
  IF NOT (_card = ANY(_hand)) THEN RAISE EXCEPTION 'carte absente'; END IF;

  _new_hand := public._rami_remove_one(_hand, _card);
  _discard := ARRAY(SELECT jsonb_array_elements_text(_state->'discard'))::int[];
  _discard := array_append(_discard, _card);
  _hands := jsonb_set(_state->'hands', ARRAY[_uid::text], to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{hands}', _hands);
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard));

  UPDATE public.rami_participants
     SET hand_count = COALESCE(array_length(_new_hand, 1), 0)
   WHERE game_id = _game_id AND user_id = _uid;

  IF COALESCE(array_length(_new_hand, 1), 0) = 0 THEN
    _comm := round(_g.pot * _g.commission_pct / 100.0, 0);
    _payout := _g.pot - _comm;
    UPDATE public.profiles SET balance_ar = balance_ar + _payout WHERE id = _uid;
    INSERT INTO public.transactions (user_id, type, amount, ref_id, note)
    VALUES (_uid, 'rami_win', _payout, _game_id, 'Win rami');
    UPDATE public.rami_games SET status = 'finished', winner_id = _uid, finished_at = now(), state = _state WHERE id = _game_id;
    RETURN;
  END IF;

  SELECT array_agg(slot ORDER BY slot) INTO _parts
    FROM public.rami_participants
   WHERE game_id = _game_id AND NOT forfeited;

  _next := _g.current_turn;
  LOOP
    _next := (_next + 1) % _g.max_players;
    EXIT WHEN _next = ANY(_parts);
  END LOOP;

  UPDATE public.rami_games
     SET state = _state,
         current_turn = _next,
         turn_phase = 'draw',
         turn_deadline = now() + interval '45 seconds',
         updated_at = now()
   WHERE id = _game_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.rami_forfeit(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _uid uuid := auth.uid();
  _g public.rami_games;
  _alive uuid[];
  _winner uuid;
  _payout numeric;
  _comm numeric;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id = _game_id FOR UPDATE;
  IF _g.status NOT IN ('waiting', 'playing') THEN RETURN; END IF;

  UPDATE public.rami_participants SET forfeited = true WHERE game_id = _game_id AND user_id = _uid;
  SELECT array_agg(user_id) INTO _alive FROM public.rami_participants WHERE game_id = _game_id AND NOT forfeited;

  IF _g.status = 'waiting' THEN
    UPDATE public.rami_games SET status = 'finished', finished_at = now() WHERE id = _game_id;
    IF _g.stake > 0 THEN
      UPDATE public.profiles SET balance_ar = balance_ar + _g.stake WHERE id = _uid;
      INSERT INTO public.transactions (user_id, type, amount, ref_id, note)
      VALUES (_uid, 'rami_refund', _g.stake, _game_id, 'Refund rami');
    END IF;
    RETURN;
  END IF;

  IF COALESCE(array_length(_alive, 1), 0) = 1 THEN
    _winner := _alive[1];
    _comm := round(_g.pot * _g.commission_pct / 100.0, 0);
    _payout := _g.pot - _comm;
    UPDATE public.profiles SET balance_ar = balance_ar + _payout WHERE id = _winner;
    INSERT INTO public.transactions (user_id, type, amount, ref_id, note)
    VALUES (_winner, 'rami_win', _payout, _game_id, 'Win rami by forfeit');
    UPDATE public.rami_games SET status = 'finished', winner_id = _winner, finished_at = now() WHERE id = _game_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rami_create(numeric, integer, boolean, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rami_join_code(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rami_discard(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rami_forfeit(uuid) TO authenticated;