-- ═══════════════════════════════════════════════════════════════
-- Fix Rami : unifier le modèle de défausse
--
-- Bug : rami_discard et rami_draw utilisent discard+discard_by+normalize,
-- mais rami_validate_hand utilise l'ancien modèle discards (multi-pile)
-- sans mettre à jour discard_by ni appeler _rami_normalize_state.
-- Résultat : après un validate_hand, le state est désynchronisé.
--
-- Solution : les 3 fonctions utilisent toutes le même modèle :
--   - discard (int[]) : pile plate des cartes défaussées
--   - discard_by (text[]) : qui a défaussé chaque carte
--   - _rami_normalize_state dérive discards (multi-pile) + last_discard_by
-- ═══════════════════════════════════════════════════════════════

-- ── 1. rami_draw : pioche depuis deck ou défausse ──
CREATE OR REPLACE FUNCTION public.rami_draw(_game_id uuid, _from text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
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
    IF array_length(_discard_arr, 1) IS NULL THEN RAISE EXCEPTION 'défausse vide'; END IF;
    _card := _discard_arr[array_length(_discard_arr, 1)];
    _discard_arr := _discard_arr[1:array_length(_discard_arr, 1)-1];
    IF array_length(_discard_by, 1) > 0 THEN
      _discard_by := _discard_by[1:array_length(_discard_by, 1)-1];
    END IF;
  ELSE
    IF COALESCE(array_length(_deck, 1), 0) = 0 THEN
      IF array_length(_discard_arr, 1) IS NOT NULL AND array_length(_discard_arr, 1) > 1 THEN
        _all := _discard_arr[1:array_length(_discard_arr, 1)-1];
        _discard_arr := ARRAY[_discard_arr[array_length(_discard_arr, 1)]];
        IF array_length(_discard_by, 1) > 0 THEN
          _discard_by := ARRAY[_discard_by[array_length(_discard_by, 1)]];
        END IF;
        _deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_all) c);
      ELSE
        RAISE EXCEPTION 'plus de cartes';
      END IF;
    END IF;
    _card := _deck[1];
    _deck := _deck[2:array_length(_deck, 1)];
  END IF;

  _hand := array_append(_hand, _card);
  _hands := jsonb_set(_state->'hands', ARRAY[_uid::text], to_jsonb(_hand));

  _action_log := COALESCE(_state->'action_log', '[]'::jsonb) ||
    jsonb_build_object('t', 'draw', 'p', _uid::text, 'from', _from, 'card', _card, 'ts', extract(epoch from now())::bigint);

  _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
  _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);
  _state := jsonb_set(_state, '{hands}', _hands);
  _state := jsonb_set(_state, '{action_log}', _action_log);
  _state := public._rami_normalize_state(_state);

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

-- ── 2. rami_discard : défausser une carte ──
CREATE OR REPLACE FUNCTION public.rami_discard(_game_id uuid, _card integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $function$
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
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _key := _uid::text;
  _seven := COALESCE(_g.seven_cards, false);
  _state := public._rami_normalize_state(_g.state);
  _hand := COALESCE(public._rami_jarr(_state->'hands'->_key), ARRAY[]::int[]);
  IF NOT (_card = ANY(_hand)) THEN RAISE EXCEPTION 'carte absente'; END IF;
  _new_hand := public._rami_remove_one(_hand, _card);

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
END $function$;
REVOKE ALL ON FUNCTION public.rami_discard(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_discard(uuid, integer) TO authenticated;

-- ── 3. rami_validate_hand : poser melds + défausser en un coup ──
CREATE OR REPLACE FUNCTION public.rami_validate_hand(_game_id uuid, _layout jsonb, _discard_card integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
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
END $function$;
REVOKE ALL ON FUNCTION public.rami_validate_hand(uuid, jsonb, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_validate_hand(uuid, jsonb, integer) TO authenticated;

-- ── 4. Corriger les parties en cours ──
UPDATE public.rami_games g
SET state = public._rami_normalize_state(g.state)
WHERE g.status = 'playing';
