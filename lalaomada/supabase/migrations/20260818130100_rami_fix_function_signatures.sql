-- ============================================================
-- Fix: Clean up duplicate function signatures + fix _rami_check_win calls
-- Drop old versions that conflict with the latest _rami_meld_type and _rami_check_win
-- ============================================================

-- Drop old _rami_check_win signatures
DROP FUNCTION IF EXISTS public._rami_check_win(jsonb, uuid);
DROP FUNCTION IF EXISTS public._rami_check_win(jsonb, text);
DROP FUNCTION IF EXISTS public._rami_check_win(jsonb, uuid, boolean);

-- Ensure only the latest signature remains: (jsonb, text, boolean)
-- (already created in 20260818130000_rami_seven_cards_backend.sql)

-- Fix rami_discard: use _uid::text instead of _uid for _rami_check_win call
CREATE OR REPLACE FUNCTION public.rami_discard(_game_id uuid, _card integer)
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
  _new_hand int[];
  _c int;
  _discard_arr int[];
  _discard_by text[];
  _key text;
  _action_log jsonb;
  _won boolean;
  _payout numeric;
  _comm numeric;
  _winner_name text;
  _seven boolean;
  _cfg record;
  _parts int[];
  _next int;
  _next_is_bot boolean;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'draw' THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _seven := COALESCE(_g.seven_cards, false);
  _key := _uid::text;
  _state := public._rami_normalize_state(_g.state);
  _hand := COALESCE(public._rami_jarr(_state->'hands'->_key), ARRAY[]::int[]);
  _new_hand := _hand;

  IF NOT (_card = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte absente de la main'; END IF;
  _new_hand := public._rami_remove_one(_new_hand, _card);

  _discard_arr := COALESCE(public._rami_jarr(_state->'discard'), ARRAY[]::int[]);
  _discard_arr := ARRAY(SELECT x FROM unnest(_discard_arr) x WHERE x IS NOT NULL);
  _discard_arr := array_append(_discard_arr, _card);

  IF _state ? 'discard_by' AND _state->'discard_by' IS NOT NULL THEN
    _discard_by := ARRAY(SELECT elem::text FROM jsonb_array_elements_text(_state->'discard_by') elem WHERE elem IS NOT NULL);
  ELSE
    _discard_by := ARRAY[]::text[];
  END IF;
  _discard_by := array_append(_discard_by, _key);

  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
  _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);

  _action_log := COALESCE(_state->'action_log', '[]'::jsonb) ||
    jsonb_build_object('t', 'discard', 'p', _key, 'card', _card, 'ts', extract(epoch from now())::bigint);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  UPDATE public.rami_participants
     SET hand_count=COALESCE(array_length(_new_hand, 1), 0)
   WHERE game_id=_game_id AND user_id=_uid;

  IF COALESCE(array_length(_new_hand, 1), 0) = 0 THEN
    _won := public._rami_check_win(_state, _key, _seven);
    IF _won THEN
      SELECT COALESCE(pseudo, 'Joueur') INTO _winner_name FROM public.profiles WHERE id=_uid;
      _comm := round(_g.pot * (_g.commission_pct / 2.0) / 100.0, 0);
      _payout := _g.pot - _comm;
      UPDATE public.profiles SET balance_ar=COALESCE(balance_ar, balance)+_payout WHERE id=_uid;
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
REVOKE ALL ON FUNCTION public.rami_discard(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_discard(uuid, integer) TO authenticated;
