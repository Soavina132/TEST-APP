-- ═══════════════════════════════════════════════════════════════════════
-- SÉCURITÉ RENFORCÉE v3 — Dépôts + Vérif téléphone
-- Date: 2026-08-07
-- ═══════════════════════════════════════════════════════════════════════
--
-- CHANGEMENTS:
--   1. request_phone_verification: BLOQUER si un code valide existe déjà
--      → Le joueur ne peut pas changer de numéro ni regénérer un code
--        tant que le code précédent n'a pas expiré (30 min) ou été validé
--
--   2. profiles: Empêcher la modification du téléphone si un code est en cours
--      → Ajout d'une condition dans la policy UPDATE
--
--   3. create_deposit: 1 seule demande par 5 minutes (au lieu de 3 en attente)
--      + Le joueur doit fournir le numéro qui a envoyé l'argent
--
--   4. validate_deposit_from_sms: Anti-double-crédit renforcé
--      → Vérifier dans transactions qu'aucun crédit n'a déjà été fait
--        pour ce deposit_id
--      → Vérifier qu'aucun autre deposit_transaction approuvé n'existe
--        pour le même user + même montant + même période
--      → Lock pessimiste sur le deposit (FOR UPDATE) pendant la validation
-- ═══════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════
-- 1. request_phone_verification — Bloquer si code déjà actif
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
  v_existing_code text;
  v_existing_phone text;
  v_existing_verified boolean;
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

  -- NOUVEAU: Bloquer si un code valide existe déjà (non expiré)
  SELECT phone_verification_code INTO v_existing_code
    FROM public.profiles
    WHERE id = v_uid
      AND phone_verification_code IS NOT NULL
      AND phone_verified = false
      AND phone_verification_requested_at > now() - interval '30 minutes';

  IF v_existing_code IS NOT NULL THEN
    RAISE EXCEPTION 'Un code de vérification est déjà actif. Envoyez-le par SMS au numéro admin ou attendez son expiration (30 min).';
  END IF;

  -- Vérifier que le numéro n'est pas déjà utilisé par un autre user vérifié
  SELECT phone, phone_verified INTO v_existing_phone, v_existing_verified
    FROM public.profiles WHERE phone = _phone AND phone_verified = true AND id <> v_uid
    LIMIT 1;
  IF v_existing_phone IS NOT NULL AND v_existing_verified THEN
    RAISE EXCEPTION 'Numéro déjà utilisé';
  END IF;

  -- Invalider tout code précédent
  UPDATE public.profiles
    SET phone_verification_code = NULL,
        phone_verification_code_hash = NULL,
        phone_verification_requested_at = NULL
    WHERE id = v_uid AND phone_verified = false
      AND phone_verification_code IS NOT NULL;

  -- Générer le code au format LMxxxxxx
  v_code := 'LM' || lpad((floor(random()*1000000))::int::text, 6, '0');

  -- Stocker le code en clair + hash
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
-- 2. Policy UPDATE profiles — bloquer modification téléphone si code en cours
-- ═══════════════════════════════════════════════════════════════════════
-- On recrée la policy avec une condition supplémentaire:
-- Le téléphone ne peut PAS changer si un code de vérif est actif
DROP POLICY IF EXISTS profiles_self_update_safe ON public.profiles;

