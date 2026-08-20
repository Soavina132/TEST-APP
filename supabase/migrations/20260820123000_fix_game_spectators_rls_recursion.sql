-- Fix: infinite recursion in game_spectators RLS policy
--
-- Problem: spectators_select_own policy had EXISTS (SELECT 1 FROM game_spectators s WHERE ...)
-- which self-references game_spectators, causing infinite recursion when:
--   chat_messages SELECT → chat_rooms RLS → game_spectators (in EXISTS) → game_spectators RLS → RECURSION
--
-- This made ALL chat_messages SELECT queries fail with error:
--   "infinite recursion detected in policy for relation game_spectators"
--   → loadMessages() returned empty → chat appeared empty (no old messages)
--
-- Fix: Replace the self-referencing EXISTS with a SECURITY DEFINER function
--   _is_spectator() that bypasses RLS, breaking the recursion chain.

CREATE OR REPLACE FUNCTION public._is_spectator(p_game_id uuid, p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (SELECT 1 FROM public.game_spectators WHERE game_id = p_game_id AND user_id = p_user_id);
$$;

DROP POLICY IF EXISTS spectators_select_own ON public.game_spectators;
CREATE POLICY spectators_select_own ON public.game_spectators
FOR SELECT TO authenticated
USING ((user_id = auth.uid()) OR _is_spectator(game_id, auth.uid()) OR is_admin());
