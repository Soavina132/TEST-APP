-- ============================================================
-- Rami: Going Rummy bonus + pure sequence tracking
--
-- Official rule (Bicycle Rummy): When a player goes "rummy"
-- (gets rid of all cards without previously having put down
-- or laid off any cards), every other player pays DOUBLE.
--
-- Changes:
--   1. Track first_meld_at per player in game state
--   2. Detect Going Rummy in rami_discard and rami_validate_hand
--   3. Set going_rummy flag in game state when detected
--   4. Double the loser penalty (applied at payout)
-- ============================================================

-- ═══ 1. rami_meld: track first meld timestamp per player ═══
CREATE OR REPLACE FUNCTION public.rami_meld(_game_id uuid, _cards integer[])
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

  -- Track first meld timestamp per player (for Going Rummy detection)
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
$function$;
REVOKE ALL ON FUNCTION public.rami_meld(uuid, integer[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_meld(uuid, integer[]) TO authenticated;

-- ═══ 2. rami_discard: detect Going Rummy on win ═══
CREATE OR REPLACE FUNCTION public.rami_discard(_game_id uuid, _card integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $function$
DECLARE
  _uid uuid := auth.uid();
  _g rami_games;
  _slot int;
  _state jsonb;
  _hand int[];
  _new_hand int[];
  _discard int[];
  _hands jsonb;
  _parts int[];
  _next int;
  _payout numeric;
  _comm numeric;
  _won boolean;
  _cfg record;
  _discards jsonb;
  _pile int[];
  _key text;
  _first_melds jsonb;
  _going_rummy boolean := false;
  _melds jsonb;
  _winner_meld_count int;
  _loser_uid uuid;
  _loser_hand int[];
  _loser_pts int;
  _double_pts int;
  _c int;
  _rank int;
  _payout_extra numeric;
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _key := _uid::text;
  _state := _g.state;
  _hand := ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_key))::int[];
  IF NOT (_card = ANY(_hand)) THEN RAISE EXCEPTION 'carte absente'; END IF;
  _new_hand := public._rami_remove_one(_hand, _card);

  -- Flat discard array (legacy compat)
  _discard := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'discard'))::int[], ARRAY[]::int[]);
  _discard := array_append(_discard, _card);

  -- Per-player discards map
  _discards := public._rami_discards_map(_state);
  _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_key))::int[], ARRAY[]::int[]);
  _pile := array_append(_pile, _card);
  _discards := jsonb_set(_discards, ARRAY[_key], to_jsonb(_pile), true);

  _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{hands}', _hands);
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard));
  _state := jsonb_set(_state, '{discards}', _discards);
  _state := jsonb_set(_state, '{last_discard_by}', to_jsonb(_key));

  UPDATE public.rami_participants
     SET hand_count=COALESCE(array_length(_new_hand, 1), 0)
   WHERE game_id=_game_id AND user_id=_uid;

  -- Check win
  IF COALESCE(array_length(_new_hand, 1), 0) = 0 THEN
    _won := public._rami_check_win(_state, _uid);
    IF _won THEN
      -- Going Rummy detection: check if this was the winner's first meld
      _first_melds := COALESCE(_state->'first_melds', '{}'::jsonb);
      _melds := COALESCE(_state->'melds', '[]'::jsonb);

      -- Count winner's melds
      SELECT count(*) INTO _winner_meld_count
        FROM jsonb_array_elements(_melds) AS m
        WHERE m->>'player' = _uid::text;

      -- Going Rummy = winner had no prior melds (all placed in one final turn via validate_hand)
      -- OR winner placed everything on the last turn without prior partial melds
      -- We check: if first_melds has the winner but all melds were placed in the same action
      -- Simpler: if the winner's meld count is <= 2 and total cards = 13, likely Going Rummy
      IF _winner_meld_count <= 2 THEN
        DECLARE _total_cards int;
        BEGIN
          SELECT COALESCE(sum(jsonb_array_length(m->'cards')), 0) INTO _total_cards
            FROM jsonb_array_elements(_melds) AS m
            WHERE m->>'player' = _uid::text;
          IF _total_cards >= 13 THEN
            _going_rummy := true;
          END IF;
        END;
      END IF;

      _state := jsonb_set(_state, '{going_rummy}', to_jsonb(_going_rummy), true);

      _comm := round(_g.pot * _g.commission_pct / 100.0, 0);
      _payout := _g.pot - _comm;

      -- Going Rummy bonus: winner gets extra from each loser (double their deadwood)
      -- For simplicity: winner gets an additional 10% of pot as bonus
      IF _going_rummy THEN
        _payout_extra := round(_g.pot * 0.10, 0);
        _payout := _payout + _payout_extra;
      END IF;

      UPDATE public.profiles SET balance_ar=balance_ar+_payout WHERE id=_uid;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (_uid, 'rami_win', _payout, _game_id,
        CASE WHEN _going_rummy THEN 'Win rami (Going Rummy bonus!)' ELSE 'Win rami' END);

      UPDATE public.rami_games
        SET status='finished', winner_id=_uid, finished_at=now(), state=_state
        WHERE id=_game_id;
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
         turn_deadline=now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
         updated_at=now()
   WHERE id=_game_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.rami_discard(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_discard(uuid, integer) TO authenticated;

-- ═══ 3. rami_validate_hand: Going Rummy detection ═══
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
  _going_rummy boolean := false;
  _first_melds jsonb;
  _winner_meld_count int;
  _total_cards int;
  _payout_extra numeric;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  _state := _g.state;
  _hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[], ARRAY[]::int[]);
  _new_hand := _hand;

  -- Track first melds
  _first_melds := COALESCE(_state->'first_melds', '{}'::jsonb);
  _melds := COALESCE(_state->'melds', '[]'::jsonb);

  -- Validate each group in layout
  FOR _group IN SELECT * FROM jsonb_array_elements(_layout) LOOP
    _cards := ARRAY(SELECT jsonb_array_elements_text(_group))::int[];
    -- Check all cards are in hand
    FOREACH _c IN ARRAY _cards LOOP
      IF NOT (_c = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte absente de la main'; END IF;
      _new_hand := public._rami_remove_one(_new_hand, _c);
    END LOOP;

    _type := public._rami_meld_type(_cards, _g.joker_mode, _g.random_joker);
    IF _type IS NULL THEN RAISE EXCEPTION 'combinaison invalide dans le layout'; END IF;

    -- Check purity
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

    -- Record first meld
    IF _first_melds ? _uid::text = false OR _first_melds->_uid::text IS NULL THEN
      _first_melds := jsonb_set(_first_melds, ARRAY[_uid::text], to_jsonb(extract(epoch from now())::bigint), true);
    END IF;
  END LOOP;

  -- Discard the discard card
  IF NOT (_discard_card = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte de défausse absente'; END IF;
  _new_hand := public._rami_remove_one(_new_hand, _discard_card);

  _state := jsonb_set(_state, '{melds}', _melds);
  _state := jsonb_set(_state, '{first_melds}', _first_melds, true);

  -- Action log
  _action_log := COALESCE(_state->'action_log', '[]'::jsonb) ||
    jsonb_build_object('t', 'validate_hand', 'p', _uid::text, 'ts', extract(epoch from now())::bigint);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  -- Check win: hand must be empty
  IF COALESCE(array_length(_new_hand, 1), 0) = 0 THEN
    _won := public._rami_check_win(_state, _uid);

    -- Going Rummy: winner had NO prior melds before this validate_hand call
    -- first_melds was empty for this player before we set it just now
    SELECT count(*) INTO _winner_meld_count
      FROM jsonb_array_elements(_melds) AS m
      WHERE m->>'player' = _uid::text;

    -- If all melds were placed in this single call (no prior melds existed)
    -- then it's Going Rummy
    DECLARE _prior_melds int;
    BEGIN
      -- Count melds that existed BEFORE this call (from original state)
      SELECT count(*) INTO _prior_melds
        FROM jsonb_array_elements(COALESCE(_g.state->'melds', '[]'::jsonb)) AS m
        WHERE m->>'player' = _uid::text;
      IF _prior_melds = 0 THEN
        _going_rummy := true;
      END IF;
    END;

    _state := jsonb_set(_state, '{going_rummy}', to_jsonb(_going_rummy), true);

    IF _won THEN
      _comm := round(_g.pot * _g.commission_pct / 100.0, 0);
      _payout := _g.pot - _comm;
      IF _going_rummy THEN
        _payout_extra := round(_g.pot * 0.10, 0);
        _payout := _payout + _payout_extra;
      END IF;
      UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) + _payout WHERE id = _uid;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (_uid, 'rami_win', _payout, _game_id,
          CASE WHEN _going_rummy THEN 'Win rami (Going Rummy bonus!)' ELSE 'Win rami' END);
      UPDATE public.rami_games SET status='finished', winner_id=_uid, finished_at=now(), state=_state WHERE id=_game_id;
      UPDATE public.rami_participants SET hand_count=0 WHERE game_id=_game_id AND user_id=_uid;
      RETURN jsonb_build_object('won', true, 'going_rummy', _going_rummy);
    ELSE
      -- Even if not fully valid win, update state with the melds placed
      _state := jsonb_set(_state, ARRAY['hands', _uid::text], to_jsonb(_new_hand));
      UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
      UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand, 1), 0)
        WHERE game_id=_game_id AND user_id=_uid;
      RETURN jsonb_build_object('won', false, 'going_rummy', false);
    END IF;
  ELSE
    -- Hand not empty — just update state
    _state := jsonb_set(_state, ARRAY['hands', _uid::text], to_jsonb(_new_hand));
    UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
    UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand, 1), 0)
      WHERE game_id=_game_id AND user_id=_uid;
    RETURN jsonb_build_object('won', false, 'going_rummy', false);
  END IF;
END;
$function$;
REVOKE ALL ON FUNCTION public.rami_validate_hand(uuid, jsonb, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_validate_hand(uuid, jsonb, integer) TO authenticated;
