
CREATE OR REPLACE FUNCTION public.game_request_pause(_slug TEXT, _game_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid              UUID    := auth.uid();
  v_status           TEXT;
  v_paused           BOOLEAN;
  v_turn_deadline    TIMESTAMPTZ;
  v_turn_timer       INT;
  v_remaining        FLOAT;
  v_is_participant   BOOLEAN := FALSE;
  v_pause_used       BOOLEAN := FALSE;
  v_turn_uid         UUID;
  v_turn_skips       JSONB;
  v_skips            INT;
  v_has_bot          BOOLEAN := FALSE;
  v_turn_color       TEXT;
  v_white_id         UUID;
  v_black_id         UUID;
  v_current_turn     INT;
  v_turn_started_at  TIMESTAMPTZ;
  v_afk_t1           INT;
  v_afk_t2           INT;
  v_afk_t1_max       INT;
  v_afk_t2_max       INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;

  CASE _slug
    WHEN 'chess' THEN
      SELECT status, paused, turn_deadline, turn, white_id, black_id, pause_used, turn_skips
        INTO v_status, v_paused, v_turn_deadline, v_turn_color, v_white_id, v_black_id, v_pause_used, v_turn_skips
        FROM public.chess_games WHERE id = _game_id;
      v_turn_uid := CASE WHEN v_turn_color = 'w' THEN v_white_id ELSE v_black_id END;
      v_is_participant := (v_uid = v_white_id OR v_uid = v_black_id);

    WHEN 'fanorona' THEN
      SELECT status, paused, turn_deadline, current_turn, pause_used, turn_skips
        INTO v_status, v_paused, v_turn_deadline, v_current_turn, v_pause_used, v_turn_skips
        FROM public.fanorona_games WHERE id = _game_id;
      SELECT user_id INTO v_turn_uid FROM public.fanorona_participants
        WHERE game_id = _game_id AND slot = v_current_turn;
      SELECT EXISTS(SELECT 1 FROM public.fanorona_participants
        WHERE game_id = _game_id AND user_id = v_uid) INTO v_is_participant;
      SELECT EXISTS(SELECT 1 FROM public.fanorona_participants
        WHERE game_id = _game_id AND is_bot = TRUE) INTO v_has_bot;

    WHEN 'domino' THEN
      SELECT status, paused, turn_deadline, current_turn, pause_used, turn_skips
        INTO v_status, v_paused, v_turn_deadline, v_current_turn, v_pause_used, v_turn_skips
        FROM public.domino_games WHERE id = _game_id;
      SELECT user_id INTO v_turn_uid FROM public.domino_participants
        WHERE game_id = _game_id AND slot = v_current_turn;
      SELECT EXISTS(SELECT 1 FROM public.domino_participants
        WHERE game_id = _game_id AND user_id = v_uid) INTO v_is_participant;
      SELECT EXISTS(SELECT 1 FROM public.domino_participants
        WHERE game_id = _game_id AND is_bot = TRUE) INTO v_has_bot;

    WHEN 'rami' THEN
      SELECT status, paused, turn_deadline, current_turn, pause_used, turn_skips
        INTO v_status, v_paused, v_turn_deadline, v_current_turn, v_pause_used, v_turn_skips
        FROM public.rami_games WHERE id = _game_id;
      SELECT user_id INTO v_turn_uid FROM public.rami_participants
        WHERE game_id = _game_id AND slot = v_current_turn;
      SELECT EXISTS(SELECT 1 FROM public.rami_participants
        WHERE game_id = _game_id AND user_id = v_uid) INTO v_is_participant;

    WHEN 'poker' THEN
      SELECT status, paused, turn_deadline, current_player, pause_used
        INTO v_status, v_paused, v_turn_deadline, v_turn_uid, v_pause_used
        FROM public.poker_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.poker_players
        WHERE game_id = _game_id AND user_id = v_uid) INTO v_is_participant;

    WHEN 'ludo' THEN
      SELECT status, paused, (state->>'turn_started_at')::timestamptz, current_turn, pause_used
        INTO v_status, v_paused, v_turn_started_at, v_current_turn, v_pause_used
        FROM public.ludo_games WHERE id = _game_id;
      v_turn_deadline := NULL;
      SELECT user_id INTO v_turn_uid FROM public.ludo_participants
        WHERE game_id = _game_id AND slot = v_current_turn;
      SELECT afk_t1, afk_t2 INTO v_afk_t1, v_afk_t2 FROM public.ludo_participants
        WHERE game_id = _game_id AND slot = v_current_turn;
      SELECT afk_t1_max, afk_t2_max INTO v_afk_t1_max, v_afk_t2_max
        FROM public.app_settings WHERE id = 1;
      SELECT EXISTS(SELECT 1 FROM public.ludo_participants
        WHERE game_id = _game_id AND user_id = v_uid AND is_bot = FALSE) INTO v_is_participant;
      SELECT EXISTS(SELECT 1 FROM public.ludo_participants
        WHERE game_id = _game_id AND is_bot = TRUE) INTO v_has_bot;

    ELSE RAISE EXCEPTION 'slug invalide: %', _slug;
  END CASE;

  IF NOT FOUND            THEN RAISE EXCEPTION 'partie introuvable'; END IF;
  IF v_status <> 'playing' THEN RAISE EXCEPTION 'la partie n''est pas en cours'; END IF;
  IF v_paused              THEN RAISE EXCEPTION 'la partie est déjà en pause'; END IF;
  IF NOT v_is_participant  THEN RAISE EXCEPTION 'vous n''êtes pas participant'; END IF;

  -- vs-bot: pause libre, sans échéance, sans limite d'usage.
  IF v_has_bot THEN
    CASE _slug
      WHEN 'fanorona' THEN
        UPDATE public.fanorona_games
          SET paused=TRUE, pause_deadline=NULL,
              paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))),
              turn_deadline=NULL
          WHERE id=_game_id AND status='playing' AND paused=FALSE;
      WHEN 'domino' THEN
        UPDATE public.domino_games
          SET paused=TRUE, pause_deadline=NULL,
              paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))),
              turn_deadline=NULL
          WHERE id=_game_id AND status='playing' AND paused=FALSE;
      WHEN 'ludo' THEN
        UPDATE public.ludo_games
          SET paused=TRUE, pause_deadline=NULL,
              state=jsonb_set(state,'{turn_started_at}',
                to_jsonb((now()+interval '100 years')::text), true)
          WHERE id=_game_id AND status='playing' AND paused=FALSE;
      ELSE NULL;
    END CASE;
    RETURN;
  END IF;

  IF v_pause_used          THEN RAISE EXCEPTION 'la pause a déjà été utilisée pour cette partie'; END IF;

  IF v_turn_uid IS NOT NULL AND v_uid = v_turn_uid THEN
    RAISE EXCEPTION 'seul un joueur qui attend son tour peut demander la pause';
  END IF;

  IF _slug = 'ludo' THEN
    IF v_turn_started_at IS NULL THEN RAISE EXCEPTION 'pas de tour actif'; END IF;
    v_afk_t1_max := COALESCE(v_afk_t1_max, 2);
    v_afk_t2_max := COALESCE(v_afk_t2_max, 2);
    IF COALESCE(v_afk_t1,0) < v_afk_t1_max AND COALESCE(v_afk_t2,0) < v_afk_t2_max THEN
      RAISE EXCEPTION 'pause disponible seulement après % tours manqués consécutifs',
        LEAST(v_afk_t1_max, v_afk_t2_max);
    END IF;
  ELSIF _slug = 'poker' THEN
    IF v_turn_deadline IS NULL THEN RAISE EXCEPTION 'pas de tour actif'; END IF;
    v_turn_timer := COALESCE((SELECT turn_timer_seconds FROM public._game_cfg(_slug)), 30);
    v_remaining  := GREATEST(0, EXTRACT(EPOCH FROM (v_turn_deadline - now())));
    IF v_remaining > (v_turn_timer * 2.0 / 5.0) THEN
      RAISE EXCEPTION 'pause disponible seulement après 3/5 du temps de tour';
    END IF;
  ELSE
    IF v_turn_deadline IS NULL THEN RAISE EXCEPTION 'pas de tour actif'; END IF;
    v_skips := COALESCE((v_turn_skips->>v_turn_uid::text)::int, 0);
    IF v_skips < 2 THEN
      RAISE EXCEPTION 'pause disponible seulement après 2 tours manqués consécutifs';
    END IF;
  END IF;

  CASE _slug
    WHEN 'chess' THEN
      UPDATE public.chess_games
         SET paused=TRUE, pause_deadline=now()+interval '3 minutes',
             paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))),
             turn_deadline=NULL, pause_used=TRUE
       WHERE id=_game_id AND status='playing' AND paused=FALSE;
    WHEN 'fanorona' THEN
      UPDATE public.fanorona_games
         SET paused=TRUE, pause_deadline=now()+interval '3 minutes',
             paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))),
             turn_deadline=NULL, pause_used=TRUE
       WHERE id=_game_id AND status='playing' AND paused=FALSE;
    WHEN 'domino' THEN
      UPDATE public.domino_games
         SET paused=TRUE, pause_deadline=now()+interval '3 minutes',
             paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))),
             turn_deadline=NULL, pause_used=TRUE
       WHERE id=_game_id AND status='playing' AND paused=FALSE;
    WHEN 'rami' THEN
      UPDATE public.rami_games
         SET paused=TRUE, pause_deadline=now()+interval '3 minutes',
             paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))),
             turn_deadline=NULL, pause_used=TRUE
       WHERE id=_game_id AND status='playing' AND paused=FALSE;
    WHEN 'poker' THEN
      UPDATE public.poker_games
         SET paused=TRUE, pause_deadline=now()+interval '3 minutes',
             paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))),
             turn_deadline=NULL, pause_used=TRUE
       WHERE id=_game_id AND status='playing' AND paused=FALSE;
    WHEN 'ludo' THEN
      UPDATE public.ludo_games
         SET paused=TRUE, pause_deadline=now()+interval '3 minutes',
             pause_used=TRUE,
             state=jsonb_set(state,'{turn_started_at}',
               to_jsonb((now()+interval '1 hour')::text), true)
       WHERE id=_game_id AND status='playing' AND paused=FALSE;
  END CASE;
END $$;

GRANT EXECUTE ON FUNCTION public.game_request_pause(TEXT, UUID) TO authenticated;
