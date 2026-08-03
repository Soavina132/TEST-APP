-- ================================================================
-- GAME PAUSE — WAITING PLAYERS ONLY, 3-MIN DURATION, ONCE PER TURN
-- ----------------------------------------------------------------
-- Fixes:
-- 1. The pause button must be usable by the WAITING players (the
--    participants who are NOT on turn), never by the player whose
--    turn it is and never by an admin. They use it to give a
--    struggling teammate/opponent time to come back.
-- 2. Pause duration is 3 minutes (was 5). Auto-resume unchanged.
-- 3. The pause can be requested only ONCE per turn. A new turn
--    (detected via the game's turn-owner column changing) resets
--    the allowance.
-- ================================================================

-- 1) Schema: track whether pause has already been used this turn
ALTER TABLE public.chess_games     ADD COLUMN IF NOT EXISTS pause_used_this_turn BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.domino_games    ADD COLUMN IF NOT EXISTS pause_used_this_turn BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.fanorona_games  ADD COLUMN IF NOT EXISTS pause_used_this_turn BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.rami_games      ADD COLUMN IF NOT EXISTS pause_used_this_turn BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.poker_games     ADD COLUMN IF NOT EXISTS pause_used_this_turn BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.ludo_games      ADD COLUMN IF NOT EXISTS pause_used_this_turn BOOLEAN NOT NULL DEFAULT FALSE;

-- 2) Triggers: reset the "used this turn" flag whenever the turn actually
--    changes to a different player, regardless of which code path moved
--    the turn forward (a normal move, a timeout tick, etc).
CREATE OR REPLACE FUNCTION public._reset_pause_used_chess()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.turn IS DISTINCT FROM OLD.turn THEN
    NEW.pause_used_this_turn := FALSE;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_reset_pause_used_chess ON public.chess_games;
CREATE TRIGGER trg_reset_pause_used_chess BEFORE UPDATE ON public.chess_games
  FOR EACH ROW EXECUTE FUNCTION public._reset_pause_used_chess();

CREATE OR REPLACE FUNCTION public._reset_pause_used_by_current_turn()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.current_turn IS DISTINCT FROM OLD.current_turn THEN
    NEW.pause_used_this_turn := FALSE;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_reset_pause_used_domino ON public.domino_games;
CREATE TRIGGER trg_reset_pause_used_domino BEFORE UPDATE ON public.domino_games
  FOR EACH ROW EXECUTE FUNCTION public._reset_pause_used_by_current_turn();

DROP TRIGGER IF EXISTS trg_reset_pause_used_fanorona ON public.fanorona_games;
CREATE TRIGGER trg_reset_pause_used_fanorona BEFORE UPDATE ON public.fanorona_games
  FOR EACH ROW EXECUTE FUNCTION public._reset_pause_used_by_current_turn();

DROP TRIGGER IF EXISTS trg_reset_pause_used_rami ON public.rami_games;
CREATE TRIGGER trg_reset_pause_used_rami BEFORE UPDATE ON public.rami_games
  FOR EACH ROW EXECUTE FUNCTION public._reset_pause_used_by_current_turn();

DROP TRIGGER IF EXISTS trg_reset_pause_used_ludo ON public.ludo_games;
CREATE TRIGGER trg_reset_pause_used_ludo BEFORE UPDATE ON public.ludo_games
  FOR EACH ROW EXECUTE FUNCTION public._reset_pause_used_by_current_turn();

CREATE OR REPLACE FUNCTION public._reset_pause_used_poker()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.current_player IS DISTINCT FROM OLD.current_player THEN
    NEW.pause_used_this_turn := FALSE;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_reset_pause_used_poker ON public.poker_games;
CREATE TRIGGER trg_reset_pause_used_poker BEFORE UPDATE ON public.poker_games
  FOR EACH ROW EXECUTE FUNCTION public._reset_pause_used_poker();

