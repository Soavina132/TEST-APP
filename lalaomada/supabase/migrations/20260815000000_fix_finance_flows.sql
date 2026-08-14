-- ============================================================
-- FIX FLUX FINANCIER
-- ============================================================

-- ============================================================
-- 1. CRITIQUE: admin_process_withdrawal — double débit + pas de remboursement
--    create_withdrawal débite immédiatement (balance_ar -= amount)
--    admin_process_withdrawal débitait ENCORE → double débit
--    Et ne remboursait pas en cas de refus → argent perdu
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_process_withdrawal(_id uuid, _approve boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_w public.withdrawals%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  SELECT * INTO v_w FROM public.withdrawals WHERE id=_id FOR UPDATE;
  IF v_w.id IS NULL OR v_w.status <> 'pending' THEN RAISE EXCEPTION 'Retrait non valide'; END IF;

  IF _approve THEN
    -- Le solde a déjà été débité par create_withdrawal
    -- On valide juste le retrait, pas de second débit
    UPDATE public.withdrawals SET status='approved', processed_at=now() WHERE id=_id;

    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_w.user_id,'withdraw',-v_w.amount,_id,'Retrait approuvé');

    INSERT INTO public.notifications(user_id, kind, title, body, link, ref_id)
    VALUES (v_w.user_id, 'withdraw',
      'Retrait approuvé ✅',
      format('Votre retrait de %s Ar a été validé.', to_char(v_w.amount,'FM999G999G999')),
      '/history', _id);
  ELSE
    -- Rembourser le montant débité par create_withdrawal
    UPDATE public.profiles SET balance_ar = balance_ar + v_w.amount WHERE id = v_w.user_id;
    UPDATE public.withdrawals SET status='rejected', processed_at=now() WHERE id=_id;

    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_w.user_id,'withdraw_refund',v_w.amount,_id,'Retrait refusé - montant remboursé');

    INSERT INTO public.notifications(user_id, kind, title, body, link, ref_id)
    VALUES (v_w.user_id, 'withdraw',
      'Retrait refusé ❌',
      format('Votre retrait de %s Ar a été refusé. %s Ar ont été crédités sur votre solde.',
        to_char(v_w.amount,'FM999G999G999'), to_char(v_w.amount,'FM999G999G999')),
      '/history', _id);
  END IF;
END $function$;

-- ============================================================
-- 2. withdrawal_debts — pas de politique RLS → default-deny
--    Ajouter au moins admin SELECT/UPDATE/INSERT/DELETE
-- ============================================================

CREATE POLICY withdrawal_debts_admin_select ON public.withdrawal_debts
  FOR SELECT TO authenticated
  USING (public.is_admin());

CREATE POLICY withdrawal_debts_admin_update ON public.withdrawal_debts
  FOR UPDATE TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY withdrawal_debts_admin_insert ON public.withdrawal_debts
  FOR INSERT TO authenticated
  WITH CHECK (public.is_admin());

CREATE POLICY withdrawal_debts_admin_delete ON public.withdrawal_debts
  FOR DELETE TO authenticated
  USING (public.is_admin());

-- ============================================================
-- 3. transactions — ajouter INSERT pour les fonctions SECURITY DEFINER
--    qui ne sont pas owner (elles bypass RLS mais au cas où)
--    Actuellement seul is_admin() peut INSERT, ce qui est OK car
--    toutes les fonctions sont SECURITY DEFINER.
--    Mais ajoutons une policy pour service_role pour être sûr
-- ============================================================
-- Pas nécessaire: toutes les fonctions financières sont SECURITY DEFINER
-- et bypassent RLS pour les INSERT.

-- ============================================================
-- 4. notifications — pas de politique INSERT
--    Les fonctions SECURITY DEFINER bypass RLS donc ça marche,
--    mais ajoutons quand même pour robustesse
-- ============================================================
CREATE POLICY notifications_admin_insert ON public.notifications
  FOR INSERT TO authenticated
  WITH CHECK (public.is_admin());

-- ============================================================
-- 5. GRANT EXECUTE manquants sur fonctions financières
-- ============================================================

-- credit_user_balance et debit_user_balance n'ont pas EXECUTE pour authenticated
-- C'est OK car ils sont appelés par d'autres fonctions SECURITY DEFINER
-- Mais au cas où une fonction non-SECURITY DEFINER les appelle:
GRANT EXECUTE ON FUNCTION public.credit_user_balance(uuid, numeric, text, uuid, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.debit_user_balance(uuid, numeric, text, uuid, text, jsonb) TO authenticated;

-- _guard_balance_non_negative est un trigger, pas besoin de GRANT

-- _petanque_settle n'est pas SECURITY DEFINER et n'a peut-être pas EXECUTE
GRANT EXECUTE ON FUNCTION public._petanque_settle(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public._petanque_end_round(uuid) TO authenticated;
