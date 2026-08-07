-- ═══════════════════════════════════════════════════════════════════════
-- FIX: Race condition validate_deposit_from_sms + Sécurité vérif téléphone
--
-- BUGS corrigés:
--   1. CRITIQUE: validate_deposit_from_sms matchait n'importe quel dépôt
--      en attente si le téléphone ne correspondait pas → mauvais crédit
--      FIX: Ne plus faire de fallback "n'importe quel dépôt". Exiger le
--      match par téléphone OU par montant exact + proximité temporelle.
--
--   2. CRITIQUE: auto_verify_phone_by_sms retournait le code dans la réponse
--      FIX: Ne plus retourner le code
--
--   3. CRITIQUE: auto_verify_phone_by_sms accordée à authenticated
--      (migration 20260806010000 l'avait fait, 20260806193000 l'a corrigé
--      mais si l'ancienne migration est appliquée après, ça ré-ouvre le trou)
--      FIX: REVOKE définitif + commentaire explicite
-- ═══════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════
-- BUG 1: validate_deposit_from_sms — supprimer le fallback dangereux
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
    LIMIT 1;

  -- 3. FIX: Si pas de match par téléphone, chercher par montant EXACT
  --    + dépôt créé dans les 30 dernières minutes (proximité temporelle)
  --    On ne prend plus "n'importe quel dépôt en attente" au hasard.
  IF v_deposit.id IS NULL THEN
    SELECT d.id, d.user_id, d.amount, d.user_phone, d.method, p.pseudo
      INTO v_deposit
      FROM public.deposits d
      JOIN public.profiles p ON p.id = d.user_id
      WHERE d.status = 'pending'
        AND d.amount = _amount
        AND d.created_at > now() - interval '30 minutes'
      ORDER BY d.created_at DESC
      LIMIT 1;

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

  -- 5. Vérification du numéro (si enregistré et match par montant seul)
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

  -- 6. Tout est valide → créditer
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

-- ═══════════════════════════════════════════════════════════════════════
-- BUG 2+3: auto_verify_phone_by_sms — ne pas retourner le code + REVOKE
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

  -- FIX BUG 2: Ne JAMAIS retourner le code dans la réponse
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Phone verified successfully',
    'user_id', v_user_id,
    'phone', v_user_phone
  );
END $function$;

-- FIX BUG 3: REVOKE définitif sur authenticated — seul service_role peut appeler
REVOKE EXECUTE ON FUNCTION public.auto_verify_phone_by_sms(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.auto_verify_phone_by_sms(text, text) TO service_role;
