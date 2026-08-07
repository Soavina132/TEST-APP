-- ═══════════════════════════════════════════════════════════════════════════
-- CORRECTION DES 6 BUGS DU FLUX FINANCIER
-- Date: 2026-08-07
-- 
-- Bug 1 (CRITIQUE): create_withdrawal n'existait pas → retraits cassés
-- Bug 2 (CRITIQUE): trigger _validate_deposit_insert rejetait les dépôts
-- Bug 3 (HAUT): double-dépense sur retraits (solde non réservé)
-- Bug 4 (MOYEN): infos bancaires perdues (colonnes manquantes)
-- Bug 5 (MOYEN): admin affichait mauvaise référence
-- Bug 6 (BAS): limites incohérentes (1 vs 5)
-- ═══════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- Bug 2 (CRITIQUE): Fix du trigger _validate_deposit_insert
-- Le regex ^[A-Za-z0-9]+$ rejetait les _ et - présents dans l'UUID généré
-- par create_deposit ('deposit_550e8400-e29b-...')
-- Solution: valider user_reference (la vraie réf du user) au lieu de reference
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._validate_deposit_insert()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_pending_count INT;
  v_min_deposit   NUMERIC;
BEGIN
  -- Rate limit: max 3 dépôts en attente (aligné avec create_deposit)
  SELECT count(*) INTO v_pending_count FROM public.deposits
  WHERE user_id = NEW.user_id AND status = 'pending';
  IF v_pending_count >= 3 THEN
    RAISE EXCEPTION 'Trop de dépôts en attente (max 3). Veuillez attendre la validation.';
  END IF;

  -- Valider user_reference (la référence fournie par l'utilisateur)
  -- Pas reference qui est un identifiant interne généré
  IF NEW.user_reference IS NOT NULL AND length(trim(NEW.user_reference)) > 0 THEN
    IF length(trim(NEW.user_reference)) < 3 THEN
      RAISE EXCEPTION 'Code de référence trop court (minimum 3 caractères)';
    END IF;
    -- Autoriser: alphanumérique, points, espaces, tirets (format Orange: PP260519.1245.C46612)
    IF NEW.user_reference !~ '^[A-Za-z0-9. \-]+$' THEN
      RAISE EXCEPTION 'Référence invalide: caractères alphanumériques uniquement';
    END IF;
  END IF;

  -- Normaliser la méthode
  NEW.method := lower(trim(NEW.method));

  -- Valider le montant minimum
  SELECT min_deposit INTO v_min_deposit FROM public.app_settings WHERE id = 1;
  IF v_min_deposit IS NOT NULL AND NEW.amount < v_min_deposit THEN
    RAISE EXCEPTION 'Montant minimum: % Ar', v_min_deposit;
  END IF;

  RETURN NEW;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Bug 4 (MOYEN): Ajouter les colonnes bancaires à withdrawals
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE public.withdrawals ADD COLUMN IF NOT EXISTS bank_name TEXT;
ALTER TABLE public.withdrawals ADD COLUMN IF NOT EXISTS bank_account_number TEXT;

-- ═══════════════════════════════════════════════════════════════════════════
-- Bug 1 (CRITIQUE) + Bug 3 (HAUT): Créer create_withdrawal
-- 
-- Correspond exactement aux paramètres envoyés par le frontend:
--   _amount, _method, _bank_name, _bank_account_number, _phone_number
--
-- Bug 3 fix: le solde est RÉSERVÉ (débité) au moment de la demande.
-- Si l'admin rejette, le montant est remboursé.
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.create_withdrawal(
  _amount              NUMERIC,
  _method              TEXT,
  _bank_name           TEXT DEFAULT NULL,
  _bank_account_number TEXT DEFAULT NULL,
  _phone_number        TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid            UUID := auth.uid();
  v_balance        NUMERIC;
  v_min_withdraw   NUMERIC;
  v_pending_count  INT;
  v_withdrawal_id  UUID;
  v_method         TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _amount IS NULL OR _amount <= 0 THEN RAISE EXCEPTION 'Montant invalide'; END IF;
  IF _method IS NULL OR length(trim(_method)) = 0 THEN RAISE EXCEPTION 'Méthode requise'; END IF;

  v_method := lower(trim(_method));

  -- Valider selon la méthode
  IF v_method = 'bank' THEN
    IF _bank_name IS NULL OR length(trim(_bank_name)) = 0 THEN
      RAISE EXCEPTION 'Nom de la banque requis';
    END IF;
    IF _bank_account_number IS NULL OR length(trim(_bank_account_number)) = 0 THEN
      RAISE EXCEPTION 'Numéro de compte bancaire requis';
    END IF;
  ELSE
    IF _phone_number IS NULL OR length(trim(_phone_number)) < 8 THEN
      RAISE EXCEPTION 'Numéro de téléphone requis';
    END IF;
  END IF;

  -- Rate limit: max 3 retraits en attente
  SELECT count(*) INTO v_pending_count FROM public.withdrawals
  WHERE user_id = v_uid AND status = 'pending';
  IF v_pending_count >= 3 THEN
    RAISE EXCEPTION 'Trop de retraits en attente (max 3)';
  END IF;

  -- Vérifier le minimum
  SELECT min_withdraw INTO v_min_withdraw FROM public.app_settings WHERE id = 1;
  IF v_min_withdraw IS NOT NULL AND _amount < v_min_withdraw THEN
    RAISE EXCEPTION 'Montant minimum: % Ar', v_min_withdraw;
  END IF;

  -- Vérifier le solde AVEC verrou (Bug 3 fix: on débite immédiatement)
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance IS NULL THEN RAISE EXCEPTION 'Profil introuvable'; END IF;
  IF v_balance < _amount THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  -- RÉSERVER le montant: débit immédiat (Bug 3 fix)
  UPDATE public.profiles SET balance_ar = balance_ar - _amount WHERE id = v_uid;

  -- Insérer la demande de retrait
  INSERT INTO public.withdrawals(
    user_id, amount, method, user_phone, status,
    recipient_name, bank_name, bank_account_number
  )
  VALUES(
    v_uid, _amount, v_method,
    CASE WHEN v_method = 'bank' THEN NULL ELSE trim(_phone_number) END,
    'pending'::public.tx_status,
    NULL,
    CASE WHEN v_method = 'bank' THEN trim(_bank_name) ELSE NULL END,
    CASE WHEN v_method = 'bank' THEN trim(_bank_account_number) ELSE NULL END
  )
  RETURNING id INTO v_withdrawal_id;

  -- Logger la transaction
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
  VALUES(v_uid, 'withdraw', -_amount, v_withdrawal_id, 'Retrait demandé (solde réservé)');

  RETURN v_withdrawal_id;
END $$;

GRANT EXECUTE ON FUNCTION public.create_withdrawal(NUMERIC, TEXT, TEXT, TEXT, TEXT) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.create_withdrawal(NUMERIC, TEXT, TEXT, TEXT, TEXT) FROM anon;

-- ═══════════════════════════════════════════════════════════════════════════
-- Bug 3 (HAUT): Mettre à jour admin_process_withdrawal
-- Le solde est déjà débité à la demande. 
-- - Approbation: ne pas re-débiter, juste marquer approved
-- - Rejet: REMBOURSER le montant au joueur
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.admin_process_withdrawal(_id UUID, _approve BOOLEAN)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_w         public.withdrawals%ROWTYPE;
  v_fee_pct   NUMERIC;
  v_fee       NUMERIC;
  v_net       NUMERIC;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  SELECT * INTO v_w FROM public.withdrawals WHERE id=_id FOR UPDATE;
  IF v_w.id IS NULL OR v_w.status <> 'pending' THEN RAISE EXCEPTION 'Retrait non valide'; END IF;

  IF _approve THEN
    -- Le solde a déjà été débité à la demande (create_withdrawal)
    SELECT withdrawal_fee_pct INTO v_fee_pct FROM public.app_settings WHERE id = 1;
    v_fee := ROUND(v_w.amount * COALESCE(v_fee_pct, 0) / 100.0, 0);
    v_net := v_w.amount - v_fee;

    UPDATE public.withdrawals
      SET status='approved', processed_at=now(), fee_amount = v_fee
      WHERE id=_id;
    UPDATE public.transactions
      SET note = 'Retrait approuvé (' || v_w.amount || ' Ar — frais: ' || v_fee || ' Ar — net: ' || v_net || ' Ar)'
      WHERE ref_id = _id AND type = 'withdraw';
  ELSE
    -- REJET: rembourser le montant au joueur (le solde avait été réservé)
    UPDATE public.profiles SET balance_ar = balance_ar + v_w.amount WHERE id=v_w.user_id;
    UPDATE public.withdrawals SET status='rejected', processed_at=now() WHERE id=_id;
    UPDATE public.transactions
      SET note = 'Retrait rejeté — montant remboursé', amount = v_w.amount
      WHERE ref_id = _id AND type = 'withdraw';
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Bug 6 (BAS): Aligner create_deposit à 3 dépôts en attente max
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.create_deposit(
  _amount numeric,
  _method text,
  _user_phone text DEFAULT NULL,
  _user_reference text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
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

  -- Max 3 dépôts en attente (aligné avec le trigger)
  SELECT count(*) INTO v_pending_count
    FROM public.deposits
    WHERE user_id = v_uid AND status = 'pending';
  IF v_pending_count >= 3 THEN
    RAISE EXCEPTION 'Vous avez trop de dépôts en attente. Attendez leur validation.';
  END IF;

  INSERT INTO public.deposits(user_id, amount, method, user_phone, user_reference, status, reference)
    VALUES (v_uid, _amount, _method, trim(_user_phone), trim(_user_reference),
            'pending'::public.tx_status, 'deposit_' || gen_random_uuid()::text)
    RETURNING id INTO v_deposit_id;

  RETURN v_deposit_id;
END $$;

GRANT EXECUTE ON FUNCTION public.create_deposit(NUMERIC, TEXT, TEXT, TEXT) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.create_deposit(NUMERIC, TEXT, TEXT, TEXT) FROM anon;

-- ═══════════════════════════════════════════════════════════════════════════
-- Conserver request_withdrawal pour rétro-compatibilité (aussi avec réservation)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.request_withdrawal(
  _amount        NUMERIC,
  _method        TEXT,
  _user_phone    TEXT,
  _recipient_name TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid            UUID := auth.uid();
  v_balance        NUMERIC;
  v_min_withdraw   NUMERIC;
  v_pending_count  INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _amount <= 0 THEN RAISE EXCEPTION 'Montant invalide'; END IF;
  IF _method IS NULL OR length(trim(_method)) = 0 THEN RAISE EXCEPTION 'Méthode requise'; END IF;
  IF _user_phone IS NULL OR length(trim(_user_phone)) = 0 THEN RAISE EXCEPTION 'Numéro requis'; END IF;

  SELECT count(*) INTO v_pending_count FROM public.withdrawals
  WHERE user_id = v_uid AND status = 'pending';
  IF v_pending_count >= 3 THEN RAISE EXCEPTION 'Trop de retraits en attente (max 3)'; END IF;

  SELECT min_withdraw INTO v_min_withdraw FROM public.app_settings WHERE id = 1;
  IF v_min_withdraw IS NOT NULL AND _amount < v_min_withdraw THEN
    RAISE EXCEPTION 'Montant minimum: % Ar', v_min_withdraw;
  END IF;

  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance IS NULL THEN RAISE EXCEPTION 'Profil introuvable'; END IF;
  IF v_balance < _amount THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  -- Bug 3 fix: réserver le solde immédiatement
  UPDATE public.profiles SET balance_ar = balance_ar - _amount WHERE id = v_uid;

  INSERT INTO public.withdrawals(user_id, amount, method, user_phone, status, recipient_name)
  VALUES(v_uid, _amount, lower(trim(_method)), trim(_user_phone), 'pending'::public.tx_status, trim(_recipient_name));

  INSERT INTO public.transactions(user_id, type, amount, note)
  VALUES(v_uid, 'withdraw', -_amount, 'Retrait demandé (solde réservé)');
END $$;

GRANT EXECUTE ON FUNCTION public.request_withdrawal(NUMERIC, TEXT, TEXT, TEXT) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.request_withdrawal(NUMERIC, TEXT, TEXT, TEXT) FROM anon;
