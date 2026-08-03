-- ================================================================
-- GAME PAUSE — CORRECTIONS (once per GAME, trigger on 2 consecutive
-- missed turns instead of elapsed-time fraction)
-- ----------------------------------------------------------------
-- 1. The pause button must be usable ONLY ONCE PER GAME (not once
--    per turn). Once used, it must never come back for the rest of
--    that game. We repurpose pause_used_this_turn -> pause_used and
--    remove the "reset on turn change" triggers entirely.
-- 2. The pause becomes available once the player currently on turn
--    has missed 2 CONSECUTIVE turns, using each game's existing
--    missed-turn counters:
--      - chess / domino / fanorona / rami: turn_skips (jsonb, keyed
--        by user id, already incremented by each game's *_tick fn)
--      - ludo: afk_t1 / afk_t2 counters on ludo_participants
--      - poker: has no server-side missed-turn counter yet (no
--        poker_tick / auto-fold-on-timeout function exists in this
--        codebase), so we keep the previous elapsed-time fallback
--        (>= 3/5 of the turn timer elapsed) for poker only, until a
--        proper poker turn-timeout/skip-counter feature is built.
-- 3. Still restricted to WAITING players (never the player on turn,
--    never an admin). Still a 3-minute pause, auto-resume unchanged.
-- ================================================================

-- 1) Drop the "reset every turn" triggers — pause_used must now be permanent
DROP TRIGGER IF EXISTS trg_reset_pause_used_chess    ON public.chess_games;
DROP TRIGGER IF EXISTS trg_reset_pause_used_domino   ON public.domino_games;
DROP TRIGGER IF EXISTS trg_reset_pause_used_fanorona ON public.fanorona_games;
DROP TRIGGER IF EXISTS trg_reset_pause_used_rami     ON public.rami_games;
DROP TRIGGER IF EXISTS trg_reset_pause_used_ludo     ON public.ludo_games;
DROP TRIGGER IF EXISTS trg_reset_pause_used_poker    ON public.poker_games;

DROP FUNCTION IF EXISTS public._reset_pause_used_chess();
DROP FUNCTION IF EXISTS public._reset_pause_used_by_current_turn();
DROP FUNCTION IF EXISTS public._reset_pause_used_poker();

-- 2) Rename the per-turn flag into a permanent per-game flag
ALTER TABLE public.chess_games     RENAME COLUMN pause_used_this_turn TO pause_used;
ALTER TABLE public.domino_games    RENAME COLUMN pause_used_this_turn TO pause_used;
ALTER TABLE public.fanorona_games  RENAME COLUMN pause_used_this_turn TO pause_used;
ALTER TABLE public.rami_games      RENAME COLUMN pause_used_this_turn TO pause_used;
ALTER TABLE public.poker_games     RENAME COLUMN pause_used_this_turn TO pause_used;
ALTER TABLE public.ludo_games      RENAME COLUMN pause_used_this_turn TO pause_used;

