-- ================================================================
-- GAME PAUSE FIXES
-- 1. game_request_pause: add ludo server-side 3/5 elapsed check
--    + race-safe UPDATE WHERE clauses (status+paused predicate)
-- 2. game_resume:  block unauthenticated external callers;
--    internal auto-resume now goes through _game_resume_internal
--    + race-safe UPDATE WHERE clauses
-- 3. _auto_resume_paused_games: calls internal helper (no uid)
-- ================================================================

-- ── Internal helper (no auth required — only callable server-side) ──────────
CREATE OR REPLACE FUNCTION public._game_resume_internal(_slug TEXT, _game_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_status      TEXT;
  v_paused      BOOLEAN;
  v_remaining_s INTEGER;
BEGIN
  CASE _slug
    WHEN 'chess' THEN
      SELECT status, paused, paused_turn_remaining_s
        INTO v_status, v_paused, v_remaining_s
        FROM public.chess_games WHERE id = _game_id;
    WHEN 'fanorona' THEN
      SELECT status, paused, paused_turn_remaining_s
        INTO v_status, v_paused, v_remaining_s
        FROM public.fanorona_games WHERE id = _game_id;
    WHEN 'domino' THEN
      SELECT status, paused, paused_turn_remaining_s
        INTO v_status, v_paused, v_remaining_s
        FROM public.domino_games WHERE id = _game_id;
    WHEN 'rami' THEN
      SELECT status, paused, paused_turn_remaining_s
        INTO v_status, v_paused, v_remaining_s
        FROM public.rami_games WHERE id = _game_id;
    WHEN 'poker' THEN
      SELECT status, paused, paused_turn_remaining_s
        INTO v_status, v_paused, v_remaining_s
        FROM public.poker_games WHERE id = _game_id;
    WHEN 'ludo' THEN
      SELECT status, paused INTO v_status, v_paused
        FROM public.ludo_games WHERE id = _game_id;
    ELSE RAISE EXCEPTION 'slug invalide: %', _slug;
  END CASE;

  IF NOT FOUND THEN RETURN; END IF;
  IF v_status <> 'playing' OR NOT v_paused THEN RETURN; END IF;

  CASE _slug
    WHEN 'chess' THEN
      UPDATE public.chess_games
         SET paused=FALSE, pause_deadline=NULL, paused_turn_remaining_s=NULL,
             turn_deadline = now() + (COALESCE(v_remaining_s,30) || ' seconds')::interval
       WHERE id = _game_id AND paused = TRUE AND status = 'playing';

    WHEN 'fanorona' THEN
      UPDATE public.fanorona_games
         SET paused=FALSE, pause_deadline=NULL, paused_turn_remaining_s=NULL,
             turn_deadline = now() + (COALESCE(v_remaining_s,60) || ' seconds')::interval
       WHERE id = _game_id AND paused = TRUE AND status = 'playing';

    WHEN 'domino' THEN
      UPDATE public.domino_games
         SET paused=FALSE, pause_deadline=NULL, paused_turn_remaining_s=NULL,
             turn_deadline = now() + (COALESCE(v_remaining_s,60) || ' seconds')::interval
       WHERE id = _game_id AND paused = TRUE AND status = 'playing';

    WHEN 'rami' THEN
      UPDATE public.rami_games
         SET paused=FALSE, pause_deadline=NULL, paused_turn_remaining_s=NULL,
             turn_deadline = now() + (COALESCE(v_remaining_s,45) || ' seconds')::interval
       WHERE id = _game_id AND paused = TRUE AND status = 'playing';

    WHEN 'poker' THEN
      UPDATE public.poker_games
         SET paused=FALSE, pause_deadline=NULL, paused_turn_remaining_s=NULL,
             turn_deadline = now() + (COALESCE(v_remaining_s,30) || ' seconds')::interval
       WHERE id = _game_id AND paused = TRUE AND status = 'playing';

    WHEN 'ludo' THEN
      UPDATE public.ludo_games
         SET paused=FALSE, pause_deadline=NULL,
             state = jsonb_set(state, '{turn_started_at}', to_jsonb(now()::text), true)
       WHERE id = _game_id AND paused = TRUE AND status = 'playing';
  END CASE;
END $$;
-- NOT granted to authenticated/anon — internal use only

-- ── game_request_pause: full rewrite with fixes ──────────────────────────────
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
  -- ludo-specific
  v_turn_started_at  TIMESTAMPTZ;
  v_elapsed          FLOAT;
  v_ludo_turn_secs   INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;

  CASE _slug
    WHEN 'chess' THEN
      SELECT status, paused, turn_deadline
        INTO v_status, v_paused, v_turn_deadline
        FROM public.chess_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.chess_games
        WHERE id = _game_id AND (white_id = v_uid OR black_id = v_uid))
        INTO v_is_participant;

    WHEN 'fanorona' THEN
      SELECT status, paused, turn_deadline
        INTO v_status, v_paused, v_turn_deadline
        FROM public.fanorona_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.fanorona_participants
        WHERE game_id = _game_id AND user_id = v_uid)
        INTO v_is_participant;

    WHEN 'domino' THEN
      SELECT status, paused, turn_deadline
        INTO v_status, v_paused, v_turn_deadline
        FROM public.domino_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.domino_participants
        WHERE game_id = _game_id AND user_id = v_uid)
        INTO v_is_participant;

    WHEN 'rami' THEN
      SELECT status, paused, turn_deadline
        INTO v_status, v_paused, v_turn_deadline
        FROM public.rami_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.rami_participants
        WHERE game_id = _game_id AND user_id = v_uid)
        INTO v_is_participant;

    WHEN 'poker' THEN
      SELECT status, paused, turn_deadline
        INTO v_status, v_paused, v_turn_deadline
        FROM public.poker_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.poker_players
        WHERE game_id = _game_id AND user_id = v_uid)
        INTO v_is_participant;

    WHEN 'ludo' THEN
      SELECT status, paused, (state->>'turn_started_at')::timestamptz
        INTO v_status, v_paused, v_turn_started_at
        FROM public.ludo_games WHERE id = _game_id;
      v_turn_deadline := NULL;
      SELECT EXISTS(SELECT 1 FROM public.ludo_participants
        WHERE game_id = _game_id AND user_id = v_uid AND is_bot = FALSE)
        INTO v_is_participant;

    ELSE RAISE EXCEPTION 'slug invalide: %', _slug;
  END CASE;

  IF NOT FOUND        THEN RAISE EXCEPTION 'partie introuvable'; END IF;
  IF v_status <> 'playing' THEN RAISE EXCEPTION 'la partie n''est pas en cours'; END IF;
  IF v_paused             THEN RAISE EXCEPTION 'la partie est déjà en pause'; END IF;
  IF NOT v_is_participant THEN RAISE EXCEPTION 'vous n''êtes pas participant'; END IF;

  -- Enforce 3/5-elapsed rule server-side for ALL slugs
  IF _slug = 'ludo' THEN
    -- Ludo uses JSONB state.turn_started_at as its timer anchor
    IF v_turn_started_at IS NULL THEN RAISE EXCEPTION 'pas de tour actif'; END IF;
    v_elapsed := GREATEST(0, EXTRACT(EPOCH FROM (now() - v_turn_started_at)));
    SELECT COALESCE((SELECT turn_seconds FROM public.app_settings WHERE id = 1), 30)
      INTO v_ludo_turn_secs;
    IF v_elapsed < (v_ludo_turn_secs * 3.0 / 5.0) THEN
      RAISE EXCEPTION 'pause disponible seulement après 3/5 du temps de tour';
    END IF;
  ELSE
    IF v_turn_deadline IS NULL THEN RAISE EXCEPTION 'pas de tour actif'; END IF;
    v_turn_timer := COALESCE(
      (SELECT turn_timer_seconds FROM public._game_cfg(_slug)), 30);
    v_remaining  := GREATEST(0, EXTRACT(EPOCH FROM (v_turn_deadline - now())));
    IF v_remaining > (v_turn_timer * 2.0 / 5.0) THEN
      RAISE EXCEPTION 'pause disponible seulement après 3/5 du temps de tour';
    END IF;
  END IF;

  -- Apply pause — include status+paused predicates to guard against race conditions
  CASE _slug
    WHEN 'chess' THEN
      UPDATE public.chess_games
         SET paused=TRUE, pause_deadline=now()+interval '5 minutes',
             paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))),
             turn_deadline=NULL
       WHERE id=_game_id AND status='playing' AND paused=FALSE;

    WHEN 'fanorona' THEN
      UPDATE public.fanorona_games
         SET paused=TRUE, pause_deadline=now()+interval '5 minutes',
             paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))),
             turn_deadline=NULL
       WHERE id=_game_id AND status='playing' AND paused=FALSE;

    WHEN 'domino' THEN
      UPDATE public.domino_games
         SET paused=TRUE, pause_deadline=now()+interval '5 minutes',
             paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))),
             turn_deadline=NULL
       WHERE id=_game_id AND status='playing' AND paused=FALSE;

    WHEN 'rami' THEN
      UPDATE public.rami_games
         SET paused=TRUE, pause_deadline=now()+interval '5 minutes',
             paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))),
             turn_deadline=NULL
       WHERE id=_game_id AND status='playing' AND paused=FALSE;

    WHEN 'poker' THEN
      UPDATE public.poker_games
         SET paused=TRUE, pause_deadline=now()+interval '5 minutes',
             paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))),
             turn_deadline=NULL
       WHERE id=_game_id AND status='playing' AND paused=FALSE;

    WHEN 'ludo' THEN
      UPDATE public.ludo_games
         SET paused=TRUE, pause_deadline=now()+interval '5 minutes',
             state=jsonb_set(state,'{turn_started_at}',
               to_jsonb((now()+interval '1 hour')::text), true)
       WHERE id=_game_id AND status='playing' AND paused=FALSE;
  END CASE;
