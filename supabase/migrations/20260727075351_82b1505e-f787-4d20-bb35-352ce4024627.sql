
-- 1) Audit log table
CREATE TABLE IF NOT EXISTS public.balance_audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  old_balance numeric NOT NULL,
  new_balance numeric NOT NULL,
  delta numeric NOT NULL,
  db_user text,
  txid bigint,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.balance_audit_log TO authenticated;
GRANT ALL ON public.balance_audit_log TO service_role;
ALTER TABLE public.balance_audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "audit_admin_read" ON public.balance_audit_log;
CREATE POLICY "audit_admin_read" ON public.balance_audit_log FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::app_role));
CREATE INDEX IF NOT EXISTS idx_balance_audit_user ON public.balance_audit_log(user_id, created_at DESC);

-- 2) Trigger AFTER UPDATE OF balance_ar
CREATE OR REPLACE FUNCTION public._trg_balance_audit()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.balance_ar IS DISTINCT FROM OLD.balance_ar THEN
    INSERT INTO public.balance_audit_log(user_id, old_balance, new_balance, delta, db_user, txid)
    VALUES (NEW.id, OLD.balance_ar, NEW.balance_ar, NEW.balance_ar - OLD.balance_ar, current_user, txid_current());
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_balance_audit ON public.profiles;
CREATE TRIGGER trg_balance_audit
  AFTER UPDATE OF balance_ar ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public._trg_balance_audit();

-- 3) Guard : les bots ne reçoivent/perdent jamais d'argent
CREATE OR REPLACE FUNCTION public._trg_no_bot_money()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF COALESCE(NEW.is_bot,false) = true AND NEW.balance_ar IS DISTINCT FROM COALESCE(OLD.balance_ar, 0) THEN
    NEW.balance_ar := COALESCE(OLD.balance_ar, 0);
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_no_bot_money ON public.profiles;
CREATE TRIGGER trg_no_bot_money
  BEFORE UPDATE OF balance_ar ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public._trg_no_bot_money();

-- Bloque aussi les insertions de transactions pour les bots (idempotent : skippe silencieusement)
CREATE OR REPLACE FUNCTION public._trg_no_bot_tx()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_isbot boolean;
BEGIN
  SELECT COALESCE(is_bot,false) INTO v_isbot FROM public.profiles WHERE id = NEW.user_id;
  IF v_isbot THEN RETURN NULL; END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_no_bot_tx ON public.transactions;
CREATE TRIGGER trg_no_bot_tx
  BEFORE INSERT ON public.transactions
  FOR EACH ROW EXECUTE FUNCTION public._trg_no_bot_tx();

