-- ═══════════════════════════════════════════════════════════════
-- SYNC : Toutes les fonctions Rami synchronisées avec l'état déployé
-- sur Supabase. Cette migration capture l'état exact des fonctions
-- au 2026-08-17 pour éviter les régressions futures.
--
-- ATTENTION : Ne touche QUE les fonctions Rami. Aucune autre fonction
-- ou table n'est modifiée.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._is_rami_participant(_game uuid, _uid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.rami_participants p
    WHERE p.game_id = _game AND p.user_id = _uid
  )
$function$



CREATE OR REPLACE FUNCTION public._maybe_end_bot_only_rami(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE public.rami_games g SET status='finished', finished_at=now()
  WHERE g.id=_game_id AND g.status='playing'
    AND NOT EXISTS (SELECT 1 FROM public.rami_participants p WHERE p.game_id=g.id AND p.is_bot=false AND COALESCE(p.forfeited,false)=false);
END $function$



CREATE OR REPLACE FUNCTION public._rami_active_humans(_gid uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT count(*)::int FROM public.rami_participants
  WHERE game_id = _gid AND forfeited = false AND COALESCE(is_bot, false) = false
$function$



CREATE OR REPLACE FUNCTION public._rami_all_discards(_state jsonb)
 RETURNS integer[]
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE _m jsonb := public._rami_discards_map(_state);
  _k text; _acc int[] := ARRAY[]::int[];
BEGIN
  IF _m IS NULL OR jsonb_typeof(_m) <> 'object' THEN RETURN _acc; END IF;
  FOR _k IN SELECT jsonb_object_keys(_m) LOOP
    _acc := _acc || public._rami_safe_int_array(_m->_k);
  END LOOP;
  RETURN _acc;
END $function$



CREATE OR REPLACE FUNCTION public._rami_autoplay_bots(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  g public.rami_games; part public.rami_participants; guard int := 0;
  _key text; _hand int[]; _card int; _deck int[]; _new_hand int[]; _hands jsonb;
  _melds jsonb; _melded int[]; _type text; _intel int; _parts int[];
  _next int; _top int; _matched boolean;
  _cfg record;
  _state jsonb; _last text;
  _discard_arr int[];
  _discard_by text[];
  _all int[];
  _winner_name text; _payout numeric; _comm numeric;
  _seven boolean;
  _action_log jsonb;
BEGIN
  LOOP
    guard := guard + 1;
    IF guard > 100 THEN EXIT; END IF;

    SELECT * INTO g FROM public.rami_games WHERE id = _game_id FOR UPDATE;
    IF NOT FOUND OR g.status <> 'playing' THEN EXIT; END IF;
    IF COALESCE(g.paused, false) THEN EXIT; END IF;

    SELECT * INTO part FROM public.rami_participants
     WHERE game_id = _game_id AND slot = g.current_turn AND forfeited = false;
    IF NOT FOUND OR NOT COALESCE(part.is_bot, false) THEN EXIT; END IF;

    _key   := COALESCE(part.user_id::text, 'bot:' || part.slot::text);
    _intel := COALESCE(part.bot_intelligence, 70);
    _seven := COALESCE(g.seven_cards, false);
    SELECT * INTO _cfg FROM public._game_cfg('rami');
    _state := public._rami_normalize_state(g.state);
    _discard_arr := COALESCE(public._rami_jarr(_state->'discard'), ARRAY[]::int[]);
    _discard_arr := ARRAY(SELECT x FROM unnest(_discard_arr) x WHERE x IS NOT NULL);
    IF _state ? 'discard_by' AND _state->'discard_by' IS NOT NULL THEN
      _discard_by := ARRAY(SELECT elem::text FROM jsonb_array_elements_text(_state->'discard_by') elem WHERE elem IS NOT NULL);
    ELSE
      _discard_by := ARRAY[]::text[];
    END IF;

    IF g.turn_phase = 'draw' THEN
      _deck := COALESCE(public._rami_jarr(_state->'deck'), ARRAY[]::int[]);
      _hand := COALESCE(public._rami_jarr(_state->'hands'->_key), ARRAY[]::int[]);
      _card := NULL;
      _matched := false;

      -- ═══ Bot pioche sur défausse si la carte match ═══
      IF _intel >= 70 AND array_length(_discard_arr, 1) IS NOT NULL AND array_length(_discard_arr, 1) > 0 THEN
        _top := _discard_arr[array_length(_discard_arr, 1)];
        IF (_top % 56) < 52 AND EXISTS (
          SELECT 1 FROM unnest(_hand) c
          WHERE (c % 56) < 52 AND c%13 = _top%13
        ) THEN
          _matched := true;
          _card := _top;
          _discard_arr := _discard_arr[1:array_length(_discard_arr, 1)-1];
          IF array_length(_discard_by, 1) > 0 THEN
            _discard_by := _discard_by[1:array_length(_discard_by, 1)-1];
          END IF;
        END IF;
      END IF;

      IF NOT _matched THEN
        -- Piocher depuis le deck
        IF COALESCE(array_length(_deck, 1), 0) = 0 THEN
          IF array_length(_discard_arr, 1) IS NOT NULL AND array_length(_discard_arr, 1) > 1 THEN
            _all := _discard_arr[1:array_length(_discard_arr, 1)-1];
            _discard_arr := ARRAY[_discard_arr[array_length(_discard_arr, 1)]];
            _discard_by := ARRAY[_discard_by[array_length(_discard_by, 1)]];
            _deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_all) c);
          ELSE
            EXIT;
          END IF;
        END IF;
        IF COALESCE(array_length(_deck, 1), 0) = 0 THEN EXIT; END IF;
        _card := _deck[1];
        _deck := _deck[2:array_length(_deck, 1)];
      END IF;

      _hand := array_append(_hand, _card);
      _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_hand));
      _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
      _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
      _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);
      _state := jsonb_set(_state, '{hands}', _hands);
      _state := public._rami_normalize_state(_state);

      UPDATE public.rami_games SET state = _state, turn_phase = 'play', updated_at = now() WHERE id = _game_id;
      UPDATE public.rami_participants SET hand_count = COALESCE(array_length(_hand, 1), 0)
       WHERE game_id = _game_id AND slot = part.slot;
      CONTINUE;
    END IF;

    -- ═══ Phase 'play' ═══
    _hand := COALESCE(public._rami_jarr(_state->'hands'->_key), ARRAY[]::int[]);
    _melds := COALESCE(_state->'melds', '[]'::jsonb);
    _melded := NULL;

    IF _intel >= 50 AND COALESCE(array_length(_hand, 1), 0) >= 4 THEN
      SELECT ARRAY[_hand[ai], _hand[aj], _hand[ak], _hand[al]] INTO _melded
        FROM generate_subscripts(_hand, 1) ai, generate_subscripts(_hand, 1) aj,
             generate_subscripts(_hand, 1) ak, generate_subscripts(_hand, 1) al
       WHERE ai < aj AND aj < ak AND ak < al
         AND public._rami_meld_type(ARRAY[_hand[ai], _hand[aj], _hand[ak], _hand[al]], g.joker_mode, g.random_joker) IS NOT NULL
       LIMIT 1;

      IF _melded IS NULL THEN
        SELECT ARRAY[_hand[bi], _hand[bj], _hand[bk]] INTO _melded
          FROM generate_subscripts(_hand, 1) bi, generate_subscripts(_hand, 1) bj, generate_subscripts(_hand, 1) bk
         WHERE bi < bj AND bj < bk
           AND public._rami_meld_type(ARRAY[_hand[bi], _hand[bj], _hand[bk]], g.joker_mode, g.random_joker) IS NOT NULL
         LIMIT 1;
      END IF;

      IF _melded IS NOT NULL THEN
        _type := public._rami_meld_type(_melded, g.joker_mode, g.random_joker);
        _new_hand := _hand;
        FOREACH _card IN ARRAY _melded LOOP
          _new_hand := public._rami_remove_one(_new_hand, _card);
        END LOOP;
        _melds := _melds || jsonb_build_array(jsonb_build_object(
          'player', _key, 'cards', to_jsonb(_melded), 'type', _type
        ));
        _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_new_hand));
        _state := jsonb_set(_state, '{hands}', _hands);
        _state := jsonb_set(_state, '{melds}', _melds);
        UPDATE public.rami_games SET state = _state, updated_at = now() WHERE id = _game_id;
        UPDATE public.rami_participants SET hand_count = COALESCE(array_length(_new_hand, 1), 0)
          WHERE game_id = _game_id AND slot = part.slot;
        CONTINUE;
      END IF;
    END IF;

    IF COALESCE(array_length(_hand, 1), 0) = 0 THEN EXIT; END IF;

    -- Choisir une carte à défausser
    IF _intel < 50 THEN
      _card := _hand[1 + floor(random() * array_length(_hand, 1))::int];
    ELSE
      SELECT c INTO _card FROM unnest(_hand) c
        ORDER BY (CASE WHEN (c % 56) < 52 THEN c%13 ELSE -1 END) DESC, random()
        LIMIT 1;
    END IF;

    _new_hand := public._rami_remove_one(_hand, _card);

    -- ═══ Gérer le cas où _new_hand est vide (dernière carte) ═══
    IF COALESCE(array_length(_new_hand, 1), 0) = 0 THEN
      -- Ajouter à la défausse
      _discard_arr := array_append(_discard_arr, _card);
      _discard_by := array_append(_discard_by, _key);
      _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_new_hand));
      _state := jsonb_set(_state, '{hands}', _hands);
      _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
      _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);
      _state := public._rami_normalize_state(_state);

      IF public._rami_check_win(_state, _key, _seven) THEN
        SELECT COALESCE(pseudo, 'Bot') INTO _winner_name FROM public.profiles WHERE id = part.user_id;
        IF part.user_id IS NOT NULL THEN
          _comm := round(g.pot * (g.commission_pct / 2.0) / 100.0, 0);
          _payout := g.pot - _comm;
          UPDATE public.profiles SET balance_ar = balance_ar + _payout WHERE id = part.user_id;
          INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
            VALUES (part.user_id, 'rami_win', _payout, _game_id, 'Win rami (bot)');
        END IF;
        UPDATE public.rami_games
           SET status='finished', winner_id=part.user_id, winner_name=COALESCE(_winner_name, part.display_name), finished_at=now(), state=_state
         WHERE id = _game_id;
        UPDATE public.rami_participants SET hand_count = 0
         WHERE game_id = _game_id AND slot = part.slot;
        EXIT;
      ELSE
        -- Remettre la carte dans la main
        _new_hand := ARRAY[_card];
        _discard_arr := _discard_arr[1:array_length(_discard_arr, 1)-1];
        _discard_by := _discard_by[1:array_length(_discard_by, 1)-1];
        _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_new_hand));
        _state := jsonb_set(_state, '{hands}', _hands);
        _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
        _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);
        _state := public._rami_normalize_state(_state);
        UPDATE public.rami_games SET state = _state, updated_at = now() WHERE id = _game_id;
        UPDATE public.rami_participants SET hand_count = 1
         WHERE game_id = _game_id AND slot = part.slot;
        CONTINUE;
      END IF;
    END IF;

    -- Défausser normalement
    _discard_arr := array_append(_discard_arr, _card);
    _discard_by := array_append(_discard_by, _key);
    _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_new_hand));
    _state := jsonb_set(_state, '{hands}', _hands);
    _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
    _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);

    -- Action log
    _action_log := COALESCE(_state->'action_log', '[]'::jsonb) ||
      jsonb_build_object('t', 'discard', 'p', _key, 'card', _card, 'ts', extract(epoch from now())::bigint);
    _state := jsonb_set(_state, '{action_log}', _action_log);

    -- Passer au suivant
    SELECT array_agg(slot ORDER BY slot) INTO _parts
      FROM public.rami_participants WHERE game_id = _game_id AND NOT forfeited;
    _next := g.current_turn;
    LOOP
      _next := (_next + 1) % g.max_players;
      EXIT WHEN _next = ANY(_parts);
    END LOOP;

    _state := public._rami_normalize_state(_state);
    UPDATE public.rami_games SET state = _state, current_turn = _next, turn_phase = 'draw', updated_at = now()
     WHERE id = _game_id;
    UPDATE public.rami_participants SET hand_count = COALESCE(array_length(_new_hand, 1), 0)
     WHERE game_id = _game_id AND slot = part.slot;
  END LOOP;
