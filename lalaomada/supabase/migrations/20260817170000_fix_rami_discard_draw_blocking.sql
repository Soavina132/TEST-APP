-- ═══════════════════════════════════════════════════════════════
-- Fix Rami : pioche sur la défausse ne fonctionne pas toujours
--
-- Bugs corrigés :
-- 1. rami_discard utilise pg_sleep(5) qui bloque le verrou FOR UPDATE
--    pendant 5 secondes → toute action du joueur pendant ce temps
--    est bloquée → "la pioche ne fonctionne pas"
-- 2. rami_discard ne calling pas _rami_normalize_state → l'état peut
--    être désynchronisé (discards multi-pile stale)
-- 3. rami_discard ne vérifie pas _slot IS NULL → un non-participant
--    peut passer la vérification (NULL <> X = NULL ≠ TRUE en SQL)
-- 4. _rami_reshuffle utilise l'ancien modèle multi-pile (discards)
--    sans retourner discard/discard_by → état désynchronisé
-- 5. rami_tick n'attend pas bot_think_until avant de déclencher le bot
--
-- Solution :
-- - rami_discard utilise bot_think_until (comme rami_validate_hand)
--   au lieu de pg_sleep(5) — non bloquant
-- - rami_discard appelle _rami_normalize_state au début et avant save
-- - rami_discard vérifie _slot IS NULL
-- - _rami_reshuffle utilise le modèle plat (discard + discard_by)
-- - rami_tick respecte bot_think_until
-- - rami_draw accepte turn_phase='play' au 1er tour (1er joueur)
-- ═══════════════════════════════════════════════════════════════

-- ── 1. Fix rami_discard : non-bloquant + normalisation + sécurité ──
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
END $function$;
REVOKE ALL ON FUNCTION public.rami_discard(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_discard(uuid, integer) TO authenticated;

-- ── 2. Fix _rami_reshuffle : utiliser le modèle plat ──
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
END $function$;

-- ── 3. Fix rami_tick : respecter bot_think_until ──
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
END $function$;
REVOKE ALL ON FUNCTION public.rami_tick(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_tick(uuid) TO authenticated;

-- ── 4. Fix rami_draw : accepter turn_phase='play' au 1er tour ──
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
END $function$;
REVOKE ALL ON FUNCTION public.rami_draw(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_draw(uuid,text) TO authenticated;
