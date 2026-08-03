
-- ============ Schema additions ============
ALTER TABLE public.rami_games
  ADD COLUMN IF NOT EXISTS joker_mode text NOT NULL DEFAULT 'classique',
  ADD COLUMN IF NOT EXISTS random_joker integer;

ALTER TABLE public.rami_games DROP CONSTRAINT IF EXISTS rami_games_joker_mode_chk;
ALTER TABLE public.rami_games ADD CONSTRAINT rami_games_joker_mode_chk
  CHECK (joker_mode IN ('sans','aleatoire','classique','double'));

-- ============ Joker helper ============
CREATE OR REPLACE FUNCTION public._rami_is_joker(_c int, _mode text, _rj int)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE _rd int; _sd int; _r int; _s int; _color_d int; _color int;
BEGIN
  IF _c IS NULL THEN RETURN false; END IF;
  IF _c >= 52 AND _mode IN ('classique','double') THEN RETURN true; END IF;
  IF _mode IN ('aleatoire','double') AND _rj IS NOT NULL AND _c < 52 AND _rj < 52 THEN
    _rd := _rj % 13; _sd := _rj / 13;
    _r  := _c  % 13; _s  := _c  / 13;
    IF _r = _rd AND _s <> _sd THEN
      _color_d := CASE WHEN _sd IN (0,3) THEN 0 ELSE 1 END; -- 0 = noir, 1 = rouge
      _color   := CASE WHEN _s  IN (0,3) THEN 0 ELSE 1 END;
      IF _color <> _color_d THEN RETURN true; END IF; -- Vrai Joker = couleur opposée
    END IF;
  END IF;
  RETURN false;
END $$;

-- ============ Meld validator (typed) ============
CREATE OR REPLACE FUNCTION public._rami_meld_type(_cards int[], _mode text, _rj int)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  _n int := COALESCE(array_length(_cards,1),0);
  _c int; _jokers int := 0; _reals int := 0;
  _rank int := -1; _suit int := -1; _r int; _s int;
  _ranks int[] := ARRAY[]::int[];
  _is_set boolean := true; _is_run boolean := true;
  _try_high int; _base int; _ok boolean; _used boolean[]; _idx int;
BEGIN
  IF _n < 3 THEN RETURN NULL; END IF;
  FOREACH _c IN ARRAY _cards LOOP
    IF _c < 0 THEN RETURN NULL; END IF;
    IF public._rami_is_joker(_c,_mode,_rj) THEN
      _jokers := _jokers + 1;
    ELSE
      IF _c >= 52 THEN RETURN NULL; END IF; -- classique joker non actif dans ce mode
      _reals := _reals + 1;
      _r := _c % 13; _s := _c / 13;
      IF _rank = -1 THEN _rank := _r; ELSIF _rank <> _r THEN _is_set := false; END IF;
      IF _suit = -1 THEN _suit := _s; ELSIF _suit <> _s THEN _is_run := false; END IF;
      _ranks := _ranks || _r;
    END IF;
  END LOOP;
  IF _reals < 2 THEN RETURN NULL; END IF;
  IF _jokers > _reals THEN RETURN NULL; END IF;

  -- TRIO / CARRE
  IF _is_set AND _n IN (3,4) THEN
    IF _n = 4 THEN RETURN 'carre'; ELSE RETURN 'trio'; END IF;
  END IF;

  -- ESCALIER
  IF _is_run THEN
    FOR _try_high IN 0..1 LOOP
      DECLARE _rs int[] := _ranks; _i int; BEGIN
        IF _try_high = 1 THEN
          FOR _i IN 1..array_length(_rs,1) LOOP
            IF _rs[_i] = 0 THEN _rs[_i] := 13; END IF;
          END LOOP;
        END IF;
        -- distinct ranks
        IF (SELECT count(*) FROM (SELECT DISTINCT unnest(_rs)) x) <> array_length(_rs,1) THEN
          CONTINUE;
        END IF;
        FOR _base IN GREATEST(0,(SELECT min(x) FROM unnest(_rs) x) - _jokers)
                  .. LEAST(13 - _n + 1, (SELECT min(x) FROM unnest(_rs) x)) LOOP
          _used := array_fill(false, ARRAY[_n]); _ok := true;
          FOR _i IN 1..array_length(_rs,1) LOOP
            _idx := _rs[_i] - _base + 1;
            IF _idx < 1 OR _idx > _n OR _used[_idx] THEN _ok := false; EXIT; END IF;
            _used[_idx] := true;
          END LOOP;
          IF _ok THEN RETURN 'run'; END IF;
        END LOOP;
      END;
    END LOOP;
  END IF;
  RETURN NULL;