END $function$



CREATE OR REPLACE FUNCTION public._rami_check_win(_state jsonb, _key text, _seven_cards boolean DEFAULT false)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  _carre int := 0; _trio int := 0; _run int := 0; _total int := 0;
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
      END IF;
    END IF;
  END LOOP;

  -- Victoire: 13+ cartes en melds, au moins 3 melds valides
  -- Toutes les combinaisons valides sont acceptées:
  --   2 trios + 1 run + 1 carre = 13 (standard)
  --   1 carre + 1 trio + 2 runs = 13
  --   3 trios + 1 run = 13
  --   2 trios + 2 runs = 12 + (joker?) etc.
  IF _total >= 13 AND _meld_count >= 3 THEN
    RETURN true;
  END IF;
  RETURN false;
END;
$function$



CREATE OR REPLACE FUNCTION public._rami_discards_map(_state jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE _discards jsonb;
BEGIN
  _discards := _state->'discards';
  IF _discards IS NULL OR jsonb_typeof(_discards) = 'null' THEN
    _discards := jsonb_build_object('_seed', _state->'discard');
  END IF;
  IF _discards IS NULL OR jsonb_typeof(_discards) = 'null' THEN
    _discards := '{}'::jsonb;
  END IF;
  RETURN _discards;
END $function$



CREATE OR REPLACE FUNCTION public._rami_game_visible(_game uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.rami_games g
    WHERE g.id = _game
      AND (g.is_private = false OR g.created_by = auth.uid() OR public.is_admin())
  )
$function$



CREATE OR REPLACE FUNCTION public._rami_gen_code()
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE c text; BEGIN
  LOOP
    c := upper(substr(md5(random()::text||clock_timestamp()::text),1,6));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.rami_games WHERE room_code = c);
  END LOOP;
  RETURN c;
END $function$



CREATE OR REPLACE FUNCTION public._rami_is_joker(_c integer, _mode text, _rj integer)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE 
  _norm int;
  _rd int; _sd int; _r int; _s int; 
  _color_d int; _color int;
BEGIN
  IF _c IS NULL THEN RETURN false; END IF;
  -- Normaliser: 2eme paquet (56+) → equivalent 1er paquet
  _norm := _c % 56;
  IF _norm >= 52 AND _mode IN ('classique','double') THEN RETURN true; END IF;
  IF _mode IN ('aleatoire','double') AND _rj IS NOT NULL AND _norm < 52 AND _rj < 52 THEN
    _rd := _rj % 13; _sd := _rj / 13;
    _r  := _norm % 13; _s  := _norm / 13;
    IF _r = _rd AND _s <> _sd THEN
      _color_d := CASE WHEN _sd IN (0,3) THEN 0 ELSE 1 END;
      _color   := CASE WHEN _s  IN (0,3) THEN 0 ELSE 1 END;
      IF _color <> _color_d THEN RETURN true; END IF;
    END IF;
  END IF;
  RETURN false;
END $function$



CREATE OR REPLACE FUNCTION public._rami_jarr(_v jsonb)
 RETURNS integer[]
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
  IF _v IS NULL THEN RETURN ARRAY[]::int[]; END IF;
  IF jsonb_typeof(_v) <> 'array' THEN RETURN ARRAY[]::int[]; END IF;
  RETURN COALESCE(
    ARRAY(SELECT elem::int FROM jsonb_array_elements_text(_v) elem
          WHERE elem IS NOT NULL AND elem ~ '^[0-9]+$'),
    ARRAY[]::int[]);
END $function$



CREATE OR REPLACE FUNCTION public._rami_jset(_arr integer[])
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
  RETURN to_jsonb(COALESCE(_arr, ARRAY[]::int[]));
END $function$



CREATE OR REPLACE FUNCTION public._rami_last_discarder(_state jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
  RETURN COALESCE(_state->>'last_discard_by', '_seed');
END $function$



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
BEGIN
  IF _n < 3 THEN RETURN NULL; END IF;
  FOREACH _c IN ARRAY _cards LOOP
    IF _c < 0 THEN RETURN NULL; END IF;
    _norm := _c % 56;  -- Normaliser 2eme paquet
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
  RETURN NULL;
END $function$



CREATE OR REPLACE FUNCTION public._rami_normalize_state(_state jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _discard_arr int[];
  _discard_by text[];
  _all int[];
  _k text; _v jsonb;
  _last_by text;
  _discards jsonb;
  i int;
BEGIN
  IF _state IS NULL THEN RETURN '{}'::jsonb; END IF;

  -- Lire le flat array
  _discard_arr := COALESCE(public._rami_jarr(_state->'discard'), ARRAY[]::int[]);
  _discard_arr := ARRAY(SELECT x FROM unnest(_discard_arr) x WHERE x IS NOT NULL);

  -- Lire discard_by
  IF _state ? 'discard_by' AND _state->'discard_by' IS NOT NULL THEN
    _discard_by := ARRAY(SELECT elem::text FROM jsonb_array_elements_text(_state->'discard_by') elem WHERE elem IS NOT NULL);
  ELSE
    -- Pas de discard_by: tout assigner à last_discard_by ou _seed
    _last_by := COALESCE(_state->>'last_discard_by', '_seed');
    _discard_by := ARRAY(SELECT _last_by FROM generate_series(1, COALESCE(array_length(_discard_arr, 1), 0)));
  END IF;

  -- Assurer même longueur
  IF array_length(_discard_arr, 1) IS NULL AND array_length(_discard_by, 1) IS NULL THEN
    NULL;
  ELSIF array_length(_discard_arr, 1) IS NULL THEN
    _discard_by := ARRAY[]::text[];
  ELSIF array_length(_discard_by, 1) IS NULL THEN
    _last_by := COALESCE(_state->>'last_discard_by', '_seed');
    _discard_by := ARRAY(SELECT _last_by FROM generate_series(1, array_length(_discard_arr, 1)));
  ELSIF array_length(_discard_arr, 1) <> array_length(_discard_by, 1) THEN
    IF array_length(_discard_by, 1) > array_length(_discard_arr, 1) THEN
      _discard_by := _discard_by[1:array_length(_discard_arr, 1)];
    ELSE
      _last_by := COALESCE(_state->>'last_discard_by', '_seed');
      _discard_by := _discard_by || ARRAY(SELECT _last_by FROM generate_series(1, array_length(_discard_arr, 1) - array_length(_discard_by, 1)));
    END IF;
  END IF;

  -- Dériver discards (per-player map) depuis discard + discard_by
  _discards := '{}'::jsonb;
  IF array_length(_discard_arr, 1) IS NOT NULL THEN
    FOR _k IN SELECT DISTINCT unnest(_discard_by) LOOP
      _all := ARRAY[]::int[];
      FOR i IN 1..array_length(_discard_arr, 1) LOOP
        IF _discard_by[i] = _k THEN
          _all := array_append(_all, _discard_arr[i]);
        END IF;
      END LOOP;
      IF array_length(_all, 1) IS NOT NULL THEN
        _discards := _discards || jsonb_build_object(_k, to_jsonb(_all));
      END IF;
    END LOOP;
  END IF;

  -- Dériver last_discard_by depuis le dernier élément de discard_by
  IF array_length(_discard_by, 1) IS NOT NULL THEN
    _last_by := _discard_by[array_length(_discard_by, 1)];
  ELSE
    _last_by := NULL;
  END IF;

  -- Sauvegarder
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
  _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);
  _state := jsonb_set(_state, '{discards}', _discards, true);
  IF _last_by IS NOT NULL THEN
    _state := jsonb_set(_state, '{last_discard_by}', to_jsonb(_last_by), true);
  ELSE
    _state := _state - 'last_discard_by';
  END IF;

  IF _state ? 'melds' = false THEN
    _state := jsonb_set(_state, '{melds}', '[]'::jsonb, true);
  END IF;
  IF _state ? 'action_log' = false THEN
    _state := jsonb_set(_state, '{action_log}', '[]'::jsonb, true);
  END IF;
  RETURN _state;
END $function$



CREATE OR REPLACE FUNCTION public._rami_remove_one(_arr integer[], _v integer)
 RETURNS integer[]
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
DECLARE i int; out int[] := ARRAY[]::int[]; removed boolean := false;
BEGIN
  IF _arr IS NULL THEN RETURN ARRAY[]::int[]; END IF;
  FOR i IN 1..array_length(_arr,1) LOOP
    IF NOT removed AND _arr[i] = _v THEN removed := true;
    ELSE out := array_append(out, _arr[i]);
    END IF;
  END LOOP;
  RETURN out;
END $function$



CREATE OR REPLACE FUNCTION public._rami_reshuffle(_state jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  _discard_arr int[];
  _discard_by text[];
  _all int[];
  _top_card int;
  _top_by text;
  _deck int[];
  _discards jsonb;
BEGIN
  _discard_arr := COALESCE(public._rami_jarr(_state->'discard'), ARRAY[]::int[]);
  _discard_arr := ARRAY(SELECT x FROM unnest(_discard_arr) x WHERE x IS NOT NULL);

  IF _state ? 'discard_by' AND _state->'discard_by' IS NOT NULL THEN
    _discard_by := ARRAY(SELECT elem::text FROM jsonb_array_elements_text(_state->'discard_by') elem WHERE elem IS NOT NULL);
  ELSE
    _discard_by := ARRAY[]::text[];
  END IF;

  IF array_length(_discard_arr, 1) IS NULL OR array_length(_discard_arr, 1) <= 1 THEN
    RETURN jsonb_build_object(
      'deck', '[]'::jsonb,
      'discard', to_jsonb(_discard_arr),
      'discard_by', to_jsonb(_discard_by),
      'discards', '{}'::jsonb
    );
  END IF;

  _top_card := _discard_arr[array_length(_discard_arr, 1)];
  _top_by := COALESCE(_discard_by[array_length(_discard_by, 1)], '_seed');
  _all := _discard_arr[1:array_length(_discard_arr, 1)-1];
  _deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_all) c);
  _discard_arr := ARRAY[_top_card];
  _discard_by := ARRAY[_top_by];
  _discards := jsonb_build_object(_top_by, to_jsonb(_discard_arr));

  RETURN jsonb_build_object(
    'deck', to_jsonb(_deck),
    'discard', to_jsonb(_discard_arr),
    'discard_by', to_jsonb(_discard_by),
    'discards', _discards
  );
