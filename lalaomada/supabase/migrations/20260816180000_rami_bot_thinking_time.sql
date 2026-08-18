-- ═══════════════════════════════════════════════════════════════
-- Fix 1: Bot a un temps de réflexion de 5 secondes minimum
-- Fix 2: rami_discard déclenche le bot après pg_sleep(5)
-- Fix 3: rami_bot_tick_all utilise 5 secondes (cohérent)
-- ═══════════════════════════════════════════════════════════════

-- ── 1. rami_discard avec délai de 5s avant le bot ──

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

  -- Mettre à jour hand_count du joueur
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

  -- Commit la défausse + changement de tour AVANT le sleep
  -- pour que le front-end voie l'état intermédiaire via realtime
  UPDATE public.rami_games
     SET state=_state, current_turn=_next, turn_phase='draw',
         turn_deadline=now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
         updated_at=now()
   WHERE id=_game_id;

  -- Si le prochain joueur est un bot, attendre 5 secondes puis déclencher
  BEGIN
    PERFORM pg_sleep(5);
    PERFORM public._rami_autoplay_bots(_game_id);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END;
$function$;
REVOKE ALL ON FUNCTION public.rami_discard(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_discard(uuid, integer) TO authenticated;


-- ── 2. rami_bot_tick_all: 5 secondes au lieu de 2 ──

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
$function$;
REVOKE ALL ON FUNCTION public.rami_bot_tick_all() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_bot_tick_all() TO authenticated;
