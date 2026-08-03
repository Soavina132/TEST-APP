ALTER TABLE public.referral_settings
  ADD COLUMN IF NOT EXISTS first_deposit_bonus_ar numeric NOT NULL DEFAULT 25;

CREATE UNIQUE INDEX IF NOT EXISTS referral_events_first_deposit_uniq
  ON public.referral_events (referee_id) WHERE event_type = 'first_deposit_bonus';

CREATE OR REPLACE FUNCTION public.admin_process_deposit(_id uuid, _approve boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_dep public.deposits%ROWTYPE;
  v_debt NUMERIC;
  v_repay NUMERIC;
  v_credit NUMERIC;
  v_ref uuid;
  v_bonus NUMERIC;
  v_prev int;
  v_pseudo text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  SELECT * INTO v_dep FROM public.deposits WHERE id=_id FOR UPDATE;
  IF v_dep.id IS NULL OR v_dep.status <> 'pending' THEN RAISE EXCEPTION 'Dépôt non valide'; END IF;

  IF _approve THEN
    SELECT COUNT(*) INTO v_prev FROM public.deposits d
      WHERE d.user_id = v_dep.user_id AND d.status = 'approved' AND d.id <> _id;

    UPDATE public.deposits SET status='approved', processed_at=now() WHERE id=_id;

    SELECT amount_ar INTO v_debt FROM public.withdrawal_debts WHERE user_id = v_dep.user_id FOR UPDATE;
    v_debt := COALESCE(v_debt, 0);
    v_repay := LEAST(v_debt, v_dep.amount);
    v_credit := v_dep.amount - v_repay;

    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_dep.user_id,'deposit',v_dep.amount,_id,'Dépôt approuvé');

    IF v_repay > 0 THEN
      UPDATE public.withdrawal_debts
        SET amount_ar = amount_ar - v_repay, updated_at = now()
        WHERE user_id = v_dep.user_id;
      DELETE FROM public.withdrawal_debts WHERE user_id = v_dep.user_id AND amount_ar <= 0;
      INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
        VALUES (v_dep.user_id,'debt_repayment', -v_repay, _id,
          format('Remboursement automatique de retrait antérieur (%s Ar)', to_char(v_repay,'FM999G999G999')));
    END IF;

    IF v_credit > 0 THEN
      UPDATE public.profiles SET balance_ar = balance_ar + v_credit WHERE id = v_dep.user_id;
    END IF;

    INSERT INTO public.notifications(user_id, kind, title, body, link, ref_id)
    VALUES (v_dep.user_id, 'deposit',
      'Dépôt approuvé ✅',
      CASE WHEN v_repay > 0 THEN
        format('Dépôt de %s Ar approuvé. %s Ar utilisés pour régler un retrait antérieur, %s Ar crédités.',
          to_char(v_dep.amount,'FM999G999G999'),
          to_char(v_repay,'FM999G999G999'),
          to_char(v_credit,'FM999G999G999'))
      ELSE
        format('Votre dépôt de %s Ar a été crédité sur votre solde.', to_char(v_dep.amount,'FM999G999G999'))
      END,
      '/history', _id);

    -- Bonus parrain sur le tout premier dépôt validé du filleul
    IF v_prev = 0 THEN
      SELECT p.referred_by, p.pseudo INTO v_ref, v_pseudo FROM public.profiles p WHERE p.id = v_dep.user_id;
      SELECT COALESCE(first_deposit_bonus_ar, 0) INTO v_bonus FROM public.referral_settings WHERE id = 1;
      IF v_ref IS NOT NULL AND v_ref <> v_dep.user_id AND COALESCE(v_bonus,0) > 0
         AND COALESCE((SELECT enabled FROM public.referral_settings WHERE id=1), true) THEN
        BEGIN
          INSERT INTO public.referral_events(referrer_id, referee_id, event_type, reward_amount, note)
          VALUES (v_ref, v_dep.user_id, 'first_deposit_bonus', v_bonus,
                  format('Bonus premier dépôt de %s', COALESCE(v_pseudo,'votre filleul')));

          UPDATE public.profiles SET balance_ar = balance_ar + v_bonus WHERE id = v_ref;

          INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
          VALUES (v_ref,'referral_bonus', v_bonus, _id,
                  format('Bonus parrainage : premier dépôt de %s', COALESCE(v_pseudo,'filleul')));

          INSERT INTO public.notifications(user_id, kind, title, body, link, ref_id)
          VALUES (v_ref, 'referral', 'Bonus parrainage 🎁',
                  format('%s Ar crédités : votre filleul %s a validé son premier dépôt.',
                         to_char(v_bonus,'FM999G999G999'), COALESCE(v_pseudo,'')),
                  '/parrainage', _id);
        EXCEPTION WHEN unique_violation THEN
          NULL;
        END;
      END IF;
    END IF;
  ELSE
    UPDATE public.deposits SET status='rejected', processed_at=now() WHERE id=_id;
    INSERT INTO public.notifications(user_id, kind, title, body, link, ref_id)
    VALUES (v_dep.user_id, 'deposit',
      'Dépôt refusé ❌',
      format('Votre dépôt de %s Ar a été refusé.', to_char(v_dep.amount,'FM999G999G999')),
      '/history', _id);
  END IF;
END $function$;