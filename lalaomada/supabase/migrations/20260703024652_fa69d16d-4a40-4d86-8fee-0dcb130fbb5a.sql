-- Add is_premium column to profiles for gating premium features
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_premium boolean NOT NULL DEFAULT false;

GRANT UPDATE (is_premium) ON public.profiles TO service_role;

DROP POLICY IF EXISTS "profiles_premium_admin_update" ON public.profiles;
CREATE POLICY "profiles_premium_admin_update"
  ON public.profiles
  FOR UPDATE
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- === Notifications table (required by many pending migrations) ===
CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  kind text NOT NULL DEFAULT 'info',
  type text,
  title text NOT NULL,
  body text,
  link text,
  ref_id uuid,
  read boolean NOT NULL DEFAULT false,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS notifications_user_unread ON public.notifications(user_id, read, created_at DESC);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notifications TO authenticated;
GRANT ALL ON public.notifications TO service_role;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "notif_read_own" ON public.notifications;
CREATE POLICY "notif_read_own" ON public.notifications
  FOR SELECT TO authenticated USING (user_id = auth.uid());
DROP POLICY IF EXISTS "notif_update_own" ON public.notifications;
CREATE POLICY "notif_update_own" ON public.notifications
  FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS "notif_delete_own" ON public.notifications;
CREATE POLICY "notif_delete_own" ON public.notifications
  FOR DELETE TO authenticated USING (user_id = auth.uid());

-- mark_notif_read: mark one or all notifs as read
CREATE OR REPLACE FUNCTION public.mark_notif_read(_id UUID DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF _id IS NULL THEN
    UPDATE public.notifications
      SET read = TRUE, read_at = now()
      WHERE user_id = auth.uid() AND read = FALSE;
  ELSE
    UPDATE public.notifications
      SET read = TRUE, read_at = now()
      WHERE id = _id AND user_id = auth.uid();
  END IF;
END; $$;
REVOKE ALL ON FUNCTION public.mark_notif_read(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_notif_read(UUID) TO authenticated;