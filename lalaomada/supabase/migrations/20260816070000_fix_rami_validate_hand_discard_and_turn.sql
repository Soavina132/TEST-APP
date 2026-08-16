-- ═══ Fix: la carte défaussée via "Valider" n'apparaît pas sur la défausse ═══
--
-- Bug: rami_validate_hand retire la carte de la main mais ne l'ajoute JAMAIS
-- à la pile de défausse (state.discards / state.discard / state.last_discard_by).
-- La carte disparaît dans le vide → l'adversaire ne peut pas la piocher.
--
-- Bug 2: rami_validate_hand ne passe pas le tour au joueur suivant quand le
-- joueur ne gagne pas → la partie reste bloquée sur le même joueur en phase 'play'.
--
-- Bug 3: _rami_safe_int_array (modifié précédemment) crashe sur les valeurs
-- jsonb 'null' car jsonb_array_elements_text retourne le texte 'null' qui
-- ne peut pas être casté en int. Fix: utiliser un filtre regex.

-- ── Fix 1: _rami_safe_int_array robuste contre les null ──
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
END $function$;

-- ── Fix 2: rami_validate_hand — ajoute la carte à la défausse + passe le tour ──
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
  _discard int[];
  _discards jsonb;
  _pile int[];
  _key text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _seven := COALESCE(_g.seven_cards, false);
  _state := _g.state;
  _hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[], ARRAY[]::int[]);
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
        'player', _uid::text,
        'cards', to_jsonb(_cards),
        'type', _type,
        'pure', _is_pure
      )
    );

    IF _first_melds ? _uid::text = false OR _first_melds->_uid::text IS NULL THEN
      _first_melds := jsonb_set(_first_melds, ARRAY[_uid::text], to_jsonb(extract(epoch from now())::bigint), true);
    END IF;
  END LOOP;

  IF NOT (_discard_card = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte de défausse absente'; END IF;
  _new_hand := public._rami_remove_one(_new_hand, _discard_card);

  _state := jsonb_set(_state, '{melds}', _melds);
  _state := jsonb_set(_state, '{first_melds}', _first_melds, true);

  -- ── NOUVEAU: ajouter la carte à la pile de défausse ──
  _key := _uid::text;
  _discard := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'discard'))::int[], ARRAY[]::int[]);
  _discard := array_append(_discard, _discard_card);

  _discards := public._rami_discards_map(_state);
  _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_key))::int[], ARRAY[]::int[]);
  _pile := array_append(_pile, _discard_card);
  _discards := jsonb_set(_discards, ARRAY[_key], to_jsonb(_pile), true);

  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard));
  _state := jsonb_set(_state, '{discards}', _discards);
  _state := jsonb_set(_state, '{last_discard_by}', to_jsonb(_key));

  _action_log := COALESCE(_state->'action_log', '[]'::jsonb) ||
    jsonb_build_object('t', 'validate_hand', 'p', _uid::text, 'discard', _discard_card, 'ts', extract(epoch from now())::bigint);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  -- Mettre à jour le hand_count
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
      UPDATE public.rami_games SET status='finished', winner_id=_uid, winner_name=_winner_name, finished_at=now(), state=_state WHERE id=_game_id;
      RETURN jsonb_build_object('won', true, 'winner_name', _winner_name);
    ELSE
      _state := jsonb_set(_state, ARRAY['hands', _uid::text], to_jsonb(_new_hand));
      UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
      RETURN jsonb_build_object('won', false);
    END IF;
  ELSE
    _state := jsonb_set(_state, ARRAY['hands', _uid::text], to_jsonb(_new_hand));

    -- ── NOUVEAU: passer le tour au joueur suivant ──
    SELECT array_agg(slot ORDER BY slot) INTO _parts
      FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited;
    _next := _g.current_turn;
    LOOP
      _next := (_next + 1) % _g.max_players;
      EXIT WHEN _next = ANY(_parts);
    END LOOP;

    UPDATE public.rami_games
       SET state=_state, current_turn=_next, turn_phase='draw',
           turn_deadline=now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
           updated_at=now()
     WHERE id=_game_id;
    RETURN jsonb_build_object('won', false);
  END IF;
END;
$function$;

-- ── Fix 3: nettoyer les nulls dans les parties en cours ──
UPDATE public.rami_games g
SET state = jsonb_set(
      jsonb_set(g.state, '{discard}', to_jsonb(public._rami_safe_int_array(g.state->'discard'))),
      '{deck}', to_jsonb(public._rami_safe_int_array(g.state->'deck'))
    )
WHERE g.status = 'playing'
  AND (
    g.state->'discard' @> 'null'::jsonb
    OR g.state->'deck' @> 'null'::jsonb
  );
