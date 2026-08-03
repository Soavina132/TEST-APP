-- ================================================================
-- GAME PAUSE SYSTEM v2 — fixes per product spec:
-- 1. Pause button must be offered to the WAITING players (not the
--    player whose turn it is) once 2/5 of the turn time has elapsed
--    (was previously gated the wrong way round, at 3/5 elapsed).
-- 2. Pause duration becomes admin-configurable (app_settings.game_pause_minutes,
--    default 3 minutes) instead of a hardcoded 5 minutes.
-- 3. Once a pause has been used for a given turn/stoppage, it cannot be
--    requested again until a genuinely new turn starts (pause_used_deadline
--    marker, propagated across resume so an immediate re-pause is blocked).
-- 4. Resuming manually is now restricted to the absent player who is
--    coming back (paused_turn_holder_id) — the waiting players can no
--    longer resume the game manually; the game only resumes when the
--    absent player returns or when the pause timer runs out.
-- ================================================================

-- 1) app_settings: admin-configurable pause duration
ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS game_pause_minutes INTEGER NOT NULL DEFAULT 3;

-- 2) Schema: track "already used for this turn" + "who is the absent player"
ALTER TABLE public.chess_games
  ADD COLUMN IF NOT EXISTS pause_used_deadline TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS paused_turn_holder_id UUID;

ALTER TABLE public.domino_games
  ADD COLUMN IF NOT EXISTS pause_used_deadline TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS paused_turn_holder_id UUID;

ALTER TABLE public.fanorona_games
  ADD COLUMN IF NOT EXISTS pause_used_deadline TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS paused_turn_holder_id UUID;

ALTER TABLE public.rami_games
  ADD COLUMN IF NOT EXISTS pause_used_deadline TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS paused_turn_holder_id UUID;

ALTER TABLE public.poker_games
  ADD COLUMN IF NOT EXISTS pause_used_deadline TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS paused_turn_holder_id UUID;

ALTER TABLE public.ludo_games
  ADD COLUMN IF NOT EXISTS pause_used_deadline TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS paused_turn_holder_id UUID;

