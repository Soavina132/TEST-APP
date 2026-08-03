
-- 1) chat_presence: restrict SELECT to own row or rows in rooms the viewer can access
DROP POLICY IF EXISTS chat_presence_select ON public.chat_presence;
CREATE POLICY chat_presence_select ON public.chat_presence
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_admin()
    OR (typing_room IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.chat_rooms r
      WHERE r.id = chat_presence.typing_room
        AND (
          r.type = 'global'
          OR (r.type = 'dm' AND (r.dm_user_a = auth.uid() OR r.dm_user_b = auth.uid()))
          OR (r.type = 'game' AND (
            public._is_game_participant(r.game_id, auth.uid())
            OR EXISTS (SELECT 1 FROM public.game_spectators s WHERE s.game_id = r.game_id AND s.user_id = auth.uid())
          ))
        )
    ))
    OR (current_game IS NOT NULL AND (
      public._is_game_participant(current_game, auth.uid())
      OR EXISTS (SELECT 1 FROM public.game_spectators s WHERE s.game_id = chat_presence.current_game AND s.user_id = auth.uid())
    ))
  );

-- 2) Hide internal engine field dice_override from clients
REVOKE SELECT (dice_override) ON public.ludo_games FROM anon, authenticated;

-- 3) Hide bot tuning fields from clients (admins use RPC below)
REVOKE SELECT (bot_intelligence, bot_win_bias) ON public.ludo_participants FROM anon, authenticated;

-- Admin RPC to fetch bot tuning for a participant
CREATE OR REPLACE FUNCTION public.admin_get_bot_config(_participant_id uuid)
RETURNS TABLE(intelligence int, win_bias int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  RETURN QUERY
    SELECT bot_intelligence, bot_win_bias
    FROM public.ludo_participants
    WHERE id = _participant_id AND is_bot = true;
END $$;

REVOKE EXECUTE ON FUNCTION public.admin_get_bot_config(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_bot_config(uuid) TO authenticated;
