-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Secure 2FA: move totp_secret to a restricted table + server-side verify
-- 2. Prepare for Google OAuth: ensure handle_new_user supports OAuth users
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Create restricted table for TOTP secrets ──────────────────────────
-- Only service-role / SECURITY DEFINER functions can read this.
-- Regular users CANNOT select from this table (no RLS SELECT policy).
CREATE TABLE IF NOT EXISTS public.user_totp_secrets (
  user_id    uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  totp_secret text NOT NULL,
  enabled     boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- Enable RLS — no SELECT/INSERT/UPDATE/DELETE policies for authenticated users
ALTER TABLE public.user_totp_secrets ENABLE ROW LEVEL SECURITY;

-- Only service role can access directly
REVOKE ALL ON public.user_totp_secrets FROM authenticated, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_totp_secrets TO service_role;

-- ── 2. RPC: Store TOTP secret (called from securite page via service-role edge fn) ──
CREATE OR REPLACE FUNCTION public.set_totp_secret(_secret text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.user_totp_secrets (user_id, totp_secret, enabled)
    VALUES (auth.uid(), _secret, true)
    ON CONFLICT (user_id) DO UPDATE
      SET totp_secret = EXCLUDED.totp_secret, enabled = true;
  -- Also set the flag on profiles (for client to know 2FA is on)
  UPDATE public.profiles SET two_factor_enabled = true WHERE id = auth.uid();
END $$;
REVOKE ALL ON FUNCTION public.set_totp_secret(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_totp_secret(text) TO authenticated;

-- ── 3. RPC: Disable 2FA ──
CREATE OR REPLACE FUNCTION public.disable_totp()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  DELETE FROM public.user_totp_secrets WHERE user_id = auth.uid();
  UPDATE public.profiles SET two_factor_enabled = false WHERE id = auth.uid();
END $$;
REVOKE ALL ON FUNCTION public.disable_totp() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.disable_totp() TO authenticated;

-- ── 4. RPC: Check if user has 2FA enabled (no secret returned!) ──
CREATE OR REPLACE FUNCTION public.check_2fa_status()
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _enabled boolean;
BEGIN
  SELECT enabled INTO _enabled FROM public.user_totp_secrets WHERE user_id = auth.uid();
  RETURN COALESCE(_enabled, false);
END $$;
REVOKE ALL ON FUNCTION public.check_2fa_status() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_2fa_status() TO authenticated;

-- ── 5. Remove totp_secret from profiles (keep two_factor_enabled as flag) ──
-- Migration is non-destructive: copy existing secrets first
INSERT INTO public.user_totp_secrets (user_id, totp_secret, enabled)
  SELECT id, totp_secret, true FROM public.profiles
  WHERE totp_secret IS NOT NULL AND two_factor_enabled = true
  ON CONFLICT (user_id) DO NOTHING;

-- Drop the column so clients can never read the secret
ALTER TABLE public.profiles DROP COLUMN IF EXISTS totp_secret;

-- ── 6. Update handle_new_user for Google OAuth ────────────────────────────
-- Google users have no password and no pseudo — derive a pseudo from email
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_pseudo TEXT;
  v_ref_code TEXT;
  v_referred_by UUID;
  v_input_ref TEXT;
  v_bonus NUMERIC;
  v_unique TEXT;
  v_email TEXT;
  v_provider TEXT;
BEGIN
  v_email := COALESCE(NEW.email, '');
  v_provider := COALESCE(NEW.raw_app_meta_data->>'provider', NEW.raw_user_meta_data->>'provider', '');

  -- For OAuth users, use name from metadata or derive from email
  IF v_provider = 'google' THEN
    v_pseudo := COALESCE(
      NEW.raw_user_meta_data->>'full_name',
      NEW.raw_user_meta_data->>'name',
      split_part(v_email, '@', 1)
    );
  ELSE
    v_pseudo := COALESCE(NEW.raw_user_meta_data->>'pseudo', split_part(v_email, '@', 1));
  END IF;

  -- Ensure pseudo uniqueness
  IF EXISTS (SELECT 1 FROM public.profiles WHERE lower(pseudo) = lower(v_pseudo)) THEN
    v_pseudo := v_pseudo || '_' || substr(encode(gen_random_bytes(3), 'hex'), 1, 6);
  END IF;

  v_input_ref := NEW.raw_user_meta_data->>'referral_code';
  v_ref_code := public.gen_referral_code();
  v_unique := public.gen_unique_code();

  IF v_input_ref IS NOT NULL AND v_input_ref <> '' THEN
    SELECT id INTO v_referred_by FROM public.profiles WHERE referral_code = upper(v_input_ref);
  END IF;

  SELECT signup_bonus INTO v_bonus FROM public.app_settings WHERE id = 1;

  INSERT INTO public.profiles(id, pseudo, email, referral_code, referred_by, balance_ar, unique_code)
  VALUES (NEW.id, v_pseudo, v_email, v_ref_code, v_referred_by, COALESCE(v_bonus,0), v_unique);

  IF COALESCE(v_bonus,0) > 0 THEN
    INSERT INTO public.transactions(user_id,type,amount,note) VALUES (NEW.id,'bonus',v_bonus,'Bonus inscription');
  END IF;

  IF lower(v_email) = 'soavinapierrit@gmail.com' THEN
    INSERT INTO public.user_roles(user_id, role) VALUES (NEW.id, 'admin') ON CONFLICT DO NOTHING;
  ELSE
    INSERT INTO public.user_roles(user_id, role) VALUES (NEW.id, 'user') ON CONFLICT DO NOTHING;
  END IF;

  RETURN NEW;
END $$;
