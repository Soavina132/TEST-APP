-- Simplify phone verification: no expiration + normalize phone numbers
-- Handles formats: +261341234567, 261341234567, 0341234567, 341234567
-- All normalized to 0XXXXXXXX (10 digits starting with 0)

-- ── 1. Normalisation des numéros de téléphone ──
CREATE OR REPLACE FUNCTION public.normalize_phone(_phone text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE v text;
BEGIN
  v := btrim(_phone);
  v := regexp_replace(v, '[\s\-\(\)\.]', '', 'g');
  
  IF v ~* '^\+261' THEN
    v := '0' || substring(v from 5);
  ELSIF v ~* '^261' AND length(v) >= 11 THEN
    v := '0' || substring(v from 4);
  ELSIF v ~* '^[234]' AND length(v) = 9 THEN
    v := '0' || v;
  END IF;
  
  IF v !~* '^0[0-9]{9}$' THEN
    RETURN NULL;
  END IF;
  
  RETURN v;
END $function$;

-- ── 2. request_phone_verification — avec normalisation ──
CREATE OR REPLACE FUNCTION public.request_phone_verification(_phone text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE v_uid uuid := auth.uid(); v_code text; v_phone text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  
  v_phone := public.normalize_phone(_phone);
  IF v_phone IS NULL THEN RAISE EXCEPTION 'Numero invalide'; END IF;
  
  IF EXISTS (SELECT 1 FROM public.profiles 
             WHERE phone = v_phone AND phone_verified = true AND id <> v_uid) THEN
    RAISE EXCEPTION 'Numero deja utilise';
  END IF;
  
  v_code := 'LM' || lpad((floor(random()*1000000))::int::text, 6, '0');
  
  UPDATE public.profiles
    SET phone = v_phone,
        phone_verified = false,
        phone_verification_code = v_code,
        phone_verification_code_hash = encode(extensions.digest(v_code || id::text, 'sha256'), 'hex'),
        phone_verification_requested_at = now()
    WHERE id = v_uid;
  
  RETURN v_code;
END $function$;

-- ── 3. get_pending_phone_verification — sans expiration ──
CREATE OR REPLACE FUNCTION public.get_pending_phone_verification()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE v_uid uuid := auth.uid();
  v_phone text; v_code text; v_requested timestamptz;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifie'; END IF;
  
  SELECT phone, phone_verification_code, phone_verification_requested_at
    INTO v_phone, v_code, v_requested
    FROM public.profiles WHERE id = v_uid;
  
  IF v_code IS NULL THEN
    RETURN jsonb_build_object('pending', false);
  END IF;
  
  RETURN jsonb_build_object(
    'pending', true,
    'phone', v_phone,
    'code', v_code,
    'requested_at', to_char(v_requested AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  );
END $function$;

-- ── 4. auto_verify_phone_by_sms — sans expiration ──
CREATE OR REPLACE FUNCTION public.auto_verify_phone_by_sms(_sender_phone text, _sms_body text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_code text;
  v_user_id uuid;
  v_user_phone text;
BEGIN
  v_code := NULL;
  
  IF _sms_body ~* 'LM[0-9]{6}' THEN
    v_code := substring(_sms_body from 'LM[0-9]{6}');
  END IF;
  
  IF v_code IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'No verification code found in SMS');
  END IF;
  
  SELECT id, phone INTO v_user_id, v_user_phone
    FROM public.profiles
    WHERE phone_verification_code = v_code
      AND phone_verified = false
    LIMIT 1;
  
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Code non trouve ou deja utilise');
  END IF;
  
  UPDATE public.profiles
    SET phone_verified = true,
        phone_verification_code = NULL,
        phone_verification_code_hash = NULL,
        phone_verification_requested_at = NULL
    WHERE id = v_user_id;
  
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Phone verified successfully',
    'user_id', v_user_id,
    'phone', v_user_phone,
    'code', v_code
  );
END $function$;

REVOKE EXECUTE ON FUNCTION public.auto_verify_phone_by_sms(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.auto_verify_phone_by_sms(text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.normalize_phone(text) TO authenticated, service_role, anon;