END $$;

GRANT EXECUTE ON FUNCTION public.game_request_pause(TEXT, UUID) TO authenticated;

-- ── game_resume: requires auth for external callers ──────────────────────────
CREATE OR REPLACE FUNCTION public.game_resume(_slug TEXT, _game_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid            UUID := auth.uid();
  v_is_participant BOOLEAN := FALSE;
  v_status         TEXT;
  v_paused         BOOLEAN;
BEGIN
  -- Authenticated users only (internal auto-resume uses _game_resume_internal)
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;

  -- Check participation + load game state in one pass
  CASE _slug
    WHEN 'chess' THEN
      SELECT status, paused INTO v_status, v_paused
        FROM public.chess_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.chess_games
        WHERE id=_game_id AND (white_id=v_uid OR black_id=v_uid))
        INTO v_is_participant;

    WHEN 'fanorona' THEN
      SELECT status, paused INTO v_status, v_paused
        FROM public.fanorona_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.fanorona_participants
        WHERE game_id=_game_id AND user_id=v_uid) INTO v_is_participant;

    WHEN 'domino' THEN
      SELECT status, paused INTO v_status, v_paused
        FROM public.domino_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.domino_participants
        WHERE game_id=_game_id AND user_id=v_uid) INTO v_is_participant;

    WHEN 'rami' THEN
      SELECT status, paused INTO v_status, v_paused
        FROM public.rami_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.rami_participants
        WHERE game_id=_game_id AND user_id=v_uid) INTO v_is_participant;

    WHEN 'poker' THEN
      SELECT status, paused INTO v_status, v_paused
        FROM public.poker_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.poker_players
        WHERE game_id=_game_id AND user_id=v_uid) INTO v_is_participant;

    WHEN 'ludo' THEN
      SELECT status, paused INTO v_status, v_paused
        FROM public.ludo_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.ludo_participants
        WHERE game_id=_game_id AND user_id=v_uid AND is_bot=FALSE)
        INTO v_is_participant;

    ELSE RAISE EXCEPTION 'slug invalide: %', _slug;
  END CASE;

  IF NOT FOUND          THEN RAISE EXCEPTION 'partie introuvable'; END IF;
  IF v_status <> 'playing' THEN RETURN; END IF;
  IF NOT v_paused        THEN RETURN; END IF;
  IF NOT v_is_participant THEN RAISE EXCEPTION 'vous n''êtes pas participant'; END IF;

  -- Delegate to the internal function (contains the actual UPDATE logic)
  PERFORM public._game_resume_internal(_slug, _game_id);
