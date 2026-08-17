-- ═══════════════════════════════════════════════════════════════════
-- REWRITE RAMI: Source de vérité unique pour la défausse
--
-- discard (int[]) + discard_by (text[]) = source de vérité
-- discards (multi-pile) + last_discard_by = dérivés
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. _rami_normalize_state ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public._rami_normalize_state(_state jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $function$
DECLARE
  _discards jsonb;
  _discard_arr int[];
  _discard_by text[];
  _all int[];
  _by_all text[];
  _k text; _v jsonb;
  _last_by text;
  _new_discards jsonb;
BEGIN
  IF _state IS NULL THEN RETURN '{}'::jsonb; END IF;

  -- ── Étape 1: Assurer discard + discard_by exist et sont cohérents ──
  _discard_arr := COALESCE(public._rami_jarr(_state->'discard'), ARRAY[]::int[]);

  IF _state ? 'discard_by' AND _state->'discard_by' IS NOT NULL THEN
    _discard_by := ARRAY(SELECT elem::text FROM jsonb_array_elements_text(_state->'discard_by') elem WHERE elem IS NOT NULL);
  ELSE
    -- Pas de discard_by: construire depuis discards ou last_discard_by
    _last_by := COALESCE(_state->>'last_discard_by', '_seed');
    _discard_by := ARRAY(SELECT _last_by FROM generate_series(1, COALESCE(array_length(_discard_arr, 1), 0)));
  END IF;

  -- Assurer même longueur
  IF array_length(_discard_arr, 1) IS NULL AND array_length(_discard_by, 1) IS NULL THEN
    -- Les deux vides, OK
    NULL;
  ELSIF array_length(_discard_arr, 1) IS NULL THEN
    _discard_by := ARRAY[]::text[];
  ELSIF array_length(_discard_by, 1) IS NULL THEN
    _last_by := COALESCE(_state->>'last_discard_by', '_seed');
    _discard_by := ARRAY(SELECT _last_by FROM generate_series(1, array_length(_discard_arr, 1)));
  ELSIF array_length(_discard_arr, 1) <> array_length(_discard_by, 1) THEN
    -- Désynchronisation: tronquer au plus court
    IF array_length(_discard_by, 1) > array_length(_discard_arr, 1) THEN
      _discard_by := _discard_by[1:array_length(_discard_arr, 1)];
    ELSE
      _last_by := COALESCE(_state->>'last_discard_by', '_seed');
      _discard_by := _discard_by || ARRAY(SELECT _last_by FROM generate_series(1, array_length(_discard_arr, 1) - array_length(_discard_by, 1)));
    END IF;
  END IF;

  -- ── Étape 2: Dériver discards (multi-pile) depuis discard + discard_by ──
  _new_discards := '{}'::jsonb;
  IF array_length(_discard_arr, 1) IS NOT NULL THEN
    FOR _k IN SELECT DISTINCT unnest(_discard_by) LOOP
      _all := ARRAY[]::int[];
      FOR i IN 1..array_length(_discard_arr, 1) LOOP
        IF _discard_by[i] = _k THEN
          _all := array_append(_all, _discard_arr[i]);
        END IF;
      END LOOP;
      IF array_length(_all, 1) IS NOT NULL THEN
        _new_discards := _new_discards || jsonb_build_object(_k, to_jsonb(_all));
      END IF;
    END LOOP;
  END IF;

  -- ── Étape 3: last_discard_by = dernier élément de discard_by ──
  IF array_length(_discard_by, 1) IS NOT NULL THEN
    _last_by := _discard_by[array_length(_discard_by, 1)];
  ELSE
    _last_by := NULL;
  END IF;

  -- ── Étape 4: Sauvegarder tout ──
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
  _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);
  _state := jsonb_set(_state, '{discards}', _new_discards, true);
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
END $function$;

