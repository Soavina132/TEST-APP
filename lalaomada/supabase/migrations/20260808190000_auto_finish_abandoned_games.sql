-- ================================================================
-- Auto-finish abandoned games: when no human players remain active
-- (all humans have forfeited or left), auto-finish the game and
-- declare the last remaining bot / player as winner.
-- Also handles games where a single human player is left alone
-- (opponent forfeited) — auto-declares them winner.
-- ================================================================

CREATE OR REPLACE FUNCTION public.auto_finish_abandoned_games()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  g record;
  v_winner uuid;
  v_active_human_count int;
  v_last_human uuid;
BEGIN
  -- ── LUDO ──
  FOR g IN SELECT id, pot, commission_pct FROM public.ludo_games WHERE status = 'playing'
  LOOP
    SELECT count(*) INTO v_active_human_count
      FROM public.ludo_participants
      WHERE game_id = g.id AND is_bot = false AND forfeited = false;
    IF v_active_human_count = 0 THEN
      -- All humans left → winner = last non-forfeited bot/player
      SELECT user_id INTO v_winner FROM public.ludo_participants
        WHERE game_id = g.id AND forfeited = false
        ORDER BY slot LIMIT 1;
      UPDATE public.ludo_games
        SET status = 'finished', winner_id = v_winner, finished_at = now()
        WHERE id = g.id;
    ELSIF v_active_human_count = 1 THEN
      -- Only 1 human left → check if everyone else forfeited
      SELECT count(*) INTO v_active_human_count
        FROM public.ludo_participants
        WHERE game_id = g.id AND forfeited = false;
      IF v_active_human_count <= 1 THEN
        SELECT user_id INTO v_winner FROM public.ludo_participants
          WHERE game_id = g.id AND forfeited = false LIMIT 1;
        UPDATE public.ludo_games
          SET status = 'finished', winner_id = v_winner, finished_at = now()
          WHERE id = g.id;
      END IF;
    END IF;
  END LOOP;

  -- ── DOMINO ──
  FOR g IN SELECT id, pot, commission_pct FROM public.domino_games WHERE status = 'playing'
  LOOP
    SELECT count(*) INTO v_active_human_count
      FROM public.domino_participants
      WHERE game_id = g.id AND is_bot = false AND forfeited = false;
    IF v_active_human_count = 0 THEN
      SELECT user_id INTO v_winner FROM public.domino_participants
        WHERE game_id = g.id AND forfeited = false
        ORDER BY slot LIMIT 1;
      UPDATE public.domino_games
        SET status = 'finished', winner_id = v_winner, finished_at = now()
        WHERE id = g.id;
    ELSIF v_active_human_count = 1 THEN
      SELECT count(*) INTO v_active_human_count
        FROM public.domino_participants
        WHERE game_id = g.id AND forfeited = false;
      IF v_active_human_count <= 1 THEN
        SELECT user_id INTO v_winner FROM public.domino_participants
          WHERE game_id = g.id AND forfeited = false LIMIT 1;
        UPDATE public.domino_games
          SET status = 'finished', winner_id = v_winner, finished_at = now()
          WHERE id = g.id;
      END IF;
    END IF;
  END LOOP;

  -- ── FANORONA ──
  FOR g IN SELECT id, pot, commission_pct FROM public.fanorona_games WHERE status = 'playing'
  LOOP
    SELECT count(*) INTO v_active_human_count
      FROM public.fanorona_participants
      WHERE game_id = g.id AND is_bot = false AND forfeited = false;
    IF v_active_human_count = 0 THEN
      SELECT user_id INTO v_winner FROM public.fanorona_participants
        WHERE game_id = g.id AND forfeited = false
        ORDER BY slot LIMIT 1;
      UPDATE public.fanorona_games
        SET status = 'finished', winner_id = v_winner, finished_at = now()
        WHERE id = g.id;
    ELSIF v_active_human_count = 1 THEN
      SELECT count(*) INTO v_active_human_count
        FROM public.fanorona_participants
        WHERE game_id = g.id AND forfeited = false;
      IF v_active_human_count <= 1 THEN
        SELECT user_id INTO v_winner FROM public.fanorona_participants
          WHERE game_id = g.id AND forfeited = false LIMIT 1;
        UPDATE public.fanorona_games
          SET status = 'finished', winner_id = v_winner, finished_at = now()
          WHERE id = g.id;
      END IF;
    END IF;
  END LOOP;

  -- ── RAMI ──
  FOR g IN SELECT id, pot, commission_pct FROM public.rami_games WHERE status = 'playing'
  LOOP
    SELECT count(*) INTO v_active_human_count
      FROM public.rami_participants
      WHERE game_id = g.id AND is_bot = false AND forfeited = false;
    IF v_active_human_count = 0 THEN
      SELECT user_id INTO v_winner FROM public.rami_participants
        WHERE game_id = g.id AND forfeited = false
        ORDER BY slot LIMIT 1;
      UPDATE public.rami_games
        SET status = 'finished', winner_id = v_winner, finished_at = now()
        WHERE id = g.id;
    ELSIF v_active_human_count = 1 THEN
      SELECT count(*) INTO v_active_human_count
        FROM public.rami_participants
        WHERE game_id = g.id AND forfeited = false;
      IF v_active_human_count <= 1 THEN
        SELECT user_id INTO v_winner FROM public.rami_participants
          WHERE game_id = g.id AND forfeited = false LIMIT 1;
        UPDATE public.rami_games
          SET status = 'finished', winner_id = v_winner, finished_at = now()
          WHERE id = g.id;
      END IF;
    END IF;
  END LOOP;

  -- ── CHESS ── (1v1, no bots typically, but handle forfeit)
  FOR g IN SELECT id, white_id, black_id, stake, pot FROM public.chess_games WHERE status = 'playing'
  LOOP
    -- If both players are NULL (shouldn't happen, but guard)
    IF g.white_id IS NULL AND g.black_id IS NULL THEN
      UPDATE public.chess_games SET status = 'cancelled', finished_at = now() WHERE id = g.id;
    ELSIF g.white_id IS NOT NULL AND g.black_id IS NULL THEN
      -- No opponent joined → cancel & refund
      UPDATE public.chess_games SET status = 'cancelled', finished_at = now() WHERE id = g.id;
    ELSIF g.white_id IS NOT NULL AND g.black_id IS NOT NULL THEN
      -- Both players exist — game is active, leave it (chess has turn timer)
      NULL;
    END IF;
  END LOOP;

  -- ── POKER ──
  FOR g IN SELECT id, pot, commission_pct FROM public.poker_games WHERE status = 'playing'
  LOOP
    SELECT count(*) INTO v_active_human_count
      FROM public.poker_players
      WHERE game_id = g.id AND status = 'playing';
    IF v_active_human_count = 0 THEN
      -- No active players → finish with last remaining player
      SELECT user_id INTO v_winner FROM public.poker_players
        WHERE game_id = g.id ORDER BY chips DESC LIMIT 1;
      UPDATE public.poker_games
        SET status = 'finished', winner_id = v_winner, finished_at = now()
        WHERE id = g.id;
    ELSIF v_active_human_count = 1 THEN
      SELECT count(*) INTO v_active_human_count
        FROM public.poker_players
        WHERE game_id = g.id AND status NOT IN ('out', 'folded');
      IF v_active_human_count <= 1 THEN
        SELECT user_id INTO v_winner FROM public.poker_players
          WHERE game_id = g.id AND status = 'playing' LIMIT 1;
        UPDATE public.poker_games
          SET status = 'finished', winner_id = v_winner, finished_at = now()
          WHERE id = g.id;
      END IF;
    END IF;
  END LOOP;
END $$;

-- Schedule it to run every 2 minutes via pg_cron (if available)
-- The existing _auto_cancel_open_games() already runs on a schedule;
-- we add this alongside it.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'auto-finish-abandoned-games',
      '*/2 * * * *',
      $$SELECT public.auto_finish_abandoned_games();$$
    );
    EXCEPTION WHEN OTHERS THEN
      -- Already scheduled, ignore
      NULL;
  END IF;
END $$;
