CREATE OR REPLACE FUNCTION public.rami_claim_seven(_game_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  _uid uuid := auth.uid();
  _g public.rami_games;
  _state jsonb; _melds jsonb; _m jsonb;
  _idx int; _i int; _j int;
  _mine int[] := ARRAY[]::int[];        -- indices of my melds
  _cards_i int[]; _cards_j int[]; _combo int[];
  _stake numeric; _refunded jsonb; _found boolean := false;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid) THEN
    RAISE EXCEPTION 'non participant';
  END IF;

  _state := public._rami_normalize_state(_g.state);
  _melds := COALESCE(_state->'melds','[]'::jsonb);
  IF jsonb_typeof(_melds) <> 'array' THEN RETURN false; END IF;

  _idx := 0;
  FOR _m IN SELECT * FROM jsonb_array_elements(_melds) LOOP
    IF _m->>'player' = _uid::text THEN _mine := _mine || _idx; END IF;
    _idx := _idx + 1;
  END LOOP;

  IF COALESCE(array_length(_mine,1),0) < 2 THEN RETURN false; END IF;

  FOR _i IN 1..array_length(_mine,1) LOOP
    FOR _j IN (_i+1)..array_length(_mine,1) LOOP
      _cards_i := public._rami_jarr(_melds->_mine[_i]->'cards');
      _cards_j := public._rami_jarr(_melds->_mine[_j]->'cards');
      IF COALESCE(array_length(_cards_i,1),0) + COALESCE(array_length(_cards_j,1),0) = 7 THEN
        _combo := _cards_i || _cards_j;
        IF public._rami_is_seven(_combo, _g.joker_mode, _g.random_joker) THEN
          _melds := jsonb_set(_melds, ARRAY[_mine[_i]::text,'seven'], 'true'::jsonb, true);
          _melds := jsonb_set(_melds, ARRAY[_mine[_j]::text,'seven'], 'true'::jsonb, true);
          _found := true;
          EXIT;
        END IF;
      END IF;
    END LOOP;
    EXIT WHEN _found;
  END LOOP;

  IF NOT _found THEN RETURN false; END IF;

  _state := jsonb_set(_state, '{melds}', _melds, true);
  _state := jsonb_set(_state, '{last_seven}', jsonb_build_object('player',_uid::text,'at',to_jsonb(now())), true);

  _refunded := COALESCE(_state->'refunded','{}'::jsonb);
  IF jsonb_typeof(_refunded) <> 'object' THEN _refunded := '{}'::jsonb; END IF;
  IF NOT (_refunded ? _uid::text) THEN
    _stake := COALESCE(_g.stake,0);
    IF _stake > 0 THEN
      UPDATE public.profiles SET balance_ar = balance_ar + _stake WHERE id = _uid;
      INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (_uid,'rami_refund',_stake,_game_id,'Retour de mise — 7 cartes (miverim-bola)');
      UPDATE public.rami_games SET pot = GREATEST(pot - _stake, 0) WHERE id = _game_id;
    END IF;
    _state := jsonb_set(_state,'{refunded}', _refunded || jsonb_build_object(_uid::text,true), true);
  END IF;

  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  RETURN true;
END $$;

REVOKE ALL ON FUNCTION public.rami_claim_seven(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_claim_seven(uuid) TO authenticated;