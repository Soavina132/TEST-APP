-- Fix: private games visible to everyone. Restrict to host/participants/admin.

-- chess_games
DROP POLICY IF EXISTS chess_games_select ON public.chess_games;
CREATE POLICY chess_games_select ON public.chess_games
  FOR SELECT USING (
    is_private = false
    OR host_id = auth.uid()
    OR white_id = auth.uid()
    OR black_id = auth.uid()
    OR public.is_admin()
  );

-- billiard_games
DROP POLICY IF EXISTS billiard_games_select ON public.billiard_games;
CREATE POLICY billiard_games_select ON public.billiard_games
  FOR SELECT USING (
    is_private = false
    OR host_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.billiard_participants p WHERE p.game_id = billiard_games.id AND p.user_id = auth.uid())
    OR public.is_admin()
  );

-- poker_games
DROP POLICY IF EXISTS poker_games_read ON public.poker_games;
CREATE POLICY poker_games_read ON public.poker_games
  FOR SELECT USING (
    is_private = false
    OR created_by = auth.uid()
    OR EXISTS (SELECT 1 FROM public.poker_players p WHERE p.game_id = poker_games.id AND p.user_id = auth.uid())
    OR public.is_admin()
  );

-- rami_games
DROP POLICY IF EXISTS "rami_games read all auth" ON public.rami_games;
CREATE POLICY rami_games_select ON public.rami_games
  FOR SELECT USING (
    is_private = false
    OR created_by = auth.uid()
    OR EXISTS (SELECT 1 FROM public.rami_participants p WHERE p.game_id = rami_games.id AND p.user_id = auth.uid())
    OR public.is_admin()
  );

-- Also fix: chess_moves, poker_players, rami_participants should only be visible for games the user can see
DROP POLICY IF EXISTS chess_moves_select ON public.chess_moves;
CREATE POLICY chess_moves_select ON public.chess_moves
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.chess_games g WHERE g.id = chess_moves.game_id
     AND (g.is_private = false OR g.host_id = auth.uid() OR g.white_id = auth.uid() OR g.black_id = auth.uid() OR public.is_admin()))
  );

DROP POLICY IF EXISTS poker_players_read ON public.poker_players;
CREATE POLICY poker_players_read ON public.poker_players
  FOR SELECT USING (
    user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.poker_games g WHERE g.id = poker_players.game_id
     AND (g.is_private = false OR g.created_by = auth.uid() OR public.is_admin()))
  );

DROP POLICY IF EXISTS "rami_participants read all auth" ON public.rami_participants;
CREATE POLICY rami_participants_select ON public.rami_participants
  FOR SELECT USING (
    user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.rami_games g WHERE g.id = rami_participants.game_id
     AND (g.is_private = false OR g.created_by = auth.uid() OR public.is_admin()))
  );
