-- ════════════════════════════════════════════════════════════════════
-- Rami : 3 Vies + Fix Timer Auto-Pass
--
-- A. 3 VIES :
--    Chaque joueur a 3 vies. À chaque expiration du timer (90s),
--    le joueur perd 1 vie. À 0 vie → éliminé (forfait).
--    Les vies sont reset quand le joueur joue normalement.
--
-- B. FIX TIMER :
--    rami_tick ne sauvegardait jamais turn_skips dans la DB.
--    Le compteur restait à 0 → le tour ne passait jamais automatiquement.
-- ════════════════════════════════════════════════════════════════════

-- ── 1. Changer max_turn_skips à 3 (3 vies) ────────────────────────────
UPDATE public.game_configs SET max_turn_skips = 3 WHERE slug = 'rami';

-- ── 2. Fix rami_tick : sauvegarder turn_skips + 3 vies ────────────────
CREATE OR REPLACE FUNCTION public.rami_tick(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  _g rami_games; _state jsonb; _uid uuid; _is_bot boolean; _slot int;
  _hand int[]; _new_hand int[];
  _deck int[]; _card int; _next int; _cfg record;
  _skips int; _pkey text;
  _discard_arr int[];
  _discard_by text[];
  _think text;
  _max_lives int;
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
  _max_lives := COALESCE(_cfg.max_turn_skips, 3);

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

  -- ── Phase DRAW : auto-pioche ──
  IF _g.turn_phase = 'draw' THEN
    _deck := COALESCE(public._rami_jarr(_state->'deck'), ARRAY[]::int[]);
    IF array_length(_deck,1) IS NULL AND array_length(_discard_arr,1) IS NOT NULL AND array_length(_discard_arr,1) > 1 THEN
      DECLARE _all int[]; BEGIN
        _all := _discard_arr[1:array_length(_discard_arr, 1)-1];
        _discard_arr := ARRAY[_discard_arr[array_length(_discard_arr, 1)]];
        _discard_by := ARRAY[_discard_by[array_length(_discard_by, 1)]];
        _deck := (SELECT array_agg(c ORDER BY gen_random_uuid()) FROM unnest(_all) c);
      END;
    END IF;

    IF array_length(_deck,1) IS NULL THEN
      IF array_length(_hand, 1) IS NULL THEN RETURN; END IF;
      _card := _hand[1 + public._crypto_rand_int(array_length(_hand,1))];
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

  -- ── Phase PLAY : auto-défausse + perte de vie ──
  _skips := COALESCE((_g.turn_skips->>_pkey)::int, 0) + 1;

  -- Sauvegarder le compteur de vies perdues dans la DB
  UPDATE rami_games
    SET turn_skips = jsonb_set(COALESCE(turn_skips, '{}'::jsonb), ARRAY[_pkey], to_jsonb(_skips))
    WHERE id = _game_id;

  IF _skips >= _max_lives THEN
    -- 0 vie restante → éliminé
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
  _card := _hand[1 + public._crypto_rand_int(array_length(_hand,1))];
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

-- ── 3. rami_discard : reset turn_skips quand le joueur joue ────────────
CREATE OR REPLACE FUNCTION public.rami_discard(_game_id uuid, _card integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  _uid uuid := auth.uid();
  _g public.rami_games;
  _slot int;
  _state jsonb;
  _hand int[];
  _new_hand int[];
  _discard int[];
  _next int;
  _parts int[];
  _cfg record;
  _won boolean;
  _payout numeric;
  _comm numeric;
  _winner_name text;
  _seven boolean;
  _action_log jsonb;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _seven := COALESCE(_g.seven_cards, false);
  _state := public._rami_normalize_state(_g.state);

  _hand := COALESCE(public._rami_jarr(_state->'hands'->_uid::text), ARRAY[]::int[]);
  IF NOT (_card = ANY(_hand)) THEN RAISE EXCEPTION 'carte absente'; END IF;
  _new_hand := public._rami_remove_one(_hand, _card);

  _discard := COALESCE(public._rami_jarr(_state->'discard'), ARRAY[]::int[]);
  _discard := ARRAY(SELECT x FROM unnest(_discard) x WHERE x IS NOT NULL);
  _discard := array_append(_discard, _card);

  _state := jsonb_set(_state, ARRAY['hands', _uid::text], to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard), true);

  _action_log := COALESCE(_state->'action_log', '[]'::jsonb) ||
    jsonb_build_object('t', 'discard', 'p', _uid::text, 'card', _card,
                       'ts', extract(epoch from now())::bigint);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand, 1), 0)
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
      UPDATE public.rami_games
        SET status='finished', winner_id=_uid, winner_name=_winner_name,
            finished_at=now(), state=_state
        WHERE id=_game_id;
      RETURN;
    ELSE
      RAISE EXCEPTION 'combinaisons incompletes';
    END IF;
  END IF;

  SELECT array_agg(slot ORDER BY slot) INTO _parts
    FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited;
  _next := _g.current_turn;
  LOOP
    _next := (_next + 1) % _g.max_players;
    EXIT WHEN _next = ANY(_parts);
  END LOOP;

  -- Reset turn_skips pour ce joueur (il a joué normalement)
  UPDATE public.rami_games
    SET state=_state, current_turn=_next, turn_phase='draw',
        turn_deadline=now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
        turn_skips = COALESCE(turn_skips, '{}'::jsonb) - _uid::text,
        updated_at=now()
    WHERE id=_game_id;

  PERFORM public._rami_autoplay_bots(_game_id);
END $function$;