END $function$



CREATE OR REPLACE FUNCTION public._rami_safe_int_array(_v jsonb)
 RETURNS integer[]
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
  IF _v IS NULL THEN RETURN ARRAY[]::int[]; END IF;
  IF jsonb_typeof(_v) <> 'array' THEN RETURN ARRAY[]::int[]; END IF;
  RETURN COALESCE(
    ARRAY(
      SELECT elem::int
      FROM jsonb_array_elements_text(_v) elem
      WHERE elem IS NOT NULL AND elem ~ '^[0-9]+$'
    ), ARRAY[]::int[]
  );
END $function$



CREATE OR REPLACE FUNCTION public._rami_validate_meld(_cards integer[])
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  n int; jokers int := 0; non_jokers int[] := ARRAY[]::int[];
  suits int[] := ARRAY[]::int[]; ranks int[] := ARRAY[]::int[];
  c int; norm int; min_r int; max_r int; span int; nj int;
BEGIN
  n := COALESCE(array_length(_cards,1),0);
  IF n < 3 OR n > 14 THEN RETURN false; END IF;
  FOREACH c IN ARRAY _cards LOOP
    IF c < 0 THEN RETURN false; END IF;
    norm := c % 56;  -- Normaliser 2eme paquet
    IF norm >= 52 THEN jokers := jokers + 1;
    ELSE
      non_jokers := array_append(non_jokers, norm);
      suits := array_append(suits, norm/13);
      ranks := array_append(ranks, norm%13);
    END IF;
  END LOOP;
  nj := COALESCE(array_length(non_jokers,1),0);
  IF nj = 0 THEN RETURN false; END IF;
  -- SET (trio/carre)
  IF n <= 4
    AND (SELECT count(DISTINCT x) FROM unnest(ranks) x) = 1
    AND (SELECT count(DISTINCT x) FROM unnest(suits) x) = nj
  THEN RETURN true; END IF;
  -- RUN (suite)
  IF (SELECT count(DISTINCT x) FROM unnest(suits) x) = 1
    AND (SELECT count(DISTINCT x) FROM unnest(ranks) x) = nj
  THEN
    SELECT min(x), max(x) INTO min_r, max_r FROM unnest(ranks) x;
    span := max_r - min_r + 1;
    IF span <= n AND n <= 13 AND jokers >= (span - nj) THEN RETURN true; END IF;
  END IF;
  RETURN false;
END $function$



