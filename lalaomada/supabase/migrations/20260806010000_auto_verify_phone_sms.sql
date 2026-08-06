-- Auto-verify phone from SMS received by Termux
-- Termux script reads incoming SMS, extracts code (LMxxxxxx = LM + 6 digits),
-- calls this function which checks if the code matches a pending verification.
-- If match: marks phone as verified.

CREATE OR REPLACE FUNCTION public.request_phone_verification(_phone text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_code text; v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _phone IS NULL OR length(trim(_phone))<8 THEN RAISE EXCEPTION 'Numéro invalide'; END IF;
  IF EXISTS (SELECT 1 FROM public.profiles WHERE phone=_phone AND phone_verified=true AND id<>v_uid) THEN
    RAISE EXCEPTION 'Numéro déjà utilisé';
  END IF;
  v_code := 'LM' || lpad((floor(random()*1000000))::int::text, 6, '0');
  UPDATE public.profiles
    SET phone = _phone, phone_verified = false,
        phone_verification_code = v_code,
        phone_verification_requested_at = now()
    WHERE id = v_uid;
  RETURN v_code;
END $$;

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
  
  -- Pattern: LMxxxxxx (LM + 6 digits)
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
      AND phone_verification_requested_at > now() - interval '30 minutes'
    LIMIT 1;
  
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'No pending verification matches code: ' || v_code);
  END IF;
  
  UPDATE public.profiles
    SET phone_verified = true,
        phone_verification_code = NULL,
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
