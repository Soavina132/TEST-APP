-- ═══════════════════════════════════════════════════════════════
-- Fix Rami: parties qui ne se terminent pas
--
-- Bugs corrigés :
-- 1. rami_bot_tick_all ignore les tours d'humains expirés → jeu bloqué
--    si l'humain quitte la page
-- 2. Trigger _trg_rami_participant_end_check jamais créé → parties
--    avec seulement des bots jamais terminées
-- 3. rami_tick auto-play ne vérifie pas la victoire quand la main
--    devient vide après défausse auto
-- ═══════════════════════════════════════════════════════════════

-- ── 1. Fix rami_bot_tick_all: gérer aussi les tours d'humains expirés ──
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
  _deadline timestamptz;
BEGIN
  FOR _g_id IN
    SELECT r.id FROM public.rami_games r
    WHERE r.status='playing'
  LOOP
    BEGIN
      SELECT p.is_bot, r.updated_at, r.turn_deadline
        INTO _is_bot, _updated, _deadline
      FROM public.rami_games r
      JOIN public.rami_participants p ON p.game_id=r.id AND p.slot=r.current_turn
      WHERE r.id=_g_id;

      IF COALESCE(_is_bot, false) AND _updated IS NOT NULL
         AND now() - _updated >= interval '5 seconds' THEN
        PERFORM public._rami_autoplay_bots(_g_id);
      ELSIF NOT COALESCE(_is_bot, false)
            AND _deadline IS NOT NULL AND _deadline < now() THEN
        -- Tour d'humain expiré — auto-play via rami_tick
        PERFORM public.rami_tick(_g_id);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
END;
$function$;
REVOKE ALL ON FUNCTION public.rami_bot_tick_all() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_bot_tick_all() TO authenticated;

-- ── 2. Créer le trigger manquant sur rami_participants ──
DROP TRIGGER IF EXISTS trg_rami_participant_end_check ON public.rami_participants;
CREATE TRIGGER trg_rami_participant_end_check
  AFTER UPDATE ON public.rami_participants
  FOR EACH ROW
  EXECUTE FUNCTION public._trg_rami_participant_end_check();

