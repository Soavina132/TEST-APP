-- ============================================================
-- Fix: _rami_meld_type now accepts 7-card combos (Miverim-bola)
--
-- Compositions acceptees (100% PUR -- aucun Joker) :
--  1. Tri (3 meme valeur) + Escalier (4 consecutives, meme couleur)
--  2. Tri (3 meme valeur) + Carre (4 meme valeur, couleurs differentes)
--  3. Escalier (3 consecutives, meme couleur) + Carre (4 meme valeur)
--  4. Escalier (3 consecutives) + Escalier (4 consecutives, meme couleur)
--
-- Retourne 'seven' pour ces combos.
-- ============================================================

-- Helper: check if 3 cards form a pure trio (same rank, distinct suits, no joker)
CREATE OR REPLACE FUNCTION public._rami_is_pure_trio(_cards integer[], _mode text, _rj integer)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  _c int; _norm int; _rank int; _suit int;
  _ranks int[] := ARRAY[]::int[]; _suits int[] := ARRAY[]::int[];
  _n int;
BEGIN
  _n := COALESCE(array_length(_cards,1),0);
  IF _n <> 3 THEN RETURN false; END IF;
  FOREACH _c IN ARRAY _cards LOOP
    IF public._rami_is_joker(_c, _mode, _rj) THEN RETURN false; END IF;
    _norm := _c % 56;
    IF _norm >= 52 THEN RETURN false; END IF;
    _rank := _norm % 13; _suit := _norm / 13;
    _ranks := array_append(_ranks, _rank);
    _suits := array_append(_suits, _suit);
  END LOOP;
  IF (SELECT count(DISTINCT x) FROM unnest(_ranks) x) <> 1 THEN RETURN false; END IF;
  IF (SELECT count(DISTINCT x) FROM unnest(_suits) x) <> 3 THEN RETURN false; END IF;
  RETURN true;
END $$;

-- Helper: check if 4 cards form a pure carre (same rank, distinct suits, no joker)
CREATE OR REPLACE FUNCTION public._rami_is_pure_carre(_cards integer[], _mode text, _rj integer)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  _c int; _norm int; _rank int; _suit int;
  _ranks int[] := ARRAY[]::int[]; _suits int[] := ARRAY[]::int[];
  _n int;
BEGIN
  _n := COALESCE(array_length(_cards,1),0);
  IF _n <> 4 THEN RETURN false; END IF;
  FOREACH _c IN ARRAY _cards LOOP
    IF public._rami_is_joker(_c, _mode, _rj) THEN RETURN false; END IF;
    _norm := _c % 56;
    IF _norm >= 52 THEN RETURN false; END IF;
    _rank := _norm % 13; _suit := _norm / 13;
    _ranks := array_append(_ranks, _rank);
    _suits := array_append(_suits, _suit);
  END LOOP;
  IF (SELECT count(DISTINCT x) FROM unnest(_ranks) x) <> 1 THEN RETURN false; END IF;
  IF (SELECT count(DISTINCT x) FROM unnest(_suits) x) <> 4 THEN RETURN false; END IF;
  RETURN true;
END $$;

-- Helper: check if 3-4 cards form a pure escalier (consecutive, same suit, no joker, no gaps)
CREATE OR REPLACE FUNCTION public._rami_is_pure_run(_cards integer[], _mode text, _rj integer)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  _c int; _norm int; _rank int; _suit int; _first_suit int := -1;
  _ranks int[] := ARRAY[]::int[]; _suits int[] := ARRAY[]::int[];
  _n int; _min_r int; _max_r int;
  _i int; _try_high int; _rs int[];
BEGIN
  _n := COALESCE(array_length(_cards,1),0);
  IF _n < 3 OR _n > 4 THEN RETURN false; END IF;
  FOREACH _c IN ARRAY _cards LOOP
    IF public._rami_is_joker(_c, _mode, _rj) THEN RETURN false; END IF;
    _norm := _c % 56;
    IF _norm >= 52 THEN RETURN false; END IF;
    _rank := _norm % 13; _suit := _norm / 13;
    IF _first_suit = -1 THEN _first_suit := _suit;
    ELSIF _first_suit <> _suit THEN RETURN false; END IF;
    _ranks := array_append(_ranks, _rank);
    _suits := array_append(_suits, _suit);
  END LOOP;
  IF (SELECT count(DISTINCT x) FROM unnest(_ranks) x) <> _n THEN RETURN false; END IF;
  FOR _try_high IN 0..1 LOOP
    _rs := _ranks;
    IF _try_high = 1 THEN
      FOR _i IN 1..array_length(_rs,1) LOOP
        IF _rs[_i] = 0 THEN _rs[_i] := 13; END IF;
      END LOOP;
    END IF;
    SELECT min(x), max(x) INTO _min_r, _max_r FROM unnest(_rs) x;
    IF _max_r - _min_r + 1 = _n THEN RETURN true; END IF;
  END LOOP;
  RETURN false;
