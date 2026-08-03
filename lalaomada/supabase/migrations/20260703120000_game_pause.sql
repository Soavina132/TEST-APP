-- ============================================================
-- GAME PAUSE SYSTEM
-- - Adds pause / pause_deadline / paused_turn_remaining_s
--   to all game tables
-- - Adds game_request_pause() and game_resume() RPCs
-- - Adds _auto_resume_paused_games() called in tick_all_games()
-- - Updates _auto_advance_overdue_turns() to skip paused games
-- ============================================================

-- 1) Schema: add pause columns to every game table
ALTER TABLE public.chess_games
  ADD COLUMN IF NOT EXISTS paused BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS pause_deadline TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS paused_turn_remaining_s INTEGER;

ALTER TABLE public.domino_games
  ADD COLUMN IF NOT EXISTS paused BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS pause_deadline TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS paused_turn_remaining_s INTEGER;

ALTER TABLE public.fanorona_games
  ADD COLUMN IF NOT EXISTS paused BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS pause_deadline TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS paused_turn_remaining_s INTEGER;

ALTER TABLE public.rami_games
  ADD COLUMN IF NOT EXISTS paused BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS pause_deadline TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS paused_turn_remaining_s INTEGER;

ALTER TABLE public.poker_games
  ADD COLUMN IF NOT EXISTS paused BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS pause_deadline TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS paused_turn_remaining_s INTEGER;

ALTER TABLE public.ludo_games
  ADD COLUMN IF NOT EXISTS paused BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS pause_deadline TIMESTAMPTZ;
  -- ludo uses JSONB state.turn_started_at instead of turn_deadline,
  -- so no paused_turn_remaining_s needed (full timer reset on resume)