-- 3) game_request_pause — rewritten:
--    - only a WAITING participant may request it (unchanged)
--    - blocked forever once used for THIS GAME (pause_used, no reset)
--    - available once the turn player has missed 2 consecutive turns
--      (turn_skips / afk counters), poker keeps the elapsed fallback
--    - pause window is 3 minutes (unchanged)
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
  -- chess-specific
  v_turn_color       TEXT;
  v_white_id         UUID;
  v_black_id         UUID;
  -- slot-based games
  v_current_turn     INT;
  -- ludo-specific
  v_turn_started_at  TIMESTAMPTZ;
  v_afk_t1           INT;
  v_afk_t2           INT;
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
        WHERE game_id = _game_id AND user_id = v_uid)
        INTO v_is_participant;

    WHEN 'domino' THEN
      SELECT status, paused, turn_deadline, current_turn, pause_used, turn_skips
        INTO v_status, v_paused, v_turn_deadline, v_current_turn, v_pause_used, v_turn_skips
        FROM public.domino_games WHERE id = _game_id;
      SELECT user_id INTO v_turn_uid FROM public.domino_participants
        WHERE game_id = _game_id AND slot = v_current_turn;
      SELECT EXISTS(SELECT 1 FROM public.domino_participants
        WHERE game_id = _game_id AND user_id = v_uid)
        INTO v_is_participant;

    WHEN 'rami' THEN
      SELECT status, paused, turn_deadline, current_turn, pause_used, turn_skips
        INTO v_status, v_paused, v_turn_deadline, v_current_turn, v_pause_used, v_turn_skips
        FROM public.rami_games WHERE id = _game_id;
      SELECT user_id INTO v_turn_uid FROM public.rami_participants
        WHERE game_id = _game_id AND slot = v_current_turn;
      SELECT EXISTS(SELECT 1 FROM public.rami_participants
        WHERE game_id = _game_id AND user_id = v_uid)
        INTO v_is_participant;

    WHEN 'poker' THEN
      SELECT status, paused, turn_deadline, current_player, pause_used
        INTO v_status, v_paused, v_turn_deadline, v_turn_uid, v_pause_used
        FROM public.poker_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.poker_players
        WHERE game_id = _game_id AND user_id = v_uid)
        INTO v_is_participant;

    WHEN 'ludo' THEN
      SELECT status, paused, (state->>'turn_started_at')::timestamptz, current_turn, pause_used
        INTO v_status, v_paused, v_turn_started_at, v_current_turn, v_pause_used
        FROM public.ludo_games WHERE id = _game_id;
      v_turn_deadline := NULL;
      SELECT user_id INTO v_turn_uid FROM public.ludo_participants
        WHERE game_id = _game_id AND slot = v_current_turn;
      SELECT afk_t1, afk_t2 INTO v_afk_t1, v_afk_t2 FROM public.ludo_participants
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
  IF v_pause_used          THEN RAISE EXCEPTION 'la pause a déjà été utilisée pour cette partie'; END IF;

  -- Only a WAITING player may request the pause — never the player on turn
  IF v_turn_uid IS NOT NULL AND v_uid = v_turn_uid THEN
    RAISE EXCEPTION 'seul un joueur qui attend son tour peut demander la pause';
  END IF;

  -- Eligibility: the player on turn must have missed 2 consecutive turns
  IF _slug = 'ludo' THEN
    IF v_turn_started_at IS NULL THEN RAISE EXCEPTION 'pas de tour actif'; END IF;
    IF GREATEST(COALESCE(v_afk_t1,0), COALESCE(v_afk_t2,0)) < 2 THEN
      RAISE EXCEPTION 'pause disponible seulement après 2 tours manqués consécutifs';
    END IF;
  ELSIF _slug = 'poker' THEN
    -- No missed-turn counter exists yet for poker; fall back to the
    -- elapsed-time rule (>= 3/5 of the turn timer elapsed) as before.
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

  -- Apply pause — 3 minutes, flag this game's ONE allowance as spent forever
  CASE _slug
    WHEN 'chess' THEN
      UPDATE public.chess_games
         SET paused=TRUE, pause_deadline=now()+interval '3 minutes',
             paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))),
             turn_deadline=NULL,
             pause_used=TRUE
       WHERE id=_game_id AND status='playing' AND paused=FALSE;

    WHEN 'fanorona' THEN
      UPDATE public.fanorona_games
         SET paused=TRUE, pause_deadline=now()+interval '3 minutes',
             paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))),
             turn_deadline=NULL,
             pause_used=TRUE
       WHERE id=_game_id AND status='playing' AND paused=FALSE;

    WHEN 'domino' THEN
      UPDATE public.domino_games
         SET paused=TRUE, pause_deadline=now()+interval '3 minutes',
             paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))),
             turn_deadline=NULL,
             pause_used=TRUE
       WHERE id=_game_id AND status='playing' AND paused=FALSE;

    WHEN 'rami' THEN
      UPDATE public.rami_games
         SET paused=TRUE, pause_deadline=now()+interval '3 minutes',
             paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))),
             turn_deadline=NULL,
             pause_used=TRUE
       WHERE id=_game_id AND status='playing' AND paused=FALSE;

    WHEN 'poker' THEN
      UPDATE public.poker_games
         SET paused=TRUE, pause_deadline=now()+interval '3 minutes',
             paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))),
             turn_deadline=NULL,
             pause_used=TRUE
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
