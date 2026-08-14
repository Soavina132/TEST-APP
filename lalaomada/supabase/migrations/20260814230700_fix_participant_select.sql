-- Fix participant tables that had SELECT qual=true (visible to everyone)
DROP POLICY IF EXISTS billiard_participants_select ON public.billiard_participants;
CREATE POLICY billiard_participants_select ON public.billiard_participants
  FOR SELECT USING (
    user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.billiard_games g WHERE g.id = billiard_participants.game_id
     AND (g.is_private = false OR g.host_id = auth.uid() OR public.is_admin()))
  );

DROP POLICY IF EXISTS domino_participants_select ON public.domino_participants;
CREATE POLICY domino_participants_select ON public.domino_participants
  FOR SELECT USING (
    user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.domino_games g WHERE g.id = domino_participants.game_id
     AND (g.is_private = false OR g.host_id = auth.uid() OR public.is_admin()))
  );

-- poker_hand_history was also visible to all
DROP POLICY IF EXISTS poker_hand_history_read_all ON public.poker_hand_history;
CREATE POLICY poker_hand_history_read ON public.poker_hand_history
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.poker_games g WHERE g.id = poker_hand_history.game_id
     AND (g.is_private = false OR g.created_by = auth.uid() OR public.is_admin()))
  );

-- player_game_stats was visible to all — restrict to own or admin
DROP POLICY IF EXISTS pgstats_select ON public.player_game_stats;
DROP POLICY IF EXISTS player_achievements_read_all ON public.player_achievements;
DROP POLICY IF EXISTS player_achievements_own ON public.player_achievements;
CREATE POLICY pgstats_select ON public.player_game_stats
  FOR SELECT USING (user_id = auth.uid() OR public.is_admin());
CREATE POLICY player_achievements_select ON public.player_achievements
  FOR SELECT USING (user_id = auth.uid() OR public.is_admin());
