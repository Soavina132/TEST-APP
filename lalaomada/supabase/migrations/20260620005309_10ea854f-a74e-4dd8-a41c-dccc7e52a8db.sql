
-- Add help texts and password reset requests
ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS signup_help_html text DEFAULT '<p>Pour créer un compte sur Lalao MADA : choisissez un pseudo, entrez votre e-mail et un mot de passe. Validez ensuite votre numéro de téléphone dans votre profil pour pouvoir jouer aux parties payantes.</p>',
  ADD COLUMN IF NOT EXISTS password_reset_help_html text DEFAULT '<p>Entrez l''adresse e-mail ou le numéro de téléphone de votre compte. L''admin vous contactera avec un code de réinitialisation par SMS, WhatsApp ou e-mail.</p>';

CREATE TABLE IF NOT EXISTS public.password_reset_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contact text NOT NULL,
  contact_type text NOT NULL CHECK (contact_type IN ('email','phone')),
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  code text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','sent','done','rejected')),
  admin_note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz
);

GRANT SELECT, INSERT, UPDATE ON public.password_reset_requests TO authenticated;
GRANT SELECT, INSERT ON public.password_reset_requests TO anon;
GRANT ALL ON public.password_reset_requests TO service_role;

ALTER TABLE public.password_reset_requests ENABLE ROW LEVEL SECURITY;

-- Anyone (incl. anon) can submit a reset request
CREATE POLICY "prr_insert_any" ON public.password_reset_requests
  FOR INSERT TO anon, authenticated
  WITH CHECK (length(contact) BETWEEN 3 AND 200);

-- Only admin can read/update
CREATE POLICY "prr_admin_read" ON public.password_reset_requests
  FOR SELECT TO authenticated
  USING (is_admin());

CREATE POLICY "prr_admin_update" ON public.password_reset_requests
  FOR UPDATE TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());

CREATE OR REPLACE FUNCTION public._prr_touch() RETURNS trigger AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END $$ LANGUAGE plpgsql SET search_path = public;

DROP TRIGGER IF EXISTS prr_touch ON public.password_reset_requests;
CREATE TRIGGER prr_touch BEFORE UPDATE ON public.password_reset_requests
  FOR EACH ROW EXECUTE FUNCTION public._prr_touch();
