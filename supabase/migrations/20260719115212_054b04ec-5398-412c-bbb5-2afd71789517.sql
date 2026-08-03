
-- 1) Table
CREATE TABLE IF NOT EXISTS public.withdrawal_debts (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  amount_ar NUMERIC NOT NULL DEFAULT 0 CHECK (amount_ar >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

GRANT SELECT ON public.withdrawal_debts TO authenticated;
GRANT ALL ON public.withdrawal_debts TO service_role;

ALTER TABLE public.withdrawal_debts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "own_or_admin_read" ON public.withdrawal_debts
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id OR public.is_admin());

-- 2) Seed with current unpaid debt for previously approved withdrawals
INSERT INTO public.withdrawal_debts (user_id, amount_ar)
SELECT w.user_id,
       (SUM(w.amount) - COALESCE((
          SELECT SUM(-t.amount) FROM public.transactions t
          WHERE t.user_id = w.user_id AND t.type = 'withdrawal_reconcile'
       ), 0))::numeric AS debt
FROM public.withdrawals w
WHERE w.status = 'approved'
GROUP BY w.user_id
HAVING (SUM(w.amount) - COALESCE((
          SELECT SUM(-t.amount) FROM public.transactions t
          WHERE t.user_id = w.user_id AND t.type = 'withdrawal_reconcile'
       ), 0)) > 0
ON CONFLICT (user_id) DO UPDATE SET amount_ar = EXCLUDED.amount_ar, updated_at = now();

-- 3) Update admin_process_deposit to auto-debit debt on approval
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
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  SELECT * INTO v_dep FROM public.deposits WHERE id=_id FOR UPDATE;
  IF v_dep.id IS NULL OR v_dep.status <> 'pending' THEN RAISE EXCEPTION 'Dépôt non valide'; END IF;

  IF _approve THEN
    UPDATE public.deposits SET status='approved', processed_at=now() WHERE id=_id;

    -- Check outstanding debt
    SELECT amount_ar INTO v_debt FROM public.withdrawal_debts WHERE user_id = v_dep.user_id FOR UPDATE;
    v_debt := COALESCE(v_debt, 0);
    v_repay := LEAST(v_debt, v_dep.amount);
    v_credit := v_dep.amount - v_repay;

    -- Full deposit transaction (transparent)
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
  ELSE
    UPDATE public.deposits SET status='rejected', processed_at=now() WHERE id=_id;
    INSERT INTO public.notifications(user_id, kind, title, body, link, ref_id)
    VALUES (v_dep.user_id, 'deposit',
      'Dépôt refusé ❌',
      format('Votre dépôt de %s Ar a été refusé.', to_char(v_dep.amount,'FM999G999G999')),
      '/history', _id);
  END IF;
END $function$;