-- 4) RPC admin : rapport de réconciliation (lecture seule)
CREATE OR REPLACE FUNCTION public.admin_reconcile_balances()
RETURNS TABLE(user_id uuid, pseudo text, balance numeric, tx_sum numeric, diff numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN RAISE EXCEPTION 'Forbidden'; END IF;
  RETURN QUERY
  SELECT p.id, p.pseudo, p.balance_ar::numeric,
         COALESCE((SELECT SUM(amount) FROM public.transactions WHERE user_id = p.id),0)::numeric AS tx_sum,
         (p.balance_ar - COALESCE((SELECT SUM(amount) FROM public.transactions WHERE user_id = p.id),0))::numeric AS diff
  FROM public.profiles p
  WHERE COALESCE(p.is_bot,false) = false
    AND (p.balance_ar - COALESCE((SELECT SUM(amount) FROM public.transactions WHERE user_id = p.id),0)) <> 0
  ORDER BY ABS(p.balance_ar - COALESCE((SELECT SUM(amount) FROM public.transactions WHERE user_id = p.id),0)) DESC;
END $$;
GRANT EXECUTE ON FUNCTION public.admin_reconcile_balances() TO authenticated;

-- 5) RPC admin : alignement automatique
--   Stratégie :
--     target_balance = GREATEST(sum_txs, 0)
--     Insère UNE transaction 'admin_adjust' d'un montant tel qu'après :
--       - le solde final = target_balance
--       - sum(transactions) = target_balance (ledger auto-cohérent)
--     Concrètement, on met à jour le solde et on insère une transaction dont le montant vaut (target - old_sum),
--     ce qui rend le ledger cohérent avec le nouveau solde.
CREATE OR REPLACE FUNCTION public.admin_align_balances()
RETURNS TABLE(user_id uuid, pseudo text, old_balance numeric, new_balance numeric, tx_delta numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record; v_target numeric; v_tx_delta numeric;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN RAISE EXCEPTION 'Forbidden'; END IF;
  FOR r IN
    SELECT p.id, p.pseudo, p.balance_ar::numeric AS bal,
           COALESCE((SELECT SUM(amount) FROM public.transactions WHERE user_id = p.id),0)::numeric AS txs
    FROM public.profiles p
    WHERE COALESCE(p.is_bot,false) = false
    FOR UPDATE OF p
  LOOP
    IF r.bal = r.txs THEN CONTINUE; END IF;
    v_target := GREATEST(r.txs, 0);
    v_tx_delta := v_target - r.txs;  -- rend le ledger cohérent avec la nouvelle balance
    -- update balance to target
    UPDATE public.profiles SET balance_ar = v_target WHERE id = r.id;
    -- insère une transaction traçable qui reflète l'ajustement
    IF v_tx_delta <> 0 THEN
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (r.id, 'admin_adjust', v_tx_delta, NULL,
              'Réconciliation auto : alignement ledger (ancien solde=' || r.bal || ', txs=' || r.txs || ')');
    END IF;
    user_id := r.id; pseudo := r.pseudo; old_balance := r.bal; new_balance := v_target; tx_delta := v_tx_delta;
    RETURN NEXT;
  END LOOP;
END $$;
GRANT EXECUTE ON FUNCTION public.admin_align_balances() TO authenticated;

-- 6) KPI Finance
CREATE OR REPLACE FUNCTION public.admin_finance_kpi()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN RAISE EXCEPTION 'Forbidden'; END IF;
  SELECT jsonb_build_object(
    'total_deposits',   COALESCE((SELECT SUM(amount) FROM public.transactions WHERE type = 'deposit'),0),
    'total_withdraws',  COALESCE((SELECT -SUM(amount) FROM public.transactions WHERE type = 'withdraw'),0),
    'total_stakes',     COALESCE((SELECT -SUM(amount) FROM public.transactions WHERE type LIKE '%stake' OR type = 'stake'),0),
    'total_payouts',    COALESCE((SELECT SUM(amount) FROM public.transactions WHERE type LIKE '%win' OR type LIKE '%payout' OR type = 'win'),0),
    'total_refunds',    COALESCE((SELECT SUM(amount) FROM public.transactions WHERE type LIKE '%refund' OR type = 'refund'),0),
    'total_bonus',      COALESCE((SELECT SUM(amount) FROM public.transactions WHERE type IN ('bonus','referral')),0),
    'sum_balances',     COALESCE((SELECT SUM(balance_ar) FROM public.profiles WHERE COALESCE(is_bot,false)=false),0),
    'sum_transactions', COALESCE((SELECT SUM(amount) FROM public.transactions WHERE user_id IN (SELECT id FROM public.profiles WHERE COALESCE(is_bot,false)=false)),0),
    'pending_withdrawals', COALESCE((SELECT SUM(amount) FROM public.withdrawals WHERE status = 'pending'),0),
    'pending_deposits',    COALESCE((SELECT SUM(amount) FROM public.deposits WHERE status = 'pending'),0)
  ) INTO v;
  v := v || jsonb_build_object('reconciliation_gap', (v->>'sum_balances')::numeric - (v->>'sum_transactions')::numeric);
  RETURN v;
END $$;
GRANT EXECUTE ON FUNCTION public.admin_finance_kpi() TO authenticated;
