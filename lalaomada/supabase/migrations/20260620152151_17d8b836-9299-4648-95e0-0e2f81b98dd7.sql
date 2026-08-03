
CREATE OR REPLACE FUNCTION public.rami_layoff(_game_id uuid, _meld_index integer, _cards integer[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _uid uuid := auth.uid(); _g rami_games; _slot int; _state jsonb;
  _hand int[]; _c int; _new_hand int[]; _melds jsonb; _existing int[]; _combined int[];
  _new_type text; _old_type text;
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  SELECT slot INTO _slot FROM rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;
  _state := _g.state;
  _melds := _state->'melds';
  IF _meld_index < 0 OR _meld_index >= jsonb_array_length(_melds) THEN RAISE EXCEPTION 'meld inexistant'; END IF;
  _existing := ARRAY(SELECT jsonb_array_elements_text(_melds->_meld_index->'cards'))::int[];
  _combined := _existing || _cards;
  _new_type := public._rami_meld_type(_combined, _g.joker_mode, _g.random_joker);
  IF _new_type IS NULL THEN RAISE EXCEPTION 'ajout invalide'; END IF;
  _old_type := _melds->_meld_index->>'type';
  -- Layoff doit conserver la nature trio↔carré ou run
  IF _old_type IS NOT NULL THEN
    IF (_old_type IN ('trio','carre') AND _new_type NOT IN ('trio','carre'))
       OR (_old_type = 'run' AND _new_type <> 'run') THEN
      RAISE EXCEPTION 'ajout invalide';
    END IF;
  END IF;
  _hand := ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[];
  _new_hand := _hand;
  FOREACH _c IN ARRAY _cards LOOP
    IF NOT (_c = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte absente'; END IF;
    _new_hand := _rami_remove_one(_new_hand, _c);
  END LOOP;
  _melds := jsonb_set(_melds, ARRAY[_meld_index::text, 'cards'], to_jsonb(_combined));
  _melds := jsonb_set(_melds, ARRAY[_meld_index::text, 'type'], to_jsonb(_new_type));
  _state := jsonb_set(_state, '{hands,'||_uid::text||'}', to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{melds}', _melds);
  UPDATE rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  UPDATE rami_participants SET hand_count=COALESCE(array_length(_new_hand,1),0) WHERE game_id=_game_id AND user_id=_uid;
END $$;