-- ── 3. Fix rami_tick: vérifier la victoire après auto-défausse ──
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
  _won boolean;
  _winner_name text;
  _payout numeric;
  _comm numeric;
  _seven boolean;
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
  _seven := COALESCE(_g.seven_cards, false);
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
      IF array_length(_hand, 1) IS NULL THEN
        -- No deck, no hand → skip turn
        _next := _g.current_turn;
        LOOP
          _next := (_next + 1) % _g.max_players;
          EXIT WHEN _next IN (SELECT slot FROM rami_participants WHERE game_id=_game_id AND NOT forfeited);
        END LOOP;
        UPDATE rami_games SET current_turn=_next, turn_phase='draw',
          turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
          updated_at=now() WHERE id=_game_id;
        PERFORM public._rami_autoplay_bots(_game_id);
        RETURN;
      END IF;
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
      -- Vérifier la victoire si la main est vide
      IF COALESCE(array_length(_new_hand, 1), 0) = 0 THEN
        _won := public._rami_check_win(_state, _uid, _seven);
        IF _won THEN
          SELECT COALESCE(pseudo, 'Joueur') INTO _winner_name FROM public.profiles WHERE id=_uid;
          _comm := round(_g.pot * (_g.commission_pct / 2.0) / 100.0, 0);
          _payout := _g.pot - _comm;
          UPDATE public.profiles SET balance_ar=COALESCE(balance_ar, balance)+_payout WHERE id=_uid;
          INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (_uid, 'rami_win', _payout, _game_id, 'Win rami (auto-tick)');
          _state := public._rami_normalize_state(_state);
          UPDATE public.rami_games
            SET status='finished', winner_id=_uid, winner_name=_winner_name, finished_at=now(), state=_state
            WHERE id=_game_id;
          RETURN;
        END IF;
      END IF;
      UPDATE rami_games SET state=_state, current_turn=_next, turn_phase='draw',
        turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
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
        turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
        updated_at=now() WHERE id=_game_id;
    RETURN;
  END IF;

  -- Phase 'play' : auto-défausse
  _skips := COALESCE((_g.turn_skips->>_uid::text)::int, 0) + 1;
  IF _skips >= COALESCE(_cfg.max_turn_skips, 3) THEN
    UPDATE rami_participants SET forfeited = true WHERE game_id=_game_id AND user_id=_uid;
    IF (SELECT count(*) FROM rami_participants WHERE game_id=_game_id AND NOT forfeited) <= 1 THEN
      DECLARE _win uuid; BEGIN
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

  IF array_length(_hand, 1) IS NULL THEN
    -- Pas de carte à défausser → passer le tour
    _next := _g.current_turn;
    LOOP
      _next := (_next + 1) % _g.max_players;
      EXIT WHEN _next IN (SELECT slot FROM rami_participants WHERE game_id=_game_id AND NOT forfeited);
    END LOOP;
    UPDATE rami_games SET current_turn=_next, turn_phase='draw',
      turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
      turn_skips = jsonb_set(COALESCE(_g.turn_skips, '{}'::jsonb), ARRAY[_uid::text], to_jsonb(_skips)),
      updated_at=now() WHERE id=_game_id;
    PERFORM public._rami_autoplay_bots(_game_id);
    RETURN;
  END IF;

  _card := _hand[1 + floor(random()*array_length(_hand,1))::int];
  _new_hand := public._rami_remove_one(_hand, _card);
  _discard_arr := array_append(_discard_arr, _card);
  _discard_by := array_append(_discard_by, _pkey);
  _state := jsonb_set(_state, ARRAY['hands',_pkey], to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
  _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);
  UPDATE rami_participants SET hand_count=COALESCE(array_length(_new_hand,1),0) WHERE game_id=_game_id AND user_id=_uid;

  -- Vérifier la victoire si la main est vide après auto-défausse
  IF COALESCE(array_length(_new_hand, 1), 0) = 0 THEN
    _won := public._rami_check_win(_state, _uid, _seven);
    IF _won THEN
      SELECT COALESCE(pseudo, 'Joueur') INTO _winner_name FROM public.profiles WHERE id=_uid;
      _comm := round(_g.pot * (_g.commission_pct / 2.0) / 100.0, 0);
      _payout := _g.pot - _comm;
      UPDATE public.profiles SET balance_ar=COALESCE(balance_ar, balance)+_payout WHERE id=_uid;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (_uid, 'rami_win', _payout, _game_id, 'Win rami (auto-tick play)');
      _state := public._rami_normalize_state(_state);
      UPDATE public.rami_games
        SET status='finished', winner_id=_uid, winner_name=_winner_name, finished_at=now(), state=_state
        WHERE id=_game_id;
      RETURN;
    END IF;
  END IF;

  _next := _g.current_turn;
  LOOP
    _next := (_next + 1) % _g.max_players;
    EXIT WHEN _next IN (SELECT slot FROM rami_participants WHERE game_id=_game_id AND NOT forfeited);
  END LOOP;

  _state := public._rami_normalize_state(_state);
  UPDATE rami_games SET state=_state, current_turn=_next, turn_phase='draw',
    turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
    turn_skips = jsonb_set(COALESCE(_g.turn_skips, '{}'::jsonb), ARRAY[_uid::text], to_jsonb(_skips)),
    updated_at=now() WHERE id=_game_id;
  PERFORM public._rami_autoplay_bots(_game_id);
END $function$;
REVOKE ALL ON FUNCTION public.rami_tick(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_tick(uuid) TO authenticated;

-- ── 4. Terminer la partie actuellement bloquée ──
UPDATE public.rami_games
  SET status='finished', finished_at=now()
WHERE id = 'c4f64a1f-1f51-46e9-b92a-6947cbdd3511'
  AND status = 'playing';