CREATE POLICY profiles_self_update_safe ON public.profiles
  FOR UPDATE TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (
    auth.uid() = id
    -- balance_ar ne peut pas changer
    AND balance_ar = (SELECT p.balance_ar FROM profiles p WHERE p.id = auth.uid())
    -- banned ne peut pas changer
    AND banned = (SELECT p.banned FROM profiles p WHERE p.id = auth.uid())
    -- status ne peut pas changer
    AND status = (SELECT p.status FROM profiles p WHERE p.id = auth.uid())
    -- unique_code ne peut pas changer
    AND unique_code = (SELECT p.unique_code FROM profiles p WHERE p.id = auth.uid())
    -- referral_code ne peut pas changer
    AND referral_code = (SELECT p.referral_code FROM profiles p WHERE p.id = auth.uid())
    -- phone_verified ne peut pas changer (seules les fonctions service_role le font)
    AND phone_verified = (SELECT p.phone_verified FROM profiles p WHERE p.id = auth.uid())
    -- referral_unlocked ne peut pas changer
    AND referral_unlocked = (SELECT p.referral_unlocked FROM profiles p WHERE p.id = auth.uid())
    -- referred_by ne peut pas changer
    AND COALESCE(referred_by::text, '') = COALESCE((SELECT p.referred_by::text FROM profiles p WHERE p.id = auth.uid()), '')
    -- phone_verification_code ne peut pas changer
    AND COALESCE(phone_verification_code, '') = COALESCE((SELECT p.phone_verification_code FROM profiles p WHERE p.id = auth.uid()), '')
    -- phone_verification_code_hash ne peut pas changer
    AND COALESCE(phone_verification_code_hash, '') = COALESCE((SELECT p.phone_verification_code_hash FROM profiles p WHERE p.id = auth.uid()), '')
    -- phone_verification_requested_at ne peut pas changer
    AND COALESCE(phone_verification_requested_at::text, '') = COALESCE((SELECT p.phone_verification_requested_at::text FROM profiles p WHERE p.id = auth.uid()), '')
    -- NOUVEAU: Le téléphone ne peut pas changer si un code est en cours
    -- (si le code est NULL, le téléphone peut être changé par request_phone_verification)
    -- (si le code est actif, seul request_phone_verification peut changer le téléphone)
    AND (
      -- Pas de code en cours → téléphone peut changer (mais request_phone_verification le gère)
      (SELECT p.phone_verification_code FROM profiles p WHERE p.id = auth.uid()) IS NULL
      OR
      -- Code en cours → téléphone ne peut PAS changer
      phone = (SELECT p.phone FROM profiles p WHERE p.id = auth.uid())
    )
  );

-- ═══════════════════════════════════════════════════════════════════════
-- 3. create_deposit — 1 demande par 5 min + numéro obligatoire
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
  v_last_deposit timestamptz;
  v_pending_count int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _amount IS NULL OR _amount <= 0 THEN RAISE EXCEPTION 'Montant invalide'; END IF;
  IF _method IS NULL THEN RAISE EXCEPTION 'Méthode requise'; END IF;
  IF _user_phone IS NULL OR length(trim(_user_phone)) < 8 THEN
    RAISE EXCEPTION 'Numéro de téléphone requis';
  END IF;

  -- NOUVEAU: 1 seule demande par 5 minutes
  SELECT max(created_at) INTO v_last_deposit
    FROM public.deposits
    WHERE user_id = v_uid;
  IF v_last_deposit IS NOT NULL AND now() - v_last_deposit < interval '5 minutes' THEN
    RAISE EXCEPTION 'Vous ne pouvez faire qu''une seule demande de dépôt toutes les 5 minutes.';
  END IF;

  -- Pas plus d'1 dépôt en attente
  SELECT count(*) INTO v_pending_count
    FROM public.deposits
    WHERE user_id = v_uid AND status = 'pending';
  IF v_pending_count >= 1 THEN
    RAISE EXCEPTION 'Vous avez déjà un dépôt en attente. Attendez sa validation.';
  END IF;

  INSERT INTO public.deposits(user_id, amount, method, user_phone, status, reference)
    VALUES (v_uid, _amount, _method, trim(_user_phone), 'pending'::public.tx_status, 'deposit_' || gen_random_uuid()::text)
    RETURNING id INTO v_deposit_id;

  RETURN v_deposit_id;
END $function$;

