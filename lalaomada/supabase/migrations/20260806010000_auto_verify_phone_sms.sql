-- Auto-verify phone from SMS received by Termux
-- Termux script reads incoming SMS, extracts code, calls this function
-- This function checks if the code matches a pending verification
-- If match: marks phone as verified

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
  v_match boolean := false;
BEGIN
  -- Extract code from SMS body (format: LMxxxx or just the code)
  -- Try to find LM followed by 4 digits, or any 4-6 char alphanumeric code
  v_code := NULL;
  
  -- Pattern 1: LMxxxx (LM + 4 digits)
  IF _sms_body ~* 'LM[0-9]{4}' THEN
    v_code := substring(_sms_body from 'LM[0-9]{4}');
  END IF;
  
  -- If no code found, return error
  IF v_code IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'No verification code found in SMS');
  END IF;
  
  -- Find the pending verification matching this code
  SELECT id, phone INTO v_user_id, v_user_phone
    FROM public.profiles
    WHERE phone_verification_code = v_code
      AND phone_verified = false
      AND phone_verification_requested_at > now() - interval '30 minutes'
    LIMIT 1;
  
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'No pending verification matches code: ' || v_code);
  END IF;
  
  -- Verify the phone
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

-- Grant execute to authenticated (Termux will use service_role key via REST)
REVOKE EXECUTE ON FUNCTION public.auto_verify_phone_by_sms(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.auto_verify_phone_by_sms(text, text) TO authenticated, service_role;
