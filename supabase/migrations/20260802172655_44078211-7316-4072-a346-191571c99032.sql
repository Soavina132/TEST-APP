-- 1) Mode de jeu sur les parties de Rami
ALTER TABLE public.rami_games
  ADD COLUMN IF NOT EXISTS game_mode text NOT NULL DEFAULT 'bordel';

ALTER TABLE public.rami_games DROP CONSTRAINT IF EXISTS rami_games_game_mode_check;
ALTER TABLE public.rami_games
  ADD CONSTRAINT rami_games_game_mode_check CHECK (game_mode IN ('bordel','naturel'));

-- 2) Détection "7 cartes miverim-bola" : carré+brelan ou suite de 4 + brelan
CREATE OR REPLACE FUNCTION public._rami_is_seven(_cards integer[], _mode text, _rj integer)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path TO 'public' AS $$
DECLARE
  _n int := COALESCE(array_length(_cards,1),0);
  i int; j int; k int; l int; m int;
  _four int[]; _three int[]; _t4 text; _t3 text;
BEGIN
  IF _n <> 7 THEN RETURN false; END IF;
  FOR i IN 1..4 LOOP
  FOR j IN i+1..5 LOOP
  FOR k IN j+1..6 LOOP
  FOR l IN k+1..7 LOOP
    _four  := ARRAY[_cards[i],_cards[j],_cards[k],_cards[l]];
    _three := ARRAY[]::int[];
    FOR m IN 1..7 LOOP
      IF m <> i AND m <> j AND m <> k AND m <> l THEN
        _three := _three || _cards[m];
      END IF;
    END LOOP;
    _t4 := public._rami_meld_type(_four,  _mode, _rj);
    _t3 := public._rami_meld_type(_three, _mode, _rj);
    IF _t4 IN ('carre','run') AND _t3 = 'trio' THEN RETURN true; END IF;
  END LOOP; END LOOP; END LOOP; END LOOP;
  RETURN false;
END $$;

-- 3) _rami_meld_type reconnaît le type 'seven'
CREATE OR REPLACE FUNCTION public._rami_meld_type(_cards integer[], _mode text, _rj integer)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path TO 'public' AS $$
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
      IF _c >= 52 THEN RETURN NULL; END IF;
      _reals := _reals + 1;
      _r := _c % 13; _s := _c / 13;
      IF _rank = -1 THEN _rank := _r; ELSIF _rank <> _r THEN _is_set := false; END IF;
      IF _suit = -1 THEN _suit := _s; ELSIF _suit <> _s THEN _is_run := false; END IF;
      _ranks := _ranks || _r;
    END IF;
  END LOOP;
  IF _reals < 2 THEN RETURN NULL; END IF;
  IF _jokers > _reals THEN RETURN NULL; END IF;

  IF _is_set AND _n IN (3,4) THEN
    IF _n = 4 THEN RETURN 'carre'; ELSE RETURN 'trio'; END IF;
  END IF;

  IF _is_run THEN
    FOR _try_high IN 0..1 LOOP
      DECLARE _rs int[] := _ranks; _i int; BEGIN
        IF _try_high = 1 THEN
          FOR _i IN 1..array_length(_rs,1) LOOP
            IF _rs[_i] = 0 THEN _rs[_i] := 13; END IF;
          END LOOP;
        END IF;
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

  -- 7 cartes miverim-bola : carré + brelan, ou suite de 4 + brelan
  IF _n = 7 AND public._rami_is_seven(_cards, _mode, _rj) THEN RETURN 'seven'; END IF;

  RETURN NULL;
END $$;

-- 4) rami_create accepte le mode de jeu
CREATE OR REPLACE FUNCTION public.rami_create(_stake numeric, _max integer, _private boolean, _commission integer, _joker_mode text DEFAULT 'classique'::text, _game_mode text DEFAULT 'bordel'::text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _uid uuid := auth.uid(); _id uuid; _code text; _bal numeric; _name text; _mode text; _gmode text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _max < 2 OR _max > 4 THEN RAISE EXCEPTION 'players 2-4'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'stake invalid'; END IF;
  _mode := COALESCE(_joker_mode,'classique');
  IF _mode NOT IN ('sans','aleatoire','classique','double') THEN
    RAISE EXCEPTION 'mode joker invalide';
  END IF;
  _gmode := COALESCE(_game_mode,'bordel');
  IF _gmode NOT IN ('bordel','naturel') THEN RAISE EXCEPTION 'mode de jeu invalide'; END IF;

  SELECT balance_ar, COALESCE(pseudo,'Joueur') INTO _bal,_name
    FROM public.profiles WHERE id=_uid FOR UPDATE;
  IF _bal IS NULL OR _bal < _stake THEN RAISE EXCEPTION 'solde insuffisant'; END IF;
  _code := public._rami_gen_code();

  INSERT INTO public.rami_games (room_code,is_private,stake,max_players,commission_pct,created_by,pot,joker_mode,game_mode)
  VALUES (_code,COALESCE(_private,true),_stake,_max,COALESCE(_commission,10),_uid,_stake,_mode,_gmode)
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
REVOKE ALL ON FUNCTION public.rami_create(numeric,integer,boolean,integer,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_create(numeric,integer,boolean,integer,text,text) TO authenticated;

-- 5) rami_meld : première pose valide + drapeau miverim-bola
CREATE OR REPLACE FUNCTION public.rami_meld(_game_id uuid, _cards integer[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _hand int[]; _c int; _new_hand int[]; _melds jsonb; _type text; _seven boolean;
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

  -- Mode naturel : la première pose doit être un brelan/carré ou une suite (min 3)
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
  END IF;
  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand,1),0)
    WHERE game_id=_game_id AND user_id=_uid;
END $$;

-- 6) rami_layoff : interdit avant la première pose en mode naturel
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

  IF COALESCE(_g.game_mode,'bordel') = 'naturel'
     AND NOT EXISTS (
       SELECT 1 FROM jsonb_array_elements(_melds) m WHERE m->>'player' = _uid::text
     ) THEN
    RAISE EXCEPTION 'Mode naturel : pose d''abord ta propre combinaison avant d''ajouter des cartes';
  END IF;

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
      || jsonb_build_object('type', _type, 'seven', (_type = 'seven')));
  _state := jsonb_set(_state, ARRAY['hands',_uid::text], to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{melds}', _melds);
  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand,1),0)
    WHERE game_id=_game_id AND user_id=_uid;
END $$;

-- 7) Victoire : la combinaison "seven" compte comme carré + brelan (+ suite)
CREATE OR REPLACE FUNCTION public._rami_check_win(_state jsonb, _key text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path TO 'public' AS $$
DECLARE _carre int := 0; _trio int := 0; _run int := 0; _total int := 0;
  _m jsonb; _t text; _cards int[]; _n int;
BEGIN
  FOR _m IN SELECT * FROM jsonb_array_elements(COALESCE(_state->'melds','[]'::jsonb)) LOOP
    IF _m->>'player' = _key THEN
      _t := _m->>'type';
      _cards := ARRAY(SELECT jsonb_array_elements_text(_m->'cards'))::int[];
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

CREATE OR REPLACE FUNCTION public._rami_check_win(_state jsonb, _uid uuid)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path TO 'public' AS $$
BEGIN
  RETURN public._rami_check_win(_state, _uid::text);
END $$;
