
-- Lecteur sûr: renvoie toujours un int[] (jamais d'erreur sur scalaire/null)
CREATE OR REPLACE FUNCTION public._rami_jarr(_v jsonb)
RETURNS integer[] LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN _v IS NULL OR jsonb_typeof(_v) <> 'array'
              THEN ARRAY[]::int[]
              ELSE COALESCE((SELECT array_agg(x::int) FROM jsonb_array_elements_text(_v) x), ARRAY[]::int[])
         END
$$;

-- Ecriture sûre: un tableau vide/NULL devient [] et non 'null'
CREATE OR REPLACE FUNCTION public._rami_jset(_a integer[])
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT COALESCE(to_jsonb(_a), '[]'::jsonb)
$$;

-- Map de défausses robuste
CREATE OR REPLACE FUNCTION public._rami_discards_map(_state jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE _m jsonb; _out jsonb := '{}'::jsonb; _k text; _v jsonb;
BEGIN
  _m := _state->'discards';
  IF _m IS NULL OR jsonb_typeof(_m) <> 'object' THEN
    IF jsonb_typeof(COALESCE(_state->'discard','null'::jsonb)) = 'array'
       AND jsonb_array_length(_state->'discard') > 0 THEN
      RETURN jsonb_build_object('_seed', _state->'discard');
    END IF;
    RETURN '{}'::jsonb;
  END IF;
  FOR _k, _v IN SELECT * FROM jsonb_each(_m) LOOP
    IF jsonb_typeof(_v) = 'array' AND jsonb_array_length(_v) > 0 THEN
      _out := _out || jsonb_build_object(_k, _v);
    END IF;
  END LOOP;
  RETURN _out;
END $$;

-- Normalisation: répare deck / hands / discards s'ils sont null ou scalaires
CREATE OR REPLACE FUNCTION public._rami_normalize_state(_state jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE _s jsonb := _state; _hands jsonb := '{}'::jsonb; _k text; _v jsonb;
BEGIN
  IF _s IS NULL THEN RETURN _s; END IF;

  IF jsonb_typeof(COALESCE(_s->'deck','null'::jsonb)) <> 'array' THEN
    _s := jsonb_set(_s, '{deck}', '[]'::jsonb, true);
  END IF;

  IF jsonb_typeof(COALESCE(_s->'melds','null'::jsonb)) <> 'array' THEN
    _s := jsonb_set(_s, '{melds}', '[]'::jsonb, true);
  END IF;

  IF jsonb_typeof(COALESCE(_s->'hands','null'::jsonb)) = 'object' THEN
    FOR _k, _v IN SELECT * FROM jsonb_each(_s->'hands') LOOP
      _hands := _hands || jsonb_build_object(
        _k, CASE WHEN jsonb_typeof(_v) = 'array' THEN _v ELSE '[]'::jsonb END);
    END LOOP;
  END IF;
  _s := jsonb_set(_s, '{hands}', _hands, true);

  _s := jsonb_set(_s, '{discards}', public._rami_discards_map(_state), true);
  IF NOT (_s ? 'last_discard_by') THEN
    _s := jsonb_set(_s, '{last_discard_by}', to_jsonb(public._rami_last_discarder(_state)), true);
  END IF;
  RETURN _s;
END $$;

CREATE OR REPLACE FUNCTION public._rami_all_discards(_state jsonb)
RETURNS integer[] LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE _m jsonb := public._rami_discards_map(_state);
  _k text; _acc int[] := ARRAY[]::int[];
BEGIN
  FOR _k IN SELECT jsonb_object_keys(_m) LOOP
    _acc := _acc || public._rami_jarr(_m->_k);
  END LOOP;
  RETURN _acc;
END $$;

CREATE OR REPLACE FUNCTION public._rami_check_win(_state jsonb, _key text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path TO 'public' AS $$
DECLARE _carre int := 0; _trio int := 0; _run int := 0; _total int := 0;
  _m jsonb; _t text; _cards int[]; _n int; _melds jsonb;
BEGIN
  _melds := _state->'melds';
  IF jsonb_typeof(COALESCE(_melds,'null'::jsonb)) <> 'array' THEN RETURN false; END IF;
  FOR _m IN SELECT * FROM jsonb_array_elements(_melds) LOOP
    IF _m->>'player' = _key THEN
      _t := _m->>'type';
      _cards := public._rami_jarr(_m->'cards');
      _n := COALESCE(array_length(_cards,1),0);
      _total := _total + _n;
      IF _t = 'carre' THEN _carre := _carre + 1;
      ELSIF _t = 'trio' THEN _trio := _trio + 1;
      ELSIF _t = 'run'  THEN _run  := _run  + 1;
      ELSIF _t = 'seven' THEN _carre := _carre + 1; _trio := _trio + 1; _run := _run + 1;
      END IF;
    END IF;
  END LOOP;
  RETURN _carre >= 1 AND _trio >= 2 AND _run >= 1 AND _total >= 13;
END $$;

CREATE OR REPLACE FUNCTION public._rami_reshuffle(_state jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  _m jsonb := public._rami_discards_map(_state);
  _last text := public._rami_last_discarder(_state);
  _top_pile int[] := public._rami_jarr(_m->_last);
  _keep int; _pool int[] := ARRAY[]::int[]; _k text; _arr int[]; _new_deck int[]; _new_map jsonb;
BEGIN
  IF array_length(_top_pile,1) IS NULL THEN
    RETURN jsonb_build_object('deck','[]'::jsonb,'discards','{}'::jsonb,'last', _last);
  END IF;
  _keep := _top_pile[array_length(_top_pile,1)];
  FOR _k IN SELECT jsonb_object_keys(_m) LOOP
    _arr := public._rami_jarr(_m->_k);
    IF _k = _last THEN _arr := _arr[1:array_length(_arr,1)-1]; END IF;
    IF array_length(_arr,1) IS NOT NULL THEN _pool := _pool || _arr; END IF;
  END LOOP;
  _new_deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_pool) c);
  _new_map := jsonb_build_object(_last, jsonb_build_array(_keep));
  RETURN jsonb_build_object(
    'deck', COALESCE(to_jsonb(_new_deck), '[]'::jsonb),
    'discards', _new_map,
    'last', _last
  );
END $$;

-- POSE (validation explicite uniquement, jamais automatique)
CREATE OR REPLACE FUNCTION public.rami_meld(_game_id uuid, _cards integer[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
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
  END IF;

  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand,1),0)
    WHERE game_id=_game_id AND user_id=_uid;
END $$;

-- CASSER une combinaison déjà posée (uniquement la sienne, à son tour)
CREATE OR REPLACE FUNCTION public.rami_unmeld(_game_id uuid, _meld_index integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _melds jsonb; _m jsonb; _cards int[]; _hand int[]; _new_melds jsonb := '[]'::jsonb;
  _i int; _stake numeric; _refunded jsonb; _bal numeric;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour de jouer'; END IF;

  _state := public._rami_normalize_state(_g.state);
  _melds := _state->'melds';
  IF _meld_index < 0 OR _meld_index >= jsonb_array_length(_melds) THEN
    RAISE EXCEPTION 'combinaison introuvable';
  END IF;
  _m := _melds->_meld_index;
  IF _m->>'player' <> _uid::text THEN RAISE EXCEPTION 'ce n''est pas ta combinaison'; END IF;

  _cards := public._rami_jarr(_m->'cards');
  _hand  := public._rami_jarr(_state->'hands'->_uid::text) || _cards;

  FOR _i IN 0..jsonb_array_length(_melds)-1 LOOP
    IF _i <> _meld_index THEN _new_melds := _new_melds || jsonb_build_array(_melds->_i); END IF;
  END LOOP;

  -- Annule le remboursement « 7 cartes » si c'était cette combinaison
  IF COALESCE(_m->>'type','') = 'seven' THEN
    _refunded := COALESCE(_state->'refunded','{}'::jsonb);
    IF jsonb_typeof(_refunded) <> 'object' THEN _refunded := '{}'::jsonb; END IF;
    IF _refunded ? _uid::text THEN
      _stake := COALESCE(_g.stake,0);
      IF _stake > 0 THEN
        SELECT balance_ar INTO _bal FROM public.profiles WHERE id=_uid FOR UPDATE;
        IF COALESCE(_bal,0) < _stake THEN
          RAISE EXCEPTION 'solde insuffisant pour annuler le retour de mise';
        END IF;
        UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id=_uid;
        INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
        VALUES (_uid,'rami_refund_cancel',-_stake,_game_id,'Annulation du retour de mise — 7 cartes cassées');
        UPDATE public.rami_games SET pot = pot + _stake WHERE id=_game_id;
      END IF;
      _state := jsonb_set(_state,'{refunded}', _refunded - _uid::text, true);
      _state := _state - 'last_seven';
    END IF;
  END IF;

  _state := jsonb_set(_state, '{melds}', _new_melds, true);
  _state := jsonb_set(_state, ARRAY['hands',_uid::text], public._rami_jset(_hand), true);

  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_hand,1),0)
    WHERE game_id=_game_id AND user_id=_uid;
END $$;

-- LAYOFF durci
CREATE OR REPLACE FUNCTION public.rami_layoff(_game_id uuid, _meld_index integer, _cards integer[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _hand int[]; _c int; _new_hand int[]; _melds jsonb; _existing int[]; _combined int[];
  _new_type text; _old_type text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL OR _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;
  _state := public._rami_normalize_state(_g.state);
  _melds := _state->'melds';
  IF _meld_index < 0 OR _meld_index >= jsonb_array_length(_melds) THEN RAISE EXCEPTION 'meld inexistant'; END IF;

  IF COALESCE(_g.game_mode,'bordel') = 'naturel'
     AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(_melds) m WHERE m->>'player' = _uid::text) THEN
    RAISE EXCEPTION 'Mode naturel : pose d''abord ta propre combinaison';
  END IF;

  _existing := public._rami_jarr(_melds->_meld_index->'cards');
  _combined := _existing || _cards;
  _new_type := public._rami_meld_type(_combined, _g.joker_mode, _g.random_joker);
  IF _new_type IS NULL THEN RAISE EXCEPTION 'ajout invalide'; END IF;
  _old_type := _melds->_meld_index->>'type';
  IF _old_type IS NOT NULL THEN
    IF (_old_type IN ('trio','carre') AND _new_type NOT IN ('trio','carre'))
       OR (_old_type = 'run' AND _new_type <> 'run') THEN
      RAISE EXCEPTION 'ajout invalide';
    END IF;
  END IF;

  _hand := public._rami_jarr(_state->'hands'->_uid::text);
  _new_hand := _hand;
  FOREACH _c IN ARRAY _cards LOOP
    IF NOT (_c = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte absente'; END IF;
    _new_hand := public._rami_remove_one(_new_hand, _c);
  END LOOP;

  _melds := jsonb_set(_melds, ARRAY[_meld_index::text, 'cards'], public._rami_jset(_combined), true);
  _melds := jsonb_set(_melds, ARRAY[_meld_index::text, 'type'], to_jsonb(_new_type), true);
  _state := jsonb_set(_state, ARRAY['hands',_uid::text], public._rami_jset(_new_hand), true);
  _state := jsonb_set(_state, '{melds}', _melds, true);
  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand,1),0) WHERE game_id=_game_id AND user_id=_uid;
END $$;

-- PIOCHE durcie
CREATE OR REPLACE FUNCTION public.rami_draw(_game_id uuid, _from text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _deck int[]; _pile int[]; _hand int[]; _card int; _hands jsonb; _cfg record;
  _discards jsonb; _last text; _reshuffle jsonb;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL OR _slot <> _g.current_turn THEN RAISE EXCEPTION 'pas ton tour'; END IF;
  IF _g.turn_phase <> 'draw' THEN RAISE EXCEPTION 'déjà pioché'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _state := public._rami_normalize_state(_g.state);
  _discards := public._rami_discards_map(_state);
  _last := public._rami_last_discarder(_state);
  _deck := public._rami_jarr(_state->'deck');
  _pile := public._rami_jarr(_discards->_last);
  _hand := public._rami_jarr(_state->'hands'->_uid::text);

  IF _from = 'discard' THEN
    IF array_length(_pile,1) IS NULL THEN RAISE EXCEPTION 'défausse vide'; END IF;
    _card := _pile[array_length(_pile,1)];
    _pile := _pile[1:array_length(_pile,1)-1];
    IF array_length(_pile,1) IS NULL THEN
      _discards := _discards - _last;
    ELSE
      _discards := jsonb_set(_discards, ARRAY[_last], public._rami_jset(_pile), true);
    END IF;
  ELSE
    IF array_length(_deck,1) IS NULL THEN
      _reshuffle := public._rami_reshuffle(_state);
      _deck := public._rami_jarr(_reshuffle->'deck');
      _discards := COALESCE(_reshuffle->'discards','{}'::jsonb);
      IF array_length(_deck,1) IS NULL THEN RAISE EXCEPTION 'plus de cartes'; END IF;
    END IF;
    _card := _deck[1];
    _deck := _deck[2:array_length(_deck,1)];
  END IF;

  _hand := array_append(_hand, _card);
  _hands := jsonb_set(_state->'hands', ARRAY[_uid::text], public._rami_jset(_hand), true);
  _state := jsonb_set(_state, '{deck}', public._rami_jset(_deck), true);
  _state := jsonb_set(_state, '{discards}', COALESCE(_discards,'{}'::jsonb), true);
  _state := jsonb_set(_state, '{hands}', _hands, true);
  _state := _state - 'discard';

  UPDATE public.rami_games
     SET state = _state, turn_phase = 'play',
         turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
         updated_at = now()
   WHERE id = _game_id;

  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_hand,1),0)
   WHERE game_id=_game_id AND user_id=_uid;
END $$;

-- DEFAUSSE durcie
CREATE OR REPLACE FUNCTION public.rami_discard(_game_id uuid, _card integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _hand int[]; _new_hand int[]; _pile int[]; _hands jsonb; _discards jsonb;
  _parts int[]; _next int; _cfg record;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _state := public._rami_normalize_state(_g.state);
  _discards := public._rami_discards_map(_state);
  _hand := public._rami_jarr(_state->'hands'->_uid::text);
  IF NOT (_card = ANY(_hand)) THEN RAISE EXCEPTION 'carte absente'; END IF;
  _new_hand := public._rami_remove_one(_hand,_card);

  _pile := public._rami_jarr(_discards->_uid::text);
  _pile := array_append(_pile, _card);
  _discards := jsonb_set(COALESCE(_discards,'{}'::jsonb), ARRAY[_uid::text], public._rami_jset(_pile), true);

  _hands := jsonb_set(_state->'hands', ARRAY[_uid::text], public._rami_jset(_new_hand), true);
  _state := jsonb_set(_state,'{hands}',_hands, true);
  _state := jsonb_set(_state,'{discards}',_discards, true);
  _state := jsonb_set(_state,'{last_discard_by}', to_jsonb(_uid::text), true);
  _state := _state - 'discard';

  UPDATE public.rami_participants
     SET hand_count=COALESCE(array_length(_new_hand,1),0)
   WHERE game_id=_game_id AND user_id=_uid;

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

  BEGIN
    PERFORM public._rami_autoplay_bots(_game_id);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END $$;

-- VALIDATION FINALE de la main durcie
CREATE OR REPLACE FUNCTION public.rami_validate_hand(_game_id uuid, _layout jsonb, _discard_card integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _hand int[]; _all_cards int[] := ARRAY[]::int[]; _grp jsonb; _grp_arr int[];
  _mtype text; _c int; _melds jsonb := '[]'::jsonb; _pile int[]; _discards jsonb;
  _payout numeric; _comm numeric;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id = _game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id = _game_id AND user_id = _uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN
    RAISE EXCEPTION 'ce n''est pas ton tour de valider';
  END IF;

  _state := public._rami_normalize_state(_g.state);
  _discards := public._rami_discards_map(_state);
  _hand := public._rami_jarr(_state->'hands'->_uid::text);

  IF NOT (_discard_card = ANY(_hand)) THEN
    RAISE EXCEPTION 'carte à défausser absente de la main';
  END IF;

  IF jsonb_typeof(COALESCE(_layout,'null'::jsonb)) <> 'array' THEN
    RAISE EXCEPTION 'aucune combinaison fournie';
  END IF;

  FOR _grp IN SELECT * FROM jsonb_array_elements(_layout) LOOP
    _grp_arr := public._rami_jarr(_grp);
    IF COALESCE(array_length(_grp_arr, 1), 0) < 3 THEN
      RAISE EXCEPTION 'un groupe doit contenir au moins 3 cartes';
    END IF;
    _mtype := public._rami_meld_type(_grp_arr, _g.joker_mode, _g.random_joker);
    IF _mtype IS NULL THEN
      RAISE EXCEPTION 'un des groupes est invalide (ni trio, ni carré, ni suite)';
    END IF;
    _all_cards := _all_cards || _grp_arr;
    _melds := _melds || jsonb_build_array(
      jsonb_build_object('player', _uid::text, 'cards', public._rami_jset(_grp_arr), 'type', _mtype)
    );
  END LOOP;

  _all_cards := _all_cards || ARRAY[_discard_card];

  IF COALESCE(array_length(_all_cards, 1), 0) <> COALESCE(array_length(_hand, 1), 0) THEN
    RAISE EXCEPTION 'toutes tes cartes doivent être placées dans des combinaisons';
  END IF;

  DECLARE _remaining int[] := _hand;
  BEGIN
    FOREACH _c IN ARRAY _all_cards LOOP
      IF NOT (_c = ANY(_remaining)) THEN RAISE EXCEPTION 'carte % absente de la main', _c; END IF;
      _remaining := public._rami_remove_one(_remaining, _c);
    END LOOP;
  END;

  _pile := public._rami_jarr(_discards->_uid::text) || ARRAY[_discard_card];
  _discards := jsonb_set(COALESCE(_discards,'{}'::jsonb), ARRAY[_uid::text], public._rami_jset(_pile), true);

  _state := jsonb_set(_state, ARRAY['hands', _uid::text], '[]'::jsonb, true);
  _state := jsonb_set(_state, '{discards}', _discards, true);
  _state := jsonb_set(_state, '{last_discard_by}', to_jsonb(_uid::text), true);
  _state := jsonb_set(_state, '{melds}', (_state->'melds') || _melds, true);
  _state := _state - 'discard';

  _comm := round(_g.pot * _g.commission_pct / 100.0, 0);
  _payout := _g.pot - _comm;

  UPDATE public.rami_participants SET hand_count = 0 WHERE game_id = _game_id AND user_id = _uid;

  IF _payout > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar + _payout WHERE id = _uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
    VALUES (_uid, 'rami_win', _payout, _game_id, 'Rami win (validation)');
  END IF;

  UPDATE public.rami_games
     SET status = 'finished', winner_id = _uid, finished_at = now(),
         state = _state, updated_at = now()
   WHERE id = _game_id;

  RETURN jsonb_build_object('ok', true, 'payout', _payout);
END $$;

GRANT EXECUTE ON FUNCTION public.rami_unmeld(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public._rami_jarr(jsonb) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public._rami_jset(integer[]) TO authenticated, anon, service_role;

-- Répare les états existants corrompus (main/deck enregistrés comme 'null')
UPDATE public.rami_games
   SET state = public._rami_normalize_state(state)
 WHERE status IN ('open','playing') AND state IS NOT NULL;