-- 2) game_request_pause — only available when ≥ 3/5 of turn time has elapsed
CREATE OR REPLACE FUNCTION public.game_request_pause(_slug TEXT, _game_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid            UUID    := auth.uid();
  v_status         TEXT;
  v_paused         BOOLEAN;
  v_turn_deadline  TIMESTAMPTZ;
  v_turn_timer     INT;
  v_remaining      FLOAT;
  v_is_participant BOOLEAN := FALSE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;

  -- Validate slug and load game state
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
      SELECT status, paused
        INTO v_status, v_paused
        FROM public.ludo_games WHERE id = _game_id;
      -- turn_deadline is NULL for ludo; skip it
      v_turn_deadline := NULL;
      SELECT EXISTS(SELECT 1 FROM public.ludo_participants
        WHERE game_id = _game_id AND user_id = v_uid AND is_bot = FALSE)
        INTO v_is_participant;

    ELSE RAISE EXCEPTION 'slug invalide: %', _slug;
  END CASE;

  IF NOT FOUND       THEN RAISE EXCEPTION 'partie introuvable'; END IF;
  IF v_status <> 'playing' THEN RAISE EXCEPTION 'la partie n''est pas en cours'; END IF;
  IF v_paused            THEN RAISE EXCEPTION 'la partie est déjà en pause'; END IF;
  IF NOT v_is_participant THEN RAISE EXCEPTION 'vous n''êtes pas participant'; END IF;

  -- For turn-deadline games: enforce 3/5 elapsed rule server-side
  IF _slug <> 'ludo' THEN
    IF v_turn_deadline IS NULL THEN RAISE EXCEPTION 'pas de tour actif'; END IF;
    v_turn_timer := COALESCE(
      (SELECT turn_timer_seconds FROM public._game_cfg(_slug)), 30);
    v_remaining  := GREATEST(0, EXTRACT(EPOCH FROM (v_turn_deadline - now())));
    IF v_remaining > (v_turn_timer * 2.0 / 5.0) THEN
      RAISE EXCEPTION 'pause disponible seulement après 3/5 du temps de tour (%.0f s restantes, seuil %.0f s)',
        v_remaining, (v_turn_timer * 2.0 / 5.0);
    END IF;
  END IF;

  -- Apply pause
  CASE _slug
    WHEN 'chess' THEN
      UPDATE public.chess_games
         SET paused                  = TRUE,
             pause_deadline          = now() + interval '5 minutes',
             paused_turn_remaining_s = CEIL(GREATEST(0, EXTRACT(EPOCH FROM (v_turn_deadline - now())))),
             turn_deadline           = NULL
       WHERE id = _game_id;

    WHEN 'fanorona' THEN
      UPDATE public.fanorona_games
         SET paused                  = TRUE,
             pause_deadline          = now() + interval '5 minutes',
             paused_turn_remaining_s = CEIL(GREATEST(0, EXTRACT(EPOCH FROM (v_turn_deadline - now())))),
             turn_deadline           = NULL
       WHERE id = _game_id;

    WHEN 'domino' THEN
      UPDATE public.domino_games
         SET paused                  = TRUE,
             pause_deadline          = now() + interval '5 minutes',
             paused_turn_remaining_s = CEIL(GREATEST(0, EXTRACT(EPOCH FROM (v_turn_deadline - now())))),
             turn_deadline           = NULL
       WHERE id = _game_id;

    WHEN 'rami' THEN
      UPDATE public.rami_games
         SET paused                  = TRUE,
             pause_deadline          = now() + interval '5 minutes',
             paused_turn_remaining_s = CEIL(GREATEST(0, EXTRACT(EPOCH FROM (v_turn_deadline - now())))),
             turn_deadline           = NULL
       WHERE id = _game_id;

    WHEN 'poker' THEN
      UPDATE public.poker_games
         SET paused                  = TRUE,
             pause_deadline          = now() + interval '5 minutes',
             paused_turn_remaining_s = CEIL(GREATEST(0, EXTRACT(EPOCH FROM (v_turn_deadline - now())))),
             turn_deadline           = NULL
       WHERE id = _game_id;

    WHEN 'ludo' THEN
      -- Freeze AFK timer by pushing turn_started_at far into the future;
      -- the auto-resume will reset it to now() so the player gets a fresh turn.
      UPDATE public.ludo_games
         SET paused         = TRUE,
             pause_deadline = now() + interval '5 minutes',
             state          = jsonb_set(
               state,
               '{turn_started_at}',
               to_jsonb((now() + interval '1 hour')::text),
               true
             )
       WHERE id = _game_id;
  END CASE;
END $$;

GRANT EXECUTE ON FUNCTION public.game_request_pause(TEXT, UUID) TO authenticated;

-- 3) game_resume — any participant can resume; also called by auto-resume
CREATE OR REPLACE FUNCTION public.game_resume(_slug TEXT, _game_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid             UUID    := auth.uid();
  v_status          TEXT;
  v_paused          BOOLEAN;
  v_remaining_s     INTEGER;
  v_is_participant  BOOLEAN := FALSE;
BEGIN
  -- Allow internal calls (from auto-resume cron) without auth
  -- v_uid may be NULL when called from _auto_resume_paused_games

  -- Validate slug and load game state
  CASE _slug
    WHEN 'chess' THEN
      SELECT status, paused, paused_turn_remaining_s
        INTO v_status, v_paused, v_remaining_s
        FROM public.chess_games WHERE id = _game_id;
      IF v_uid IS NOT NULL THEN
        SELECT EXISTS(SELECT 1 FROM public.chess_games
          WHERE id = _game_id AND (white_id = v_uid OR black_id = v_uid))
          INTO v_is_participant;
      ELSE v_is_participant := TRUE; END IF;

    WHEN 'fanorona' THEN
      SELECT status, paused, paused_turn_remaining_s
        INTO v_status, v_paused, v_remaining_s
        FROM public.fanorona_games WHERE id = _game_id;
      IF v_uid IS NOT NULL THEN
        SELECT EXISTS(SELECT 1 FROM public.fanorona_participants
          WHERE game_id = _game_id AND user_id = v_uid)
          INTO v_is_participant;
      ELSE v_is_participant := TRUE; END IF;

    WHEN 'domino' THEN
      SELECT status, paused, paused_turn_remaining_s
        INTO v_status, v_paused, v_remaining_s
        FROM public.domino_games WHERE id = _game_id;
      IF v_uid IS NOT NULL THEN
        SELECT EXISTS(SELECT 1 FROM public.domino_participants
          WHERE game_id = _game_id AND user_id = v_uid)
          INTO v_is_participant;
      ELSE v_is_participant := TRUE; END IF;

    WHEN 'rami' THEN
      SELECT status, paused, paused_turn_remaining_s
        INTO v_status, v_paused, v_remaining_s
        FROM public.rami_games WHERE id = _game_id;
      IF v_uid IS NOT NULL THEN
        SELECT EXISTS(SELECT 1 FROM public.rami_participants
          WHERE game_id = _game_id AND user_id = v_uid)
          INTO v_is_participant;
      ELSE v_is_participant := TRUE; END IF;

    WHEN 'poker' THEN
      SELECT status, paused, paused_turn_remaining_s
        INTO v_status, v_paused, v_remaining_s
        FROM public.poker_games WHERE id = _game_id;
      IF v_uid IS NOT NULL THEN
        SELECT EXISTS(SELECT 1 FROM public.poker_players
          WHERE game_id = _game_id AND user_id = v_uid)
          INTO v_is_participant;
      ELSE v_is_participant := TRUE; END IF;

    WHEN 'ludo' THEN
      SELECT status, paused
        INTO v_status, v_paused
        FROM public.ludo_games WHERE id = _game_id;
      IF v_uid IS NOT NULL THEN
        SELECT EXISTS(SELECT 1 FROM public.ludo_participants
          WHERE game_id = _game_id AND user_id = v_uid AND is_bot = FALSE)
          INTO v_is_participant;
      ELSE v_is_participant := TRUE; END IF;

    ELSE RAISE EXCEPTION 'slug invalide: %', _slug;
  END CASE;

  IF NOT FOUND          THEN RAISE EXCEPTION 'partie introuvable'; END IF;
  IF v_status <> 'playing' THEN RETURN; END IF;   -- no-op for finished/cancelled
  IF NOT v_paused        THEN RETURN; END IF;       -- already unpaused
  IF NOT v_is_participant THEN RAISE EXCEPTION 'vous n''êtes pas participant'; END IF;

  -- Resume
  CASE _slug
    WHEN 'chess' THEN
      UPDATE public.chess_games
         SET paused                  = FALSE,
             pause_deadline          = NULL,
             paused_turn_remaining_s = NULL,
             turn_deadline           = now() + (COALESCE(v_remaining_s, 30) || ' seconds')::interval
       WHERE id = _game_id;

    WHEN 'fanorona' THEN
      UPDATE public.fanorona_games
         SET paused                  = FALSE,
             pause_deadline          = NULL,
             paused_turn_remaining_s = NULL,
             turn_deadline           = now() + (COALESCE(v_remaining_s, 60) || ' seconds')::interval
       WHERE id = _game_id;

    WHEN 'domino' THEN
      UPDATE public.domino_games
         SET paused                  = FALSE,
             pause_deadline          = NULL,
             paused_turn_remaining_s = NULL,
             turn_deadline           = now() + (COALESCE(v_remaining_s, 60) || ' seconds')::interval
       WHERE id = _game_id;

    WHEN 'rami' THEN
      UPDATE public.rami_games
         SET paused                  = FALSE,
             pause_deadline          = NULL,
             paused_turn_remaining_s = NULL,
             turn_deadline           = now() + (COALESCE(v_remaining_s, 45) || ' seconds')::interval
       WHERE id = _game_id;

    WHEN 'poker' THEN
      UPDATE public.poker_games
         SET paused                  = FALSE,
             pause_deadline          = NULL,
             paused_turn_remaining_s = NULL,
             turn_deadline           = now() + (COALESCE(v_remaining_s, 30) || ' seconds')::interval
       WHERE id = _game_id;

    WHEN 'ludo' THEN
      -- Reset AFK timer to now so the player gets a fresh turn
      UPDATE public.ludo_games
         SET paused         = FALSE,
             pause_deadline = NULL,
             state          = jsonb_set(
               state,
               '{turn_started_at}',
               to_jsonb(now()::text),
               true
             )
       WHERE id = _game_id;
  END CASE;
END $$;

GRANT EXECUTE ON FUNCTION public.game_resume(TEXT, UUID) TO authenticated;

-- 4) _auto_resume_paused_games — called by tick_all_games
CREATE OR REPLACE FUNCTION public._auto_resume_paused_games()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record;
BEGIN
  FOR r IN SELECT id FROM public.chess_games
           WHERE paused = TRUE AND pause_deadline IS NOT NULL AND pause_deadline < now() AND status = 'playing'
  LOOP PERFORM public.game_resume('chess', r.id); END LOOP;

  FOR r IN SELECT id FROM public.fanorona_games
           WHERE paused = TRUE AND pause_deadline IS NOT NULL AND pause_deadline < now() AND status = 'playing'
  LOOP PERFORM public.game_resume('fanorona', r.id); END LOOP;

  FOR r IN SELECT id FROM public.domino_games
           WHERE paused = TRUE AND pause_deadline IS NOT NULL AND pause_deadline < now() AND status = 'playing'
  LOOP PERFORM public.game_resume('domino', r.id); END LOOP;

  FOR r IN SELECT id FROM public.rami_games
           WHERE paused = TRUE AND pause_deadline IS NOT NULL AND pause_deadline < now() AND status = 'playing'
  LOOP PERFORM public.game_resume('rami', r.id); END LOOP;

  FOR r IN SELECT id FROM public.poker_games
           WHERE paused = TRUE AND pause_deadline IS NOT NULL AND pause_deadline < now() AND status = 'playing'
  LOOP PERFORM public.game_resume('poker', r.id); END LOOP;

  FOR r IN SELECT id FROM public.ludo_games
           WHERE paused = TRUE AND pause_deadline IS NOT NULL AND pause_deadline < now() AND status = 'playing'
  LOOP PERFORM public.game_resume('ludo', r.id); END LOOP;
