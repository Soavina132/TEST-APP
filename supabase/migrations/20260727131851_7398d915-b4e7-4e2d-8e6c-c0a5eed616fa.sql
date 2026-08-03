-- 1. Drop the obsolete duplicate refund path
DROP FUNCTION IF EXISTS public.cleanup_stale_open_games() CASCADE;

-- 2. Remove duplicate refund transactions and claw back the fraudulent balance
WITH dups AS (
  SELECT id, user_id, amount,
         ROW_NUMBER() OVER (PARTITION BY user_id, ref_id, type ORDER BY created_at) AS rn
  FROM public.transactions
  WHERE ref_id IS NOT NULL
    AND type IN ('refund','domino_refund','ludo_refund','chess_refund',
                 'rami_refund','fanorona_refund','poker_refund','petanque_refund')
),
extras AS (SELECT * FROM dups WHERE rn > 1),
clawback AS (
  SELECT user_id, SUM(amount)::int AS extra FROM extras GROUP BY user_id
),
apply AS (
  UPDATE public.profiles p
     SET balance_ar = GREATEST(0, p.balance_ar - c.extra)
    FROM clawback c
   WHERE p.id = c.user_id
   RETURNING p.id
),
log AS (
  INSERT INTO public.transactions(user_id, type, amount, note)
  SELECT user_id, 'admin_adjust', -extra,
         'Retrait des remboursements dupliqués (correction faille sécurité)'
    FROM clawback
)
DELETE FROM public.transactions WHERE id IN (SELECT id FROM extras);

-- 3. Enforce idempotency for future refunds
CREATE UNIQUE INDEX IF NOT EXISTS transactions_refund_unique
  ON public.transactions(user_id, ref_id, type)
  WHERE ref_id IS NOT NULL
    AND type IN ('refund','domino_refund','ludo_refund','chess_refund',
                 'rami_refund','fanorona_refund','poker_refund','petanque_refund');

-- 4. Reset rindra04 to zero and log
DO $$
DECLARE v_uid uuid := 'd3cccb0f-e1d4-4b72-93ce-979755fece45'; v_old int;
BEGIN
  SELECT balance_ar INTO v_old FROM public.profiles WHERE id = v_uid;
  IF v_old > 0 THEN
    UPDATE public.profiles SET balance_ar = 0 WHERE id = v_uid;
    INSERT INTO public.transactions(user_id, type, amount, note)
      VALUES (v_uid, 'admin_adjust', -v_old,
              'Remise à 0 (compte enrichi par faille double-remboursement)');
  END IF;
END $$;