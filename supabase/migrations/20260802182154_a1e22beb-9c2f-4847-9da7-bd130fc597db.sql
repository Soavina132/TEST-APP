CREATE OR REPLACE FUNCTION public.rami_meld(_game_id uuid, _cards integer[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _hand int[]; _c int; _new_hand int[]; _melds jsonb; _type text; _seven boolean;
  _stake numeric; _refunded jsonb;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour de jouer'; END IF;
  _type := public._rami_meld_type(_cards, _g.joker_mode, _g.random_joker);
  IF _type IS NULL THEN RAISE EXCEPTION 'combinaison invalide'; END IF;
  _seven := (_type = 'seven');

  _state := _g.state;

  IF COALESCE(_g.game_mode,'bordel') = 'naturel'
     AND NOT EXISTS (
       SELECT 1 FROM jsonb_array_elements(COALESCE(_state->'melds','[]'::jsonb)) m
       WHERE m->>'player' = _uid::text
     )
     AND _type NOT IN ('trio','carre','run','seven') THEN
    RAISE EXCEPTION 'Mode naturel : ta première pose doit être un brelan (3 cartes) ou une suite de 3 cartes minimum';
  END IF;

  _hand := ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[];
  _new_hand := _hand;
  FOREACH _c IN ARRAY _cards LOOP
    IF NOT (_c = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte absente de la main'; END IF;
    _new_hand := public._rami_remove_one(_new_hand,_c);
  END LOOP;
  _melds := COALESCE(_state->'melds','[]'::jsonb) || jsonb_build_array(
    jsonb_build_object('player',_uid::text,'cards',to_jsonb(_cards),'type',_type,'seven',_seven)
  );
  _state := jsonb_set(_state, ARRAY['hands',_uid::text], to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{melds}', _melds);

  IF _seven THEN
    _state := jsonb_set(_state, '{last_seven}', jsonb_build_object('player',_uid::text,'at',to_jsonb(now())));
    _refunded := COALESCE(_state->'refunded','{}'::jsonb);
    IF NOT (_refunded ? _uid::text) THEN
      _stake := COALESCE(_g.stake,0);
      IF _stake > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + _stake WHERE id = _uid;
        INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
        VALUES (_uid,'rami_refund',_stake,_game_id,'Retour de mise — 7 cartes (miverim-bola)');
        UPDATE public.rami_games SET pot = GREATEST(pot - _stake, 0) WHERE id = _game_id;
      END IF;
      _state := jsonb_set(_state,'{refunded}', _refunded || jsonb_build_object(_uid::text,true));
    END IF;
  END IF;

  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand,1),0)
    WHERE game_id=_game_id AND user_id=_uid;
END $function$;