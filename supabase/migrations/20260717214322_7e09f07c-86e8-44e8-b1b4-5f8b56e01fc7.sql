
-- 1. game_request_pause: skip the 3/5 turn-time restriction for vs-bot games (any bot participant)
CREATE OR REPLACE FUNCTION public.game_request_pause(_slug text, _game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid(); v_status TEXT; v_paused BOOLEAN;
  v_turn_deadline TIMESTAMPTZ; v_turn_timer INT; v_remaining FLOAT;
  v_is_participant BOOLEAN := FALSE;
  v_turn_started_at TIMESTAMPTZ; v_elapsed FLOAT; v_ludo_turn_secs INT;
  v_has_bot BOOLEAN := FALSE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  CASE _slug
    WHEN 'chess' THEN
      SELECT status, paused, turn_deadline INTO v_status, v_paused, v_turn_deadline FROM public.chess_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.chess_games WHERE id = _game_id AND (white_id = v_uid OR black_id = v_uid)) INTO v_is_participant;
    WHEN 'fanorona' THEN
      SELECT status, paused, turn_deadline INTO v_status, v_paused, v_turn_deadline FROM public.fanorona_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.fanorona_participants WHERE game_id = _game_id AND user_id = v_uid) INTO v_is_participant;
      SELECT EXISTS(SELECT 1 FROM public.fanorona_participants WHERE game_id = _game_id AND is_bot = TRUE) INTO v_has_bot;
    WHEN 'domino' THEN
      SELECT status, paused, turn_deadline INTO v_status, v_paused, v_turn_deadline FROM public.domino_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid) INTO v_is_participant;
      SELECT EXISTS(SELECT 1 FROM public.domino_participants WHERE game_id = _game_id AND is_bot = TRUE) INTO v_has_bot;
    WHEN 'rami' THEN
      SELECT status, paused, turn_deadline INTO v_status, v_paused, v_turn_deadline FROM public.rami_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.rami_participants WHERE game_id = _game_id AND user_id = v_uid) INTO v_is_participant;
    WHEN 'poker' THEN
      SELECT status, paused, turn_deadline INTO v_status, v_paused, v_turn_deadline FROM public.poker_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.poker_players WHERE game_id = _game_id AND user_id = v_uid) INTO v_is_participant;
    WHEN 'ludo' THEN
      SELECT status, paused, (state->>'turn_started_at')::timestamptz INTO v_status, v_paused, v_turn_started_at FROM public.ludo_games WHERE id = _game_id;
      v_turn_deadline := NULL;
      SELECT EXISTS(SELECT 1 FROM public.ludo_participants WHERE game_id = _game_id AND user_id = v_uid AND is_bot = FALSE) INTO v_is_participant;
      SELECT EXISTS(SELECT 1 FROM public.ludo_participants WHERE game_id = _game_id AND is_bot = TRUE) INTO v_has_bot;
    ELSE RAISE EXCEPTION 'slug invalide: %', _slug;
  END CASE;
  IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
  IF NOT v_is_participant THEN RAISE EXCEPTION 'non participant'; END IF;
  IF v_status <> 'playing' THEN RAISE EXCEPTION 'partie non en cours'; END IF;
  IF v_paused THEN RAISE EXCEPTION 'déjà en pause'; END IF;

  -- vs-bot: pause disponible à tout moment, aucune restriction de temps
  IF NOT v_has_bot THEN
    IF _slug = 'ludo' THEN
      IF v_turn_started_at IS NULL THEN RAISE EXCEPTION 'pas de tour actif'; END IF;
      v_elapsed := GREATEST(0, EXTRACT(EPOCH FROM (now() - v_turn_started_at)));
      SELECT COALESCE((SELECT turn_seconds FROM public.app_settings WHERE id = 1), 30) INTO v_ludo_turn_secs;
      IF v_elapsed < (v_ludo_turn_secs * 3.0 / 5.0) THEN RAISE EXCEPTION 'pause disponible seulement après 3/5 du temps de tour'; END IF;
    ELSE
      IF v_turn_deadline IS NULL THEN RAISE EXCEPTION 'pas de tour actif'; END IF;
      v_turn_timer := COALESCE((SELECT turn_timer_seconds FROM public._game_cfg(_slug)), 30);
      v_remaining := GREATEST(0, EXTRACT(EPOCH FROM (v_turn_deadline - now())));
      IF v_remaining > (v_turn_timer * 2.0 / 5.0) THEN RAISE EXCEPTION 'pause disponible seulement après 3/5 du temps de tour'; END IF;
    END IF;
  END IF;

  CASE _slug
    WHEN 'chess' THEN UPDATE public.chess_games SET paused=TRUE, pause_deadline=now()+interval '5 minutes', paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))), turn_deadline=NULL WHERE id=_game_id AND status='playing' AND paused=FALSE;
    WHEN 'fanorona' THEN UPDATE public.fanorona_games SET paused=TRUE, pause_deadline=now()+interval '5 minutes', paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))), turn_deadline=NULL WHERE id=_game_id AND status='playing' AND paused=FALSE;
    WHEN 'domino' THEN UPDATE public.domino_games SET paused=TRUE, pause_deadline=now()+interval '5 minutes', paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))), turn_deadline=NULL WHERE id=_game_id AND status='playing' AND paused=FALSE;
    WHEN 'rami' THEN UPDATE public.rami_games SET paused=TRUE, pause_deadline=now()+interval '5 minutes', paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))), turn_deadline=NULL WHERE id=_game_id AND status='playing' AND paused=FALSE;
    WHEN 'poker' THEN UPDATE public.poker_games SET paused=TRUE, pause_deadline=now()+interval '5 minutes', paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))), turn_deadline=NULL WHERE id=_game_id AND status='playing' AND paused=FALSE;
    WHEN 'ludo' THEN UPDATE public.ludo_games SET paused=TRUE, pause_deadline=now()+interval '5 minutes', state=jsonb_set(state,'{turn_started_at}',to_jsonb((now()+interval '1 hour')::text), true) WHERE id=_game_id AND status='playing' AND paused=FALSE;
  END CASE;
