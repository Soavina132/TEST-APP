CREATE OR REPLACE FUNCTION public.debit_user_balance(
  _user_id UUID, _amount NUMERIC, _type TEXT,
  _ref_id UUID DEFAULT NULL, _note TEXT DEFAULT NULL, _meta JSONB DEFAULT NULL
) RETURNS NUMERIC LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _new_balance NUMERIC; _is_bot BOOLEAN;
BEGIN
  IF _amount IS NULL OR _amount <= 0 THEN RAISE EXCEPTION 'debit: montant invalide (%)', _amount; END IF;
  SELECT is_bot INTO _is_bot FROM public.profiles WHERE id = _user_id;
  IF _is_bot THEN RETURN 0; END IF;
  UPDATE public.profiles SET balance_ar = balance_ar - _amount
  WHERE id = _user_id AND balance_ar >= _amount
  RETURNING balance_ar INTO _new_balance;
  IF _new_balance IS NULL THEN RAISE EXCEPTION 'Solde insuffisant' USING ERRCODE = 'P0001'; END IF;
  INSERT INTO public.transactions (user_id, amount, type, ref_id, note, meta)
  VALUES (_user_id, -_amount, _type, _ref_id, _note, COALESCE(_meta, '{}'::jsonb));
  RETURN _new_balance;
END; $$;
REVOKE ALL ON FUNCTION public.debit_user_balance(UUID, NUMERIC, TEXT, UUID, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.debit_user_balance(UUID, NUMERIC, TEXT, UUID, TEXT, JSONB) TO service_role;

CREATE OR REPLACE FUNCTION public.credit_user_balance(
  _user_id UUID, _amount NUMERIC, _type TEXT,
  _ref_id UUID DEFAULT NULL, _note TEXT DEFAULT NULL, _meta JSONB DEFAULT NULL
) RETURNS NUMERIC LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _new_balance NUMERIC; _is_bot BOOLEAN;
BEGIN
  IF _amount IS NULL OR _amount <= 0 THEN RAISE EXCEPTION 'credit: montant invalide (%)', _amount; END IF;
  SELECT is_bot INTO _is_bot FROM public.profiles WHERE id = _user_id;
  IF _is_bot THEN RETURN 0; END IF;
  UPDATE public.profiles SET balance_ar = balance_ar + _amount
  WHERE id = _user_id RETURNING balance_ar INTO _new_balance;
  IF _new_balance IS NULL THEN RAISE EXCEPTION 'Utilisateur introuvable %', _user_id; END IF;
  INSERT INTO public.transactions (user_id, amount, type, ref_id, note, meta)
  VALUES (_user_id, _amount, _type, _ref_id, _note, COALESCE(_meta, '{}'::jsonb));
  RETURN _new_balance;
END; $$;
REVOKE ALL ON FUNCTION public.credit_user_balance(UUID, NUMERIC, TEXT, UUID, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.credit_user_balance(UUID, NUMERIC, TEXT, UUID, TEXT, JSONB) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_audit_unlogged_changes(_hours INT DEFAULT 24)
RETURNS TABLE(user_id UUID, pseudo TEXT, audit_delta NUMERIC, tx_delta NUMERIC, unlogged NUMERIC)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin only' USING ERRCODE = '42501'; END IF;
  RETURN QUERY
  WITH a AS (
    SELECT bal.user_id AS uid, COALESCE(SUM(bal.delta), 0) AS ad
    FROM public.balance_audit_log bal
    WHERE bal.created_at >= now() - make_interval(hours => _hours)
    GROUP BY bal.user_id
  ), t AS (
    SELECT tx.user_id AS uid, COALESCE(SUM(tx.amount), 0) AS td
    FROM public.transactions tx
    WHERE tx.created_at >= now() - make_interval(hours => _hours)
    GROUP BY tx.user_id
  )
  SELECT COALESCE(a.uid, t.uid), p.pseudo,
         COALESCE(a.ad, 0), COALESCE(t.td, 0),
         COALESCE(a.ad, 0) - COALESCE(t.td, 0)
  FROM a FULL OUTER JOIN t ON t.uid = a.uid
  LEFT JOIN public.profiles p ON p.id = COALESCE(a.uid, t.uid)
  WHERE ABS(COALESCE(a.ad, 0) - COALESCE(t.td, 0)) >= 1
  ORDER BY ABS(COALESCE(a.ad, 0) - COALESCE(t.td, 0)) DESC
  LIMIT 200;
END; $$;
REVOKE ALL ON FUNCTION public.admin_audit_unlogged_changes(INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_audit_unlogged_changes(INT) TO authenticated, service_role;

CREATE OR REPLACE VIEW public.v_finance_daily AS
SELECT
  date_trunc('day', created_at)::date AS day,
  SUM(CASE WHEN type = 'deposit'    THEN amount ELSE 0 END) AS deposits,
  SUM(CASE WHEN type = 'withdraw'   THEN -amount ELSE 0 END) AS withdrawals,
  SUM(CASE WHEN type = 'stake'      THEN -amount ELSE 0 END) AS stakes,
  SUM(CASE WHEN type = 'payout'     THEN amount ELSE 0 END) AS payouts,
  SUM(CASE WHEN type = 'refund'     THEN amount ELSE 0 END) AS refunds,
  SUM(CASE WHEN type = 'commission' THEN -amount ELSE 0 END) AS commissions,
  SUM(CASE WHEN type IN ('bonus','referral','admin_adjust') THEN amount ELSE 0 END) AS bonuses_adjustments,
  COUNT(*) AS tx_count
FROM public.transactions
WHERE created_at >= now() - interval '90 days'
GROUP BY 1 ORDER BY 1 DESC;
GRANT SELECT ON public.v_finance_daily TO authenticated, service_role;