-- 3) game_request_pause — full rewrite
CREATE OR REPLACE FUNCTION public.game_request_pause(_slug TEXT, _game_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid                UUID    := auth.uid();
  v_status             TEXT;
  v_paused             BOOLEAN;
  v_turn_deadline      TIMESTAMPTZ;
  v_turn_timer         INT;
  v_remaining          FLOAT;
  v_is_participant     BOOLEAN := FALSE;
  v_pause_used_deadline TIMESTAMPTZ;
  v_turn_holder_id     UUID;
  v_pause_minutes      INT;
  -- per-slug turn-holder resolution
  v_turn_color         TEXT;
  v_white_id           UUID;
  v_black_id           UUID;
  v_current_turn       INT;
  -- ludo-specific
  v_turn_started_at    TIMESTAMPTZ;
  v_elapsed            FLOAT;
  v_ludo_turn_secs     INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;

  SELECT COALESCE((SELECT game_pause_minutes FROM public.app_settings WHERE id = 1), 3)
    INTO v_pause_minutes;

  CASE _slug
    WHEN 'chess' THEN
      SELECT status, paused, turn_deadline, pause_used_deadline, turn, white_id, black_id
        INTO v_status, v_paused, v_turn_deadline, v_pause_used_deadline, v_turn_color, v_white_id, v_black_id
        FROM public.chess_games WHERE id = _game_id;
      v_turn_holder_id := CASE WHEN v_turn_color = 'white' THEN v_white_id ELSE v_black_id END;
      SELECT EXISTS(SELECT 1 FROM public.chess_games
        WHERE id = _game_id AND (white_id = v_uid OR black_id = v_uid))
        INTO v_is_participant;

    WHEN 'fanorona' THEN
      SELECT status, paused, turn_deadline, pause_used_deadline, current_turn
        INTO v_status, v_paused, v_turn_deadline, v_pause_used_deadline, v_current_turn
        FROM public.fanorona_games WHERE id = _game_id;
      SELECT user_id INTO v_turn_holder_id FROM public.fanorona_participants
        WHERE game_id = _game_id AND slot = v_current_turn;
      SELECT EXISTS(SELECT 1 FROM public.fanorona_participants
        WHERE game_id = _game_id AND user_id = v_uid)
        INTO v_is_participant;

    WHEN 'domino' THEN
      SELECT status, paused, turn_deadline, pause_used_deadline, current_turn
        INTO v_status, v_paused, v_turn_deadline, v_pause_used_deadline, v_current_turn
        FROM public.domino_games WHERE id = _game_id;
      SELECT user_id INTO v_turn_holder_id FROM public.domino_participants
        WHERE game_id = _game_id AND slot = v_current_turn;
      SELECT EXISTS(SELECT 1 FROM public.domino_participants
        WHERE game_id = _game_id AND user_id = v_uid)
        INTO v_is_participant;

    WHEN 'rami' THEN
      SELECT status, paused, turn_deadline, pause_used_deadline, current_turn
        INTO v_status, v_paused, v_turn_deadline, v_pause_used_deadline, v_current_turn
        FROM public.rami_games WHERE id = _game_id;
      SELECT user_id INTO v_turn_holder_id FROM public.rami_participants
        WHERE game_id = _game_id AND slot = v_current_turn;
      SELECT EXISTS(SELECT 1 FROM public.rami_participants
        WHERE game_id = _game_id AND user_id = v_uid)
        INTO v_is_participant;

    WHEN 'poker' THEN
      SELECT status, paused, turn_deadline, pause_used_deadline, current_player
        INTO v_status, v_paused, v_turn_deadline, v_pause_used_deadline, v_turn_holder_id
        FROM public.poker_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.poker_players
        WHERE game_id = _game_id AND user_id = v_uid)
        INTO v_is_participant;

    WHEN 'ludo' THEN
      SELECT status, paused, pause_used_deadline, (state->>'turn_started_at')::timestamptz, current_turn
        INTO v_status, v_paused, v_pause_used_deadline, v_turn_started_at, v_current_turn
        FROM public.ludo_games WHERE id = _game_id;
      v_turn_deadline := NULL;
      SELECT user_id INTO v_turn_holder_id FROM public.ludo_participants
        WHERE game_id = _game_id AND slot = v_current_turn;
      SELECT EXISTS(SELECT 1 FROM public.ludo_participants
        WHERE game_id = _game_id AND user_id = v_uid AND is_bot = FALSE)
        INTO v_is_participant;

    ELSE RAISE EXCEPTION 'slug invalide: %', _slug;
  END CASE;

  IF NOT FOUND            THEN RAISE EXCEPTION 'partie introuvable'; END IF;
  IF v_status <> 'playing' THEN RAISE EXCEPTION 'la partie n''est pas en cours'; END IF;
  IF v_paused              THEN RAISE EXCEPTION 'la partie est déjà en pause'; END IF;
  IF NOT v_is_participant  THEN RAISE EXCEPTION 'vous n''êtes pas participant'; END IF;

  -- Only a WAITING player (not the one whose turn it currently is) can request a pause
  IF v_turn_holder_id IS NOT NULL AND v_uid = v_turn_holder_id THEN
    RAISE EXCEPTION 'seul un joueur en attente du tour adverse peut demander une pause';
  END IF;

  -- Enforce 2/5-elapsed rule server-side (button/RPC available once 2/5 of the
  -- turn time has passed, i.e. remaining <= 3/5 of the total turn time)
  IF _slug = 'ludo' THEN
    IF v_turn_started_at IS NULL THEN RAISE EXCEPTION 'pas de tour actif'; END IF;
    v_elapsed := GREATEST(0, EXTRACT(EPOCH FROM (now() - v_turn_started_at)));
    SELECT COALESCE((SELECT turn_seconds FROM public.app_settings WHERE id = 1), 30)
      INTO v_ludo_turn_secs;
    IF v_elapsed < (v_ludo_turn_secs * 2.0 / 5.0) THEN
      RAISE EXCEPTION 'pause disponible seulement après 2/5 du temps de tour';
    END IF;
    IF v_pause_used_deadline IS NOT NULL AND v_pause_used_deadline = v_turn_started_at THEN
      RAISE EXCEPTION 'la pause a déjà été utilisée pour ce tour';
    END IF;
  ELSE
    IF v_turn_deadline IS NULL THEN RAISE EXCEPTION 'pas de tour actif'; END IF;
    v_turn_timer := COALESCE(
      (SELECT turn_timer_seconds FROM public._game_cfg(_slug)), 30);
    v_remaining  := GREATEST(0, EXTRACT(EPOCH FROM (v_turn_deadline - now())));
    IF v_remaining > (v_turn_timer * 3.0 / 5.0) THEN
      RAISE EXCEPTION 'pause disponible seulement après 2/5 du temps de tour';
    END IF;
    IF v_pause_used_deadline IS NOT NULL AND v_pause_used_deadline = v_turn_deadline THEN
      RAISE EXCEPTION 'la pause a déjà été utilisée pour ce tour';
    END IF;
  END IF;

  -- Apply pause — include status+paused predicates to guard against race conditions
  CASE _slug
    WHEN 'chess' THEN
      UPDATE public.chess_games
         SET paused=TRUE,
             pause_deadline=now() + (v_pause_minutes || ' minutes')::interval,
             paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))),
             turn_deadline=NULL,
             pause_used_deadline=v_turn_deadline,
             paused_turn_holder_id=v_turn_holder_id
       WHERE id=_game_id AND status='playing' AND paused=FALSE;

    WHEN 'fanorona' THEN
      UPDATE public.fanorona_games
         SET paused=TRUE,
             pause_deadline=now() + (v_pause_minutes || ' minutes')::interval,
             paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))),
             turn_deadline=NULL,
             pause_used_deadline=v_turn_deadline,
             paused_turn_holder_id=v_turn_holder_id
       WHERE id=_game_id AND status='playing' AND paused=FALSE;

    WHEN 'domino' THEN
      UPDATE public.domino_games
         SET paused=TRUE,
             pause_deadline=now() + (v_pause_minutes || ' minutes')::interval,
             paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))),
             turn_deadline=NULL,
             pause_used_deadline=v_turn_deadline,
             paused_turn_holder_id=v_turn_holder_id
       WHERE id=_game_id AND status='playing' AND paused=FALSE;

    WHEN 'rami' THEN
      UPDATE public.rami_games
         SET paused=TRUE,
             pause_deadline=now() + (v_pause_minutes || ' minutes')::interval,
             paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))),
             turn_deadline=NULL,
             pause_used_deadline=v_turn_deadline,
             paused_turn_holder_id=v_turn_holder_id
       WHERE id=_game_id AND status='playing' AND paused=FALSE;

    WHEN 'poker' THEN
      UPDATE public.poker_games
         SET paused=TRUE,
             pause_deadline=now() + (v_pause_minutes || ' minutes')::interval,
             paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))),
             turn_deadline=NULL,
             pause_used_deadline=v_turn_deadline,
             paused_turn_holder_id=v_turn_holder_id
       WHERE id=_game_id AND status='playing' AND paused=FALSE;

    WHEN 'ludo' THEN
      UPDATE public.ludo_games
         SET paused=TRUE,
             pause_deadline=now() + (v_pause_minutes || ' minutes')::interval,
             state=jsonb_set(state,'{turn_started_at}',
               to_jsonb((now()+interval '1 hour')::text), true),
             pause_used_deadline=v_turn_started_at,
             paused_turn_holder_id=v_turn_holder_id
       WHERE id=_game_id AND status='playing' AND paused=FALSE;
  END CASE;