CREATE OR REPLACE FUNCTION public._rami_visible(_game_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS(
    SELECT 1 FROM public.rami_games g
    WHERE g.id = _game_id
      AND (
        (g.status IN ('open','playing') AND g.is_private = false)
        OR g.created_by = auth.uid()
        OR EXISTS(SELECT 1 FROM public.rami_participants p WHERE p.game_id = g.id AND p.user_id = auth.uid())
        OR public.is_admin()
      )
  )
$function$



CREATE OR REPLACE FUNCTION public._trg_rami_participant_end_check()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF COALESCE(NEW.forfeited,false) IS DISTINCT FROM COALESCE(OLD.forfeited,false) THEN
    PERFORM public._maybe_end_bot_only_rami(NEW.game_id);
  END IF;
  RETURN NEW;
END $function$



CREATE OR REPLACE FUNCTION public.rami_add_bot(_game_id uuid, _bot_name text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  g public.rami_games;
  v_is_admin boolean;
  v_slot int;
  v_count int;
  v_name text;
  v_bot_names text[] := ARRAY['Bot Rija','Bot Naina','Bot Hery','Bot Voara','Bot Miora','Bot Tahina'];
  v_intel int := 70;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO g FROM public.rami_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'partie introuvable'; END IF;
  IF g.status <> 'waiting' THEN RAISE EXCEPTION 'partie déjà commencée'; END IF;

  v_is_admin := public.has_role(v_uid, 'admin'::app_role);
  IF NOT v_is_admin AND g.created_by <> v_uid THEN
    RAISE EXCEPTION 'seul l''hôte peut ajouter un bot';
  END IF;
  IF NOT v_is_admin AND g.stake > 0 THEN
    RAISE EXCEPTION 'les bots ne sont autorisés qu''en partie gratuite';
  END IF;

  SELECT count(*) INTO v_count FROM public.rami_participants WHERE game_id = _game_id;
  IF v_count >= g.max_players THEN RAISE EXCEPTION 'partie pleine'; END IF;

  -- first free slot
  SELECT s.slot INTO v_slot
  FROM generate_series(0, g.max_players - 1) s(slot)
  WHERE s.slot NOT IN (SELECT slot FROM public.rami_participants WHERE game_id = _game_id)
  ORDER BY s.slot LIMIT 1;

  v_name := COALESCE(NULLIF(_bot_name,''), v_bot_names[1 + (v_slot % array_length(v_bot_names,1))]);

  INSERT INTO public.rami_participants(
    game_id, user_id, slot, display_name, ready, is_bot, bot_name, bot_intelligence, hand_count
  ) VALUES (
    _game_id, NULL, v_slot, v_name, true, true, v_name, v_intel, 0
  );

  -- Auto-start if now full and all humans ready
  IF (SELECT count(*) FROM public.rami_participants WHERE game_id = _game_id) = g.max_players
     AND (SELECT count(*) FROM public.rami_participants WHERE game_id = _game_id AND NOT ready) = 0 THEN
    PERFORM public.rami_start(_game_id);
  END IF;
END $function$



CREATE OR REPLACE FUNCTION public.rami_bot_tick_all()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _g_id uuid;
  _is_bot boolean;
  _updated timestamptz;
BEGIN
  FOR _g_id IN
    SELECT r.id FROM public.rami_games r
    WHERE r.status='playing'
  LOOP
    BEGIN
      SELECT p.is_bot, r.updated_at INTO _is_bot, _updated
        FROM public.rami_games r
        JOIN public.rami_participants p ON p.game_id=r.id AND p.slot=r.current_turn
        WHERE r.id=_g_id;

      IF _is_bot AND _updated IS NOT NULL AND now() - _updated >= interval '5 seconds' THEN
        PERFORM public._rami_autoplay_bots(_g_id);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
END;
$function$



CREATE OR REPLACE FUNCTION public.rami_claim_seven(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _melds jsonb; _m jsonb; _total_pure int := 0; _found boolean := false;
  _refunded jsonb; _action_log jsonb;
  _cards int[]; _c int; _is_pure boolean; _n int; _run4 int := 0; _run3 int := 0;
  _set3 int := 0; _set4 int := 0; _t text;
  _refund numeric; _comm_half numeric;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;

  _state := _g.state;
  _refunded := COALESCE(_state->'refunded','{}'::jsonb);
  IF _refunded ? _uid::text THEN RAISE EXCEPTION 'deja rembourse'; END IF;

  -- Check player's melds: must have exactly 7 pure cards in valid combo
  _melds := COALESCE(_state->'melds','[]'::jsonb);
  FOR _m IN SELECT * FROM jsonb_array_elements(_melds) LOOP
    IF _m->>'player' = _uid::text THEN
      _t := _m->>'type';
      _cards := ARRAY(SELECT jsonb_array_elements_text(_m->'cards'))::int[];
      _n := COALESCE(array_length(_cards,1),0);
      _is_pure := true;
      FOREACH _c IN ARRAY _cards LOOP
        IF public._rami_is_joker(_c, _g.joker_mode, _g.random_joker) THEN
          _is_pure := false;
        END IF;
      END LOOP;
      IF _is_pure THEN
        _total_pure := _total_pure + _n;
        IF _t = 'run' AND _n >= 4 THEN _run4 := _run4 + 1;
        ELSIF _t = 'run' AND _n = 3 THEN _run3 := _run3 + 1;
        ELSIF _t = 'carre' AND _n = 4 THEN _set4 := _set4 + 1;
        ELSIF _t = 'trio' AND _n = 3 THEN _set3 := _set3 + 1;
        END IF;
      END IF;
    END IF;
  END LOOP;

  -- 7 pure cards: Option 1 (run4+set3) or Option 2 (run3+set4)
  IF _total_pure = 7 AND ((_run4 >= 1 AND _set3 >= 1) OR (_run3 >= 1 AND _set4 >= 1)) THEN
    _found := true;
  END IF;

  IF NOT _found THEN
    RAISE EXCEPTION 'tu dois poser 7 cartes pures: 4-suite + 3-brelan OU 3-suite + 4-carre';
  END IF;

  -- Refund stake minus half commission
  IF _g.stake > 0 THEN
    _comm_half := round(_g.stake * (_g.commission_pct / 2.0) / 100.0, 0);
    _refund := _g.stake - _comm_half;
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, 0) + _refund WHERE id=_uid;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (_uid,'rami_seven_refund',_refund,_game_id,'7 Cartes pures refund');
    -- Reduce pot by full stake
    UPDATE public.rami_games SET pot = GREATEST(pot - _g.stake, 0) WHERE id=_game_id;
  END IF;

  _refunded := _refunded || jsonb_build_object(_uid::text, true);
  _state := jsonb_set(_state, '{refunded}', _refunded);
  _action_log := COALESCE(_state->'action_log','[]'::jsonb) ||
    jsonb_build_object('t','seven','p',_uid::text,'ts',extract(epoch from now())::bigint,'refund',_refund);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
END;
$function$



CREATE OR REPLACE FUNCTION public.rami_create(_stake numeric, _max integer, _private boolean, _commission integer, _joker_mode text DEFAULT 'classique'::text, _game_mode text DEFAULT 'bordel'::text, _seven_cards boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _uid   uuid := auth.uid();
  _id    uuid;
  _code  text;
  _bal   numeric;
  _name  text;
  _mode  text;
  _gmode text;
  _seven boolean;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _max < 2 OR _max > 4 THEN RAISE EXCEPTION 'players 2-4'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'stake invalid'; END IF;
  IF _commission IS NULL OR _commission < 0 OR _commission > 50 THEN RAISE EXCEPTION 'commission invalide (0-50)'; END IF;

  _mode := COALESCE(_joker_mode, 'classique');
  IF _mode NOT IN ('sans','aleatoire','classique','double') THEN
    RAISE EXCEPTION 'mode joker invalide';
  END IF;

  _gmode := COALESCE(_game_mode, 'bordel');
  IF _gmode NOT IN ('bordel','naturel') THEN RAISE EXCEPTION 'mode de jeu invalide'; END IF;

  _seven := COALESCE(_seven_cards, true);

  SELECT balance_ar, COALESCE(pseudo,'Joueur') INTO _bal, _name
    FROM public.profiles WHERE id = _uid FOR UPDATE;
  IF _bal IS NULL OR _bal < _stake THEN RAISE EXCEPTION 'solde insuffisant'; END IF;

  _code := public._rami_gen_code();

  INSERT INTO public.rami_games (
    room_code, is_private, stake, max_players, commission_pct,
    created_by, pot, joker_mode, game_mode, seven_cards
  ) VALUES (
    _code, COALESCE(_private, true), _stake, _max, COALESCE(_commission, 10),
    _uid, _stake, _mode, _gmode, _seven
  ) RETURNING id INTO _id;

  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = _uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
    VALUES (_uid, 'rami_stake', -_stake, _id, 'Create rami');
  END IF;

  INSERT INTO public.rami_participants(game_id, user_id, slot, display_name)
  VALUES (_id, _uid, 0, _name);

  RETURN _id;
END $function$



CREATE OR REPLACE FUNCTION public.rami_discard(_game_id uuid, _card integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _uid uuid := auth.uid();
  _g rami_games;
  _slot int;
  _state jsonb;
  _hand int[];
  _new_hand int[];
  _discard_arr int[];
  _discard_by text[];
  _hands jsonb;
  _parts int[];
  _next int;
  _payout numeric;
  _comm numeric;
  _won boolean;
  _cfg record;
  _key text;
  _winner_name text;
  _seven boolean;
  _next_is_bot boolean;
  _action_log jsonb;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _key := _uid::text;
  _seven := COALESCE(_g.seven_cards, false);

  -- Normaliser l'état au début
  _state := public._rami_normalize_state(_g.state);
  _hand := COALESCE(public._rami_jarr(_state->'hands'->_key), ARRAY[]::int[]);
  IF NOT (_card = ANY(_hand)) THEN RAISE EXCEPTION 'carte absente'; END IF;
  _new_hand := public._rami_remove_one(_hand, _card);

  -- Modèle plat : discard + discard_by
  _discard_arr := COALESCE(public._rami_jarr(_state->'discard'), ARRAY[]::int[]);
  _discard_arr := ARRAY(SELECT x FROM unnest(_discard_arr) x WHERE x IS NOT NULL);
  _discard_arr := array_append(_discard_arr, _card);

  IF _state ? 'discard_by' AND _state->'discard_by' IS NOT NULL THEN
    _discard_by := ARRAY(SELECT elem::text FROM jsonb_array_elements_text(_state->'discard_by') elem WHERE elem IS NOT NULL);
  ELSE
    _discard_by := ARRAY[]::text[];
  END IF;
  _discard_by := array_append(_discard_by, _key);

  _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{hands}', _hands);
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
  _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);

  _action_log := COALESCE(_state->'action_log', '[]'::jsonb) ||
    jsonb_build_object('t', 'discard', 'p', _key, 'card', _card, 'ts', extract(epoch from now())::bigint);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  UPDATE public.rami_participants
     SET hand_count=COALESCE(array_length(_new_hand, 1), 0)
   WHERE game_id=_game_id AND user_id=_uid;

  IF COALESCE(array_length(_new_hand, 1), 0) = 0 THEN
    _won := public._rami_check_win(_state, _uid, _seven);
    IF _won THEN
      SELECT COALESCE(pseudo, 'Joueur') INTO _winner_name FROM public.profiles WHERE id=_uid;
      _comm := round(_g.pot * (_g.commission_pct / 2.0) / 100.0, 0);
      _payout := _g.pot - _comm;
      UPDATE public.profiles SET balance_ar=COALESCE(balance_ar, balance)+_payout WHERE id=_uid;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (_uid, 'rami_win', _payout, _game_id, 'Win rami');
      _state := public._rami_normalize_state(_state);
      UPDATE public.rami_games
        SET status='finished', winner_id=_uid, winner_name=_winner_name, finished_at=now(), state=_state
        WHERE id=_game_id;
      RETURN;
    ELSE
      RAISE EXCEPTION 'combinaisons incomplètes';
    END IF;
  END IF;

  SELECT array_agg(slot ORDER BY slot) INTO _parts
    FROM rami_participants WHERE game_id=_game_id AND NOT forfeited;
  _next := _g.current_turn;
  LOOP
    _next := (_next + 1) % _g.max_players;
    EXIT WHEN _next = ANY(_parts);
  END LOOP;

  -- bot_think_until au lieu de pg_sleep(5) — NON BLOQUANT
  SELECT COALESCE(is_bot, false) INTO _next_is_bot
    FROM rami_participants WHERE game_id=_game_id AND slot=_next;

  IF _next_is_bot THEN
    _state := jsonb_set(_state, '{bot_think_until}',
      to_jsonb(to_char(now() + interval '5 seconds', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')), true);
  ELSE
    _state := _state - 'bot_think_until';
  END IF;

  _state := public._rami_normalize_state(_state);

  UPDATE public.rami_games
     SET state=_state, current_turn=_next, turn_phase='draw',
         turn_deadline=now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
         updated_at=now()
   WHERE id=_game_id;
END $function$



CREATE OR REPLACE FUNCTION public.rami_draw(_game_id uuid, _from text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _uid uuid := auth.uid();
  _g public.rami_games;
  _slot int;
  _state jsonb;
  _deck int[];
  _discard_arr int[];
  _discard_by text[];
  _hand int[];
  _card int;
  _hands jsonb;
  _cfg record;
  _action_log jsonb;
  _last_by text;
  _discards jsonb;
  _pile int[];
  _k text;
  _i int;
  _all int[];
  _melds_count int;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  _state := public._rami_normalize_state(_g.state);
  _melds_count := COALESCE(jsonb_array_length(COALESCE(_state->'melds','[]'::jsonb)), 0);

  -- Accepter draw en phase 'play' au 1er tour (1er joueur, 0 melds)
  IF _g.turn_phase = 'play' THEN
    IF _from = 'discard' AND _melds_count = 0
       AND COALESCE(jsonb_array_length(COALESCE(_state->'action_log','[]'::jsonb)), 0) <= 1 THEN
      NULL;
    ELSE
      RAISE EXCEPTION 'deja pioché ou phase de jeu';
    END IF;
  ELSIF _g.turn_phase <> 'draw' THEN
    RAISE EXCEPTION 'deja pioché';
  END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _deck := COALESCE(public._rami_jarr(_state->'deck'), ARRAY[]::int[]);
  _discard_arr := COALESCE(public._rami_jarr(_state->'discard'), ARRAY[]::int[]);
  _discard_arr := ARRAY(SELECT x FROM unnest(_discard_arr) x WHERE x IS NOT NULL);

  IF _state ? 'discard_by' AND _state->'discard_by' IS NOT NULL THEN
    _discard_by := ARRAY(SELECT elem::text FROM jsonb_array_elements_text(_state->'discard_by') elem WHERE elem IS NOT NULL);
  ELSE
    _last_by := COALESCE(_state->>'last_discard_by', '_seed');
    _discard_by := ARRAY(SELECT _last_by FROM generate_series(1, COALESCE(array_length(_discard_arr,1),0)));
  END IF;

  _hand := COALESCE(public._rami_jarr(_state->'hands'->_uid::text), ARRAY[]::int[]);

  IF _from = 'discard' THEN
    IF array_length(_discard_arr, 1) IS NULL THEN
      RAISE EXCEPTION 'défausse vide';
    END IF;
    _card := _discard_arr[array_length(_discard_arr, 1)];
    _discard_arr := _discard_arr[1:array_length(_discard_arr, 1)-1];
    IF array_length(_discard_by, 1) > 0 THEN
      _last_by := _discard_by[array_length(_discard_by, 1)];
      _discard_by := _discard_by[1:array_length(_discard_by, 1)-1];
    ELSE
      _last_by := COALESCE(_state->>'last_discard_by', '_seed');
    END IF;
  ELSE
    IF COALESCE(array_length(_deck, 1), 0) = 0 THEN
      IF array_length(_discard_arr, 1) IS NULL OR array_length(_discard_arr, 1) <= 1 THEN
        RAISE EXCEPTION 'plus de cartes';
      END IF;
      _all := _discard_arr[1:array_length(_discard_arr, 1)-1];
      _card := _discard_arr[array_length(_discard_arr, 1)];
      _discard_arr := ARRAY[_card];
      IF array_length(_discard_by, 1) > 0 THEN
        _last_by := _discard_by[array_length(_discard_by, 1)];
        _discard_by := ARRAY[_last_by];
      ELSE
        _last_by := COALESCE(_state->>'last_discard_by', '_seed');
        _discard_by := ARRAY[_last_by];
      END IF;
      _deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_all) c);
    END IF;
    _card := _deck[1];
    _deck := _deck[2:array_length(_deck, 1)];
  END IF;

  _hand := array_append(_hand, _card);
  _hands := jsonb_set(_state->'hands', ARRAY[_uid::text], to_jsonb(_hand));

  _action_log := COALESCE(_state->'action_log', '[]'::jsonb) ||
    jsonb_build_object('t', 'draw', 'p', _uid::text, 'from', _from, 'card', _card, 'ts', extract(epoch from now())::bigint);

  -- Reconstruire discards multi-pile depuis discard + discard_by
  _discards := '{}'::jsonb;
  IF array_length(_discard_arr, 1) IS NOT NULL THEN
    FOR _k IN SELECT DISTINCT unnest(_discard_by) LOOP
      _pile := ARRAY[]::int[];
      FOR _i IN 1..array_length(_discard_arr, 1) LOOP
        IF _i <= array_length(_discard_by, 1) AND _discard_by[_i] = _k THEN
          _pile := array_append(_pile, _discard_arr[_i]);
        END IF;
      END LOOP;
      IF array_length(_pile, 1) IS NOT NULL THEN
        _discards := _discards || jsonb_build_object(_k, to_jsonb(_pile));
      END IF;
    END LOOP;
  END IF;

  IF array_length(_discard_by, 1) IS NOT NULL THEN
    _last_by := _discard_by[array_length(_discard_by, 1)];
  END IF;

  _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
  _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);
  _state := jsonb_set(_state, '{discards}', _discards, true);
  IF _last_by IS NOT NULL THEN
    _state := jsonb_set(_state, '{last_discard_by}', to_jsonb(_last_by), true);
  END IF;
  _state := jsonb_set(_state, '{hands}', _hands);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  UPDATE public.rami_games
    SET state=_state, turn_phase='play',
        turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
        updated_at=now()
    WHERE id=_game_id;

  UPDATE public.rami_participants SET hand_count=array_length(_hand, 1)
    WHERE game_id=_game_id AND user_id=_uid;
END $function$



CREATE OR REPLACE FUNCTION public.rami_forfeit(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _uid uuid := auth.uid();
  _g public.rami_games;
  _alive uuid[];
  _winner uuid;
  _winner_name text;
  _payout numeric;
  _comm numeric;
  _parts int[];
  _next int;
  _is_host boolean;
  _p record;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id = _game_id FOR UPDATE;
  IF _g.status NOT IN ('waiting', 'playing') THEN RETURN; END IF;

  -- ── Waiting room handling ──
  IF _g.status = 'waiting' THEN
    _is_host := (_g.created_by = _uid);

    IF _is_host THEN
      -- Host quits: refund ALL and cancel
      FOR _p IN SELECT user_id FROM public.rami_participants WHERE game_id = _game_id AND NOT forfeited LOOP
        UPDATE public.profiles SET balance_ar = balance_ar + _g.stake WHERE id = _p.user_id;
        INSERT INTO public.transactions (user_id, type, amount, ref_id, note)
          VALUES (_p.user_id, 'rami_refund', _g.stake, _game_id, 'Annulation salle d''attente (hôte)');
      END LOOP;
      UPDATE public.rami_games SET status = 'cancelled', finished_at = now() WHERE id = _game_id;
    ELSE
      -- Non-host quits: refund only this player, keep room open
      UPDATE public.profiles SET balance_ar = balance_ar + _g.stake WHERE id = _uid;
      INSERT INTO public.transactions (user_id, type, amount, ref_id, note)
        VALUES (_uid, 'rami_refund', _g.stake, _game_id, 'Quitter salle d''attente');
      DELETE FROM public.rami_participants WHERE game_id = _game_id AND user_id = _uid;
    END IF;
    RETURN;
  END IF;

  -- ── Playing status (existing behavior) ──
  UPDATE public.rami_participants SET forfeited = true WHERE game_id = _game_id AND user_id = _uid;
  SELECT array_agg(user_id) INTO _alive FROM public.rami_participants WHERE game_id = _game_id AND NOT forfeited AND user_id IS NOT NULL;

  IF COALESCE(array_length(_alive, 1), 0) = 1 THEN
    _winner := _alive[1];
    SELECT COALESCE(pseudo, 'Joueur') INTO _winner_name FROM public.profiles WHERE id = _winner;
    _comm := round(_g.pot * _g.commission_pct / 100.0, 0);
    _payout := _g.pot - _comm;
    UPDATE public.profiles SET balance_ar = balance_ar + _payout WHERE id = _winner;
    INSERT INTO public.transactions (user_id, type, amount, ref_id, note)
      VALUES (_winner, 'rami_win', _payout, _game_id, 'Win rami by forfeit');
    UPDATE public.rami_games SET status = 'finished', winner_id = _winner, winner_name = _winner_name, finished_at = now() WHERE id = _game_id;
  ELSE
    SELECT _g.current_turn INTO _next;
    IF EXISTS (SELECT 1 FROM public.rami_participants WHERE game_id = _game_id AND slot = _next AND user_id = _uid) THEN
      SELECT array_agg(slot ORDER BY slot) INTO _parts
        FROM public.rami_participants WHERE game_id = _game_id AND NOT forfeited;
      LOOP
        _next := (_next + 1) % _g.max_players;
        EXIT WHEN _next = ANY(_parts);
      END LOOP;
      UPDATE public.rami_games SET current_turn = _next WHERE id = _game_id;
    END IF;
  END IF;
END;
$function$



CREATE OR REPLACE FUNCTION public.rami_join(_game_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _uid uuid := auth.uid(); _g public.rami_games; _bal numeric; _name text;
  _count int; _slot int;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.id IS NULL THEN RAISE EXCEPTION 'partie introuvable'; END IF;
  IF _g.status NOT IN ('waiting','open') THEN RAISE EXCEPTION 'partie deja commencee'; END IF;
  IF _g.is_private THEN RAISE EXCEPTION 'partie privee -- utilise le code pour rejoindre'; END IF;
  IF EXISTS (SELECT 1 FROM public.rami_participants WHERE game_id=_g.id AND user_id=_uid) THEN
    RETURN _g.id;
  END IF;
  SELECT count(*) INTO _count FROM public.rami_participants WHERE game_id=_g.id;
  IF _count >= _g.max_players THEN RAISE EXCEPTION 'partie pleine'; END IF;
  SELECT COALESCE(balance_ar, balance, 0), COALESCE(pseudo, display_name, 'Joueur') INTO _bal, _name
    FROM public.profiles WHERE id=_uid FOR UPDATE;
  IF _bal IS NULL OR _bal < _g.stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
  _slot := _count;
  IF _g.stake > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar - _g.stake WHERE id=_uid;
    UPDATE public.rami_games SET pot = pot + _g.stake WHERE id=_g.id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (_uid, 'rami_stake', -_g.stake, _g.id, 'Join rami');
  END IF;
  INSERT INTO public.rami_participants(game_id, user_id, slot, display_name, is_bot)
    VALUES (_g.id, _uid, _slot, _name, false);
  -- NO auto-start: wait for all players to be ready via rami_set_ready
  RETURN _g.id;
END $function$



CREATE OR REPLACE FUNCTION public.rami_join_code(_code text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _uid   uuid := auth.uid();
  _g     public.rami_games;
  _slot  int;
  _bal   numeric;
  _name  text;
  _count int;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;

  SELECT * INTO _g FROM public.rami_games WHERE room_code = upper(_code) FOR UPDATE;
  IF _g.id IS NULL THEN RAISE EXCEPTION 'partie introuvable'; END IF;
  IF _g.status NOT IN ('waiting', 'open') THEN RAISE EXCEPTION 'partie déjà commencée'; END IF;

  -- Already a participant? Just return the game id.
  IF EXISTS (SELECT 1 FROM public.rami_participants WHERE game_id = _g.id AND user_id = _uid) THEN
    RETURN _g.id;
  END IF;

  SELECT count(*) INTO _count FROM public.rami_participants WHERE game_id = _g.id;
  IF _count >= _g.max_players THEN RAISE EXCEPTION 'partie pleine'; END IF;

  SELECT balance_ar, COALESCE(pseudo, 'Joueur') INTO _bal, _name
    FROM public.profiles WHERE id = _uid FOR UPDATE;
  IF _bal IS NULL OR _bal < _g.stake THEN RAISE EXCEPTION 'solde insuffisant'; END IF;

  _slot := _count;

  IF _g.stake > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar - _g.stake WHERE id = _uid;
    UPDATE public.rami_games SET pot = pot + _g.stake WHERE id = _g.id;
    INSERT INTO public.transactions (user_id, type, amount, ref_id, note)
      VALUES (_uid, 'rami_stake', -_g.stake, _g.id, 'Join rami via code');
  END IF;

  INSERT INTO public.rami_participants (game_id, user_id, slot, display_name, is_bot)
    VALUES (_g.id, _uid, _slot, _name, false);

  -- Auto-start when the game is full
  IF _slot + 1 = _g.max_players THEN
    PERFORM public.rami_start(_g.id);
  END IF;

  RETURN _g.id;
END $function$



CREATE OR REPLACE FUNCTION public.rami_layoff(_game_id uuid, _meld_index integer, _cards integer[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE _uid uuid := auth.uid(); _g rami_games; _slot int; _state jsonb;
  _hand int[]; _c int; _new_hand int[]; _melds jsonb; _existing int[]; _combined int[];
  _new_type text; _old_type text;
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
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
    -- FIX: public._rami_remove_one au lieu de _rami_remove_one
    _new_hand := public._rami_remove_one(_new_hand, _c);
  END LOOP;
  _melds := jsonb_set(_melds, ARRAY[_meld_index::text, 'cards'], to_jsonb(_combined));
  _melds := jsonb_set(_melds, ARRAY[_meld_index::text, 'type'], to_jsonb(_new_type));
  -- FIX: ARRAY['hands', _uid::text] au lieu de '{hands,'||_uid::text||'}'
  _state := jsonb_set(_state, ARRAY['hands', _uid::text], to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{melds}', _melds);
  UPDATE rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  UPDATE rami_participants SET hand_count=COALESCE(array_length(_new_hand,1),0) WHERE game_id=_game_id AND user_id=_uid;
END;
$function$



CREATE OR REPLACE FUNCTION public.rami_meld(_game_id uuid, _cards integer[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _uid uuid := auth.uid();
  _g public.rami_games;
  _slot int;
  _state jsonb;
  _hand int[];
  _c int;
  _new_hand int[];
  _melds jsonb;
  _type text;
  _action_log jsonb;
  _first_melds jsonb;
  _is_pure boolean;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour de jouer'; END IF;

  _type := public._rami_meld_type(_cards, _g.joker_mode, _g.random_joker);
  IF _type IS NULL THEN RAISE EXCEPTION 'combinaison invalide'; END IF;

  _state := _g.state;
  _hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[], ARRAY[]::int[]);
  _new_hand := _hand;
  FOREACH _c IN ARRAY _cards LOOP
    IF NOT (_c = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte absente de la main'; END IF;
    _new_hand := public._rami_remove_one(_new_hand, _c);
  END LOOP;

  -- Check if meld is pure (no jokers)
  _is_pure := true;
  FOREACH _c IN ARRAY _cards LOOP
    IF public._rami_is_joker(_c, _g.joker_mode, _g.random_joker) THEN
      _is_pure := false;
    END IF;
  END LOOP;

  _melds := COALESCE(_state->'melds', '[]'::jsonb) || jsonb_build_array(
    jsonb_build_object(
      'player', _uid::text,
      'cards', to_jsonb(_cards),
      'type', _type,
      'pure', _is_pure
    )
  );

  -- Track first meld timestamp per player (harmless metadata)
  _first_melds := COALESCE(_state->'first_melds', '{}'::jsonb);
  IF _first_melds ? _uid::text = false OR _first_melds->_uid::text IS NULL THEN
    _first_melds := jsonb_set(_first_melds, ARRAY[_uid::text], to_jsonb(extract(epoch from now())::bigint), true);
  END IF;

  _action_log := COALESCE(_state->'action_log', '[]'::jsonb) ||
    jsonb_build_object('t', 'meld', 'p', _uid::text, 'type', _type, 'n', array_length(_cards, 1), 'pure', _is_pure, 'ts', extract(epoch from now())::bigint);

  _state := jsonb_set(_state, ARRAY['hands', _uid::text], to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{melds}', _melds);
  _state := jsonb_set(_state, '{first_melds}', _first_melds, true);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand, 1), 0)
    WHERE game_id=_game_id AND user_id=_uid;
END;
$function$



CREATE OR REPLACE FUNCTION public.rami_request_refund(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
END $function$



CREATE OR REPLACE FUNCTION public.rami_set_ready(_game_id uuid, _ready boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_g public.rami_games;
  v_total int;
  v_ready int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM public.rami_games WHERE id = _game_id FOR UPDATE;
  IF v_g.id IS NULL THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status NOT IN ('waiting', 'open') THEN RETURN; END IF;

  UPDATE public.rami_participants
     SET ready = COALESCE(_ready, false)
   WHERE game_id = _game_id AND user_id = v_uid;

  IF NOT FOUND THEN RAISE EXCEPTION 'not a participant'; END IF;

  SELECT count(*), count(*) FILTER (WHERE ready)
    INTO v_total, v_ready
    FROM public.rami_participants
   WHERE game_id = _game_id;

  IF v_total = v_g.max_players AND v_ready = v_total THEN
    PERFORM public.rami_start(_game_id);
  END IF;
END;
$function$



CREATE OR REPLACE FUNCTION public.rami_spectate(_game_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _g public.rami_games;
  _state jsonb;
  _sanitized jsonb;
  _participants jsonb;
  _count int;
  _max int;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id = _game_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Game not found'; END IF;
  IF _g.status NOT IN ('playing', 'paused') THEN
    RAISE EXCEPTION 'Game not in progress';
  END IF;
  SELECT COALESCE(max_spectators, 50) INTO _max FROM public.app_settings WHERE id = 1;
  SELECT count(*) INTO _count FROM public.game_spectators WHERE game_id = _game_id;
  IF _count >= _max THEN
    RAISE EXCEPTION 'Spectator limit reached';
  END IF;
  INSERT INTO public.game_spectators(game_id, user_id)
    VALUES (_game_id, auth.uid()) ON CONFLICT DO NOTHING;
  _state := _g.state;
  _sanitized := jsonb_build_object(
    'deck_count', jsonb_array_length(COALESCE(_state->'deck', '[]'::jsonb)),
    'melds', COALESCE(_state->'melds', '[]'::jsonb),
    'discards', COALESCE(_state->'discards', '{}'::jsonb),
    'last_discard_by', COALESCE(_state->>'last_discard_by', ''),
    'action_log', COALESCE(_state->'action_log', '[]'::jsonb)
  );
  -- FIX: ORDER BY dans le jsonb_agg au lieu de la fin du SELECT
  SELECT jsonb_agg(jsonb_build_object(
    'user_id', p.user_id, 'display_name', p.display_name, 'slot', p.slot,
    'hand_count', p.hand_count, 'is_bot', p.is_bot, 'forfeited', p.forfeited
  ) ORDER BY p.slot) INTO _participants
  FROM public.rami_participants p WHERE p.game_id = _game_id;
  RETURN jsonb_build_object(
    'game', jsonb_build_object(
      'id', _g.id, 'status', _g.status, 'current_turn', _g.current_turn,
      'turn_phase', _g.turn_phase, 'stake', _g.stake, 'pot', _g.pot,
      'joker_mode', _g.joker_mode, 'game_mode', _g.game_mode,
      'winner_id', _g.winner_id, 'state', _sanitized
    ),
    'participants', COALESCE(_participants, '[]'::jsonb)
  );
END;
$function$



CREATE OR REPLACE FUNCTION public.rami_spectate_leave(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  DELETE FROM public.game_spectators WHERE game_id = _game_id AND user_id = auth.uid();
END;
$function$



CREATE OR REPLACE FUNCTION public.rami_start(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _g public.rami_games; _deck int[]; _i int; _j int; _tmp int;
  _hands jsonb := '{}'::jsonb; _hand int[]; _state jsonb; _key text;
  _cfg record; _joker_mode text; _random_joker int;
  _discards jsonb; _action_log jsonb;
  _slot int; _uid uuid; _is_bot boolean;
  _is_first boolean := true;
  _card_count int;
  _deck_size int;
  _max_players int;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status NOT IN ('waiting','open') THEN RETURN; END IF;

  IF (SELECT count(*) FROM public.rami_participants WHERE game_id=_game_id) < 2 THEN
    RAISE EXCEPTION 'pas assez de joueurs';
  END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');

  _joker_mode := _g.joker_mode;
  _random_joker := NULL;

  IF _joker_mode = 'aucun' THEN
    _deck_size := 52;
  ELSIF _joker_mode = 'fixe' THEN
    _deck_size := 54;
  ELSE
    _deck_size := 56;
    _random_joker := floor(random()*52)::int;
  END IF;

  _max_players := _g.max_players;
  IF _max_players <= 2 THEN
    _deck := ARRAY(SELECT generate_series(0, _deck_size-1)) ||
             ARRAY(SELECT generate_series(56, _deck_size-1+56));
  ELSE
    _deck := ARRAY(SELECT generate_series(0, _deck_size-1)) ||
             ARRAY(SELECT generate_series(56, _deck_size-1+56)) ||
             ARRAY(SELECT generate_series(112, _deck_size-1+112));
  END IF;

  FOR _i IN REVERSE array_length(_deck,1)..2 LOOP
    _j := 1 + floor(random()*_i)::int;
    _tmp := _deck[_i]; _deck[_i] := _deck[_j]; _deck[_j] := _tmp;
  END LOOP;

  -- Deal: first player gets 14, others get 13
  FOR _slot, _uid, _is_bot IN
    SELECT slot, user_id, is_bot FROM public.rami_participants
    WHERE game_id=_game_id ORDER BY slot
  LOOP
    IF _is_first THEN
      _card_count := 14;
      _is_first := false;
    ELSE
      _card_count := 13;
    END IF;

    _hand := _deck[1:_card_count];
    _deck := _deck[_card_count+1:array_length(_deck,1)];
    _key := CASE WHEN COALESCE(_is_bot, false) THEN 'bot:' || _slot::text ELSE _uid::text END;
    _hands := _hands || jsonb_build_object(_key, to_jsonb(_hand));
    UPDATE public.rami_participants SET hand_count = _card_count
      WHERE game_id=_game_id AND slot=_slot;
  END LOOP;

  -- PAS de carte seed sur la défausse — la défausse commence vide
  _discards := '{}'::jsonb;

  _action_log := jsonb_build_array(
    jsonb_build_object('t', 'start', 'ts', extract(epoch from now())::bigint)
  );

  _state := jsonb_build_object(
    'deck', to_jsonb(_deck),
    'discards', _discards,
    'discard', '[]'::jsonb,
    'last_discard_by', null::jsonb,
    'hands', _hands,
    'melds', '[]'::jsonb,
    'action_log', _action_log,
    'refunded', '{}'::jsonb
  );

  UPDATE public.rami_games SET
    status='playing', state=_state, started_at=now(),
    current_turn=0, turn_phase='play',  -- 1er joueur en phase 'play' (il a déjà 14 cartes)
    random_joker=_random_joker,
    turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval
    WHERE id=_game_id;

  PERFORM public._rami_autoplay_bots(_game_id);
END $function$



CREATE OR REPLACE FUNCTION public.rami_start_solo_bot(_max_players integer DEFAULT 2, _difficulty text DEFAULT 'medium'::text, _joker_mode text DEFAULT 'classique'::text, _game_mode text DEFAULT 'bordel'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid      uuid := auth.uid();
  v_game_id  uuid;
  v_code     text;
  v_name     text;
  v_intel    int;
  v_paused   boolean;
  v_banned   boolean;
  v_slot     int;
  v_bot_names text[] := ARRAY['Bot Rija','Bot Naina','Bot Hery','Bot Voara'];
  v_max      int;
  v_deck     int[];
  v_i        int;
  v_j        int;
  v_tmp      int;
  v_hands    jsonb := '{}'::jsonb;
  v_hand     int[];
  v_key      text;
  v_rj       int := NULL;
  v_state    jsonb;
  v_card_count int;
  v_is_first boolean := true;
BEGIN
  PERFORM public._assert_solo_bot_enabled();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _max_players < 2 OR _max_players > 4 THEN RAISE EXCEPTION 'Joueurs invalides (2-4)'; END IF;
  IF _joker_mode NOT IN ('sans','aleatoire','classique','double') THEN _joker_mode := 'classique'; END IF;
  IF _game_mode NOT IN ('bordel','naturel') THEN _game_mode := 'bordel'; END IF;

  SELECT paused INTO v_paused FROM public.app_settings WHERE id = 1;
  IF COALESCE(v_paused, false) THEN RAISE EXCEPTION 'Application en pause'; END IF;

  SELECT banned, COALESCE(pseudo,'Joueur') INTO v_banned, v_name
    FROM public.profiles WHERE id = v_uid;
  IF COALESCE(v_banned, false) THEN RAISE EXCEPTION 'Compte banni'; END IF;

  CASE lower(_difficulty)
    WHEN 'easy' THEN v_intel := 30;
    WHEN 'hard' THEN v_intel := 95;
    ELSE v_intel := 70;
  END CASE;

  v_code := public._rami_gen_code();

  INSERT INTO public.rami_games (
    room_code, is_private, stake, max_players, commission_pct,
    created_by, pot, joker_mode, game_mode, status
  ) VALUES (
    v_code, true, 0, _max_players, 0, v_uid, 0, _joker_mode, _game_mode, 'waiting'
  ) RETURNING id INTO v_game_id;

  INSERT INTO public.rami_participants(game_id, user_id, slot, display_name, ready, is_bot)
    VALUES (v_game_id, v_uid, 0, v_name, true, false);

  FOR v_slot IN 1.._max_players - 1 LOOP
    INSERT INTO public.rami_participants(
      game_id, user_id, slot, display_name, ready, is_bot, bot_name, bot_intelligence
    ) VALUES (
      v_game_id, NULL, v_slot, v_bot_names[v_slot], true, true, v_bot_names[v_slot], v_intel
    );
  END LOOP;

  IF _joker_mode IN ('classique','double') THEN v_max := 56; ELSE v_max := 52; END IF;
  v_deck := ARRAY(SELECT generate_series(0, v_max - 1));
  FOR v_i IN REVERSE v_max..2 LOOP
    v_j := 1 + floor(random() * v_i)::int;
    v_tmp := v_deck[v_i]; v_deck[v_i] := v_deck[v_j]; v_deck[v_j] := v_tmp;
  END LOOP;

  -- Deal: 1er joueur (humain, slot 0) a 14 cartes, les autres 13
  v_is_first := true;
  FOR v_slot IN 0.._max_players - 1 LOOP
    IF v_is_first THEN
      v_card_count := 14;
      v_is_first := false;
    ELSE
      v_card_count := 13;
    END IF;

    v_hand := v_deck[1:v_card_count];
    v_deck := v_deck[v_card_count+1:array_length(v_deck,1)];
    v_key := CASE WHEN v_slot = 0 THEN v_uid::text ELSE 'bot:' || v_slot::text END;
    v_hands := v_hands || jsonb_build_object(v_key, to_jsonb(v_hand));
    UPDATE public.rami_participants SET hand_count = v_card_count
      WHERE game_id = v_game_id AND slot = v_slot;
  END LOOP;

  -- Joker aléatoire si mode aleatoire/double
  IF _joker_mode IN ('aleatoire','double') THEN
    v_i := 1;
    WHILE v_i <= array_length(v_deck,1) AND v_deck[v_i] >= 52 LOOP
      v_i := v_i + 1;
    END LOOP;
    IF v_i <= array_length(v_deck,1) THEN
      v_rj := v_deck[v_i];
      v_deck := v_deck[1:v_i-1] || v_deck[v_i+1:array_length(v_deck,1)];
    END IF;
  END IF;

  -- PAS de carte _seed sur la défausse (aligné avec rami_start)
  v_state := jsonb_build_object(
    'deck',           to_jsonb(v_deck),
    'discards',       '{}'::jsonb,
    'discard',        '[]'::jsonb,
    'last_discard_by', null::jsonb,
    'hands',          v_hands,
    'melds',          '[]'::jsonb,
    'first_player',   0
  );

  UPDATE public.rami_games SET
    status        = 'playing',
    state         = v_state,
    started_at    = now(),
    current_turn  = 0,           -- L'humain (slot 0) commence toujours
    turn_phase    = 'play',      -- 14 cartes, doit défausser une carte
    random_joker  = v_rj,
    turn_deadline = now() + interval '60 seconds'
  WHERE id = v_game_id;

  -- Ne pas autoplay les bots au démarrage — c'est à l'humain de jouer
  RETURN v_game_id;
END $function$



CREATE OR REPLACE FUNCTION public.rami_tick(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _g rami_games; _state jsonb; _uid uuid; _is_bot boolean; _slot int;
  _hand int[]; _new_hand int[];
  _deck int[]; _card int; _next int; _cfg record;
  _skips int; _pkey text;
  _discard_arr int[];
  _discard_by text[];
  _think text;
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RETURN; END IF;

  SELECT user_id, is_bot, slot INTO _uid, _is_bot, _slot
    FROM rami_participants WHERE game_id=_game_id AND slot=_g.current_turn;

  IF COALESCE(_is_bot, false) THEN
    -- Respecter bot_think_until
    _think := _g.state->>'bot_think_until';
    IF _think IS NOT NULL THEN
      IF _think > to_char(now(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') THEN
        RETURN;
      END IF;
      _state := _g.state - 'bot_think_until';
      UPDATE rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
    END IF;
    PERFORM public._rami_autoplay_bots(_game_id);
    RETURN;
  END IF;

  IF _g.turn_deadline IS NULL OR _g.turn_deadline > now() THEN RETURN; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _state := public._rami_normalize_state(_g.state);
  _pkey := _uid::text;
  _hand := COALESCE(public._rami_jarr(_state->'hands'->_pkey), ARRAY[]::int[]);
  _discard_arr := COALESCE(public._rami_jarr(_state->'discard'), ARRAY[]::int[]);
  _discard_arr := ARRAY(SELECT x FROM unnest(_discard_arr) x WHERE x IS NOT NULL);
  IF _state ? 'discard_by' AND _state->'discard_by' IS NOT NULL THEN
    _discard_by := ARRAY(SELECT elem::text FROM jsonb_array_elements_text(_state->'discard_by') elem WHERE elem IS NOT NULL);
  ELSE
    _discard_by := ARRAY[]::text[];
  END IF;

  IF _g.turn_phase = 'draw' THEN
    _deck := COALESCE(public._rami_jarr(_state->'deck'), ARRAY[]::int[]);
    IF array_length(_deck,1) IS NULL AND array_length(_discard_arr,1) IS NOT NULL AND array_length(_discard_arr,1) > 1 THEN
      DECLARE _all int[]; BEGIN
        _all := _discard_arr[1:array_length(_discard_arr, 1)-1];
        _discard_arr := ARRAY[_discard_arr[array_length(_discard_arr, 1)]];
        _discard_by := ARRAY[_discard_by[array_length(_discard_by, 1)]];
        _deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_all) c);
      END;
    END IF;

    IF array_length(_deck,1) IS NULL THEN
      IF array_length(_hand, 1) IS NULL THEN RETURN; END IF;
      _card := _hand[1 + floor(random()*array_length(_hand,1))::int];
      _new_hand := public._rami_remove_one(_hand, _card);
      _discard_arr := array_append(_discard_arr, _card);
      _discard_by := array_append(_discard_by, _pkey);
      _state := jsonb_set(_state, ARRAY['hands',_pkey], to_jsonb(_new_hand));
      _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
      _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);
      UPDATE rami_participants SET hand_count=array_length(_new_hand,1) WHERE game_id=_game_id AND user_id=_uid;
      _next := _g.current_turn;
      LOOP
        _next := (_next + 1) % _g.max_players;
        EXIT WHEN _next IN (SELECT slot FROM rami_participants WHERE game_id=_game_id AND NOT forfeited);
      END LOOP;
      _state := public._rami_normalize_state(_state);
      UPDATE rami_games SET state=_state, current_turn=_next, turn_phase='draw',
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
        updated_at=now() WHERE id=_game_id;
      PERFORM public._rami_autoplay_bots(_game_id);
      RETURN;
    END IF;

    _card := _deck[1];
    _deck := _deck[2:array_length(_deck,1)];
    _hand := array_append(_hand, _card);
    _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
    _state := jsonb_set(_state, ARRAY['hands',_pkey], to_jsonb(_hand));
    _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
    _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);
    _state := public._rami_normalize_state(_state);
    UPDATE rami_participants SET hand_count=COALESCE(array_length(_hand,1),0)
      WHERE game_id=_game_id AND user_id=_uid;
    UPDATE rami_games SET state=_state, turn_phase='play',
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
        updated_at=now() WHERE id=_game_id;
    RETURN;
  END IF;

  _skips := COALESCE((_g.turn_skips->>_uid::text)::int, 0) + 1;
  IF _skips >= COALESCE(_cfg.max_turn_skips, 3) THEN
    UPDATE rami_participants SET forfeited = true WHERE game_id=_game_id AND user_id=_uid;
    IF (SELECT count(*) FROM rami_participants WHERE game_id=_game_id AND NOT forfeited) <= 1 THEN
      DECLARE _win uuid; _payout numeric; BEGIN
        SELECT user_id INTO _win FROM rami_participants WHERE game_id=_game_id AND NOT forfeited LIMIT 1;
        UPDATE rami_games SET status='finished', winner_id=_win, finished_at=now() WHERE id=_game_id;
        IF _win IS NOT NULL THEN
          _payout := _g.pot * (100 - _g.commission_pct) / 100;
          UPDATE profiles SET balance_ar = COALESCE(balance_ar, balance) + _payout WHERE id=_win;
          INSERT INTO transactions(user_id,type,amount,ref_id,note)
            VALUES (_win,'rami_win', _payout, _game_id, 'Rami win (forfait)');
        END IF;
        RETURN;
      END;
    END IF;
  END IF;

  IF array_length(_hand, 1) IS NULL THEN RETURN; END IF;
  _card := _hand[1 + floor(random()*array_length(_hand,1))::int];
  _new_hand := public._rami_remove_one(_hand, _card);
  _discard_arr := array_append(_discard_arr, _card);
  _discard_by := array_append(_discard_by, _pkey);
  _state := jsonb_set(_state, ARRAY['hands',_pkey], to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
  _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);
  UPDATE rami_participants SET hand_count=array_length(_new_hand,1) WHERE game_id=_game_id AND user_id=_uid;

  _next := _g.current_turn;
  LOOP
    _next := (_next + 1) % _g.max_players;
    EXIT WHEN _next IN (SELECT slot FROM rami_participants WHERE game_id=_game_id AND NOT forfeited);
  END LOOP;

  _state := public._rami_normalize_state(_state);
  UPDATE rami_games SET state=_state, current_turn=_next, turn_phase='draw',
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
    updated_at=now() WHERE id=_game_id;
  PERFORM public._rami_autoplay_bots(_game_id);
END $function$



CREATE OR REPLACE FUNCTION public.rami_unmeld(_game_id uuid, _meld_index integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _melds jsonb; _m jsonb; _cards int[]; _hand int[]; _new_melds jsonb := '[]'::jsonb;
  _i int; _stake numeric; _refunded jsonb; _bal numeric;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase NOT IN ('draw','play') THEN RAISE EXCEPTION 'pas ton tour de jouer'; END IF;

  _state := public._rami_normalize_state(_g.state);
  _melds := _state->'melds';
  IF _meld_index < 0 OR _meld_index >= jsonb_array_length(_melds) THEN
    RAISE EXCEPTION 'combinaison introuvable';
  END IF;
  _m := _melds->_meld_index;
  IF _m->>'player' <> _uid::text THEN RAISE EXCEPTION 'ce n''est pas ta combinaison'; END IF;

  -- Inline replacement for _rami_jarr: jsonb array → int[]
  _cards := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_m->'cards'))::int[], ARRAY[]::int[]);
  _hand  := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[], ARRAY[]::int[]) || _cards;

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
  -- Inline replacement for _rami_jset: int[] → jsonb
  _state := jsonb_set(_state, ARRAY['hands',_uid::text], to_jsonb(_hand), true);

  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_hand,1),0)
    WHERE game_id=_game_id AND user_id=_uid;
END $function$



CREATE OR REPLACE FUNCTION public.rami_validate_hand(_game_id uuid, _layout jsonb, _discard_card integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _uid uuid := auth.uid();
  _g public.rami_games;
  _slot int;
  _state jsonb;
  _hand int[];
  _c int;
  _new_hand int[];
  _melds jsonb;
  _group jsonb;
  _cards int[];
  _type text;
  _is_pure boolean;
  _action_log jsonb;
  _won boolean;
  _payout numeric;
  _comm numeric;
  _first_melds jsonb;
  _winner_name text;
  _seven boolean;
  _cfg record;
  _parts int[];
  _next int;
  _discard_arr int[];
  _discard_by text[];
  _key text;
  _next_is_bot boolean;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _seven := COALESCE(_g.seven_cards, false);
  _key := _uid::text;
  _state := public._rami_normalize_state(_g.state);
  _hand := COALESCE(public._rami_jarr(_state->'hands'->_key), ARRAY[]::int[]);
  _new_hand := _hand;

  _first_melds := COALESCE(_state->'first_melds', '{}'::jsonb);
  _melds := COALESCE(_state->'melds', '[]'::jsonb);

  FOR _group IN SELECT * FROM jsonb_array_elements(_layout) LOOP
    _cards := ARRAY(SELECT jsonb_array_elements_text(_group))::int[];
    FOREACH _c IN ARRAY _cards LOOP
      IF NOT (_c = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte absente de la main'; END IF;
      _new_hand := public._rami_remove_one(_new_hand, _c);
    END LOOP;

    _type := public._rami_meld_type(_cards, _g.joker_mode, _g.random_joker);
    IF _type IS NULL THEN RAISE EXCEPTION 'combinaison invalide dans le layout'; END IF;

    _is_pure := true;
    FOREACH _c IN ARRAY _cards LOOP
      IF public._rami_is_joker(_c, _g.joker_mode, _g.random_joker) THEN
        _is_pure := false;
      END IF;
    END LOOP;

    _melds := _melds || jsonb_build_array(
      jsonb_build_object(
        'player', _key,
        'cards', to_jsonb(_cards),
        'type', _type,
        'pure', _is_pure
      )
    );

    IF _first_melds ? _key = false OR _first_melds->_key IS NULL THEN
      _first_melds := jsonb_set(_first_melds, ARRAY[_key], to_jsonb(extract(epoch from now())::bigint), true);
    END IF;
  END LOOP;

  IF NOT (_discard_card = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte de défausse absente'; END IF;
  _new_hand := public._rami_remove_one(_new_hand, _discard_card);

  _state := jsonb_set(_state, '{melds}', _melds);
  _state := jsonb_set(_state, '{first_melds}', _first_melds, true);

  -- MODÈLE UNIFIÉ : discard + discard_by (comme rami_discard)
  _discard_arr := COALESCE(public._rami_jarr(_state->'discard'), ARRAY[]::int[]);
  _discard_arr := ARRAY(SELECT x FROM unnest(_discard_arr) x WHERE x IS NOT NULL);
  _discard_arr := array_append(_discard_arr, _discard_card);

  IF _state ? 'discard_by' AND _state->'discard_by' IS NOT NULL THEN
    _discard_by := ARRAY(SELECT elem::text FROM jsonb_array_elements_text(_state->'discard_by') elem WHERE elem IS NOT NULL);
  ELSE
    _discard_by := ARRAY[]::text[];
  END IF;
  _discard_by := array_append(_discard_by, _key);

  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
  _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);

  _action_log := COALESCE(_state->'action_log', '[]'::jsonb) ||
    jsonb_build_object('t', 'validate_hand', 'p', _key, 'discard', _discard_card, 'ts', extract(epoch from now())::bigint);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand, 1), 0)
    WHERE game_id=_game_id AND user_id=_uid;

  IF COALESCE(array_length(_new_hand, 1), 0) = 0 THEN
    _won := public._rami_check_win(_state, _uid, _seven);
    IF _won THEN
      SELECT COALESCE(pseudo, 'Joueur') INTO _winner_name FROM public.profiles WHERE id=_uid;
      _comm := round(_g.pot * (_g.commission_pct / 2.0) / 100.0, 0);
      _payout := _g.pot - _comm;
      UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) + _payout WHERE id = _uid;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (_uid, 'rami_win', _payout, _game_id, 'Win rami');
      _state := public._rami_normalize_state(_state);
      UPDATE public.rami_games SET status='finished', winner_id=_uid, winner_name=_winner_name, finished_at=now(), state=_state WHERE id=_game_id;
      RETURN jsonb_build_object('won', true, 'winner_name', _winner_name);
    ELSE
      _state := jsonb_set(_state, ARRAY['hands', _key], to_jsonb(_new_hand));
      _state := public._rami_normalize_state(_state);
      UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
      RETURN jsonb_build_object('won', false);
    END IF;
  ELSE
    _state := jsonb_set(_state, ARRAY['hands', _key], to_jsonb(_new_hand));

    SELECT array_agg(slot ORDER BY slot) INTO _parts
      FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited;
    _next := _g.current_turn;
    LOOP
      _next := (_next + 1) % _g.max_players;
      EXIT WHEN _next = ANY(_parts);
    END LOOP;

    SELECT COALESCE(is_bot, false) INTO _next_is_bot
      FROM public.rami_participants
      WHERE game_id=_game_id AND slot=_next;

    IF _next_is_bot THEN
      _state := jsonb_set(_state, '{bot_think_until}',
        to_jsonb(to_char(now() + interval '5 seconds', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')), true);
    ELSE
      _state := _state - 'bot_think_until';
    END IF;

    _state := public._rami_normalize_state(_state);

    UPDATE public.rami_games
       SET state=_state, current_turn=_next, turn_phase='draw',
           turn_deadline=now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
           updated_at=now()
     WHERE id=_game_id;
    RETURN jsonb_build_object('won', false);
  END IF;
END $function$


-- ── Grants pour les fonctions publiques Rami ──
REVOKE ALL ON FUNCTION public.rami_create(uuid, text, text, int, int, boolean, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_create(uuid, text, text, int, int, boolean, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.rami_join(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_join(uuid, uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.rami_join_code(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_join_code(uuid, text) TO authenticated;
REVOKE ALL ON FUNCTION public.rami_start(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_start(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.rami_start_solo_bot(uuid, text, int, int, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_start_solo_bot(uuid, text, int, int, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.rami_draw(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_draw(uuid, text) TO authenticated;
REVOKE ALL ON FUNCTION public.rami_discard(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_discard(uuid, integer) TO authenticated;
REVOKE ALL ON FUNCTION public.rami_meld(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_meld(uuid, jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.rami_unmeld(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_unmeld(uuid, jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.rami_layoff(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_layoff(uuid, jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.rami_validate_hand(uuid, jsonb, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_validate_hand(uuid, jsonb, integer) TO authenticated;
REVOKE ALL ON FUNCTION public.rami_forfeit(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_forfeit(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.rami_add_bot(uuid, int, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_add_bot(uuid, int, int) TO authenticated;
REVOKE ALL ON FUNCTION public.rami_set_ready(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_set_ready(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.rami_tick(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_tick(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.rami_spectate(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_spectate(uuid, uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.rami_spectate_leave(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_spectate_leave(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.rami_claim_seven(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_claim_seven(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.rami_request_refund(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_request_refund(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.rami_bot_tick_all() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_bot_tick_all() TO authenticated;
