
CREATE OR REPLACE FUNCTION public.admin_process_withdrawal(_id uuid, _approve boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_w public.withdrawals%ROWTYPE;
  v_balance numeric;
  v_extra numeric;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  SELECT * INTO v_w FROM public.withdrawals WHERE id=_id FOR UPDATE;
  IF v_w.id IS NULL OR v_w.status <> 'pending' THEN RAISE EXCEPTION 'Retrait non valide'; END IF;

  IF _approve THEN
    SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_w.user_id FOR UPDATE;
    IF v_balance IS NULL THEN RAISE EXCEPTION 'Profil introuvable'; END IF;
    IF v_balance < v_w.amount THEN
      RAISE EXCEPTION 'Solde insuffisant pour approuver ce retrait (solde: % Ar, demandé: % Ar)', v_balance, v_w.amount;
    END IF;

    -- Remise à zéro du solde
    UPDATE public.profiles SET balance_ar = 0 WHERE id = v_w.user_id;
    UPDATE public.withdrawals SET status='approved', processed_at=now() WHERE id=_id;

    -- Transaction principale : retrait
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_w.user_id,'withdraw',-v_w.amount,_id,'Retrait approuvé');

    -- Ajustement pour le reliquat (solde - montant demandé)
    v_extra := v_balance - v_w.amount;
    IF v_extra > 0 THEN
      INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
        VALUES (v_w.user_id,'balance_reset', -v_extra, _id,
          format('Remise à zéro du solde après retrait (reliquat: %s Ar)', to_char(v_extra,'FM999G999G999')));
    END IF;

    INSERT INTO public.notifications(user_id, kind, title, body, link, ref_id)
    VALUES (v_w.user_id, 'withdraw',
      'Retrait approuvé ✅',
      format('Votre retrait de %s Ar a été validé. Votre solde a été remis à zéro.', to_char(v_w.amount,'FM999G999G999')),
      '/history', _id);
  ELSE
    UPDATE public.withdrawals SET status='rejected', processed_at=now() WHERE id=_id;
    INSERT INTO public.notifications(user_id, kind, title, body, link, ref_id)
    VALUES (v_w.user_id, 'withdraw',
      'Retrait refusé ❌',
      format('Votre retrait de %s Ar a été refusé.', to_char(v_w.amount,'FM999G999G999')),
      '/history', _id);
  END IF;
END $function$;
