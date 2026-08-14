-- Migration: Fix missing check_2fa_status + ensure verify_2fa_code functions
-- Date: 2026-08-14
-- These functions were defined in migration 20260809140000 but never applied to DB

CREATE OR REPLACE FUNCTION public.check_2fa_status()
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _enabled boolean;
BEGIN
  SELECT enabled INTO _enabled FROM public.user_totp_secrets WHERE user_id = auth.uid();
  RETURN COALESCE(_enabled, false);
END $$;
REVOKE ALL ON FUNCTION public.check_2fa_status() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_2fa_status() TO authenticated;

-- verify_2fa_code: verify a TOTP code against the stored secret
CREATE OR REPLACE FUNCTION public.verify_2fa_code(_code text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  _secret text;
  _expected text;
  _window int := 0;
  _time bigint;
BEGIN
  SELECT secret INTO _secret FROM public.user_totp_secrets WHERE user_id = auth.uid() AND enabled = true;
  IF _secret IS NULL THEN RETURN false; END IF;

  -- Simple TOTP verification using HMAC
  -- Current time step (30 second window)
  _time := extract(epoch from now())::bigint / 30;

  -- Check current window and ±1 window
  FOR _window IN -1..1 LOOP
    _expected := extensions.generate_totp(_secret, _time + _window, 6, 'sha1');
    IF _code = _expected THEN
      RETURN true;
    END IF;
  END LOOP;

  RETURN false;
END $$;
REVOKE ALL ON FUNCTION public.verify_2fa_code(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.verify_2fa_code(text) TO authenticated;