END $$;

GRANT EXECUTE ON FUNCTION public.game_request_pause(TEXT, UUID) TO authenticated;

-- 4) _game_resume_internal — propagate the "pause already used" marker forward
--    so the same stoppage cannot be paused again once resumed, while a
--    genuinely new turn (fresh turn_deadline / turn_started_at set by the
--    game engine itself) naturally clears the marker.
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

  -- NOTE: pause_used_deadline is set to the SAME value as the freshly
  -- computed turn_deadline / turn_started_at below, within the same
  -- statement (so now() resolves identically) — this "tags" the resumed
  -- turn as already-paused. The moment the real game engine advances the
  -- turn for real, it will write a different turn_deadline / turn_started_at,
  -- which no longer matches this marker and re-enables pausing.
  CASE _slug
    WHEN 'chess' THEN
      UPDATE public.chess_games
         SET paused=FALSE, pause_deadline=NULL, paused_turn_remaining_s=NULL,
             paused_turn_holder_id=NULL,
             turn_deadline = now() + (COALESCE(v_remaining_s,30) || ' seconds')::interval,
             pause_used_deadline = now() + (COALESCE(v_remaining_s,30) || ' seconds')::interval
       WHERE id = _game_id AND paused = TRUE AND status = 'playing';

    WHEN 'fanorona' THEN
      UPDATE public.fanorona_games
         SET paused=FALSE, pause_deadline=NULL, paused_turn_remaining_s=NULL,
             paused_turn_holder_id=NULL,
             turn_deadline = now() + (COALESCE(v_remaining_s,60) || ' seconds')::interval,
             pause_used_deadline = now() + (COALESCE(v_remaining_s,60) || ' seconds')::interval
       WHERE id = _game_id AND paused = TRUE AND status = 'playing';

    WHEN 'domino' THEN
      UPDATE public.domino_games
         SET paused=FALSE, pause_deadline=NULL, paused_turn_remaining_s=NULL,
             paused_turn_holder_id=NULL,
             turn_deadline = now() + (COALESCE(v_remaining_s,60) || ' seconds')::interval,
             pause_used_deadline = now() + (COALESCE(v_remaining_s,60) || ' seconds')::interval
       WHERE id = _game_id AND paused = TRUE AND status = 'playing';

    WHEN 'rami' THEN
      UPDATE public.rami_games
         SET paused=FALSE, pause_deadline=NULL, paused_turn_remaining_s=NULL,
             paused_turn_holder_id=NULL,
             turn_deadline = now() + (COALESCE(v_remaining_s,45) || ' seconds')::interval,
             pause_used_deadline = now() + (COALESCE(v_remaining_s,45) || ' seconds')::interval
       WHERE id = _game_id AND paused = TRUE AND status = 'playing';

    WHEN 'poker' THEN
      UPDATE public.poker_games
         SET paused=FALSE, pause_deadline=NULL, paused_turn_remaining_s=NULL,
             paused_turn_holder_id=NULL,
             turn_deadline = now() + (COALESCE(v_remaining_s,30) || ' seconds')::interval,
             pause_used_deadline = now() + (COALESCE(v_remaining_s,30) || ' seconds')::interval
       WHERE id = _game_id AND paused = TRUE AND status = 'playing';

    WHEN 'ludo' THEN
      UPDATE public.ludo_games
         SET paused=FALSE, pause_deadline=NULL,
             paused_turn_holder_id=NULL,
             state = jsonb_set(state, '{turn_started_at}', to_jsonb(now()::text), true),
             pause_used_deadline = now()
       WHERE id = _game_id AND paused = TRUE AND status = 'playing';
  END CASE;
