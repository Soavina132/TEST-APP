-- ============================================================
-- Fix winner_name in rami_discard, rami_validate_hand, rami_forfeit
--
-- Bug: These 3 functions set winner_id but NOT winner_name.
-- The _rami_autoplay_bots function (bot wins) correctly sets winner_name,
-- but human win paths were missing it.
-- Also backfill winner_name for already-finished games.
-- ============================================================

-- ═══ 1. rami_discard: add winner_name on human win ═══
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
  _winner_name text;
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

  -- Check win: hand empty AND combos valid
  IF COALESCE(array_length(_new_hand, 1), 0) = 0 THEN
    _won := public._rami_check_win(_state, _uid);
    IF _won THEN
      SELECT COALESCE(pseudo, 'Joueur') INTO _winner_name FROM public.profiles WHERE id=_uid;
      _comm := round(_g.pot * _g.commission_pct / 100.0, 0);
      _payout := _g.pot - _comm;
      UPDATE public.profiles SET balance_ar=balance_ar+_payout WHERE id=_uid;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (_uid, 'rami_win', _payout, _game_id, 'Win rami');
      UPDATE public.rami_games
        SET status='finished', winner_id=_uid, winner_name=_winner_name, finished_at=now(), state=_state
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

-- ═══ 2. rami_validate_hand: add winner_name on human win ═══
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

  _first_melds := COALESCE(_state->'first_melds', '{}'::jsonb);
  _melds := COALESCE(_state->'melds', '[]'::jsonb);

  -- Validate each group in layout
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

  -- Discard the discard card
  IF NOT (_discard_card = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte de défausse absente'; END IF;
  _new_hand := public._rami_remove_one(_new_hand, _discard_card);

  _state := jsonb_set(_state, '{melds}', _melds);
  _state := jsonb_set(_state, '{first_melds}', _first_melds, true);

  _action_log := COALESCE(_state->'action_log', '[]'::jsonb) ||
    jsonb_build_object('t', 'validate_hand', 'p', _uid::text, 'ts', extract(epoch from now())::bigint);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  -- Check win: hand must be empty
  IF COALESCE(array_length(_new_hand, 1), 0) = 0 THEN
    _won := public._rami_check_win(_state, _uid);
    IF _won THEN
      SELECT COALESCE(pseudo, 'Joueur') INTO _winner_name FROM public.profiles WHERE id=_uid;
      _comm := round(_g.pot * _g.commission_pct / 100.0, 0);
      _payout := _g.pot - _comm;
      UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) + _payout WHERE id = _uid;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (_uid, 'rami_win', _payout, _game_id, 'Win rami');
      UPDATE public.rami_games SET status='finished', winner_id=_uid, winner_name=_winner_name, finished_at=now(), state=_state WHERE id=_game_id;
      UPDATE public.rami_participants SET hand_count=0 WHERE game_id=_game_id AND user_id=_uid;
      RETURN jsonb_build_object('won', true, 'winner_name', _winner_name);
    ELSE
      _state := jsonb_set(_state, ARRAY['hands', _uid::text], to_jsonb(_new_hand));
      UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
      UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand, 1), 0)
        WHERE game_id=_game_id AND user_id=_uid;
      RETURN jsonb_build_object('won', false);
    END IF;
  ELSE
    _state := jsonb_set(_state, ARRAY['hands', _uid::text], to_jsonb(_new_hand));
    UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
    UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand, 1), 0)
      WHERE game_id=_game_id AND user_id=_uid;
    RETURN jsonb_build_object('won', false);
  END IF;
END;
$function$;
REVOKE ALL ON FUNCTION public.rami_validate_hand(uuid, jsonb, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_validate_hand(uuid, jsonb, integer) TO authenticated;

-- ═══ 3. rami_forfeit: add winner_name on forfeit win ═══
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
$function$;
REVOKE ALL ON FUNCTION public.rami_forfeit(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_forfeit(uuid) TO authenticated;

-- ═══ 4. Backfill winner_name for already-finished games ═══

-- Human winners: set from profiles.pseudo
UPDATE public.rami_games g SET winner_name = pr.pseudo
  FROM public.profiles pr
 WHERE g.winner_id = pr.id
   AND g.winner_name IS NULL
   AND g.status = 'finished';

-- Bot winners: set from rami_participants.display_name (bots have winner_id=NULL but the
-- game was ended by _maybe_end_bot_only_rami which doesn't set a winner at all — skip those)
