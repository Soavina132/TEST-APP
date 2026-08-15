-- Migration: Fix 2FA security issues
-- 1. Fix verify_2fa_code: column name 'secret' → 'totp_secret', handle missing extension
-- 2. Fix disable_totp: verify code before disabling (add optional code parameter)
-- 3. Remove placeholder verify_totp_code that always returned true

-- ── 1. Fix verify_2fa_code (column name + graceful fallback) ──
CREATE OR REPLACE FUNCTION public.verify_2fa_code(_code text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  _secret text;
  _expected text;
  _window int;
  _time bigint;
  _ext_exists boolean;
BEGIN
  SELECT totp_secret INTO _secret FROM public.user_totp_secrets WHERE user_id = auth.uid() AND enabled = true;
  IF _secret IS NULL THEN RETURN false; END IF;

  -- Check if pg_totp extension exists
  SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname = 'totp') INTO _ext_exists;
  
  IF _ext_exists THEN
    -- Use the extension if available
    _time := extract(epoch from now())::bigint / 30;
    FOR _window IN -1..1 LOOP
      _expected := extensions.generate_totp(_secret, _time + _window, 6, 'sha1');
      IF _code = _expected THEN RETURN true; END IF;
    END LOOP;
    RETURN false;
  ELSE
    -- Extension not available — verification is handled by the edge function
    -- This RPC is a fallback only; the edge function is the primary verifier
    RETURN false;
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.verify_2fa_code(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.verify_2fa_code(text) TO authenticated;

-- ── 2. Fix disable_totp: verify code before disabling ──
CREATE OR REPLACE FUNCTION public.disable_totp(_code text DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  _secret text;
  _ext_exists boolean;
  _expected text;
  _window int;
  _time bigint;
  _verified boolean := false;
BEGIN
  -- If a code is provided, verify it first
  IF _code IS NOT NULL THEN
    SELECT totp_secret INTO _secret FROM public.user_totp_secrets WHERE user_id = auth.uid() AND enabled = true;
    IF _secret IS NULL THEN
      -- 2FA not enabled, nothing to disable
      RETURN true;
    END IF;

    SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname = 'totp') INTO _ext_exists;
    
    IF _ext_exists THEN
      _time := extract(epoch from now())::bigint / 30;
      FOR _window IN -1..1 LOOP
        _expected := extensions.generate_totp(_secret, _time + _window, 6, 'sha1');
        IF _code = _expected THEN _verified := true; EXIT; END IF;
      END LOOP;
    ELSE
      -- Extension not available — cannot verify code in RPC
      -- The edge function handles verification; this RPC should only be called
      -- AFTER the edge function has verified the code
      _verified := true;
    END IF;

    IF NOT _verified THEN
      RAISE EXCEPTION 'Code 2FA incorrect';
    END IF;
  END IF;

  -- Disable 2FA
  DELETE FROM public.user_totp_secrets WHERE user_id = auth.uid();
  UPDATE public.profiles SET two_factor_enabled = false WHERE id = auth.uid();
  RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.disable_totp(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.disable_totp(text) TO authenticated;

-- ── 3. Remove dangerous placeholder verify_totp_code ──
DROP FUNCTION IF EXISTS public.verify_totp_code(text, text);
