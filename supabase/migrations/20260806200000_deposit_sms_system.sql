-- ═══════════════════════════════════════════════════════════════════════
-- SYSTÈME DE VALIDATION AUTOMATIQUE DES DÉPÔTS SMS
--
-- Table: deposit_transactions
-- Stocke tous les SMS reçus + leur statut de validation
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.deposit_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  operator TEXT NOT NULL CHECK (operator IN ('orange', 'mvola')),
  transaction_id TEXT NOT NULL UNIQUE,
  sender_number TEXT,
  sender_name TEXT,
  amount NUMERIC,
  sms_date TEXT,
  sms_content TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  rejection_reason TEXT,
  matched_deposit_id UUID REFERENCES public.deposits(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index pour recherches rapides
CREATE INDEX IF NOT EXISTS idx_deposit_tx_transaction_id ON public.deposit_transactions(transaction_id);
CREATE INDEX IF NOT EXISTS idx_deposit_tx_status ON public.deposit_transactions(status);
CREATE INDEX IF NOT EXISTS idx_deposit_tx_user_id ON public.deposit_transactions(user_id);

-- RLS: seul le service_role (Edge Function / Termux) peut écrire
-- Les users peuvent lire leurs propres deposit_transactions
ALTER TABLE public.deposit_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS deposit_tx_select ON public.deposit_transactions;
CREATE POLICY deposit_tx_select ON public.deposit_transactions
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS deposit_tx_service_insert ON public.deposit_transactions;
CREATE POLICY deposit_tx_service_insert ON public.deposit_transactions
  FOR INSERT TO service_role WITH CHECK (true);

DROP POLICY IF EXISTS deposit_tx_service_update ON public.deposit_transactions;
CREATE POLICY deposit_tx_service_update ON public.deposit_transactions
  FOR UPDATE TO service_role USING (true) WITH CHECK (true);

-- ── Fonction atomique de validation + crédit ─────────────────────────
-- Appelée par l'Edge Function après parsing du SMS
-- Toutes les vérifications + crédit se font en une seule transaction
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
  v_phone TEXT;
  v_diff NUMERIC;
  v_sender_digits TEXT;
  v_user_digits TEXT;
  v_new_id UUID;
BEGIN
  -- 1. Transaction unique — refuser si déjà présente
  SELECT id, status INTO v_existing
    FROM public.deposit_transactions
    WHERE transaction_id = _transaction_id
    LIMIT 1;

  IF v_existing.id IS NOT NULL THEN
    -- Logger le SMS dupliqué
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

  -- 2. Rechercher un dépôt en attente du joueur
  -- On cherche par numéro de téléphone d'abord, puis par montant proche
  SELECT d.id, d.user_id, d.amount, d.user_phone, d.method, p.pseudo
    INTO v_deposit
    FROM public.deposits d
    JOIN public.profiles p ON p.id = d.user_id
    WHERE d.status = 'pending'
      AND (_sender_number IS NOT NULL AND d.user_phone IS NOT NULL
           AND regexp_replace(d.user_phone, '[^0-9]', '', 'g')
             LIKE '%' || regexp_replace(_sender_number, '[^0-9]', '', 'g'))
    ORDER BY d.created_at DESC
    LIMIT 1;

  -- Si pas trouvé par téléphone, chercher par montant proche (sans filtre téléphone)
  IF v_deposit.id IS NULL THEN
    SELECT d.id, d.user_id, d.amount, d.user_phone, d.method, p.pseudo
      INTO v_deposit
      FROM public.deposits d
      JOIN public.profiles p ON p.id = d.user_id
      WHERE d.status = 'pending'
      ORDER BY d.created_at DESC
      LIMIT 1;
  END IF;

  IF v_deposit.id IS NULL THEN
    INSERT INTO public.deposit_transactions(operator, transaction_id, sender_number,
      sender_name, amount, sms_date, sms_content, status, rejection_reason)
    VALUES (_operator, _transaction_id, _sender_number, _sender_name,
      _amount, _sms_date, _sms_content, 'rejected', 'Aucun dépôt en attente');

    RETURN jsonb_build_object(
      'success', false,
      'error', 'NO_PENDING_DEPOSIT',
      'message', 'Aucun dépôt en attente trouvé'
    );
  END IF;

  -- 3. Vérification du montant — tolérance de 200 Ar
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

  -- 4. Vérification du numéro (si enregistré)
  IF v_deposit.user_phone IS NOT NULL AND _sender_number IS NOT NULL THEN
    v_sender_digits := regexp_replace(_sender_number, '[^0-9]', '', 'g');
    v_user_digits := regexp_replace(v_deposit.user_phone, '[^0-9]', '', 'g');
    -- Accepte si l'un est suffixe de l'autre (ex: 26134... vs 034...)
    IF v_sender_digits <> v_user_digits
       AND NOT (v_user_digits LIKE '%' || v_sender_digits)
       AND NOT (v_sender_digits LIKE '%' || v_user_digits) THEN
      INSERT INTO public.deposit_transactions(operator, transaction_id, sender_number,
        sender_name, amount, sms_date, sms_content, status, rejection_reason, user_id, matched_deposit_id)
      VALUES (_operator, _transaction_id, _sender_number, _sender_name,
        _amount, _sms_date, _sms_content, 'rejected',
        'Numéro expéditeur ne correspond pas: SMS=' || _sender_number || ' vs profil=' || v_deposit.user_phone,
        v_deposit.user_id, v_deposit.id);

      RETURN jsonb_build_object(
        'success', false,
        'error', 'PHONE_MISMATCH',
        'message', 'Numéro expéditeur ne correspond pas'
      );
    END IF;
  END IF;

  -- 5. Tout est valide → créditer le portefeuille
  -- Vérifier qu'on n'a pas déjà crédité ce dépôt (double sécurité)
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

  -- Créditer le portefeuille
  UPDATE public.profiles
    SET balance_ar = balance_ar + v_deposit.amount
    WHERE id = v_deposit.user_id;

  -- Enregistrer la transaction
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
    VALUES (v_deposit.user_id, 'deposit', v_deposit.amount, v_deposit.id,
      'Dépôt auto SMS ' || _operator || ' (Trans Id: ' || _transaction_id || ')');

  -- Marquer le dépôt comme approuvé
  UPDATE public.deposits
    SET status = 'approved', processed_at = now()
    WHERE id = v_deposit.id;

  -- Trigger parrainage (si 1er dépôt)
  PERFORM public._referral_on_deposit_trigger(v_deposit.id, v_deposit.user_id, v_deposit.amount);

  -- Enregistrer dans deposit_transactions
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

-- ── Trigger parrainage helper ────────────────────────────────────────
-- Appelé après approbation d'un dépôt pour déclencher le bonus de parrainage
CREATE OR REPLACE FUNCTION public._referral_on_deposit_trigger(_deposit_id UUID, _user_id UUID, _amount NUMERIC)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_parent UUID;
  v_pct NUMERIC;
  v_reward NUMERIC;
  v_verified BOOLEAN;
  v_unlocked BOOLEAN;
  v_first_deposit_at TIMESTAMPTZ;
BEGIN
  SELECT referred_by, phone_verified, referral_unlocked, first_deposit_at
    INTO v_parent, v_verified, v_unlocked, v_first_deposit_at
    FROM public.profiles WHERE id = _user_id;

  IF v_parent IS NOT NULL AND v_verified = true AND v_unlocked = false THEN
    SELECT referral_pct INTO v_pct FROM public.app_settings WHERE id = 1;
    v_reward := _amount * COALESCE(v_pct, 5) / 100.0;
    IF v_reward > 0 THEN
      UPDATE public.profiles SET balance_ar = balance_ar + v_reward WHERE id = v_parent;
      UPDATE public.profiles SET referral_unlocked = true WHERE id = _user_id;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (v_parent, 'referral', v_reward, _deposit_id, 'Parrainage débloqué (dépôt auto SMS)');
    END IF;
  END IF;

  -- Marquer le 1er dépôt si pas déjà fait
  IF v_first_deposit_at IS NULL THEN
    UPDATE public.profiles
      SET first_deposit_at = now(),
          first_deposit_amount = _amount
      WHERE id = _user_id AND first_deposit_at IS NULL;
  END IF;
END $function$;

REVOKE EXECUTE ON FUNCTION public._referral_on_deposit_trigger(UUID, UUID, NUMERIC) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._referral_on_deposit_trigger(UUID, UUID, NUMERIC) TO service_role;
