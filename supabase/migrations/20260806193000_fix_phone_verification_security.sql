-- ═══════════════════════════════════════════════════════════════════════
-- FIX SÉCURITÉ — Vérification téléphone
--
-- Bugs corrigés :
--   1. CRITIQUE : auto_verify_phone_by_sms accessible à authenticated
--      → Bypass complet : un user peut s'auto-vérifier sans envoyer de SMS
--      FIX : REVOKE authenticated, garder service_role uniquement
--   2. CRITIQUE : request_phone_verification stocke le code en clair
--      → La migration 20260605073230 avait ajouté un hash SHA-256
--        mais 20260806010000 l'a écrasé en stockant uniquement en clair
--      FIX : Restaurer le hash + garder le code en clair pour auto_verify
--        (auto_verify a besoin du clair pour matcher les SMS entrants)
--   3. MOYEN : auto_verify_phone_by_sms ne valide pas le numéro expéditeur
--      → Le paramètre _sender_phone est reçu mais jamais utilisé
--      FIX : Vérifier que _sender_phone correspond au phone du user
--   4. MOYEN : Pas de rate limiting sur request_phone_verification
--      FIX : Max 1 demande par 5 minutes par utilisateur
--   5. MOYEN : verify_phone_code cassé (hash toujours NULL)
--      FIX : Restaurer le hash dans request_phone_verification
-- ═══════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════
-- BUG 1 (CRITIQUE) : REVOKE authenticated sur auto_verify_phone_by_sms
-- Seul service_role (Termux script) doit pouvoir appeler cette fonction.
-- ═══════════════════════════════════════════════════════════════════════
REVOKE EXECUTE ON FUNCTION public.auto_verify_phone_by_sms(text, text) FROM authenticated;
-- service_role garde l'accès (déjà accordé par la migration précédente)

-- ═══════════════════════════════════════════════════════════════════════
-- BUG 2+5 (CRITIQUE) : request_phone_verification — restaurer le hash
-- ET ajouter rate limiting (BUG 4)
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.request_phone_verification(_phone text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_code text;
  v_last_req timestamptz;
  v_existing_phone text;
  v_existing_verified boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _phone IS NULL OR length(trim(_phone)) < 8 THEN
    RAISE EXCEPTION 'Numéro invalide';
  END IF;

  -- BUG 4 FIX: Rate limiting — max 1 demande par 5 minutes
  SELECT phone_verification_requested_at INTO v_last_req
    FROM public.profiles WHERE id = v_uid;
  IF v_last_req IS NOT NULL AND now() - v_last_req < interval '5 minutes' THEN
    RAISE EXCEPTION 'Trop de demandes. Attendez 5 minutes entre chaque demande.';
  END IF;

  -- Vérifier que le numéro n'est pas déjà utilisé par un autre user vérifié
  SELECT phone, phone_verified INTO v_existing_phone, v_existing_verified
    FROM public.profiles WHERE phone = _phone AND phone_verified = true AND id <> v_uid
    LIMIT 1;
  IF v_existing_phone IS NOT NULL AND v_existing_verified THEN
    RAISE EXCEPTION 'Numéro déjà utilisé';
  END IF;

  -- Générer le code au format LMxxxxxx (6 chiffres aléatoires)
  v_code := 'LM' || lpad((floor(random()*1000000))::int::text, 6, '0');

  -- BUG 2 FIX: Stocker le code en clair (pour auto_verify) ET en hash (pour verify_phone_code)
  UPDATE public.profiles
    SET phone = _phone,
        phone_verified = false,
        phone_verification_code = v_code,
        phone_verification_code_hash = encode(extensions.digest(v_code || id::text, 'sha256'), 'hex'),
        phone_verification_requested_at = now()
    WHERE id = v_uid;

  RETURN v_code;
END $function$;

REVOKE EXECUTE ON FUNCTION public.request_phone_verification(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.request_phone_verification(text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- BUG 3 (MOYEN) : auto_verify_phone_by_sms — valider le numéro expéditeur
-- Le paramètre _sender_phone doit correspondre au phone enregistré du user.
-- ═══════════════════════════════════════════════════════════════════════
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
    RETURN jsonb_build_object('success', false, 'message', 'No pending verification matches code');
  END IF;

  -- BUG 3 FIX: Valider que le numéro expéditeur correspond au phone du user
  -- (on nettoie les deux numéros pour comparer : on garde les chiffres uniquement)
  IF _sender_phone IS NOT NULL AND v_user_phone IS NOT NULL THEN
    DECLARE
      v_sender_digits text := regexp_replace(_sender_phone, '[^0-9]', '', 'g');
      v_user_digits text := regexp_replace(v_user_phone, '[^0-9]', '', 'g');
    BEGIN
      -- Accepte si le numéro expéditeur correspond (ou si l'un est suffixe de l'autre
      -- pour gérer les préfixes internationaux ex: 26134... vs 034...)
      IF v_sender_digits <> v_user_digits
         AND NOT (v_user_digits LIKE '%' || v_sender_digits)
         AND NOT (v_sender_digits LIKE '%' || v_user_digits) THEN
        RETURN jsonb_build_object('success', false, 'message', 'Sender phone does not match registered phone');
      END IF;
    END;
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
    'phone', v_user_phone
  );
END $function$;

REVOKE EXECUTE ON FUNCTION public.auto_verify_phone_by_sms(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.auto_verify_phone_by_sms(text, text) TO service_role;

-- ═══════════════════════════════════════════════════════════════════════
-- BUG 5 (MINEUR) : verify_phone_code — restaurer avec le bon search_path
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.verify_phone_code(_code text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_uid uuid := auth.uid(); v_hash text; v_expected text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth'; END IF;
  SELECT phone_verification_code_hash INTO v_hash FROM public.profiles WHERE id = v_uid;
  IF v_hash IS NULL THEN RETURN false; END IF;
  v_expected := encode(extensions.digest(_code || v_uid::text, 'sha256'), 'hex');
  IF v_hash = v_expected THEN
    UPDATE public.profiles
      SET phone_verified = true,
          phone_verification_code = NULL,
          phone_verification_code_hash = NULL,
          phone_verification_requested_at = NULL
      WHERE id = v_uid;
    RETURN true;
  END IF;
  RETURN false;
END $function$;

REVOKE EXECUTE ON FUNCTION public.verify_phone_code(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.verify_phone_code(text) TO authenticated;