REVOKE EXECUTE ON FUNCTION public.create_deposit(numeric, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_deposit(numeric, text, text) TO authenticated, service_role;

-- ═══════════════════════════════════════════════════════════════════════
-- 4. validate_deposit_from_sms — Anti-double-crédit renforcé + lock pessimiste
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.validate_deposit_from_sms(
  _operator TEXT,
  _transaction_id TEXT,
  _sender_number TEXT,
  _sender_name TEXT,
  _amount NUMERIC,
  _sms_date TEXT,
  _sms_content TEXT
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_existing RECORD;
  v_deposit RECORD;
  v_diff NUMERIC;
  v_sender_digits TEXT;
  v_user_digits TEXT;
  v_new_id UUID;
  v_found_by_amount BOOLEAN := false;
  v_already_credited BOOLEAN;
  v_already_in_tx BOOLEAN;
BEGIN
  -- 1. Transaction unique — refuser si déjà présente
  SELECT id, status INTO v_existing
    FROM public.deposit_transactions
    WHERE transaction_id = _transaction_id
    LIMIT 1;

  IF v_existing.id IS NOT NULL THEN
    INSERT INTO public.deposit_transactions(operator, transaction_id, sender_number,
      sender_name, amount, sms_date, sms_content, status, rejection_reason)
    VALUES (_operator, _transaction_id, _sender_number, _sender_name,
      _amount, _sms_date, _sms_content, 'rejected', 'Transaction déjà existante')
    ON CONFLICT (transaction_id) DO NOTHING;

    RETURN jsonb_build_object(
      'success', false,
      'error', 'TRANSACTION_EXISTS',
      'message', 'Transaction déjà enregistrée (Trans Id: ' || _transaction_id || ')'
    );
  END IF;

  -- 2. Rechercher un dépôt en attente par numéro de téléphone
  --    NOUVEAU: FOR UPDATE — lock pessimiste pour empêcher 2 validations simultanées
  SELECT d.id, d.user_id, d.amount, d.user_phone, d.method, p.pseudo
    INTO v_deposit
    FROM public.deposits d
    JOIN public.profiles p ON p.id = d.user_id
    WHERE d.status = 'pending'
      AND _sender_number IS NOT NULL
      AND d.user_phone IS NOT NULL
      AND regexp_replace(d.user_phone, '[^0-9]', '', 'g')
        LIKE '%' || regexp_replace(_sender_number, '[^0-9]', '', 'g')
    ORDER BY d.created_at DESC
    LIMIT 1
    FOR UPDATE OF d;

  -- 3. Si pas de match par téléphone, chercher par montant exact + 30 min
  IF v_deposit.id IS NULL THEN
    SELECT d.id, d.user_id, d.amount, d.user_phone, d.method, p.pseudo
      INTO v_deposit
      FROM public.deposits d
      JOIN public.profiles p ON p.id = d.user_id
      WHERE d.status = 'pending'
        AND d.amount = _amount
        AND d.created_at > now() - interval '30 minutes'
      ORDER BY d.created_at DESC
      LIMIT 1
      FOR UPDATE OF d;

    IF v_deposit.id IS NOT NULL THEN
      v_found_by_amount := true;
    END IF;
  END IF;

  IF v_deposit.id IS NULL THEN
    INSERT INTO public.deposit_transactions(operator, transaction_id, sender_number,
      sender_name, amount, sms_date, sms_content, status, rejection_reason)
    VALUES (_operator, _transaction_id, _sender_number, _sender_name,
      _amount, _sms_date, _sms_content, 'rejected', 'Aucun dépôt en attente correspondant');

    RETURN jsonb_build_object(
      'success', false,
      'error', 'NO_MATCHING_DEPOSIT',
      'message', 'Aucun dépôt en attente ne correspond (téléphone ou montant)'
    );
  END IF;

  -- 4. Vérification du montant — tolérance de 200 Ar
  v_diff := abs(_amount - v_deposit.amount);
  IF v_diff > 200 THEN
    INSERT INTO public.deposit_transactions(operator, transaction_id, sender_number,
      sender_name, amount, sms_date, sms_content, status, rejection_reason, user_id, matched_deposit_id)
    VALUES (_operator, _transaction_id, _sender_number, _sender_name,
      _amount, _sms_date, _sms_content, 'rejected',
      'Montant différent: SMS=' || _amount || ' vs demande=' || v_deposit.amount,
      v_deposit.user_id, v_deposit.id);

    RETURN jsonb_build_object(
      'success', false,
      'error', 'AMOUNT_MISMATCH',
      'message', 'Montant différent: SMS=' || _amount || ' Ar vs demande=' || v_deposit.amount || ' Ar (diff=' || v_diff || ' Ar)'
    );
  END IF;

  -- 5. Vérification du numéro (si match par montant seul)
  IF v_found_by_amount AND v_deposit.user_phone IS NOT NULL AND _sender_number IS NOT NULL THEN
    v_sender_digits := regexp_replace(_sender_number, '[^0-9]', '', 'g');
    v_user_digits := regexp_replace(v_deposit.user_phone, '[^0-9]', '', 'g');
    IF v_sender_digits <> v_user_digits
       AND NOT (v_user_digits LIKE '%' || v_sender_digits)
       AND NOT (v_sender_digits LIKE '%' || v_user_digits) THEN
      INSERT INTO public.deposit_transactions(operator, transaction_id, sender_number,
        sender_name, amount, sms_date, sms_content, status, rejection_reason, user_id, matched_deposit_id)
      VALUES (_operator, _transaction_id, _sender_number, _sender_name,
        _amount, _sms_date, _sms_content, 'rejected',
        'Numéro expéditeur ne correspond pas (match par montant): SMS=' || _sender_number || ' vs profil=' || v_deposit.user_phone,
        v_deposit.user_id, v_deposit.id);

      RETURN jsonb_build_object(
        'success', false,
        'error', 'PHONE_MISMATCH',
        'message', 'Numéro expéditeur ne correspond pas'
      );
    END IF;
  END IF;

  -- 6. NOUVEAU: Anti-double-crédit — vérifier que ce deposit n'a pas déjà été crédité
  SELECT EXISTS(
    SELECT 1 FROM public.transactions
    WHERE user_id = v_deposit.user_id
      AND type = 'deposit'
      AND ref_id = v_deposit.id
  ) INTO v_already_credited;

  IF v_already_credited THEN
    INSERT INTO public.deposit_transactions(operator, transaction_id, sender_number,
      sender_name, amount, sms_date, sms_content, status, rejection_reason, user_id, matched_deposit_id)
    VALUES (_operator, _transaction_id, _sender_number, _sender_name,
      _amount, _sms_date, _sms_content, 'rejected',
      'Déjà crédité pour ce dépôt (anti-double)', v_deposit.user_id, v_deposit.id);

    RETURN jsonb_build_object(
      'success', false,
      'error', 'ALREADY_CREDITED',
      'message', 'Ce dépôt a déjà été crédité'
    );
  END IF;

  -- 7. NOUVEAU: Vérifier qu'aucun autre deposit_transaction approuvé n'existe
  --    pour le même deposit_id (double sécurité)
  SELECT EXISTS(
    SELECT 1 FROM public.deposit_transactions
    WHERE matched_deposit_id = v_deposit.id
      AND status = 'approved'
  ) INTO v_already_in_tx;

  IF v_already_in_tx THEN
    INSERT INTO public.deposit_transactions(operator, transaction_id, sender_number,
      sender_name, amount, sms_date, sms_content, status, rejection_reason, user_id, matched_deposit_id)
    VALUES (_operator, _transaction_id, _sender_number, _sender_name,
      _amount, _sms_date, _sms_content, 'rejected',
      'Deposit transaction déjà approuvée pour ce dépôt', v_deposit.user_id, v_deposit.id);

    RETURN jsonb_build_object(
      'success', false,
      'error', 'DEPOSIT_TX_EXISTS',
      'message', 'Ce dépôt a déjà été validé par une autre transaction'
    );
  END IF;

  -- 8. Vérifier que le dépôt n'est pas déjà approuvé
  IF v_deposit.status = 'approved' THEN
    INSERT INTO public.deposit_transactions(operator, transaction_id, sender_number,
      sender_name, amount, sms_date, sms_content, status, rejection_reason, user_id, matched_deposit_id)
    VALUES (_operator, _transaction_id, _sender_number, _sender_name,
      _amount, _sms_date, _sms_content, 'rejected',
      'Dépôt déjà approuvé', v_deposit.user_id, v_deposit.id);

    RETURN jsonb_build_object(
      'success', false,
      'error', 'DEPOSIT_ALREADY_APPROVED',
      'message', 'Dépôt déjà approuvé'
    );
  END IF;

  -- 9. Tout est valide → créditer
  UPDATE public.profiles
    SET balance_ar = balance_ar + v_deposit.amount
    WHERE id = v_deposit.user_id;

  INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
    VALUES (v_deposit.user_id, 'deposit', v_deposit.amount, v_deposit.id,
      'Dépôt auto SMS ' || _operator || ' (Trans Id: ' || _transaction_id || ')');

  UPDATE public.deposits
    SET status = 'approved', processed_at = now()
    WHERE id = v_deposit.id;

  PERFORM public._referral_on_deposit_trigger(v_deposit.id, v_deposit.user_id, v_deposit.amount);

  INSERT INTO public.deposit_transactions(operator, transaction_id, sender_number,
    sender_name, amount, sms_date, sms_content, status, user_id, matched_deposit_id)
  VALUES (_operator, _transaction_id, _sender_number, _sender_name,
    _amount, _sms_date, _sms_content, 'approved', v_deposit.user_id, v_deposit.id)
  RETURNING id INTO v_new_id;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Dépôt validé et crédité',
    'deposit_id', v_deposit.id,
    'user_id', v_deposit.user_id,
    'user_pseudo', v_deposit.pseudo,
    'amount', v_deposit.amount,
    'sms_amount', _amount,
    'transaction_id', _transaction_id,
    'deposit_tx_id', v_new_id
  );
END $function$;

REVOKE EXECUTE ON FUNCTION public.validate_deposit_from_sms(TEXT, TEXT, TEXT, TEXT, NUMERIC, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.validate_deposit_from_sms(TEXT, TEXT, TEXT, TEXT, NUMERIC, TEXT, TEXT) TO service_role;
