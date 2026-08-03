
CREATE OR REPLACE FUNCTION public.request_withdrawal(_amount numeric, _method text, _user_phone text, _recipient_name text DEFAULT NULL::text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_balance numeric;
  v_min numeric;
  v_pending numeric;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentification requise'; END IF;
  IF _amount IS NULL OR _amount <= 0 THEN RAISE EXCEPTION 'Montant invalide'; END IF;
  IF _method IS NULL OR btrim(_method) = '' THEN RAISE EXCEPTION 'Opérateur requis'; END IF;
  IF _user_phone IS NULL OR btrim(_user_phone) = '' THEN RAISE EXCEPTION 'Numéro requis'; END IF;

  SELECT COALESCE(min_withdraw, 0) INTO v_min FROM public.app_settings WHERE id = 1;
  IF v_min IS NOT NULL AND _amount < v_min THEN
    RAISE EXCEPTION 'Montant inférieur au minimum autorisé (% Ar)', v_min;
  END IF;

  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance IS NULL THEN RAISE EXCEPTION 'Profil introuvable'; END IF;

  -- Vérifie solde en tenant compte des retraits pending déjà en cours
  SELECT COALESCE(SUM(amount),0) INTO v_pending FROM public.withdrawals
    WHERE user_id = v_uid AND status = 'pending';
  IF v_balance < (_amount + v_pending) THEN
    RAISE EXCEPTION 'Solde insuffisant (retraits en attente inclus)';
  END IF;

  INSERT INTO public.withdrawals(user_id, amount, method, user_phone, recipient_name, status)
  VALUES (v_uid, _amount, _method, btrim(_user_phone), NULLIF(btrim(COALESCE(_recipient_name,'')), ''), 'pending')
  RETURNING id INTO v_id;

  INSERT INTO public.notifications(user_id, kind, title, body, link, ref_id)
  VALUES (
    v_uid, 'withdraw',
    'Demande de retrait enregistrée',
    format('Votre demande de %s Ar est en attente de validation.', to_char(_amount, 'FM999G999G999')),
    '/history', v_id
  );

  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_process_withdrawal(_id uuid, _approve boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_w public.withdrawals%ROWTYPE; v_balance numeric;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  SELECT * INTO v_w FROM public.withdrawals WHERE id=_id FOR UPDATE;
  IF v_w.id IS NULL OR v_w.status <> 'pending' THEN RAISE EXCEPTION 'Retrait non valide'; END IF;

  IF _approve THEN
    -- Débit du solde au moment de l'approbation
    SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_w.user_id FOR UPDATE;
    IF v_balance IS NULL THEN RAISE EXCEPTION 'Profil introuvable'; END IF;
    IF v_balance < v_w.amount THEN
      RAISE EXCEPTION 'Solde insuffisant pour approuver ce retrait (solde: % Ar, demandé: % Ar)', v_balance, v_w.amount;
    END IF;

    UPDATE public.profiles SET balance_ar = balance_ar - v_w.amount WHERE id = v_w.user_id;
    UPDATE public.withdrawals SET status='approved', processed_at=now() WHERE id=_id;

    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_w.user_id,'withdraw',-v_w.amount,_id,'Retrait approuvé');
    INSERT INTO public.notifications(user_id, kind, title, body, link, ref_id)
    VALUES (v_w.user_id, 'withdraw',
      'Retrait approuvé ✅',
      format('Votre retrait de %s Ar a été validé et débité de votre solde.', to_char(v_w.amount,'FM999G999G999')),
      '/history', _id);
  ELSE
    -- Aucun remboursement nécessaire (le solde n'a pas été réservé)
    UPDATE public.withdrawals SET status='rejected', processed_at=now() WHERE id=_id;
    INSERT INTO public.notifications(user_id, kind, title, body, link, ref_id)
    VALUES (v_w.user_id, 'withdraw',
      'Retrait refusé ❌',
      format('Votre retrait de %s Ar a été refusé.', to_char(v_w.amount,'FM999G999G999')),
      '/history', _id);
  END IF;
END $function$;
