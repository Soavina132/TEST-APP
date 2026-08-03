-- Migration: finish_game_2p + player_game_stats
-- Handles prize distribution and ranking stats for domino/billiard end-of-game.
-- Idempotent (CREATE TABLE IF NOT EXISTS, CREATE OR REPLACE FUNCTION).

-- ── Stats table ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.player_game_stats (
  user_id        UUID    NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  game_mode      TEXT    NOT NULL,   -- 'domino' | 'billiard' | 'ludo'
  wins           INTEGER NOT NULL DEFAULT 0,
  losses         INTEGER NOT NULL DEFAULT 0,
  total_winnings NUMERIC NOT NULL DEFAULT 0,
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, game_mode)
);
ALTER TABLE public.player_game_stats ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pgstats_select ON public.player_game_stats;
CREATE POLICY pgstats_select ON public.player_game_stats FOR SELECT TO authenticated USING (true);
GRANT SELECT ON public.player_game_stats TO authenticated;
GRANT ALL    ON public.player_game_stats TO service_role;

-- ── finish_game_2p ───────────────────────────────────────────
-- Called by the client that detects game over.
-- • Validates caller is authenticated.
-- • Idempotent: returns silently if game already finished.
-- • Calculates prize = pot × (100 − commission_pct) / 100.
-- • Credits winner balance and sets pot = 0.
-- • Marks game status = 'finished', sets winner_id + finished_at.
-- • Upserts player_game_stats for winner (wins++) and loser (losses++).
-- Derives participant table name as <game_table minus "_games"> + "_participants"
-- e.g. 'domino_games' → 'domino_participants'.
CREATE OR REPLACE FUNCTION public.finish_game_2p(
  _game_table TEXT,
  _game_id    UUID,
  _winner_id  UUID
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _game       RECORD;
  _caller     UUID    := auth.uid();
  _part_table TEXT;
  _game_mode  TEXT;
  _prize      NUMERIC := 0;
  _comm       NUMERIC := 0;
  _loser_id   UUID;
BEGIN
  IF _caller IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  -- Derive auxiliary names from game table
  _part_table := replace(_game_table, '_games', '_participants');
  _game_mode  := replace(_game_table, '_games', '');

  -- Lock game row (prevents double-finish race)
  EXECUTE format('SELECT * FROM %I WHERE id = $1 FOR UPDATE', _game_table)
    INTO _game USING _game_id;
  IF NOT FOUND                    THEN RAISE EXCEPTION 'game_not_found'; END IF;
  IF _game.status = 'finished'    THEN RETURN; END IF;  -- idempotent
  IF _game.status <> 'playing'    THEN RAISE EXCEPTION 'game_not_playing'; END IF;

  -- Prize calculation (pot - commission)
  _comm  := COALESCE(_game.commission_pct, 0);
  _prize := COALESCE(_game.pot, 0) * (100 - _comm) / 100;

  -- Mark game as finished
  EXECUTE format(
    'UPDATE %I SET status = ''finished'', winner_id = $1, finished_at = now(), pot = 0 WHERE id = $2',
    _game_table
  ) USING _winner_id, _game_id;

  -- Credit winner's balance
  IF _prize > 0 AND _winner_id IS NOT NULL THEN
    UPDATE public.profiles
    SET    balance_ar = balance_ar + _prize
    WHERE  id = _winner_id;
  END IF;

  -- Upsert winner stats
  IF _winner_id IS NOT NULL THEN
    INSERT INTO public.player_game_stats (user_id, game_mode, wins, total_winnings, updated_at)
    VALUES (_winner_id, _game_mode, 1, GREATEST(_prize, 0), now())
    ON CONFLICT (user_id, game_mode) DO UPDATE SET
      wins           = public.player_game_stats.wins + 1,
      total_winnings = public.player_game_stats.total_winnings + GREATEST(EXCLUDED.total_winnings, 0),
      updated_at     = now();
  END IF;

  -- Upsert loser stats (all participants except winner)
  FOR _loser_id IN
    EXECUTE format(
      'SELECT user_id FROM %I WHERE game_id = $1 AND user_id <> $2',
      _part_table
    ) USING _game_id, COALESCE(_winner_id, '00000000-0000-0000-0000-000000000000'::uuid)
  LOOP
    INSERT INTO public.player_game_stats (user_id, game_mode, losses, updated_at)
    VALUES (_loser_id, _game_mode, 1, now())
    ON CONFLICT (user_id, game_mode) DO UPDATE SET
      losses     = public.player_game_stats.losses + 1,
      updated_at = now();
  END LOOP;

END;
$$;

GRANT EXECUTE ON FUNCTION public.finish_game_2p(TEXT, UUID, UUID) TO authenticated;
