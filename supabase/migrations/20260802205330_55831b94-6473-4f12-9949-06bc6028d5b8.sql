-- 1) Turn timer = 120s
UPDATE public.game_configs SET turn_timer_seconds = 120 WHERE slug = 'rami';

-- 2) rami_tick : 2 min -> 2e chance 3 min (une seule fois) -> forfait auto
CREATE OR REPLACE FUNCTION public.rami_tick(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  _g public.rami_games; _state jsonb; _uid uuid; _is_bot boolean;
  _extra jsonb; _key text; _next int; _left int; _win uuid; _payout numeric;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RETURN; END IF;

  SELECT COALESCE(is_bot,false), user_id INTO _is_bot, _uid
    FROM public.rami_participants WHERE game_id=_game_id AND slot=_g.current_turn;

  IF _is_bot THEN
    PERFORM public._rami_autoplay_bots(_game_id);
    RETURN;
  END IF;

  IF _g.turn_deadline IS NULL OR _g.turn_deadline > now() THEN RETURN; END IF;
  IF _uid IS NULL THEN RETURN; END IF;

  _state := public._rami_normalize_state(_g.state);
  _key := _uid::text;
  _extra := COALESCE(_state->'extra_time','{}'::jsonb);
  IF jsonb_typeof(_extra) <> 'object' THEN _extra := '{}'::jsonb; END IF;

  -- Première expiration : seconde chance de 3 minutes
  IF NOT (_extra ? _key) THEN
    _extra := _extra || jsonb_build_object(_key, true);
    _state := jsonb_set(_state, '{extra_time}', _extra, true);
    UPDATE public.rami_games
       SET state = _state,
           turn_deadline = now() + interval '3 minutes',
           updated_at = now()
     WHERE id = _game_id;
    RETURN;
  END IF;

  -- Deuxième expiration : forfait automatique
  UPDATE public.rami_participants SET forfeited = true
   WHERE game_id=_game_id AND user_id=_uid;

  SELECT count(*) INTO _left FROM public.rami_participants
   WHERE game_id=_game_id AND NOT forfeited;

  IF _left <= 1 THEN
    SELECT user_id INTO _win FROM public.rami_participants
     WHERE game_id=_game_id AND NOT forfeited LIMIT 1;
    UPDATE public.rami_games SET status='finished', winner_id=_win,
           finished_at=now(), state=_state, turn_deadline=NULL
     WHERE id=_game_id;
    IF _win IS NOT NULL THEN
      _payout := COALESCE(_g.pot,0) * (100 - COALESCE(_g.commission_pct,10)) / 100;
      IF _payout > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + _payout WHERE id=_win;
        INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
        VALUES (_win,'rami_win',_payout,_game_id,'Rami win (forfait temps)');
      END IF;
    END IF;
    RETURN;
  END IF;

  _next := _g.current_turn;
  LOOP
    _next := (_next + 1) % _g.max_players;
    EXIT WHEN _next IN (SELECT slot FROM public.rami_participants
                         WHERE game_id=_game_id AND NOT forfeited);
  END LOOP;

  UPDATE public.rami_games
     SET state=_state, current_turn=_next, turn_phase='draw',
         turn_deadline = now() + interval '2 minutes',
         updated_at=now()
   WHERE id=_game_id;

  PERFORM public._rami_autoplay_bots(_game_id);
END $function$;

-- 3) 7 cartes : un seul remboursement par partie (premier joueur qui valide)
CREATE OR REPLACE FUNCTION public.rami_claim_seven(_game_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  _uid uuid := auth.uid();
  _g public.rami_games;
  _state jsonb; _melds jsonb; _m jsonb;
  _idx int; _i int; _j int;
  _mine int[] := ARRAY[]::int[];
  _cards_i int[]; _cards_j int[]; _combo int[];
  _stake numeric; _refunded jsonb; _found boolean := false; _claimed text;
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

  _claimed := _state->>'seven_claimed';
  _refunded := COALESCE(_state->'refunded','{}'::jsonb);
  IF jsonb_typeof(_refunded) <> 'object' THEN _refunded := '{}'::jsonb; END IF;

  IF _claimed IS NULL AND NOT (_refunded ? _uid::text) THEN
    _stake := COALESCE(_g.stake,0);
    IF _stake > 0 THEN
      UPDATE public.profiles SET balance_ar = balance_ar + _stake WHERE id = _uid;
      INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (_uid,'rami_refund',_stake,_game_id,'Retour de mise — 7 cartes (miverim-bola)');
      UPDATE public.rami_games SET pot = GREATEST(pot - _stake, 0) WHERE id = _game_id;
    END IF;
    _state := jsonb_set(_state,'{refunded}', _refunded || jsonb_build_object(_uid::text,true), true);
    _state := jsonb_set(_state,'{seven_claimed}', to_jsonb(_uid::text), true);
  END IF;

  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  RETURN true;
END $function$;

-- 4) rami_meld : pose 7 cartes en une fois -> même verrou de remboursement
CREATE OR REPLACE FUNCTION public.rami_meld(_game_id uuid, _cards integer[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _hand int[]; _c int; _new_hand int[]; _melds jsonb; _type text; _seven boolean;
  _stake numeric; _refunded jsonb; _claimed text;
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

  _state := public._rami_normalize_state(_g.state);

  IF COALESCE(_g.game_mode,'bordel') = 'naturel'
     AND NOT EXISTS (
       SELECT 1 FROM jsonb_array_elements(_state->'melds') m
       WHERE m->>'player' = _uid::text
     )
     AND _type NOT IN ('trio','carre','run','seven') THEN
    RAISE EXCEPTION 'Mode naturel : ta première pose doit être un brelan (3 cartes) ou une suite de 3 cartes minimum';
  END IF;

  _hand := public._rami_jarr(_state->'hands'->_uid::text);
  _new_hand := _hand;
  FOREACH _c IN ARRAY _cards LOOP
    IF NOT (_c = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte absente de la main'; END IF;
    _new_hand := public._rami_remove_one(_new_hand,_c);
  END LOOP;

  _melds := _state->'melds' || jsonb_build_array(
    jsonb_build_object('player',_uid::text,'cards',public._rami_jset(_cards),'type',_type,'seven',_seven)
  );
  _state := jsonb_set(_state, ARRAY['hands',_uid::text], public._rami_jset(_new_hand), true);
  _state := jsonb_set(_state, '{melds}', _melds, true);

  IF _seven THEN
    _state := jsonb_set(_state, '{last_seven}', jsonb_build_object('player',_uid::text,'at',to_jsonb(now())), true);
    _claimed := _state->>'seven_claimed';
    _refunded := COALESCE(_state->'refunded','{}'::jsonb);
    IF jsonb_typeof(_refunded) <> 'object' THEN _refunded := '{}'::jsonb; END IF;
    IF _claimed IS NULL AND NOT (_refunded ? _uid::text) THEN
      _stake := COALESCE(_g.stake,0);
      IF _stake > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + _stake WHERE id = _uid;
        INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
        VALUES (_uid,'rami_refund',_stake,_game_id,'Retour de mise — 7 cartes (miverim-bola)');
        UPDATE public.rami_games SET pot = GREATEST(pot - _stake, 0) WHERE id = _game_id;
      END IF;
      _state := jsonb_set(_state,'{refunded}', _refunded || jsonb_build_object(_uid::text,true), true);
      _state := jsonb_set(_state,'{seven_claimed}', to_jsonb(_uid::text), true);
    END IF;
  END IF;

  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand,1),0)
    WHERE game_id=_game_id AND user_id=_uid;
END $function$;