END $$;
-- NOT granted to authenticated/anon — internal use only

-- 5) game_resume — external RPC now restricted to the absent player who is
--    returning (paused_turn_holder_id). Waiting players can no longer force
--    an early resume; the game only continues via the auto-resume timeout
--    (handled by _auto_resume_paused_games) or when the absent player comes back.
CREATE OR REPLACE FUNCTION public.game_resume(_slug TEXT, _game_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid                  UUID := auth.uid();
  v_status               TEXT;
  v_paused               BOOLEAN;
  v_paused_turn_holder_id UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;

  CASE _slug
    WHEN 'chess' THEN
      SELECT status, paused, paused_turn_holder_id
        INTO v_status, v_paused, v_paused_turn_holder_id
        FROM public.chess_games WHERE id = _game_id;
    WHEN 'fanorona' THEN
      SELECT status, paused, paused_turn_holder_id
        INTO v_status, v_paused, v_paused_turn_holder_id
        FROM public.fanorona_games WHERE id = _game_id;
    WHEN 'domino' THEN
      SELECT status, paused, paused_turn_holder_id
        INTO v_status, v_paused, v_paused_turn_holder_id
        FROM public.domino_games WHERE id = _game_id;
    WHEN 'rami' THEN
      SELECT status, paused, paused_turn_holder_id
        INTO v_status, v_paused, v_paused_turn_holder_id
        FROM public.rami_games WHERE id = _game_id;
    WHEN 'poker' THEN
      SELECT status, paused, paused_turn_holder_id
        INTO v_status, v_paused, v_paused_turn_holder_id
        FROM public.poker_games WHERE id = _game_id;
    WHEN 'ludo' THEN
      SELECT status, paused, paused_turn_holder_id
        INTO v_status, v_paused, v_paused_turn_holder_id
        FROM public.ludo_games WHERE id = _game_id;
    ELSE RAISE EXCEPTION 'slug invalide: %', _slug;
  END CASE;

  IF NOT FOUND            THEN RAISE EXCEPTION 'partie introuvable'; END IF;
  IF v_status <> 'playing' THEN RETURN; END IF;
  IF NOT v_paused          THEN RETURN; END IF;

  IF v_paused_turn_holder_id IS NOT NULL AND v_uid <> v_paused_turn_holder_id THEN
    RAISE EXCEPTION 'seul le joueur absent peut reprendre la partie — sinon attendez la fin du délai';
  END IF;

  PERFORM public._game_resume_internal(_slug, _game_id);
END $$;

GRANT EXECUTE ON FUNCTION public.game_resume(TEXT, UUID) TO authenticated;

-- 6) _auto_resume_paused_games — unchanged in behaviour, still relies on the
--    internal helper directly (bypasses the paused_turn_holder_id check above)
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