END $function$;

-- 2. Helper: delete a ludo game (and its dependents) — used when no human remains
CREATE OR REPLACE FUNCTION public._ludo_purge(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  DELETE FROM public.chat_rooms WHERE game_id = _game_id;
  DELETE FROM public.game_spectators WHERE game_id = _game_id;
  DELETE FROM public.game_invitations WHERE game_id = _game_id;
  DELETE FROM public.ludo_participants WHERE game_id = _game_id;
  DELETE FROM public.ludo_games WHERE id = _game_id;
END $$;

CREATE OR REPLACE FUNCTION public._domino_purge(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  DELETE FROM public.chat_rooms WHERE game_id = _game_id;
  DELETE FROM public.game_spectators WHERE game_id = _game_id;
  DELETE FROM public.game_invitations WHERE game_id = _game_id;
  DELETE FROM public.domino_participants WHERE game_id = _game_id;
  DELETE FROM public.domino_games WHERE id = _game_id;
END $$;

-- 3. ludo_quit: when playing and no human remains → delete game entirely (vs-bot cleanup)
CREATE OR REPLACE FUNCTION public.ludo_quit(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); g public.ludo_games%ROWTYPE; st jsonb;
  v_slot INT; v_winner UUID; v_remaining INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status NOT IN ('playing','open') THEN RAISE EXCEPTION 'Partie terminée'; END IF;
  SELECT slot INTO v_slot FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid AND is_bot=false;
  IF v_slot IS NULL THEN RAISE EXCEPTION 'Non participant'; END IF;

  IF g.status = 'open' THEN
    UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id=v_uid;
    UPDATE public.ludo_games SET pot = pot - g.stake WHERE id=_game_id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_uid,'refund',g.stake,_game_id,'Annulation avant départ');
    DELETE FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid AND is_bot=false;
    SELECT count(*) INTO v_remaining FROM public.ludo_participants WHERE game_id=_game_id AND is_bot=false;
    IF v_remaining = 0 THEN PERFORM public._ludo_purge(_game_id); END IF;
    RETURN;
  END IF;

  IF g.is_solo THEN
    UPDATE public.ludo_participants SET forfeited=TRUE WHERE game_id=_game_id AND user_id=v_uid AND is_bot=false;
    UPDATE public.ludo_games SET status='finished', finished_at=now() WHERE id=_game_id;
    PERFORM public._ludo_purge(_game_id);
    RETURN;
  END IF;

  UPDATE public.ludo_participants SET forfeited=TRUE WHERE game_id=_game_id AND user_id=v_uid AND is_bot=false;
  st := g.state;
  IF (st->>'turn_slot')::INT = v_slot THEN
    st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('forfeit'));
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  END IF;
  v_winner := public._ludo_check_last_standing(_game_id);
  IF v_winner IS NOT NULL THEN
    PERFORM public.finish_game(_game_id, v_winner);
  ELSIF public._ludo_active_humans(_game_id) = 0 THEN
    UPDATE public.ludo_games SET status='finished', finished_at=now() WHERE id=_game_id;
    PERFORM public._ludo_purge(_game_id);
  END IF;
END $function$;

-- 4. domino_forfeit: on human departure with no human left → purge game entirely
CREATE OR REPLACE FUNCTION public.domino_forfeit(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  g record;
  my_slot int;
  remaining int;
  last_slot int;
  humans_left int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status NOT IN ('open','playing') THEN RETURN; END IF;
  SELECT slot INTO my_slot FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid;
  IF my_slot IS NULL THEN RETURN; END IF;
  UPDATE public.domino_participants SET forfeited = true WHERE game_id = _game_id AND user_id = v_uid;

  IF g.status = 'open' THEN
    UPDATE public.profiles p SET balance_ar = balance_ar + g.stake
      FROM public.domino_participants pp
     WHERE pp.game_id = _game_id AND pp.user_id = p.id AND COALESCE(pp.is_bot,false) = false;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      SELECT user_id, 'domino_refund', g.stake, _game_id, 'Game cancelled'
        FROM public.domino_participants
       WHERE game_id = _game_id AND COALESCE(is_bot,false) = false;
    UPDATE public.domino_games SET status = 'cancelled', finished_at = now() WHERE id = _game_id;
    humans_left := public._domino_active_humans(_game_id);
    IF humans_left = 0 THEN PERFORM public._domino_purge(_game_id); END IF;
    RETURN;
  END IF;

  humans_left := public._domino_active_humans(_game_id);
  IF humans_left = 0 THEN
    UPDATE public.domino_games SET status = 'cancelled', finished_at = now() WHERE id = _game_id;
    PERFORM public._domino_purge(_game_id);
    RETURN;
  END IF;

  SELECT count(*) INTO remaining FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  IF remaining <= 1 THEN
    SELECT slot INTO last_slot FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false LIMIT 1;
    IF last_slot IS NOT NULL THEN
      PERFORM public._domino_finalize(_game_id, last_slot);
    ELSE
      UPDATE public.domino_games SET status='cancelled', finished_at=now() WHERE id = _game_id;
      PERFORM public._domino_purge(_game_id);
    END IF;
  END IF;
END $function$;
