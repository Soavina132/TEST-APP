
-- 1) Tighten chat_members SELECT: users see only rooms they belong to (or admin)
DROP POLICY IF EXISTS chat_members_read ON public.chat_members;
CREATE POLICY chat_members_read ON public.chat_members
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_admin()
    OR EXISTS (SELECT 1 FROM public.chat_members m
               WHERE m.room_id = chat_members.room_id AND m.user_id = auth.uid())
  );

-- 2) Require membership / room access to insert chat messages directly
DROP POLICY IF EXISTS chat_messages_insert ON public.chat_messages;
CREATE POLICY chat_messages_insert ON public.chat_messages
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.chat_rooms r
      WHERE r.id = chat_messages.room_id AND r.enabled = true AND (
        r.type = 'global'
        OR (r.type = 'dm' AND (r.dm_user_a = auth.uid() OR r.dm_user_b = auth.uid()))
        OR (r.type = 'game' AND (
              public._is_game_participant(r.game_id, auth.uid())
              OR EXISTS (SELECT 1 FROM public.game_spectators s
                         WHERE s.game_id = r.game_id AND s.user_id = auth.uid())
           ))
        OR public.is_admin()
      )
    )
  );

-- 3) Lock down realtime.messages (broadcast/presence). The app only uses
--    postgres_changes (governed by each table's RLS), so denying direct
--    broadcast subscriptions is safe and prevents cross-user topic snooping.
ALTER TABLE realtime.messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS realtime_messages_admin_only ON realtime.messages;
CREATE POLICY realtime_messages_admin_only ON realtime.messages
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());