END $$;

-- ============ rami_create with joker_mode ============
DROP FUNCTION IF EXISTS public.rami_create(numeric, integer, boolean, integer);
DROP FUNCTION IF EXISTS public.rami_create(numeric, integer, boolean, integer, text);
CREATE OR REPLACE FUNCTION public.rami_create(
  _stake numeric, _max integer, _private boolean, _commission integer,
  _joker_mode text DEFAULT 'classique'
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _uid uuid := auth.uid(); _id uuid; _code text; _bal numeric; _name text; _mode text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _max < 2 OR _max > 4 THEN RAISE EXCEPTION 'players 2-4'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'stake invalid'; END IF;
  _mode := COALESCE(_joker_mode,'classique');
  IF _mode NOT IN ('sans','aleatoire','classique','double') THEN
    RAISE EXCEPTION 'mode joker invalide';
  END IF;

  SELECT balance_ar, COALESCE(pseudo,'Joueur') INTO _bal,_name
    FROM public.profiles WHERE id=_uid FOR UPDATE;
  IF _bal IS NULL OR _bal < _stake THEN RAISE EXCEPTION 'solde insuffisant'; END IF;
  _code := public._rami_gen_code();

  INSERT INTO public.rami_games (room_code,is_private,stake,max_players,commission_pct,created_by,pot,joker_mode)
  VALUES (_code,COALESCE(_private,true),_stake,_max,COALESCE(_commission,10),_uid,_stake,_mode)
  RETURNING id INTO _id;

  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar=balance_ar-_stake WHERE id=_uid;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
    VALUES (_uid,'rami_stake',-_stake,_id,'Create rami');
  END IF;

  INSERT INTO public.rami_participants(game_id,user_id,slot,display_name)
  VALUES (_id,_uid,0,_name);

  RETURN _id;
END $$;

-- ============ rami_start (13 cards, joker draw, random first player) ============
CREATE OR REPLACE FUNCTION public.rami_start(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _g rami_games; _parts uuid[]; _deck int[]; _i int; _j int; _tmp int;
  _hands jsonb := '{}'::jsonb; _p uuid; _hand int[]; _state jsonb;
  _max int; _rj int := NULL; _first int; _top int;
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'waiting' THEN RETURN; END IF;
  SELECT array_agg(user_id ORDER BY slot) INTO _parts FROM rami_participants WHERE game_id=_game_id;
  IF array_length(_parts,1) < 2 THEN RAISE EXCEPTION 'pas assez de joueurs'; END IF;

  -- Deck size by mode
  IF _g.joker_mode IN ('classique','double') THEN _max := 56; -- 0..51 + 4 jokers (52..55)
  ELSE _max := 52; END IF;
  _deck := ARRAY(SELECT generate_series(0,_max-1));

  -- Fisher-Yates
  FOR _i IN REVERSE _max..2 LOOP
    _j := 1 + floor(random()*_i)::int;
    _tmp := _deck[_i]; _deck[_i] := _deck[_j]; _deck[_j] := _tmp;
  END LOOP;

  -- Deal 13 to each
  FOREACH _p IN ARRAY _parts LOOP
    _hand := _deck[1:13];
    _deck := _deck[14:array_length(_deck,1)];
    _hands := _hands || jsonb_build_object(_p::text, to_jsonb(_hand));
    UPDATE rami_participants SET hand_count=13 WHERE game_id=_game_id AND user_id=_p;
  END LOOP;

  -- Random Joker (mode 2 & 4) : pop first non-classical card
  IF _g.joker_mode IN ('aleatoire','double') THEN
    _i := 1;
    WHILE _i <= array_length(_deck,1) AND _deck[_i] >= 52 LOOP _i := _i + 1; END LOOP;
    IF _i <= array_length(_deck,1) THEN
      _rj := _deck[_i];
      _deck := _deck[1:_i-1] || _deck[_i+1:array_length(_deck,1)];
    END IF;
  END IF;

  -- First discard
  _top := _deck[1];
  _deck := _deck[2:array_length(_deck,1)];

  -- Random first player slot
  _first := floor(random() * array_length(_parts,1))::int;

  _state := jsonb_build_object(
    'deck', to_jsonb(_deck),
    'discard', jsonb_build_array(_top),
    'hands', _hands,
    'melds', '[]'::jsonb,
    'first_player', _first
  );

  UPDATE rami_games SET status='playing', state=_state, started_at=now(),
    current_turn=_first, turn_phase='draw',
    random_joker=_rj,
    turn_deadline=now() + interval '60 seconds'
  WHERE id=_game_id;
END $$;

-- ============ rami_meld using new validator + meld type ============
CREATE OR REPLACE FUNCTION public.rami_meld(_game_id uuid, _cards integer[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _uid uuid := auth.uid(); _g rami_games; _slot int; _state jsonb;
  _hand int[]; _c int; _new_hand int[]; _melds jsonb; _type text;
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour de jouer'; END IF;
  _type := public._rami_meld_type(_cards, _g.joker_mode, _g.random_joker);
  IF _type IS NULL THEN RAISE EXCEPTION 'combinaison invalide'; END IF;

  _state := _g.state;
  _hand := ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[];
  _new_hand := _hand;
  FOREACH _c IN ARRAY _cards LOOP
    IF NOT (_c = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte absente de la main'; END IF;
    _new_hand := _rami_remove_one(_new_hand,_c);
  END LOOP;
  _melds := COALESCE(_state->'melds','[]'::jsonb) || jsonb_build_array(
    jsonb_build_object('player',_uid::text,'cards',to_jsonb(_cards),'type',_type)
  );
  _state := jsonb_set(_state, '{hands,'||_uid::text||'}', to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{melds}', _melds);
  UPDATE rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  UPDATE rami_participants SET hand_count=COALESCE(array_length(_new_hand,1),0)
    WHERE game_id=_game_id AND user_id=_uid;
END $$;

-- ============ Win condition checker ============
CREATE OR REPLACE FUNCTION public._rami_check_win(_state jsonb, _uid uuid)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE _carre int := 0; _trio int := 0; _run int := 0; _total int := 0;
  _m jsonb; _t text; _cards int[]; _n int;
BEGIN
  FOR _m IN SELECT * FROM jsonb_array_elements(COALESCE(_state->'melds','[]'::jsonb)) LOOP
    IF _m->>'player' = _uid::text THEN
      _t := _m->>'type';
      _cards := ARRAY(SELECT jsonb_array_elements_text(_m->'cards'))::int[];
      _n := COALESCE(array_length(_cards,1),0);
      _total := _total + _n;
      IF _t = 'carre' THEN _carre := _carre + 1;
      ELSIF _t = 'trio' THEN _trio := _trio + 1;
      ELSIF _t = 'run' THEN _run := _run + 1;
      END IF;
    END IF;
  END LOOP;
  RETURN _carre >= 1 AND _trio >= 2 AND _run >= 1 AND _total >= 13;
END $$;

-- ============ rami_discard with proper win condition ============
CREATE OR REPLACE FUNCTION public.rami_discard(_game_id uuid, _card integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _uid uuid := auth.uid(); _g rami_games; _slot int; _state jsonb;
  _hand int[]; _new_hand int[]; _discard int[]; _hands jsonb;
  _parts int[]; _next int; _payout numeric; _comm numeric; _won boolean;
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;

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

  -- Victory: hand empty AND combo set valid (1 carré + 2 trio + 1 escalier)
  IF COALESCE(array_length(_new_hand,1),0) = 0 THEN
    _won := public._rami_check_win(_state, _uid);
    IF _won THEN
      _comm := round(_g.pot * _g.commission_pct / 100.0, 0);
      _payout := _g.pot - _comm;
      UPDATE public.profiles SET balance_ar=balance_ar+_payout WHERE id=_uid;
      INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (_uid,'rami_win',_payout,_game_id,'Win rami');
      UPDATE public.rami_games SET status='finished', winner_id=_uid, finished_at=now(), state=_state WHERE id=_game_id;
      RETURN;
    ELSE
      RAISE EXCEPTION 'combinaisons incomplètes: il faut 1 carré + 2 trios + 1 escalier';
    END IF;
  END IF;

  -- Next turn
  SELECT array_agg(slot ORDER BY slot) INTO _parts
    FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited;
  _next := _g.current_turn;
  LOOP
    _next := (_next + 1) % _g.max_players;
    EXIT WHEN _next = ANY(_parts);
  END LOOP;

  UPDATE public.rami_games
     SET state=_state, current_turn=_next, turn_phase='draw',
         turn_deadline=now() + interval '60 seconds', updated_at=now()
   WHERE id=_game_id;
END $$;

-- ============ rami_request_refund ============
CREATE OR REPLACE FUNCTION public.rami_request_refund(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _uid uuid := auth.uid(); _g rami_games; _hand int[]; _stake numeric;
  _has_carre boolean := false; _has_trio boolean := false;
  _has_run3 boolean := false; _has_run4 boolean := false;
  _refunded jsonb; _ok boolean := false;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;

  _refunded := COALESCE(_g.state->'refunded','{}'::jsonb);
  IF _refunded ? _uid::text THEN RAISE EXCEPTION 'mise déjà remboursée'; END IF;

  _hand := ARRAY(SELECT jsonb_array_elements_text(_g.state->'hands'->_uid::text))::int[];
  IF COALESCE(array_length(_hand,1),0) = 0 THEN RAISE EXCEPTION 'main vide'; END IF;

  -- Check via brute search of all valid sub-melds in hand
  -- Heuristic: try every 4-subset for carré, 3-subset for trio, 3-4 contiguous for run.
  -- We rely on _rami_meld_type to type any subset.
  DECLARE _n int := array_length(_hand,1);
    _i int; _j int; _k int; _l int;
    _sub int[]; _t text;
  BEGIN
    -- Carrés (4)
    FOR _i IN 1.._n-3 LOOP FOR _j IN _i+1.._n-2 LOOP
      FOR _k IN _j+1.._n-1 LOOP FOR _l IN _k+1.._n LOOP
        _sub := ARRAY[_hand[_i],_hand[_j],_hand[_k],_hand[_l]];
        _t := public._rami_meld_type(_sub,_g.joker_mode,_g.random_joker);
        IF _t='carre' THEN _has_carre := true; END IF;
        IF _t='run' THEN _has_run4 := true; END IF;
      END LOOP; END LOOP;
    END LOOP; END LOOP;
    -- Trios + Runs of 3
    FOR _i IN 1.._n-2 LOOP FOR _j IN _i+1.._n-1 LOOP FOR _k IN _j+1.._n LOOP
      _sub := ARRAY[_hand[_i],_hand[_j],_hand[_k]];
      _t := public._rami_meld_type(_sub,_g.joker_mode,_g.random_joker);
      IF _t='trio' THEN _has_trio := true; END IF;
      IF _t='run' THEN _has_run3 := true; END IF;
    END LOOP; END LOOP; END LOOP;
  END;

  IF (_has_carre AND _has_run3) OR (_has_trio AND _has_run4) THEN _ok := true; END IF;
  IF NOT _ok THEN RAISE EXCEPTION 'conditions de retour non remplies'; END IF;

  _stake := COALESCE(_g.stake,0);
  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar=balance_ar+_stake WHERE id=_uid;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
    VALUES (_uid,'rami_refund',_stake,_game_id,'Retour de mise rami');
    UPDATE public.rami_games SET pot=GREATEST(pot-_stake,0) WHERE id=_game_id;
  END IF;
  UPDATE public.rami_games
     SET state = jsonb_set(state,'{refunded}',COALESCE(state->'refunded','{}'::jsonb) || jsonb_build_object(_uid::text,true))
   WHERE id=_game_id;
END $$;

GRANT EXECUTE ON FUNCTION public.rami_create(numeric,integer,boolean,integer,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rami_request_refund(uuid) TO authenticated;
