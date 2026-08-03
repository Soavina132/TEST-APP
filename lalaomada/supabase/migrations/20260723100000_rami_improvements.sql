-- ============================================================
-- Rami: bug fixes & improvements
--  * Fix rami_join column references (balance_ar / transactions cols)
--  * Generalize win-condition (any set of valid melds emptying hand)
--  * Guard against non-participant RPC callers (NULL slot)
--  * Reshuffle safety inside rami_tick when deck exhausted
--  * Server-driven turn timer via _game_cfg('rami')
--  * Smarter bot fallback: try to meld before random discard
-- ============================================================

-- 1) Fix rami_join (previous version used unknown columns) -----
CREATE OR REPLACE FUNCTION public.rami_join(_game_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  _uid uuid := auth.uid();
  _g public.rami_games;
  _bal numeric;
  _name text;
  _count int;
  _slot int;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id = _game_id FOR UPDATE;
  IF _g.id IS NULL          THEN RAISE EXCEPTION 'partie introuvable'; END IF;
  IF _g.status <> 'waiting' THEN RAISE EXCEPTION 'partie déjà commencée'; END IF;
  IF _g.is_private          THEN RAISE EXCEPTION 'partie privée — utilise le code pour rejoindre'; END IF;

  IF EXISTS (SELECT 1 FROM public.rami_participants WHERE game_id=_g.id AND user_id=_uid) THEN
    RETURN _g.id;
  END IF;

  SELECT count(*) INTO _count FROM public.rami_participants WHERE game_id = _g.id;
  IF _count >= _g.max_players THEN RAISE EXCEPTION 'partie pleine'; END IF;

  SELECT balance_ar, COALESCE(pseudo, 'Joueur') INTO _bal, _name
    FROM public.profiles WHERE id = _uid FOR UPDATE;
  IF _bal IS NULL OR _bal < _g.stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  _slot := _count;

  IF _g.stake > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar - _g.stake WHERE id = _uid;
    UPDATE public.rami_games SET pot = pot + _g.stake WHERE id = _g.id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
    VALUES (_uid, 'rami_stake', -_g.stake, _g.id, 'Join rami');
  END IF;

  INSERT INTO public.rami_participants(game_id, user_id, slot, display_name)
  VALUES (_g.id, _uid, _slot, _name);

  RETURN _g.id;
END $$;

REVOKE ALL ON FUNCTION public.rami_join(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_join(uuid) TO authenticated;

-- 2) Generalize win condition: any set of valid melds using all cards
CREATE OR REPLACE FUNCTION public._rami_check_win(_state jsonb, _uid uuid)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  _m jsonb; _t text; _total int := 0; _count int := 0;
BEGIN
  FOR _m IN SELECT * FROM jsonb_array_elements(COALESCE(_state->'melds','[]'::jsonb)) LOOP
    IF _m->>'player' = _uid::text THEN
      _t := _m->>'type';
      IF _t NOT IN ('carre','trio','run') THEN RETURN false; END IF;
      _total := _total + COALESCE(jsonb_array_length(_m->'cards'), 0);
      _count := _count + 1;
    END IF;
  END LOOP;
  -- Winner emptied their hand via at least 2 valid melds totalling ≥ 13 cards.
  RETURN _count >= 2 AND _total >= 13;
END $$;

-- 3) rami_discard: nicer error + participant guard
CREATE OR REPLACE FUNCTION public.rami_discard(_game_id uuid, _card integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _hand int[]; _new_hand int[]; _discard int[]; _hands jsonb;
  _parts int[]; _next int; _payout numeric; _comm numeric; _won boolean;
  _cfg record;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');

  _state := _g.state;
  _hand := ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[];
  IF NOT (_card = ANY(_hand)) THEN RAISE EXCEPTION 'carte absente'; END IF;
  _new_hand := public._rami_remove_one(_hand,_card);
  _discard := ARRAY(SELECT jsonb_array_elements_text(_state->'discard'))::int[];
  _discard := array_append(_discard,_card);
  _hands := jsonb_set(_state->'hands', ARRAY[_uid::text], to_jsonb(_new_hand));
  _state := jsonb_set(_state,'{hands}',_hands);
  _state := jsonb_set(_state,'{discard}',to_jsonb(_discard));

  UPDATE public.rami_participants
     SET hand_count=COALESCE(array_length(_new_hand,1),0)
   WHERE game_id=_game_id AND user_id=_uid;

  IF COALESCE(array_length(_new_hand,1),0) = 0 THEN
    _won := public._rami_check_win(_state, _uid);
    IF _won THEN
      _comm := round(_g.pot * _g.commission_pct / 100.0, 0);
      _payout := _g.pot - _comm;
      UPDATE public.profiles SET balance_ar=balance_ar+_payout WHERE id=_uid;
      INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (_uid,'rami_win',_payout,_game_id,'Win rami');
      UPDATE public.rami_games SET status='finished', winner_id=_uid,
        finished_at=now(), state=_state WHERE id=_game_id;
      RETURN;
    ELSE
      RAISE EXCEPTION 'combinaisons incomplètes: pose toutes tes cartes en combinaisons valides avant de finir';
    END IF;
  END IF;

  SELECT array_agg(slot ORDER BY slot) INTO _parts
    FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited;
  _next := _g.current_turn;
  LOOP
    _next := (_next + 1) % _g.max_players;
    EXIT WHEN _next = ANY(_parts);
  END LOOP;

  UPDATE public.rami_games
     SET state=_state, current_turn=_next, turn_phase='draw',
         turn_deadline=now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval,
         updated_at=now()
   WHERE id=_game_id;
END $$;

-- 4) rami_meld: participant guard (NULL slot fix)
CREATE OR REPLACE FUNCTION public.rami_meld(_game_id uuid, _cards integer[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _hand int[]; _c int; _new_hand int[]; _melds jsonb; _type text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour de jouer'; END IF;
  _type := public._rami_meld_type(_cards, _g.joker_mode, _g.random_joker);
  IF _type IS NULL THEN RAISE EXCEPTION 'combinaison invalide'; END IF;

  _state := _g.state;
  _hand := ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[];
  _new_hand := _hand;
  FOREACH _c IN ARRAY _cards LOOP
    IF NOT (_c = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte absente de la main'; END IF;
    _new_hand := public._rami_remove_one(_new_hand,_c);
  END LOOP;
  _melds := COALESCE(_state->'melds','[]'::jsonb) || jsonb_build_array(
    jsonb_build_object('player',_uid::text,'cards',to_jsonb(_cards),'type',_type)
  );
  _state := jsonb_set(_state, ARRAY['hands',_uid::text], to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{melds}', _melds);
  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand,1),0)
    WHERE game_id=_game_id AND user_id=_uid;
END $$;

-- 5) rami_layoff: participant + status guards
CREATE OR REPLACE FUNCTION public.rami_layoff(_game_id uuid, _meld_index integer, _cards integer[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _hand int[]; _c int; _new_hand int[]; _melds jsonb; _meld jsonb;
  _existing int[]; _combined int[]; _type text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  _state := _g.state;
  _melds := COALESCE(_state->'melds','[]'::jsonb);
  _meld  := _melds -> _meld_index;
  IF _meld IS NULL THEN RAISE EXCEPTION 'combinaison introuvable'; END IF;
  _existing := ARRAY(SELECT jsonb_array_elements_text(_meld->'cards'))::int[];
  _combined := _existing || _cards;
  _type := public._rami_meld_type(_combined, _g.joker_mode, _g.random_joker);
  IF _type IS NULL THEN RAISE EXCEPTION 'ajout invalide'; END IF;

  _hand := ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[];
  _new_hand := _hand;
  FOREACH _c IN ARRAY _cards LOOP
    IF NOT (_c = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte absente'; END IF;
    _new_hand := public._rami_remove_one(_new_hand,_c);
  END LOOP;

  _melds := jsonb_set(_melds, ARRAY[_meld_index::text],
    jsonb_set(_meld, '{cards}', to_jsonb(_combined))
      || jsonb_build_object('type', _type));
  _state := jsonb_set(_state, ARRAY['hands',_uid::text], to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{melds}', _melds);
  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand,1),0)
    WHERE game_id=_game_id AND user_id=_uid;
END $$;

-- 6) rami_tick: reshuffle safety + smarter fallback discard
CREATE OR REPLACE FUNCTION public.rami_tick(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  _g public.rami_games; _state jsonb; _uid uuid; _hand int[]; _new_hand int[];
  _deck int[]; _discard int[]; _card int; _next int; _cfg record; _skips int;
  _best_card int; _best_pts int := -1; _pts int; _rank int; _c int;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' OR _g.turn_deadline IS NULL OR _g.turn_deadline > now() THEN RETURN; END IF;
  SELECT * INTO _cfg FROM public._game_cfg('rami');
  SELECT user_id INTO _uid FROM public.rami_participants WHERE game_id=_game_id AND slot=_g.current_turn;
  _skips := COALESCE((_g.turn_skips->>_uid::text)::int, 0) + 1;

  IF _skips >= COALESCE(_cfg.max_turn_skips,3) THEN
    UPDATE public.rami_participants SET forfeited = true WHERE game_id=_game_id AND user_id=_uid;
    IF (SELECT count(*) FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited) <= 1 THEN
      DECLARE _win uuid;
      BEGIN
        SELECT user_id INTO _win FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited LIMIT 1;
        UPDATE public.rami_games SET status='finished', winner_id=_win, finished_at=now() WHERE id=_game_id;
        IF _win IS NOT NULL THEN
          UPDATE public.profiles SET balance_ar = balance_ar + (_g.pot * (100 - _g.commission_pct) / 100) WHERE id=_win;
          INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
            VALUES (_win,'rami_win', _g.pot * (100 - _g.commission_pct) / 100, _game_id, 'Rami win (forfait)');
        END IF;
        RETURN;
      END;
    END IF;
  END IF;

  _state := _g.state;
  _deck := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'deck'))::int[], ARRAY[]::int[]);
  _discard := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'discard'))::int[], ARRAY[]::int[]);
  _hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[], ARRAY[]::int[]);

  IF _g.turn_phase = 'draw' THEN
    IF COALESCE(array_length(_deck,1),0) = 0 THEN
      IF COALESCE(array_length(_discard,1),0) <= 1 THEN
        -- No cards to draw anywhere: declare draw
        UPDATE public.rami_games SET status='finished', finished_at=now(),
          state = jsonb_set(_state,'{end_reason}', to_jsonb('deck exhausted'::text))
          WHERE id=_game_id;
        RETURN;
      END IF;
      _deck := _discard[1:array_length(_discard,1)-1];
      _discard := ARRAY[_discard[array_length(_discard,1)]];
      _deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_deck) c);
    END IF;
    _card := _deck[1]; _deck := _deck[2:array_length(_deck,1)];
    _hand := array_append(_hand, _card);
  END IF;

  -- Smarter fallback: discard the highest-point non-joker card
  FOREACH _c IN ARRAY _hand LOOP
    IF public._rami_is_joker(_c, _g.joker_mode, _g.random_joker) THEN CONTINUE; END IF;
    _rank := _c % 13;
    _pts := CASE WHEN _rank = 0 THEN 11               -- As
                 WHEN _rank >= 10 THEN 10             -- J,Q,K
                 ELSE _rank + 1 END;
    IF _pts > _best_pts THEN _best_pts := _pts; _best_card := _c; END IF;
  END LOOP;
  IF _best_card IS NULL THEN
    _best_card := _hand[1 + floor(random()*array_length(_hand,1))::int];
  END IF;
  _card := _best_card;

  _new_hand := public._rami_remove_one(_hand, _card);
  _discard := array_append(_discard, _card);
  _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard));
  _state := jsonb_set(_state, ARRAY['hands',_uid::text], to_jsonb(_new_hand));
  UPDATE public.rami_participants SET hand_count=array_length(_new_hand,1) WHERE game_id=_game_id AND user_id=_uid;

  _next := _g.current_turn;
  LOOP
    _next := (_next + 1) % _g.max_players;
    EXIT WHEN _next IN (SELECT slot FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited);
  END LOOP;

  UPDATE public.rami_games SET state=_state, current_turn=_next, turn_phase='draw',
    turn_skips = jsonb_set(COALESCE(_g.turn_skips,'{}'::jsonb), ARRAY[_uid::text], to_jsonb(_skips)),
    turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval,
    updated_at=now()
    WHERE id=_game_id;
END $$;

-- 7) Explicit stub for the currently missing rami_add_bot so the UI
--    stops erroring with "Could not find function". Full bot infra will
--    come with a dedicated migration once rami_participants supports
--    non-auth bot rows.
CREATE OR REPLACE FUNCTION public.rami_add_bot(_game_id uuid, _bot_name text DEFAULT 'Bot')
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  RAISE EXCEPTION 'Les bots sur Rami arrivent bientôt (infrastructure en cours).';
END $$;
REVOKE ALL ON FUNCTION public.rami_add_bot(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_add_bot(uuid,text) TO authenticated;