-- 3) game_request_pause — rewritten:
--    - only a WAITING participant (not the player on turn) may request it
--    - blocked once already used for the current turn
--    - pause window is 3 minutes
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
  -- chess-specific
  v_turn_color       TEXT;
  v_white_id         UUID;
  v_black_id         UUID;
  -- slot-based games
  v_current_turn     INT;
  -- ludo-specific
  v_turn_started_at  TIMESTAMPTZ;
  v_elapsed          FLOAT;
  v_ludo_turn_secs   INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;

  CASE _slug
    WHEN 'chess' THEN
      SELECT status, paused, turn_deadline, turn, white_id, black_id, pause_used_this_turn
        INTO v_status, v_paused, v_turn_deadline, v_turn_color, v_white_id, v_black_id, v_pause_used
        FROM public.chess_games WHERE id = _game_id;
      v_turn_uid := CASE WHEN v_turn_color = 'w' THEN v_white_id ELSE v_black_id END;
      v_is_participant := (v_uid = v_white_id OR v_uid = v_black_id);

    WHEN 'fanorona' THEN
      SELECT status, paused, turn_deadline, current_turn, pause_used_this_turn
        INTO v_status, v_paused, v_turn_deadline, v_current_turn, v_pause_used
        FROM public.fanorona_games WHERE id = _game_id;
      SELECT user_id INTO v_turn_uid FROM public.fanorona_participants
        WHERE game_id = _game_id AND slot = v_current_turn;
      SELECT EXISTS(SELECT 1 FROM public.fanorona_participants
        WHERE game_id = _game_id AND user_id = v_uid)
        INTO v_is_participant;

    WHEN 'domino' THEN
      SELECT status, paused, turn_deadline, current_turn, pause_used_this_turn
        INTO v_status, v_paused, v_turn_deadline, v_current_turn, v_pause_used
        FROM public.domino_games WHERE id = _game_id;
      SELECT user_id INTO v_turn_uid FROM public.domino_participants
        WHERE game_id = _game_id AND slot = v_current_turn;
      SELECT EXISTS(SELECT 1 FROM public.domino_participants
        WHERE game_id = _game_id AND user_id = v_uid)
        INTO v_is_participant;

    WHEN 'rami' THEN
      SELECT status, paused, turn_deadline, current_turn, pause_used_this_turn
        INTO v_status, v_paused, v_turn_deadline, v_current_turn, v_pause_used
        FROM public.rami_games WHERE id = _game_id;
      SELECT user_id INTO v_turn_uid FROM public.rami_participants
        WHERE game_id = _game_id AND slot = v_current_turn;
      SELECT EXISTS(SELECT 1 FROM public.rami_participants
        WHERE game_id = _game_id AND user_id = v_uid)
        INTO v_is_participant;

    WHEN 'poker' THEN
      SELECT status, paused, turn_deadline, current_player, pause_used_this_turn
        INTO v_status, v_paused, v_turn_deadline, v_turn_uid, v_pause_used
        FROM public.poker_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.poker_players
        WHERE game_id = _game_id AND user_id = v_uid)
        INTO v_is_participant;

    WHEN 'ludo' THEN
      SELECT status, paused, (state->>'turn_started_at')::timestamptz, current_turn, pause_used_this_turn
        INTO v_status, v_paused, v_turn_started_at, v_current_turn, v_pause_used
        FROM public.ludo_games WHERE id = _game_id;
      v_turn_deadline := NULL;
      SELECT user_id INTO v_turn_uid FROM public.ludo_participants
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
  IF v_pause_used          THEN RAISE EXCEPTION 'la pause a déjà été utilisée pour ce tour'; END IF;

  -- Only a WAITING player may request the pause — never the player on turn
  IF v_turn_uid IS NOT NULL AND v_uid = v_turn_uid THEN
    RAISE EXCEPTION 'seul un joueur qui attend son tour peut demander la pause';
  END IF;

  -- Enforce 3/5-elapsed rule server-side for ALL slugs (based on the
  -- turn player's clock, not the caller's)
  IF _slug = 'ludo' THEN
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

  -- Apply pause — 3 minutes, flag this turn's allowance as spent
  CASE _slug
    WHEN 'chess' THEN
      UPDATE public.chess_games
         SET paused=TRUE, pause_deadline=now()+interval '3 minutes',
             paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))),
             turn_deadline=NULL,
             pause_used_this_turn=TRUE
       WHERE id=_game_id AND status='playing' AND paused=FALSE;

    WHEN 'fanorona' THEN
      UPDATE public.fanorona_games
         SET paused=TRUE, pause_deadline=now()+interval '3 minutes',
             paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))),
             turn_deadline=NULL,
             pause_used_this_turn=TRUE
       WHERE id=_game_id AND status='playing' AND paused=FALSE;

    WHEN 'domino' THEN
      UPDATE public.domino_games
         SET paused=TRUE, pause_deadline=now()+interval '3 minutes',
             paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))),
             turn_deadline=NULL,
             pause_used_this_turn=TRUE
       WHERE id=_game_id AND status='playing' AND paused=FALSE;

    WHEN 'rami' THEN
      UPDATE public.rami_games
         SET paused=TRUE, pause_deadline=now()+interval '3 minutes',
             paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))),
             turn_deadline=NULL,
             pause_used_this_turn=TRUE
       WHERE id=_game_id AND status='playing' AND paused=FALSE;

    WHEN 'poker' THEN
      UPDATE public.poker_games
         SET paused=TRUE, pause_deadline=now()+interval '3 minutes',
             paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))),
             turn_deadline=NULL,
             pause_used_this_turn=TRUE
       WHERE id=_game_id AND status='playing' AND paused=FALSE;

    WHEN 'ludo' THEN
      UPDATE public.ludo_games
         SET paused=TRUE, pause_deadline=now()+interval '3 minutes',
             pause_used_this_turn=TRUE,
             state=jsonb_set(state,'{turn_started_at}',
               to_jsonb((now()+interval '1 hour')::text), true)
       WHERE id=_game_id AND status='playing' AND paused=FALSE;
  END CASE;
END $$;

GRANT EXECUTE ON FUNCTION public.game_request_pause(TEXT, UUID) TO authenticated;
