-- Fix: infinite recursion in RLS policies between fanorona_games and fanorona_participants
-- The old policies referenced each other in subqueries, causing infinite recursion.
-- Solution: use a SECURITY DEFINER helper function that bypasses RLS to break the cycle.

-- Helper: check if current user is a participant of a fanorona game
CREATE OR REPLACE FUNCTION public._fanorona_is_player(_game_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
  SELECT EXISTS(
    SELECT 1 FROM public.fanorona_participants
    WHERE game_id = _game_id AND user_id = auth.uid()
  );
$$;

-- Replace recursive policy on fanorona_participants
DROP POLICY IF EXISTS "Participants: read own or game" ON public.fanorona_participants;
CREATE POLICY "Participants: read own or game" ON public.fanorona_participants
  FOR SELECT USING (
    user_id = auth.uid() OR public._fanorona_is_player(game_id)
  );

-- Replace recursive policy on fanorona_games
DROP POLICY IF EXISTS "Games: read participants or public" ON public.fanorona_games;
CREATE POLICY "Games: read participants or public" ON public.fanorona_games
  FOR SELECT USING (
    host_id = auth.uid()
    OR is_private = false
    OR public._fanorona_is_player(id)
  );

-- Replace fanorona_games_select to also use helper (avoids subquery on participants)
DROP POLICY IF EXISTS "fanorona_games_select" ON public.fanorona_games;
CREATE POLICY "fanorona_games_select" ON public.fanorona_games
  FOR SELECT USING (
    (status IN ('open', 'playing') AND is_private = false)
    OR host_id = auth.uid()
    OR public._fanorona_is_player(id)
    OR public.is_admin()
  );