END $$;

-- Main: updated _rami_meld_type with 7-card combo support
CREATE OR REPLACE FUNCTION public._rami_meld_type(_cards integer[], _mode text, _rj integer)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  _n int := COALESCE(array_length(_cards,1),0);
  _c int; _norm int; _jokers int := 0; _reals int := 0;
  _rank int := -1; _suit int := -1; _r int; _s int;
  _ranks int[] := ARRAY[]::int[];
  _is_set boolean := true; _is_run boolean := true;
  _try_high int; _base int; _ok boolean; _used boolean[]; _idx int;
  _i int; _j int; _k int;
  _three int[]; _four int[];
BEGIN
  IF _n < 3 THEN RETURN NULL; END IF;
  FOREACH _c IN ARRAY _cards LOOP
    IF _c < 0 THEN RETURN NULL; END IF;
    _norm := _c % 56;
    IF public._rami_is_joker(_c, _mode, _rj) THEN
      _jokers := _jokers + 1;
    ELSE
      IF _norm >= 52 THEN RETURN NULL; END IF;
      _reals := _reals + 1;
      _r := _norm % 13; _s := _norm / 13;
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

  -- 7 CARTES (Miverim-bola) -- 100% PUR, aucun Joker
  IF _n = 7 AND _jokers = 0 THEN
    FOR _i IN 1..5 LOOP
      FOR _j IN _i+1..6 LOOP
        FOR _k IN _j+1..7 LOOP
          _three := ARRAY[_cards[_i], _cards[_j], _cards[_k]];
          _four := ARRAY[]::int[];
          FOR _c IN 1..7 LOOP
            IF _c <> _i AND _c <> _j AND _c <> _k THEN
              _four := array_append(_four, _cards[_c]);
            END IF;
          END LOOP;

          -- Comp. 1 : Tri + Escalier de 4
          IF public._rami_is_pure_trio(_three, _mode, _rj) AND public._rami_is_pure_run(_four, _mode, _rj) THEN
            RETURN 'seven';
          END IF;
          -- Comp. 2 : Tri + Carre
          IF public._rami_is_pure_trio(_three, _mode, _rj) AND public._rami_is_pure_carre(_four, _mode, _rj) THEN
            RETURN 'seven';
          END IF;
          -- Comp. 3 : Escalier de 3 + Carre
          IF public._rami_is_pure_run(_three, _mode, _rj) AND public._rami_is_pure_carre(_four, _mode, _rj) THEN
            RETURN 'seven';
          END IF;
          -- Comp. 4 : Escalier de 3 + Escalier de 4
          IF public._rami_is_pure_run(_three, _mode, _rj) AND public._rami_is_pure_run(_four, _mode, _rj) THEN
            RETURN 'seven';
          END IF;
        END LOOP;
      END LOOP;
    END LOOP;
  END IF;

  RETURN NULL;
END $function$;

-- Update _rami_check_win to count 'seven' melds
CREATE OR REPLACE FUNCTION public._rami_check_win(_state jsonb, _key text, _seven_cards boolean DEFAULT false)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  _carre int := 0; _trio int := 0; _run int := 0; _seven int := 0; _total int := 0;
  _m jsonb; _t text; _cards int[]; _n int;
  _meld_count int := 0;
BEGIN
  FOR _m IN SELECT * FROM jsonb_array_elements(COALESCE(_state->'melds','[]'::jsonb)) LOOP
    IF _m->>'player' = _key THEN
      _t := _m->>'type';
      _cards := ARRAY(SELECT jsonb_array_elements_text(_m->'cards'))::int[];
      _n := COALESCE(array_length(_cards,1),0);
      _total := _total + _n;
      _meld_count := _meld_count + 1;
      IF _t = 'carre' THEN _carre := _carre + 1;
      ELSIF _t = 'trio' THEN _trio := _trio + 1;
      ELSIF _t = 'run'  THEN _run  := _run  + 1;
      ELSIF _t = 'seven' THEN _seven := _seven + 1;
      END IF;
    END IF;
  END LOOP;

  -- Victoire: 13+ cartes en melds, au moins 3 melds valides
  IF _total >= 13 AND _meld_count >= 3 THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$function$;