END $$;

-- 5) Update _auto_advance_overdue_turns to skip paused games
CREATE OR REPLACE FUNCTION public._auto_advance_overdue_turns()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record;
BEGIN
  FOR r IN SELECT id FROM public.fanorona_games
           WHERE status='playing' AND paused = FALSE
             AND turn_deadline IS NOT NULL AND turn_deadline < now()
  LOOP PERFORM public.fanorona_tick(r.id); END LOOP;

  FOR r IN SELECT id FROM public.chess_games
           WHERE status='playing' AND paused = FALSE
             AND turn_deadline IS NOT NULL AND turn_deadline < now()
  LOOP PERFORM public.chess_tick(r.id); END LOOP;

  FOR r IN SELECT id FROM public.domino_games
           WHERE status='playing' AND paused = FALSE
             AND turn_deadline IS NOT NULL AND turn_deadline < now()
  LOOP PERFORM public.domino_tick(r.id); END LOOP;

  FOR r IN SELECT id FROM public.rami_games
           WHERE status='playing' AND paused = FALSE
             AND turn_deadline IS NOT NULL AND turn_deadline < now()
  LOOP PERFORM public.rami_tick(r.id); END LOOP;
END $$;

-- 6) Update tick_all_games to auto-resume paused games first
CREATE OR REPLACE FUNCTION public.tick_all_games()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public._auto_resume_paused_games();
  PERFORM public._auto_cancel_open_games();
  PERFORM public._auto_advance_overdue_turns();
END $$;
