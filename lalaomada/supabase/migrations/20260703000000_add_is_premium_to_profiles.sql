-- Add is_premium column to profiles for gating premium features (e.g. DM chat)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_premium boolean NOT NULL DEFAULT false;

-- Allow admins (service_role) to set the flag
GRANT UPDATE (is_premium) ON public.profiles TO service_role;

-- RLS: anyone can read their own is_premium; only admin can update
CREATE POLICY "profiles_premium_admin_update"
  ON public.profiles
  FOR UPDATE
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());
