-- ═══════════════════════════════════════════════════════════════════════
-- FIX: Vérification téléphone — persistance + expiration 10 min + auto-verify
--
-- PROBLÈMES:
--   1. Le code de vérification est perdu après refresh de la page
--   2. Le code n'a pas de limite de temps claire (30 min avant)
--   3. auto_verify_phone_by_sms ne vérifie pas le numéro de l'expéditeur
--   4. L'utilisateur ne voit pas le statut "en attente" dans les paramètres
--
-- FIX:
--   1. Nouvelle fonction get_pending_phone_verification() — retourne le code
--      et l'expiration pour le user actuel (permet au frontend de restaurer)
--   2. Expiration réduite à 10 minutes
--   3. auto_verify_phone_by_sms vérifie maintenant que le numéro de l'expéditeur
--      correspond au numéro enregistré (comparaison des 8 derniers chiffres)
--   4. Le frontend interroge get_pending_phone_verification au montage
-- ═══════════════════════════════════════════════════════════════════════

-- 1. request_phone_verification: inchangé (génère LMxxxxxx)
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

-- 2. NOUVELLE fonction: get_pending_phone_verification
CREATE OR REPLACE FUNCTION public.get_pending_phone_verification()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_uid uuid := auth.uid();
  v_phone text; v_code text; v_requested timestamptz;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  
  SELECT phone, phone_verification_code, phone_verification_requested_at
    INTO v_phone, v_code, v_requested
    FROM public.profiles WHERE id = v_uid;
  
  IF v_code IS NULL THEN
    RETURN jsonb_build_object('pending', false);
  END IF;
  
  -- Expiration: 10 minutes
  IF v_requested IS NULL OR v_requested < now() - interval '10 minutes' THEN
    UPDATE public.profiles 
      SET phone_verification_code = NULL, phone_verification_requested_at = NULL
      WHERE id = v_uid AND phone_verified = false;
    RETURN jsonb_build_object('pending', false, 'expired', true);
  END IF;
  
  RETURN jsonb_build_object(
    'pending', true,
    'phone', v_phone,
    'code', v_code,
    'requested_at', to_char(v_requested AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'expires_at', to_char((v_requested + interval '10 minutes') AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  );
END $$;

GRANT EXECUTE ON FUNCTION public.get_pending_phone_verification() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.get_pending_phone_verification() FROM anon;

-- 3. auto_verify_phone_by_sms: vérifier AUSSI le numéro de l'expéditeur
CREATE OR REPLACE FUNCTION public.auto_verify_phone_by_sms(_sender_phone text, _sms_body text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_code text;
  v_user_id uuid;
  v_user_phone text;
  v_clean_sender text;
  v_clean_user_phone text;
BEGIN
  v_code := NULL;
  
  IF _sms_body ~* 'LM[0-9]{6}' THEN
    v_code := substring(_sms_body from 'LM[0-9]{6}');
  END IF;
  
  IF v_code IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'No verification code found in SMS');
  END IF;
  
  v_clean_sender := regexp_replace(_sender_phone, '[\s+\-()]', '', 'g');
  
  SELECT id, phone INTO v_user_id, v_user_phone
    FROM public.profiles
    WHERE phone_verification_code = v_code
      AND phone_verified = false
      AND phone_verification_requested_at > now() - interval '10 minutes'
    LIMIT 1;
  
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'No pending verification matches code: ' || v_code);
  END IF;
  
  -- Vérifier que le numéro de l'expéditeur correspond au numéro enregistré
  v_clean_user_phone := regexp_replace(v_user_phone, '[\s+\-()]', '', 'g');
  
  IF length(v_clean_sender) >= 8 AND length(v_clean_user_phone) >= 8 THEN
    IF right(v_clean_sender, 8) <> right(v_clean_user_phone, 8) THEN
      RETURN jsonb_build_object(
        'success', false, 
        'message', 'Sender phone does not match registered phone',
        'sender', v_clean_sender,
        'registered', v_clean_user_phone
      );
    END IF;
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
END $$;

REVOKE EXECUTE ON FUNCTION public.auto_verify_phone_by_sms(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.auto_verify_phone_by_sms(text, text) TO authenticated, service_role;
