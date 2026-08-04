-- ============================================================
-- Migration: Fix missing RLS policies on chess_games / chess_moves
--
-- Root cause of "stuck on Chargement…": RLS was ENABLED on both
-- tables but had ZERO policies defined. With RLS on and no policies,
-- Postgres denies all rows to non-superuser roles — so every
-- `select("*").eq("id", id)` from the frontend silently returned
-- null (no error), and the page never left the loading state.
--
-- All actual mutations already go through SECURITY DEFINER RPCs
-- (chess_play, chess_bot_play, chess_resign, etc.) which bypass RLS,
-- so we mainly need SELECT policies here — mirroring the permissive
-- pattern already used by domino_games.
-- ============================================================

-- chess_games: readable/writable by anyone authenticated (matches domino_games pattern)
CREATE POLICY chess_games_select ON public.chess_games
  FOR SELECT USING (true);

CREATE POLICY chess_games_insert ON public.chess_games
  FOR INSERT WITH CHECK (auth.uid() = host_id);

CREATE POLICY chess_games_update ON public.chess_games
  FOR UPDATE USING (true);

-- chess_moves: readable by anyone; inserts happen via SECURITY DEFINER RPCs only,
-- but add a safety policy scoped to game participants in case of direct writes.
CREATE POLICY chess_moves_select ON public.chess_moves
  FOR SELECT USING (true);

CREATE POLICY chess_moves_insert ON public.chess_moves
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.chess_games g
      WHERE g.id = chess_moves.game_id
        AND (g.white_id = auth.uid() OR g.black_id = auth.uid())
    )
  );
