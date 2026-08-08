-- Google Authenticator (TOTP 2FA) support
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS totp_secret text,
  ADD COLUMN IF NOT EXISTS two_factor_enabled boolean NOT NULL DEFAULT false;
