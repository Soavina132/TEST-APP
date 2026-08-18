-- ═══════════════════════════════════════════════════════════════
-- Fix: rami_discard doit déclencher _rami_autoplay_bots après défausse
--
-- Problème: La migration 20260816050000 a réécrit rami_discard sans
-- l'appel à _rami_autoplay_bots. Après que l'humain défausse, le tour
-- passe au bot mais le bot ne joue jamais → partie bloquée.
--
-- Solution: Réintégrer PERFORM _rami_autoplay_bots à la fin de rami_discard
-- ═══════════════════════════════════════════════════════════════

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
  _seven boolean;
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _key := _uid::text;
  _seven := COALESCE(_g.seven_cards, false);
  _state := _g.state;
  _hand := ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_key))::int[];
  IF NOT (_card = ANY(_hand)) THEN RAISE EXCEPTION 'carte absente'; END IF;
  _new_hand := public._rami_remove_one(_hand, _card);

  _discard := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'discard'))::int[], ARRAY[]::int[]);
  _discard := array_append(_discard, _card);

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

  IF COALESCE(array_length(_new_hand, 1), 0) = 0 THEN
    _won := public._rami_check_win(_state, _uid, _seven);
    IF _won THEN
      SELECT COALESCE(pseudo, 'Joueur') INTO _winner_name FROM public.profiles WHERE id=_uid;
      _comm := round(_g.pot * (_g.commission_pct / 2.0) / 100.0, 0);
      _payout := _g.pot - _comm;
      UPDATE public.profiles SET balance_ar=balance_ar+_payout WHERE id=_uid;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (_uid, 'rami_win', _payout, _game_id, 'Win rami');
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

  UPDATE public.rami_games
     SET state=_state, current_turn=_next, turn_phase='draw',
         turn_deadline=now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
         updated_at=now()
   WHERE id=_game_id;

  -- Déclencher le bot pour qu'il joue son tour automatiquement
  BEGIN
    PERFORM public._rami_autoplay_bots(_game_id);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END;
$function$;
REVOKE ALL ON FUNCTION public.rami_discard(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_discard(uuid, integer) TO authenticated;
