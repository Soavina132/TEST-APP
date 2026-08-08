-- ═══════════════════════════════════════════════════════════════════════
-- AUDIT DE SÉCURITÉ COMPLET — Corrections
-- Date: 2026-08-07
-- ═══════════════════════════════════════════════════════════════════════
--
-- VULNÉRABILITÉS TROUVÉES ET CORRIGÉES:
--
-- 🔴 BUG 1 (CRITIQUE): verify_phone_code accordé à authenticated
--   Un utilisateur peut contourner TOUTE la vérification SMS:
--   1. request_phone_verification("fake_number") → reçoit le code LM123456
--   2. Appelle verify_phone_code("LM123456") directement via REST API
--   3. phone_verified = true SANS envoyer de SMS
--   FIX: REVOKE authenticated. Seul service_role peut appeler (admin manuel).
--
-- 🔴 BUG 2 (CRITIQUE): get_pending_phone_verification accordé à PUBLIC
--   N'importe qui (même anon) peut appeler cette fonction.
--   Le code vérifie auth.uid() mais le grant est trop large.
--   FIX: REVOKE PUBLIC, garder authenticated uniquement.
--
-- 🟠 BUG 3 (MOYEN): request_phone_verification n'expire pas les anciens codes
--   Si un user demande un nouveau code, l'ancien reste valide.
--   FIX: Invalider les anciens codes avant d'en générer un nouveau.
--
-- 🟠 BUG 4 (MOYEN): auto_verify_phone_by_sms accepte les codes expirés
--   La fenêtre de 30 minutes est vérifiée, mais le code en clair reste
--   dans la DB même après expiration.
--   FIX: Nettoyer le code après expiration (déjà partiellement fait par
--   get_pending_phone_verification, mais pas par auto_verify).
--
-- 🟠 BUG 5 (MOYEN): validate_deposit_from_sms — pas de limite sur le nombre
--   de dépôts en attente par utilisateur. Un user peut créer 100 dépôts
--   en attente et attendre qu'un SMS tombe sur l'un d'eux.
--   FIX: Limiter à 3 dépôts en attente par utilisateur (comme les retraits).
--
-- 🟡 BUG 6 (MINEUR): _referral_on_deposit_trigger n'est pas idempotent
--   Si appelé deux fois pour le même dépôt, le parrain est crédité 2x.
--   FIX: Vérifier que le trigger n'a pas déjà été exécuté.
-- ═══════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════
-- BUG 1 (CRITIQUE): REVOKE verify_phone_code de authenticated
-- ═══════════════════════════════════════════════════════════════════════
REVOKE EXECUTE ON FUNCTION public.verify_phone_code(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.verify_phone_code(text) TO service_role;

-- ═══════════════════════════════════════════════════════════════════════
-- BUG 2 (CRITIQUE): REVOKE get_pending_phone_verification de PUBLIC
-- ═══════════════════════════════════════════════════════════════════════
REVOKE EXECUTE ON FUNCTION public.get_pending_phone_verification() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pending_phone_verification() TO authenticated, service_role;

-- ═══════════════════════════════════════════════════════════════════════
-- BUG 3 (MOYEN): request_phone_verification — invalider anciens codes
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
  v_pending_count int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _phone IS NULL OR length(trim(_phone)) < 8 THEN
    RAISE EXCEPTION 'Numéro invalide';
  END IF;

  -- Rate limiting — max 1 demande par 5 minutes
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

  -- FIX: Invalider tout code précédent avant d'en générer un nouveau
  UPDATE public.profiles
    SET phone_verification_code = NULL,
        phone_verification_code_hash = NULL,
        phone_verification_requested_at = NULL
    WHERE id = v_uid AND phone_verified = false
      AND phone_verification_code IS NOT NULL;

  -- Générer le code au format LMxxxxxx
  v_code := 'LM' || lpad((floor(random()*1000000))::int::text, 6, '0');

  -- Stocker le code en clair (pour auto_verify) ET en hash (pour verify_phone_code)
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
GRANT EXECUTE ON FUNCTION public.request_phone_verification(text) TO authenticated, service_role;

-- ═══════════════════════════════════════════════════════════════════════
-- BUG 4 (MOYEN): auto_verify_phone_by_sms — nettoyer code expiré
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
    -- FIX: Nettoyer les codes expirés
    UPDATE public.profiles
      SET phone_verification_code = NULL,
          phone_verification_code_hash = NULL,
          phone_verification_requested_at = NULL
      WHERE phone_verified = false
        AND phone_verification_requested_at < now() - interval '30 minutes';
    RETURN jsonb_build_object('success', false, 'message', 'No pending verification matches code');
  END IF;

  -- Valider que le numéro expéditeur correspond au phone du user
  IF _sender_phone IS NOT NULL AND v_user_phone IS NOT NULL THEN
    DECLARE
      v_sender_digits text := regexp_replace(_sender_phone, '[^0-9]', '', 'g');
      v_user_digits text := regexp_replace(v_user_phone, '[^0-9]', '', 'g');
    BEGIN
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
-- BUG 5 (MOYEN): Limiter les dépôts en attente à 3 par utilisateur
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.create_deposit(
  _amount numeric,
  _method text,
  _user_phone text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_deposit_id uuid;
  v_pending_count int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _amount IS NULL OR _amount <= 0 THEN RAISE EXCEPTION 'Montant invalide'; END IF;
  IF _method IS NULL THEN RAISE EXCEPTION 'Méthode requise'; END IF;

  -- FIX: Limiter à 3 dépôts en attente
  SELECT count(*) INTO v_pending_count
    FROM public.deposits
    WHERE user_id = v_uid AND status = 'pending';
  IF v_pending_count >= 3 THEN
    RAISE EXCEPTION 'Trop de dépôts en attente (max 3). Attendez la validation de vos dépôts précédents.';
  END IF;

  INSERT INTO public.deposits(user_id, amount, method, user_phone, status, reference)
    VALUES (v_uid, _amount, _method, _user_phone, 'pending'::public.tx_status, 'deposit_' || gen_random_uuid()::text)
    RETURNING id INTO v_deposit_id;

  RETURN v_deposit_id;
END $function$;

REVOKE EXECUTE ON FUNCTION public.create_deposit(numeric, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_deposit(numeric, text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- BUG 6 (MINEUR): _referral_on_deposit_trigger — idempotent
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._referral_on_deposit_trigger(_deposit_id uuid, _user_id uuid, _amount numeric)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_parent uuid;
  v_pct numeric;
  v_reward numeric;
  v_verified boolean;
  v_unlocked boolean;
  v_first_deposit_at timestamptz;
  v_already_triggered boolean;
BEGIN
  SELECT referred_by, phone_verified, referral_unlocked, first_deposit_at
    INTO v_parent, v_verified, v_unlocked, v_first_deposit_at
    FROM public.profiles WHERE id = _user_id;

  IF v_parent IS NULL THEN RETURN; END IF;

  -- FIX: Vérifier qu'on n'a pas déjà déclenché pour ce dépôt
  SELECT EXISTS(
    SELECT 1 FROM public.transactions
    WHERE user_id = v_parent AND type = 'referral_bonus' AND ref_id = _deposit_id
  ) INTO v_already_triggered;
  IF v_already_triggered THEN RETURN; END IF;

  IF NOT v_verified THEN RETURN; END IF;

  IF v_unlocked THEN
    SELECT COALESCE(referral_pct, 10) INTO v_pct
      FROM public.profiles WHERE id = v_parent;
    v_reward := round((_amount * v_pct / 100)::numeric, 0);

    UPDATE public.profiles
      SET balance_ar = balance_ar + v_reward
      WHERE id = v_parent;

    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_parent, 'referral_bonus', v_reward, _deposit_id,
        'Bonus parrainage ' || v_pct || '% sur dépôt de ' || _amount || ' Ar');

    -- Marquer le premier dépôt
    IF v_first_deposit_at IS NULL THEN
      UPDATE public.profiles SET first_deposit_at = now() WHERE id = _user_id;
    END IF;
  END IF;
END $function$;

REVOKE EXECUTE ON FUNCTION public._referral_on_deposit_trigger(uuid, uuid, numeric) FROM PUBLIC, anon, authenticated;