END $$;

GRANT EXECUTE ON FUNCTION public.game_resume(TEXT, UUID) TO authenticated;

-- ── _auto_resume_paused_games: uses internal helper, no auth required ────────
CREATE OR REPLACE FUNCTION public._auto_resume_paused_games()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record;
BEGIN
  FOR r IN SELECT id FROM public.chess_games
           WHERE paused=TRUE AND pause_deadline IS NOT NULL AND pause_deadline<now() AND status='playing'
  LOOP PERFORM public._game_resume_internal('chess', r.id); END LOOP;

  FOR r IN SELECT id FROM public.fanorona_games
           WHERE paused=TRUE AND pause_deadline IS NOT NULL AND pause_deadline<now() AND status='playing'
  LOOP PERFORM public._game_resume_internal('fanorona', r.id); END LOOP;

  FOR r IN SELECT id FROM public.domino_games
           WHERE paused=TRUE AND pause_deadline IS NOT NULL AND pause_deadline<now() AND status='playing'
  LOOP PERFORM public._game_resume_internal('domino', r.id); END LOOP;

  FOR r IN SELECT id FROM public.rami_games
           WHERE paused=TRUE AND pause_deadline IS NOT NULL AND pause_deadline<now() AND status='playing'
  LOOP PERFORM public._game_resume_internal('rami', r.id); END LOOP;

  FOR r IN SELECT id FROM public.poker_games
           WHERE paused=TRUE AND pause_deadline IS NOT NULL AND pause_deadline<now() AND status='playing'
  LOOP PERFORM public._game_resume_internal('poker', r.id); END LOOP;

  FOR r IN SELECT id FROM public.ludo_games
           WHERE paused=TRUE AND pause_deadline IS NOT NULL AND pause_deadline<now() AND status='playing'
  LOOP PERFORM public._game_resume_internal('ludo', r.id); END LOOP;
END $$;
