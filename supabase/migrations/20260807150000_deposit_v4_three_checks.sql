-- ═══════════════════════════════════════════════════════════════════════
-- DÉPÔT v4 — Validation par 3 critères (téléphone + référence + montant)
--
-- Le joueur doit fournir:
--   - Montant
--   - Numéro qui a envoyé l'argent
--   - Référence: Ref (MVola/Telma) ou Trans ID (Orange Money)
--
-- La validation automatique vérifie que les 3 correspondent au SMS reçu.
-- ═══════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════
-- 1. Ajouter la colonne user_reference à deposits
-- ═══════════════════════════════════════════════════════════════════════
ALTER TABLE public.deposits ADD COLUMN IF NOT EXISTS user_reference text;

COMMENT ON COLUMN public.deposits.user_reference IS 'Référence fournie par le joueur: Ref (MVola) ou Trans ID (Orange Money)';

-- ═══════════════════════════════════════════════════════════════════════
-- 2. create_deposit — avec référence obligatoire
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.create_deposit(
  _amount numeric,
  _method text,
  _user_phone text DEFAULT NULL,
  _user_reference text DEFAULT NULL
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
  -- NOUVEAU: Référence obligatoire (Ref MVola ou Trans ID Orange)
  IF _user_reference IS NULL OR length(trim(_user_reference)) < 3 THEN
    RAISE EXCEPTION 'Référence de transaction requise (Ref pour MVola, Trans ID pour Orange Money)';
  END IF;

  -- 1 seule demande par 5 minutes
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

  INSERT INTO public.deposits(user_id, amount, method, user_phone, user_reference, status, reference)
    VALUES (v_uid, _amount, _method, trim(_user_phone), trim(_user_reference),
            'pending'::public.tx_status, 'deposit_' || gen_random_uuid()::text)
    RETURNING id INTO v_deposit_id;

  RETURN v_deposit_id;
END $function$;

REVOKE EXECUTE ON FUNCTION public.create_deposit(numeric, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_deposit(numeric, text, text, text) TO authenticated, service_role;

-- ═══════════════════════════════════════════════════════════════════════
-- 3. validate_deposit_from_sms — vérifie les 3 critères
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
  v_already_credited BOOLEAN;
  v_already_in_tx BOOLEAN;
  v_ref_match BOOLEAN := false;
  v_phone_match BOOLEAN := false;
  v_amount_match BOOLEAN := false;
  v_rejection_reason TEXT;
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

  -- 2. Chercher un dépôt en attente qui matche par RÉFÉRENCE (priorité absolue)
  --    user_reference = transaction_id du SMS (Ref MVola ou Trans ID Orange)
  SELECT d.id, d.user_id, d.amount, d.user_phone, d.user_reference, d.method, p.pseudo
    INTO v_deposit
    FROM public.deposits d
    JOIN public.profiles p ON p.id = d.user_id
    WHERE d.status = 'pending'
      AND d.user_reference IS NOT NULL
      AND trim(d.user_reference) = trim(_transaction_id)
    ORDER BY d.created_at DESC
    LIMIT 1
    FOR UPDATE OF d;

  IF v_deposit.id IS NOT NULL THEN
    v_ref_match := true;
  END IF;

  -- 3. Si pas de match par référence, chercher par téléphone + montant
  IF v_deposit.id IS NULL AND _sender_number IS NOT NULL THEN
    SELECT d.id, d.user_id, d.amount, d.user_phone, d.user_reference, d.method, p.pseudo
      INTO v_deposit
      FROM public.deposits d
      JOIN public.profiles p ON p.id = d.user_id
      WHERE d.status = 'pending'
        AND d.user_phone IS NOT NULL
        AND regexp_replace(d.user_phone, '[^0-9]', '', 'g')
          LIKE '%' || regexp_replace(_sender_number, '[^0-9]', '', 'g')
        AND d.amount = _amount
        AND d.created_at > now() - interval '30 minutes'
      ORDER BY d.created_at DESC
      LIMIT 1
      FOR UPDATE OF d;
  END IF;

  IF v_deposit.id IS NULL THEN
    INSERT INTO public.deposit_transactions(operator, transaction_id, sender_number,
      sender_name, amount, sms_date, sms_content, status, rejection_reason)
    VALUES (_operator, _transaction_id, _sender_number, _sender_name,
      _amount, _sms_date, _sms_content, 'rejected',
      'Aucun dépôt correspondant (ref=' || COALESCE(_transaction_id, 'NULL') || ', tel=' || COALESCE(_sender_number, 'NULL') || ', montant=' || _amount || ')');

    RETURN jsonb_build_object(
      'success', false,
      'error', 'NO_MATCHING_DEPOSIT',
      'message', 'Aucun dépôt en attente ne correspond (référence, téléphone ou montant)'
    );
  END IF;

  -- 4. VÉRIFICATION DES 3 CRITÈRES
  --    A) Téléphone
  IF v_deposit.user_phone IS NOT NULL AND _sender_number IS NOT NULL THEN
    v_sender_digits := regexp_replace(_sender_number, '[^0-9]', '', 'g');
    v_user_digits := regexp_replace(v_deposit.user_phone, '[^0-9]', '', 'g');
    v_phone_match := (v_sender_digits = v_user_digits)
                     OR (v_user_digits LIKE '%' || v_sender_digits)
                     OR (v_sender_digits LIKE '%' || v_user_digits);
  END IF;

  --    B) Référence (Ref/Trans ID)
  IF v_deposit.user_reference IS NOT NULL AND _transaction_id IS NOT NULL THEN
    v_ref_match := trim(v_deposit.user_reference) = trim(_transaction_id);
  END IF;

  --    C) Montant (tolérance 200 Ar)
  v_diff := abs(_amount - v_deposit.amount);
  v_amount_match := (v_diff <= 200);

  -- 5. Si la référence a été fournie par le joueur, elle DOIT matcher
  IF v_deposit.user_reference IS NOT NULL AND length(trim(v_deposit.user_reference)) >= 3 THEN
    IF NOT v_ref_match THEN
      v_rejection_reason := 'Référence ne correspond pas: joueur=' || v_deposit.user_reference || ' vs SMS=' || _transaction_id;
      INSERT INTO public.deposit_transactions(operator, transaction_id, sender_number,
        sender_name, amount, sms_date, sms_content, status, rejection_reason, user_id, matched_deposit_id)
      VALUES (_operator, _transaction_id, _sender_number, _sender_name,
        _amount, _sms_date, _sms_content, 'rejected', v_rejection_reason, v_deposit.user_id, v_deposit.id);
      RETURN jsonb_build_object(
        'success', false,
        'error', 'REF_MISMATCH',
        'message', 'Référence ne correspond pas'
      );
    END IF;
  END IF;

  -- 6. Le téléphone DOIT matcher
  IF NOT v_phone_match THEN
    v_rejection_reason := 'Numéro ne correspond pas: joueur=' || COALESCE(v_deposit.user_phone, 'NULL') || ' vs SMS=' || COALESCE(_sender_number, 'NULL');
    INSERT INTO public.deposit_transactions(operator, transaction_id, sender_number,
      sender_name, amount, sms_date, sms_content, status, rejection_reason, user_id, matched_deposit_id)
    VALUES (_operator, _transaction_id, _sender_number, _sender_name,
      _amount, _sms_date, _sms_content, 'rejected', v_rejection_reason, v_deposit.user_id, v_deposit.id);
    RETURN jsonb_build_object(
      'success', false,
      'error', 'PHONE_MISMATCH',
      'message', 'Numéro de téléphone ne correspond pas'
    );
  END IF;

  -- 7. Le montant DOIT matcher
  IF Not v_amount_match THEN
    v_rejection_reason := 'Montant ne correspond pas: joueur=' || v_deposit.amount || ' vs SMS=' || _amount || ' (diff=' || v_diff || ')';
    INSERT INTO public.deposit_transactions(operator, transaction_id, sender_number,
      sender_name, amount, sms_date, sms_content, status, rejection_reason, user_id, matched_deposit_id)
    VALUES (_operator, _transaction_id, _sender_number, _sender_name,
      _amount, _sms_date, _sms_content, 'rejected', v_rejection_reason, v_deposit.user_id, v_deposit.id);
    RETURN jsonb_build_object(
      'success', false,
      'error', 'AMOUNT_MISMATCH',
      'message', 'Montant ne correspond pas: SMS=' || _amount || ' Ar vs demande=' || v_deposit.amount || ' Ar'
    );
  END IF;

  -- 8. Anti-double-crédit — vérifier transactions
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
      'success', false, 'error', 'ALREADY_CREDITED',
      'message', 'Ce dépôt a déjà été crédité'
    );
  END IF;

  -- 9. Vérifier qu'aucun autre deposit_transaction approuvé n'existe
  SELECT EXISTS(
    SELECT 1 FROM public.deposit_transactions
    WHERE matched_deposit_id = v_deposit.id AND status = 'approved'
  ) INTO v_already_in_tx;

  IF v_already_in_tx THEN
    INSERT INTO public.deposit_transactions(operator, transaction_id, sender_number,
      sender_name, amount, sms_date, sms_content, status, rejection_reason, user_id, matched_deposit_id)
    VALUES (_operator, _transaction_id, _sender_number, _sender_name,
      _amount, _sms_date, _sms_content, 'rejected',
      'Deposit transaction déjà approuvée', v_deposit.user_id, v_deposit.id);
    RETURN jsonb_build_object(
      'success', false, 'error', 'DEPOSIT_TX_EXISTS',
      'message', 'Ce dépôt a déjà été validé'
    );
  END IF;

  -- 10. Tout est valide → créditer
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
    'message', 'Dépôt validé (3 critères vérifiés: téléphone + référence + montant)',
    'deposit_id', v_deposit.id,
    'user_id', v_deposit.user_id,
    'user_pseudo', v_deposit.pseudo,
    'amount', v_deposit.amount,
    'sms_amount', _amount,
    'transaction_id', _transaction_id,
    'deposit_tx_id', v_new_id,
    'checks', jsonb_build_object(
      'phone_match', v_phone_match,
      'ref_match', v_ref_match,
      'amount_match', v_amount_match
    )
  );
END $function$;

REVOKE EXECUTE ON FUNCTION public.validate_deposit_from_sms(TEXT, TEXT, TEXT, TEXT, NUMERIC, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.validate_deposit_from_sms(TEXT, TEXT, TEXT, TEXT, NUMERIC, TEXT, TEXT) TO service_role;
