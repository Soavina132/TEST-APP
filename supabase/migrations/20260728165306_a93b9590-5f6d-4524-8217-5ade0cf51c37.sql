
-- rami_validate_hand : validation manuelle de la main complète
-- _layout est un tableau de groupes de cartes, ex: [[1,2,3],[10,23,36],[5,6,7,8]]
-- La dernière carte de la main (14e après pioche) n'est PAS dans _layout : c'est la carte défaussée.
CREATE OR REPLACE FUNCTION public.rami_validate_hand(_game_id uuid, _layout jsonb, _discard_card integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  _uid uuid := auth.uid();
  _g public.rami_games;
  _slot int;
  _state jsonb;
  _hand int[];
  _all_cards int[] := ARRAY[]::int[];
  _grp jsonb;
  _grp_arr int[];
  _mtype text;
  _c int;
  _melds jsonb := '[]'::jsonb;
  _discard int[];
  _payout numeric;
  _comm numeric;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id = _game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id = _game_id AND user_id = _uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN
    RAISE EXCEPTION 'ce n''est pas ton tour de valider';
  END IF;

  _state := _g.state;
  _hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[], ARRAY[]::int[]);

  -- Vérifie que la carte à défausser est dans la main
  IF NOT (_discard_card = ANY(_hand)) THEN
    RAISE EXCEPTION 'carte à défausser absente de la main';
  END IF;

  -- Valide chaque groupe
  FOR _grp IN SELECT * FROM jsonb_array_elements(COALESCE(_layout, '[]'::jsonb)) LOOP
    _grp_arr := ARRAY(SELECT jsonb_array_elements_text(_grp))::int[];
    IF COALESCE(array_length(_grp_arr, 1), 0) < 3 THEN
      RAISE EXCEPTION 'un groupe doit contenir au moins 3 cartes';
    END IF;
    _mtype := public._rami_meld_type(_grp_arr, _g.joker_mode, _g.random_joker);
    IF _mtype IS NULL THEN
      RAISE EXCEPTION 'un des groupes est invalide (ni trio, ni carré, ni suite)';
    END IF;
    _all_cards := _all_cards || _grp_arr;
    _melds := _melds || jsonb_build_array(
      jsonb_build_object('player', _uid::text, 'cards', to_jsonb(_grp_arr), 'type', _mtype)
    );
  END LOOP;

  -- Ajoute la carte défaussée à la liste totale attendue
  _all_cards := _all_cards || ARRAY[_discard_card];

  -- Toutes les cartes de la main doivent être utilisées (validation + défausse)
  IF COALESCE(array_length(_all_cards, 1), 0) <> COALESCE(array_length(_hand, 1), 0) THEN
    RAISE EXCEPTION 'toutes tes cartes doivent être placées dans des combinaisons';
  END IF;

  -- Vérifie que chaque carte du layout est bien dans la main (multi-ensemble)
  DECLARE
    _remaining int[] := _hand;
  BEGIN
    FOREACH _c IN ARRAY _all_cards LOOP
      IF NOT (_c = ANY(_remaining)) THEN
        RAISE EXCEPTION 'carte % absente de la main', _c;
      END IF;
      _remaining := public._rami_remove_one(_remaining, _c);
    END LOOP;
  END;

  -- OK : pose les melds, défausse la carte, marque gagnant
  _discard := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'discard'))::int[], ARRAY[]::int[]);
  _discard := array_append(_discard, _discard_card);
  _state := jsonb_set(_state, ARRAY['hands', _uid::text], to_jsonb(ARRAY[]::int[]));
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard));
  _state := jsonb_set(_state, '{melds}', (COALESCE(_state->'melds','[]'::jsonb) || _melds));

  _comm := round(_g.pot * _g.commission_pct / 100.0, 0);
  _payout := _g.pot - _comm;

  UPDATE public.rami_participants
     SET hand_count = 0
   WHERE game_id = _game_id AND user_id = _uid;

  IF _payout > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar + _payout WHERE id = _uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
    VALUES (_uid, 'rami_win', _payout, _game_id, 'Rami win (validation)');
  END IF;

  UPDATE public.rami_games
     SET status = 'finished',
         winner_id = _uid,
         finished_at = now(),
         state = _state,
         updated_at = now()
   WHERE id = _game_id;

  RETURN jsonb_build_object('ok', true, 'payout', _payout);
END $$;

REVOKE ALL ON FUNCTION public.rami_validate_hand(uuid, jsonb, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_validate_hand(uuid, jsonb, integer) TO authenticated;

-- Neutralise la détection auto de victoire dans rami_discard :
-- Le joueur ne gagne plus qu'en appelant rami_validate_hand.
CREATE OR REPLACE FUNCTION public.rami_discard(_game_id uuid, _card integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _hand int[]; _new_hand int[]; _discard int[]; _hands jsonb;
  _parts int[]; _next int; _cfg record;
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

  -- Plus de détection auto de victoire : le joueur doit cliquer sur « Valider ma main ».

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
