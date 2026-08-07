-- ═══════════════════════════════════════════════════════════════════════
-- FIX v6 — Casse "lm"/"LM" + normalisation des références (avec/sans points)
--
-- 1. auto_verify_phone_by_sms: le check ~* est insensible à la casse mais
--    substring(... from 'LM[0-9]{6}') est SENSIBLE à la casse → si le SMS
--    contient "lm489783" (minuscule), le check passe mais l'extraction
--    échoue et retourne NULL → rejet à tort. Fix: extraction insensible
--    à la casse + upper() du résultat.
--
-- 2. validate_deposit_from_sms: la référence était comparée en exact
--    (trim = trim), donc "PP260519.1245.C46612" (avec points, Orange) ne
--    matchait pas "PP2605191245C46612" (sans points, tapé par le joueur).
--    Fix: nouvelle fonction _normalize_ref() qui garde uniquement les
--    caractères alphanumériques en majuscule, utilisée pour comparer les
--    références des deux côtés (peu importe points/espaces/casse).
-- ═══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._normalize_ref(_ref text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT upper(regexp_replace(coalesce(_ref, ''), '[^A-Za-z0-9]', '', 'g'));
$function$;

COMMENT ON FUNCTION public._normalize_ref(text) IS
  'Normalise une référence/Trans Id en majuscule sans ponctuation, pour comparer PP260519.1245.C46612 = pp2605191245c46612';

-- ═══════════════════════════════════════════════════════════════════════
-- auto_verify_phone_by_sms — fix casse lm/LM
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.auto_verify_phone_by_sms(_sender_phone text, _sms_body text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_code text;
  v_user_id uuid;
  v_user_phone text;
BEGIN
  v_code := NULL;

  -- FIX v6: extraction insensible à la casse (lm489783 ou LM489783 ou Lm489783)
  IF _sms_body ~* 'LM[0-9]{6}' THEN
    v_code := upper(substring(_sms_body from '(?i)LM[0-9]{6}'));
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
    UPDATE public.profiles
      SET phone_verification_code = NULL,
          phone_verification_code_hash = NULL,
          phone_verification_requested_at = NULL
      WHERE phone_verified = false
        AND phone_verification_requested_at < now() - interval '30 minutes';
    RETURN jsonb_build_object('success', false, 'message', 'No pending verification matches code');
  END IF;

  IF _sender_phone IS NOT NULL AND v_user_phone IS NOT NULL THEN
    IF public._normalize_mg_phone(_sender_phone) <> public._normalize_mg_phone(v_user_phone) THEN
      RETURN jsonb_build_object('success', false, 'message', 'Sender phone does not match registered phone');
    END IF;
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

-- ═══════════════════════════════════════════════════════════════════════
-- validate_deposit_from_sms — fix normalisation référence (points/casse)
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

  -- 2. Chercher un dépôt en attente qui matche par RÉFÉRENCE normalisée (priorité absolue)
  -- FIX v6: comparaison normalisée (sans points/espaces, insensible à la casse)
  SELECT d.id, d.user_id, d.amount, d.user_phone, d.user_reference, d.method, p.pseudo
    INTO v_deposit
    FROM public.deposits d
    JOIN public.profiles p ON p.id = d.user_id
    WHERE d.status = 'pending'
      AND d.user_reference IS NOT NULL
      AND public._normalize_ref(d.user_reference) = public._normalize_ref(_transaction_id)
      AND length(public._normalize_ref(d.user_reference)) >= 3
    ORDER BY d.created_at DESC
    LIMIT 1
    FOR UPDATE OF d;

  IF v_deposit.id IS NOT NULL THEN
    v_ref_match := true;
  END IF;

  -- 3. Si pas de match par référence, chercher par téléphone (normalisé) + montant
  IF v_deposit.id IS NULL AND _sender_number IS NOT NULL THEN
    SELECT d.id, d.user_id, d.amount, d.user_phone, d.user_reference, d.method, p.pseudo
      INTO v_deposit
      FROM public.deposits d
      JOIN public.profiles p ON p.id = d.user_id
      WHERE d.status = 'pending'
        AND d.user_phone IS NOT NULL
        AND public._normalize_mg_phone(d.user_phone) = public._normalize_mg_phone(_sender_number)
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
  --    A) Téléphone — cœur de numéro normalisé (9 derniers chiffres)
  IF v_deposit.user_phone IS NOT NULL AND _sender_number IS NOT NULL THEN
    v_phone_match := public._normalize_mg_phone(v_deposit.user_phone) = public._normalize_mg_phone(_sender_number);
  END IF;

  --    B) Référence (Ref/Trans ID) — normalisée (sans points/espaces, insensible casse)
  -- FIX v6
  IF v_deposit.user_reference IS NOT NULL AND _transaction_id IS NOT NULL THEN
    v_ref_match := public._normalize_ref(v_deposit.user_reference) = public._normalize_ref(_transaction_id);
  END IF;

  --    C) Montant (tolérance 200 Ar)
  v_diff := abs(_amount - v_deposit.amount);
  v_amount_match := (v_diff <= 200);

  -- 5. Si la référence a été fournie par le joueur, elle DOIT matcher
  IF v_deposit.user_reference IS NOT NULL AND length(public._normalize_ref(v_deposit.user_reference)) >= 3 THEN
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
  IF NOT v_amount_match THEN
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