-- ── 2. rami_draw ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rami_draw(_game_id uuid, _from text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
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
  _all int[];
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn THEN RAISE EXCEPTION 'pas ton tour'; END IF;
  IF _g.turn_phase <> 'draw' THEN RAISE EXCEPTION 'deja pioché ou phase de jeu'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _state := public._rami_normalize_state(_g.state);
  _deck := COALESCE(public._rami_jarr(_state->'deck'), ARRAY[]::int[]);
  _discard_arr := COALESCE(public._rami_jarr(_state->'discard'), ARRAY[]::int[]);
  _discard_arr := ARRAY(SELECT x FROM unnest(_discard_arr) x WHERE x IS NOT NULL);
  IF _state ? 'discard_by' AND _state->'discard_by' IS NOT NULL THEN
    _discard_by := ARRAY(SELECT elem::text FROM jsonb_array_elements_text(_state->'discard_by') elem WHERE elem IS NOT NULL);
  ELSE
    _discard_by := ARRAY[]::text[];
  END IF;
  _hand := COALESCE(public._rami_jarr(_state->'hands'->_uid::text), ARRAY[]::int[]);

  IF _from = 'discard' THEN
    -- ═══ Pioche sur la défausse: prendre la dernière carte ═══
    IF array_length(_discard_arr, 1) IS NULL THEN RAISE EXCEPTION 'défausse vide'; END IF;
    _card := _discard_arr[array_length(_discard_arr, 1)];
    _discard_arr := _discard_arr[1:array_length(_discard_arr, 1)-1];
    IF array_length(_discard_by, 1) > 0 THEN
      _discard_by := _discard_by[1:array_length(_discard_by, 1)-1];
    END IF;
  ELSE
    -- ═══ Pioche sur le deck ═══
    IF COALESCE(array_length(_deck, 1), 0) = 0 THEN
      -- Reshuffle: tout sauf le dessus de la défausse devient le deck
      IF array_length(_discard_arr, 1) IS NOT NULL AND array_length(_discard_arr, 1) > 1 THEN
        _all := _discard_arr[1:array_length(_discard_arr, 1)-1];
        _discard_arr := ARRAY[_discard_arr[array_length(_discard_arr, 1)]];
        _discard_by := ARRAY[_discard_by[array_length(_discard_by, 1)]];
        _deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_all) c);
      ELSIF array_length(_discard_arr, 1) = 1 THEN
        RAISE EXCEPTION 'plus de cartes';
      ELSE
        RAISE EXCEPTION 'plus de cartes';
      END IF;
    END IF;
    _card := _deck[1];
    _deck := _deck[2:array_length(_deck, 1)];
  END IF;

  -- Ajouter la carte à la main
  _hand := array_append(_hand, _card);
  _hands := jsonb_set(_state->'hands', ARRAY[_uid::text], to_jsonb(_hand));

  -- Action log
  _action_log := COALESCE(_state->'action_log', '[]'::jsonb) ||
    jsonb_build_object('t', 'draw', 'p', _uid::text, 'from', _from, 'card', _card, 'ts', extract(epoch from now())::bigint);

  -- Sauvegarder
  _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
  _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);
  _state := jsonb_set(_state, '{hands}', _hands);
  _state := jsonb_set(_state, '{action_log}', _action_log);
  -- Re-normaliser pour dériver discards + last_discard_by
  _state := public._rami_normalize_state(_state);

  UPDATE public.rami_games
    SET state=_state, turn_phase='play',
        turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
        updated_at=now()
    WHERE id=_game_id;
  UPDATE public.rami_participants SET hand_count=array_length(_hand, 1)
    WHERE game_id=_game_id AND user_id=_uid;
END $function$;

