
-- Two-deck Rami: card ids 0..55 (deck A) and 56..111 (deck B), base = id % 56

CREATE OR REPLACE FUNCTION public._rami_is_joker(_c integer, _mode text, _rj integer)
 RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path TO 'public'
AS $function$
DECLARE _rd int; _sd int; _r int; _s int; _color_d int; _color int; _cc int; _rr int;
BEGIN
  IF _c IS NULL THEN RETURN false; END IF;
  _cc := _c % 56;
  _rr := CASE WHEN _rj IS NULL THEN NULL ELSE _rj % 56 END;
  IF _cc >= 52 AND _mode IN ('classique','double') THEN RETURN true; END IF;
  IF _mode IN ('aleatoire','double') AND _rr IS NOT NULL AND _cc < 52 AND _rr < 52 THEN
    _rd := _rr % 13; _sd := _rr / 13;
    _r  := _cc % 13; _s  := _cc / 13;
    IF _r = _rd AND _s <> _sd THEN
      _color_d := CASE WHEN _sd IN (0,3) THEN 0 ELSE 1 END;
      _color   := CASE WHEN _s  IN (0,3) THEN 0 ELSE 1 END;
      IF _color <> _color_d THEN RETURN true; END IF;
    END IF;
  END IF;
  RETURN false;
END $function$;

CREATE OR REPLACE FUNCTION public._rami_meld_type(_cards integer[], _mode text, _rj integer)
 RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path TO 'public'
AS $function$
DECLARE
  _n int := COALESCE(array_length(_cards,1),0);
  _c int; _cc int; _jokers int := 0; _reals int := 0;
  _rank int := -1; _suit int := -1; _r int; _s int;
  _ranks int[] := ARRAY[]::int[];
  _suits int[] := ARRAY[]::int[];
  _is_set boolean := true; _is_run boolean := true;
  _try_high int; _base int; _ok boolean; _used boolean[]; _idx int;
BEGIN
  IF _n < 3 THEN RETURN NULL; END IF;
  FOREACH _c IN ARRAY _cards LOOP
    IF _c < 0 THEN RETURN NULL; END IF;
    IF public._rami_is_joker(_c,_mode,_rj) THEN
      _jokers := _jokers + 1;
    ELSE
      _cc := _c % 56;
      IF _cc >= 52 THEN RETURN NULL; END IF;
      _reals := _reals + 1;
      _r := _cc % 13; _s := _cc / 13;
      IF _rank = -1 THEN _rank := _r; ELSIF _rank <> _r THEN _is_set := false; END IF;
      IF _suit = -1 THEN _suit := _s; ELSIF _suit <> _s THEN _is_run := false; END IF;
      _ranks := _ranks || _r;
      _suits := _suits || _s;
    END IF;
  END LOOP;
  IF _reals < 2 THEN RETURN NULL; END IF;
  IF _jokers > _reals THEN RETURN NULL; END IF;

  -- Deux paquets : un trio/carré ne peut pas contenir deux fois la même couleur
  IF _is_set AND (SELECT count(DISTINCT x) FROM unnest(_suits) x) <> array_length(_suits,1) THEN
    _is_set := false;
  END IF;

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

  IF _n = 7 AND public._rami_is_seven(_cards, _mode, _rj) THEN RETURN 'seven'; END IF;

  RETURN NULL;
END $function$;

CREATE OR REPLACE FUNCTION public.rami_start(_game_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  _g public.rami_games;
  _rows RECORD;
  _deck int[]; _i int; _j int; _tmp int; _size int;
  _hands jsonb := '{}'::jsonb; _hand int[]; _state jsonb;
  _max int; _rj int := NULL; _first int; _top int; _key text;
  _n int;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'waiting' THEN RETURN; END IF;

  SELECT count(*) INTO _n FROM public.rami_participants WHERE game_id=_game_id;
  IF _n < 2 THEN RAISE EXCEPTION 'pas assez de joueurs'; END IF;

  IF _g.joker_mode IN ('classique','double') THEN _max := 56; ELSE _max := 52; END IF;
  -- DEUX PAQUETS : 0.._max-1 et 56..56+_max-1
  _deck := ARRAY(SELECT generate_series(0,_max-1)) || ARRAY(SELECT 56 + generate_series(0,_max-1));
  _size := array_length(_deck,1);

  FOR _i IN REVERSE _size..2 LOOP
    _j := 1 + floor(random()*_i)::int;
    _tmp := _deck[_i]; _deck[_i] := _deck[_j]; _deck[_j] := _tmp;
  END LOOP;

  FOR _rows IN SELECT slot, user_id, is_bot FROM public.rami_participants
                WHERE game_id=_game_id ORDER BY slot LOOP
    _hand := _deck[1:13];
    _deck := _deck[14:array_length(_deck,1)];
    _key := CASE WHEN COALESCE(_rows.is_bot,false) OR _rows.user_id IS NULL
                 THEN 'bot:' || _rows.slot::text
                 ELSE _rows.user_id::text END;
    _hands := _hands || jsonb_build_object(_key, to_jsonb(_hand));
    UPDATE public.rami_participants SET hand_count=13
      WHERE game_id=_game_id AND slot=_rows.slot;
  END LOOP;

  IF _g.joker_mode IN ('aleatoire','double') THEN
    _i := 1;
    WHILE _i <= array_length(_deck,1) AND (_deck[_i] % 56) >= 52 LOOP _i := _i + 1; END LOOP;
    IF _i <= array_length(_deck,1) THEN
      _rj := _deck[_i];
      _deck := _deck[1:_i-1] || _deck[_i+1:array_length(_deck,1)];
    END IF;
  END IF;

  _top := _deck[1];
  _deck := _deck[2:array_length(_deck,1)];
  _first := floor(random() * _n)::int;

  _state := jsonb_build_object(
    'deck', to_jsonb(_deck),
    'discards', jsonb_build_object('_seed', jsonb_build_array(_top)),
    'last_discard_by', '_seed',
    'hands', _hands,
    'melds', '[]'::jsonb,
    'first_player', _first
  );

  UPDATE public.rami_games
    SET status='playing', state=_state, started_at=now(),
        current_turn=_first, turn_phase='draw',
        random_joker=_rj,
        turn_deadline=now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('rami')),60) || ' seconds')::interval
  WHERE id=_game_id;

  PERFORM public._rami_autoplay_bots(_game_id);
END $function$;
