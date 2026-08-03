-- =====================================================================
-- Tests automatisés du programme de parrainage (nouvelle règle)
--
-- Règles vérifiées :
--   1. Aucun bonus à l'inscription du filleul.
--   2. Aucun bonus au premier dépôt approuvé du filleul.
--   3. À chaque mise du filleul → 5% (configurable) crédités au parrain
--      pendant ses N (=10 par défaut) premières parties avec mise.
--   4. La 11ᵉ mise ne crédite plus rien.
--
-- Usage :
--   psql "$SUPABASE_DB_URL" -f lalaomada/tests/referral.sql
--
-- Doit être lancé avec un rôle ayant les droits d'écriture (postgres /
-- service_role / supabase_admin en local, `supabase db reset` en CI).
--
-- Le fichier tourne dans une transaction ROLLBACK'ée à la fin :
-- rien n'est écrit en base. Chaque assertion RAISE EXCEPTION en cas
-- d'échec ; sinon on affiche « PASS <nom> ».
-- =====================================================================

\set ON_ERROR_STOP on
\timing off

BEGIN;
-- Escalade de privilèges pour bypasser RLS et écrire dans auth.*
-- (ignoré silencieusement si le rôle courant n'y a pas droit)
DO $$ BEGIN BEGIN SET LOCAL ROLE postgres; EXCEPTION WHEN OTHERS THEN NULL; END; END $$;

DO $tests$
DECLARE
  v_parent uuid := gen_random_uuid();
  v_child  uuid := gen_random_uuid();
  v_bal    numeric;
  v_events integer;
  v_count  integer;
  v_pct    numeric;
  v_max    integer;
  v_stake  numeric := 1000;
  v_expected_reward numeric;
  v_dep_id uuid;
  i        integer;
BEGIN
  RAISE NOTICE '--- Setup parrainage ---';

  -- S'assurer que le programme est actif avec les valeurs par défaut
  UPDATE public.referral_settings
     SET enabled = true,
         deposit_bonus_pct = 0,
         win_commission_pct = 0,
         stake_commission_pct = 5,
         stake_commission_max_matches = 10,
         require_phone_verification = false,
         require_first_deposit = false
   WHERE id = 1;

  SELECT stake_commission_pct, stake_commission_max_matches
    INTO v_pct, v_max FROM public.referral_settings WHERE id = 1;

  v_expected_reward := ROUND(v_stake * v_pct / 100.0, 0);

  -- Comptes factices (auth.users + profiles)
  INSERT INTO auth.users(id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
  VALUES
    (v_parent, '00000000-0000-0000-0000-000000000000','authenticated','authenticated','test-parrain@lovable.local','x',now(),now()),
    (v_child,  '00000000-0000-0000-0000-000000000000','authenticated','authenticated','test-filleul@lovable.local','x',now(),now());

  INSERT INTO public.profiles(id, pseudo, email, balance_ar, referral_code, referred_by, phone_verified)
  VALUES
    (v_parent, 'test_parrain', 'test-parrain@lovable.local', 0, 'PARENT'||substr(v_parent::text,1,6), NULL, true),
    (v_child,  'test_filleul', 'test-filleul@lovable.local', 100000, 'CHILD'||substr(v_child::text,1,6), v_parent, true);

  ------------------------------------------------------------------
  -- T1 : aucun bonus à l'inscription
  ------------------------------------------------------------------
  SELECT balance_ar INTO v_bal FROM public.profiles WHERE id = v_parent;
  IF v_bal <> 0 THEN
    RAISE EXCEPTION 'T1 FAIL : parrain crédité à l inscription (solde=%)', v_bal;
  END IF;

  SELECT COUNT(*) INTO v_events
    FROM public.referral_events
   WHERE referrer_id = v_parent AND reward_amount > 0;
  IF v_events <> 0 THEN
    RAISE EXCEPTION 'T1 FAIL : événement de parrainage créé à l inscription (n=%)', v_events;
  END IF;
  RAISE NOTICE 'PASS T1 — aucun bonus à l inscription';

  ------------------------------------------------------------------
  -- T2 : aucun bonus au premier dépôt approuvé
  ------------------------------------------------------------------
  INSERT INTO public.deposits(user_id, amount, method, reference, status, processed_at)
  VALUES (v_child, 20000, 'mvola', 'TEST-REF-001', 'pending', NULL)
  RETURNING id INTO v_dep_id;

  UPDATE public.deposits SET status = 'approved', processed_at = now() WHERE id = v_dep_id;

  SELECT balance_ar INTO v_bal FROM public.profiles WHERE id = v_parent;
  IF v_bal <> 0 THEN
    RAISE EXCEPTION 'T2 FAIL : parrain crédité au 1er dépôt (solde=%)', v_bal;
  END IF;

  SELECT COUNT(*) INTO v_events
    FROM public.referral_events
   WHERE referrer_id = v_parent AND event_type IN ('first_deposit','signup');
  IF v_events <> 0 THEN
    RAISE EXCEPTION 'T2 FAIL : événement first_deposit/signup rémunéré (n=%)', v_events;
  END IF;
  RAISE NOTICE 'PASS T2 — aucun bonus au premier dépôt';

  ------------------------------------------------------------------
  -- T3 : les N premières mises créditent le parrain (5%)
  ------------------------------------------------------------------
  FOR i IN 1..v_max LOOP
    INSERT INTO public.transactions(user_id, type, amount, note)
    VALUES (v_child, 'ludo_stake', -v_stake, 'test stake #'||i);
  END LOOP;

  SELECT balance_ar INTO v_bal FROM public.profiles WHERE id = v_parent;
  IF v_bal <> v_expected_reward * v_max THEN
    RAISE EXCEPTION 'T3 FAIL : solde parrain=% attendu=%',
      v_bal, v_expected_reward * v_max;
  END IF;

  SELECT referral_stake_count INTO v_count FROM public.profiles WHERE id = v_child;
  IF v_count <> v_max THEN
    RAISE EXCEPTION 'T3 FAIL : referral_stake_count=% attendu=%', v_count, v_max;
  END IF;

  SELECT COUNT(*) INTO v_events
    FROM public.referral_events
   WHERE referrer_id = v_parent
     AND referee_id  = v_child
     AND event_type LIKE 'stake\_%' ESCAPE '\';
  IF v_events <> v_max THEN
    RAISE EXCEPTION 'T3 FAIL : événements stake=% attendus=%', v_events, v_max;
  END IF;
  RAISE NOTICE 'PASS T3 — % mises créditées à %%% (total=%)',
    v_max, v_pct, v_bal;

  ------------------------------------------------------------------
  -- T4 : la (N+1)ᵉ mise ne crédite plus rien
  ------------------------------------------------------------------
  INSERT INTO public.transactions(user_id, type, amount, note)
  VALUES (v_child, 'ludo_stake', -v_stake, 'test stake overflow');

  SELECT balance_ar INTO v_bal FROM public.profiles WHERE id = v_parent;
  IF v_bal <> v_expected_reward * v_max THEN
    RAISE EXCEPTION 'T4 FAIL : mise n+1 a crédité (solde=%, attendu=%)',
      v_bal, v_expected_reward * v_max;
  END IF;

  SELECT referral_stake_count INTO v_count FROM public.profiles WHERE id = v_child;
  IF v_count <> v_max THEN
    RAISE EXCEPTION 'T4 FAIL : compteur incrémenté au-delà de la limite (=%)', v_count;
  END IF;
  RAISE NOTICE 'PASS T4 — plafond de % parties respecté', v_max;

  ------------------------------------------------------------------
  -- T5 : une mise de 0 (partie gratuite) ne crédite rien
  ------------------------------------------------------------------
  -- On remet le compteur au bord pour tester spécifiquement le 0
  UPDATE public.profiles SET referral_stake_count = 0 WHERE id = v_child;
  UPDATE public.profiles SET balance_ar = 0 WHERE id = v_parent;

  INSERT INTO public.transactions(user_id, type, amount, note)
  VALUES (v_child, 'ludo_stake', 0, 'partie gratuite');

  SELECT balance_ar, referral_stake_count
    INTO v_bal, v_count
    FROM public.profiles p JOIN public.profiles c ON c.id = v_child
   WHERE p.id = v_parent;
  IF v_bal <> 0 OR v_count <> 0 THEN
    RAISE EXCEPTION 'T5 FAIL : mise gratuite comptée (solde=%, count=%)', v_bal, v_count;
  END IF;
  RAISE NOTICE 'PASS T5 — partie gratuite ignorée';

  RAISE NOTICE '=============================================';
  RAISE NOTICE 'Tous les tests de parrainage sont PASS ✓';
  RAISE NOTICE '=============================================';
END
$tests$;

ROLLBACK;