-- ── 3. rami_discard ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rami_discard(_game_id uuid, _card integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  _uid uuid := auth.uid();
  _g public.rami_games;
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
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _key := _uid::text;
  _seven := COALESCE(_g.seven_cards, false);
  _state := public._rami_normalize_state(_g.state);
  _hand := COALESCE(public._rami_jarr(_state->'hands'->_key), ARRAY[]::int[]);
  IF NOT (_card = ANY(_hand)) THEN RAISE EXCEPTION 'carte absente'; END IF;
  _new_hand := public._rami_remove_one(_hand, _card);

  -- ═══ Ajouter la carte à la défausse (source de vérité) ═══
  _discard_arr := COALESCE(public._rami_jarr(_state->'discard'), ARRAY[]::int[]);
  _discard_arr := array_append(_discard_arr, _card);

  IF _state ? 'discard_by' AND _state->'discard_by' IS NOT NULL THEN
    _discard_by := ARRAY(SELECT elem::text FROM jsonb_array_elements_text(_state->'discard_by') elem WHERE elem IS NOT NULL);
  ELSE
    _discard_by := ARRAY[]::text[];
  END IF;
  _discard_by := array_append(_discard_by, _key);

  -- Mettre à jour la main
  _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{hands}', _hands);
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
  _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);

  -- Action log
  _action_log := COALESCE(_state->'action_log', '[]'::jsonb) ||
    jsonb_build_object('t', 'discard', 'p', _key, 'card', _card, 'ts', extract(epoch from now())::bigint);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  -- Mettre à jour hand_count
  UPDATE public.rami_participants
     SET hand_count=COALESCE(array_length(_new_hand, 1), 0)
   WHERE game_id=_game_id AND user_id=_uid;

  -- Vérifier victoire
  IF COALESCE(array_length(_new_hand, 1), 0) = 0 THEN
    _won := public._rami_check_win(_state, _uid, _seven);
    IF _won THEN
      SELECT COALESCE(pseudo, 'Joueur') INTO _winner_name FROM public.profiles WHERE id=_uid;
      _comm := round(_g.pot * (_g.commission_pct / 2.0) / 100.0, 0);
      _payout := _g.pot - _comm;
      UPDATE public.profiles SET balance_ar=balance_ar+_payout WHERE id=_uid;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (_uid, 'rami_win', _payout, _game_id, 'Win rami');
      -- Normaliser avant de sauver
      _state := public._rami_normalize_state(_state);
      UPDATE public.rami_games
        SET status='finished', winner_id=_uid, winner_name=_winner_name, finished_at=now(), state=_state
        WHERE id=_game_id;
      RETURN;
    ELSE
      RAISE EXCEPTION 'combinaisons incomplètes';
    END IF;
  END IF;

  -- Passer au joueur suivant
  SELECT array_agg(slot ORDER BY slot) INTO _parts
    FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited;
  _next := _g.current_turn;
  LOOP
    _next := (_next + 1) % _g.max_players;
    EXIT WHEN _next = ANY(_parts);
  END LOOP;

  -- Bot check
  SELECT COALESCE(is_bot, false) INTO _next_is_bot
    FROM public.rami_participants
    WHERE game_id=_game_id AND slot=_next;

  IF _next_is_bot THEN
    _state := jsonb_set(_state, '{bot_think_until}',
      to_jsonb(to_char(now() + interval '5 seconds', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')), true);
  ELSE
    _state := _state - 'bot_think_until';
  END IF;

  -- Normaliser pour dériver discards + last_discard_by
  _state := public._rami_normalize_state(_state);

  UPDATE public.rami_games
     SET state=_state, current_turn=_next, turn_phase='draw',
         turn_deadline=now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
         updated_at=now()
   WHERE id=_game_id;
END $function$;

-- ── 4. rami_tick (timeout auto-play) ──────────────────────────────
CREATE OR REPLACE FUNCTION public.rami_tick(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  _g rami_games; _state jsonb; _uid uuid; _is_bot boolean; _slot int;
  _hand int[]; _new_hand int[];
  _deck int[]; _card int; _next int; _cfg record;
  _skips int; _pkey text;
  _discard_arr int[];
  _discard_by text[];
  _reshuffle jsonb;
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RETURN; END IF;

  SELECT user_id, is_bot, slot INTO _uid, _is_bot, _slot
    FROM rami_participants WHERE game_id=_game_id AND slot=_g.current_turn;

  IF COALESCE(_is_bot, false) THEN
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
      -- Reshuffle
      DECLARE _all int[]; BEGIN
        _all := _discard_arr[1:array_length(_discard_arr, 1)-1];
        _discard_arr := ARRAY[_discard_arr[array_length(_discard_arr, 1)]];
        _discard_by := ARRAY[_discard_by[array_length(_discard_by, 1)]];
        _deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_all) c);
      END;
    END IF;

    IF array_length(_deck,1) IS NULL THEN
      -- ═══ Timeout + deck vide: forcer défausse ═══
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

    -- ═══ Auto-pioche du deck ═══
    _card := _deck[1];
    _deck := _deck[2:array_length(_deck,1)];
    _hand := array_append(_hand, _card);
    _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
    _state := jsonb_set(_state, ARRAY['hands',_pkey], to_jsonb(_hand));
    -- discard inchangé
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

  -- ═══ Timeout en play: auto-défausser ═══
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

-- ── 5. _rami_autoplay_bots ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._rami_autoplay_bots(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $function$
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
END $function$;

-- ── 6. _rami_reshuffle (update pour cohérence) ────────────────────
CREATE OR REPLACE FUNCTION public._rami_reshuffle(_state jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $function$
DECLARE
  _discard_arr int[];
  _discard_by text[];
  _deck int[];
  _all int[];
BEGIN
  _state := public._rami_normalize_state(_state);
  _discard_arr := public._rami_jarr(_state->'discard');
  _discard_arr := ARRAY(SELECT x FROM unnest(_discard_arr) x WHERE x IS NOT NULL);
  _discard_by := ARRAY(SELECT elem::text FROM jsonb_array_elements_text(_state->'discard_by') elem WHERE elem IS NOT NULL);

  IF array_length(_discard_arr, 1) IS NULL OR array_length(_discard_arr, 1) <= 1 THEN
    RETURN jsonb_build_object('deck', '[]'::jsonb, 'discards', public._rami_discards_map(_state));
  END IF;

  _all := _discard_arr[1:array_length(_discard_arr, 1)-1];
  _deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_all) c);

  RETURN jsonb_build_object(
    'deck', to_jsonb(_deck),
    'discard', to_jsonb(ARRAY[_discard_arr[array_length(_discard_arr, 1)]]),
    'discard_by', to_jsonb(ARRAY[_discard_by[array_length(_discard_by, 1)]]),
    'discards', jsonb_build_object(
      COALESCE(_discard_by[array_length(_discard_by, 1)], '_reshuffled'),
      to_jsonb(ARRAY[_discard_arr[array_length(_discard_arr, 1)]])
    )
  );
END $function$;
