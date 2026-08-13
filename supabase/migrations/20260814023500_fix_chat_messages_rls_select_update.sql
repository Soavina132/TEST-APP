-- ============================================================
-- FIX CRITICAL BUG: chat_messages had ONLY an INSERT RLS policy.
-- With RLS enabled and no SELECT policy, users could send messages
-- via chat_send() RPC (SECURITY DEFINER, bypasses RLS) but could
-- NEVER read them back (.select("*") + realtime both denied by RLS).
-- This made the chat look "broken" — messages vanish after sending.
--
-- Also missing: UPDATE policy, needed for edit/delete-own-message
-- and the "report message" feature (direct .update() calls from
-- the frontend, no RPC).
--
-- Mirrors the exact room-membership logic already used by the
-- working chat_reactions_select policy and the chat_send() RPC.
-- ============================================================

CREATE POLICY chat_messages_select ON public.chat_messages
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.chat_rooms r
    WHERE r.id = chat_messages.room_id
    AND (
      r.type = 'global'
      OR (r.type = 'dm' AND (r.dm_user_a = auth.uid() OR r.dm_user_b = auth.uid()))
      OR (r.type = 'game' AND (
            public._is_game_participant(r.game_id, auth.uid())
            OR EXISTS (SELECT 1 FROM public.game_spectators s WHERE s.game_id = r.game_id AND s.user_id = auth.uid())
          ))
      OR public.is_admin()
    )
  )
);

CREATE POLICY chat_messages_update ON public.chat_messages
FOR UPDATE TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.chat_rooms r
    WHERE r.id = chat_messages.room_id
    AND (
      r.type = 'global'
      OR (r.type = 'dm' AND (r.dm_user_a = auth.uid() OR r.dm_user_b = auth.uid()))
      OR (r.type = 'game' AND (
            public._is_game_participant(r.game_id, auth.uid())
            OR EXISTS (SELECT 1 FROM public.game_spectators s WHERE s.game_id = r.game_id AND s.user_id = auth.uid())
          ))
      OR public.is_admin()
    )
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.chat_rooms r
    WHERE r.id = chat_messages.room_id
    AND (
      r.type = 'global'
      OR (r.type = 'dm' AND (r.dm_user_a = auth.uid() OR r.dm_user_b = auth.uid()))
      OR (r.type = 'game' AND (
            public._is_game_participant(r.game_id, auth.uid())
            OR EXISTS (SELECT 1 FROM public.game_spectators s WHERE s.game_id = r.game_id AND s.user_id = auth.uid())
          ))
      OR public.is_admin()
    )
  )
);
