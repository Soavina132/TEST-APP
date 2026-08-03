-- =====================================================================
-- Tests automatisés du flux financier
--
-- Usage :
--   psql -f lalaomada/tests/finance.sql
-- ou :
--   bash lalaomada/tests/run.sh
--
-- Le fichier tourne dans une transaction ROLLBACK'ée à la fin :
-- rien n'est écrit en base. Chaque assertion RAISE EXCEPTION en cas
-- d'échec ; sinon on affiche « PASS <nom> ».
-- =====================================================================

\set ON_ERROR_STOP on
\timing off

BEGIN;

DO $tests$
DECLARE
  v_admin uuid := gen_random_uuid();
  v_p1    uuid := gen_random_uuid();
  v_p2    uuid := gen_random_uuid();
  v_dep_id uuid;
  v_wd_id  uuid;
  v_game   uuid;
  v_cpct   numeric;
  v_bal    numeric;
  v_bal2   numeric;
  v_pot    numeric;
  v_net    numeric;
  v_debt   numeric;
  v_ok     boolean;
  v_err    text;
BEGIN
  RAISE NOTICE '--- Setup ---';

  -- Utilisateurs factices (auth.users + profiles + rôle admin)
  INSERT INTO auth.users(id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
  VALUES
    (v_admin, '00000000-0000-0000-0000-000000000000','authenticated','authenticated','test-admin@lovable.local','x',now(),now()),
    (v_p1,    '00000000-0000-0000-0000-000000000000','authenticated','authenticated','test-p1@lovable.local','x',now(),now()),
    (v_p2,    '00000000-0000-0000-0000-000000000000','authenticated','authenticated','test-p2@lovable.local','x',now(),now());

  INSERT INTO public.profiles(id, username, display_name, balance_ar)
  VALUES
    (v_admin, 'test_admin','Admin Test', 0),
    (v_p1,    'test_p1',   'Joueur 1',   0),
    (v_p2,    'test_p2',   'Joueur 2',   0);

  INSERT INTO public.user_roles(user_id, role) VALUES (v_admin, 'admin');

  -- On agit en tant qu'admin pour les RPCs qui vérifient is_admin()
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);

  SELECT public.get_game_commission('ludo') INTO v_cpct;
  RAISE NOTICE 'Commission Ludo utilisée pour les tests : %', v_cpct;

  -- ================================================================
  -- T1 : Dépôt approuvé → solde crédité en totalité
  -- ================================================================
  INSERT INTO public.deposits(user_id, amount, method, reference, user_phone, status)
  VALUES (v_p1, 10000, 'mvola', 'REF-T1', '0340000000', 'pending')
  RETURNING id INTO v_dep_id;

  PERFORM public.admin_process_deposit(v_dep_id, true);
  SELECT balance_ar INTO v_bal FROM public.profiles WHERE id = v_p1;
  IF v_bal <> 10000 THEN
    RAISE EXCEPTION 'FAIL T1 dépôt approuvé : attendu 10000, obtenu %', v_bal;
  END IF;
  RAISE NOTICE 'PASS T1 — dépôt approuvé crédite le solde';

  -- ================================================================
  -- T2 : Dépôt approuvé avec dette antérieure → dette débitée d'abord
  -- ================================================================
  INSERT INTO public.withdrawal_debts(user_id, amount_ar) VALUES (v_p2, 3000);
  INSERT INTO public.deposits(user_id, amount, method, reference, user_phone, status)
  VALUES (v_p2, 5000, 'mvola', 'REF-T2', '0340000001', 'pending')
  RETURNING id INTO v_dep_id;

  PERFORM public.admin_process_deposit(v_dep_id, true);
  SELECT balance_ar INTO v_bal FROM public.profiles WHERE id = v_p2;
  SELECT COALESCE(SUM(amount_ar),0) INTO v_debt FROM public.withdrawal_debts WHERE user_id = v_p2;
  IF v_bal <> 2000 OR v_debt <> 0 THEN
    RAISE EXCEPTION 'FAIL T2 dépôt+dette : solde=% (attendu 2000) dette=% (attendu 0)', v_bal, v_debt;
  END IF;
  RAISE NOTICE 'PASS T2 — dépôt éponge la dette avant de créditer';

  -- ================================================================
  -- T3 : Retrait approuvé → solde remis à 0, reliquat tracé
  -- ================================================================
  UPDATE public.profiles SET balance_ar = 20000 WHERE id = v_p1;
  PERFORM set_config('request.jwt.claim.sub', v_p1::text, true);
  SELECT public.request_withdrawal(15000, 'mvola', '0340000000', 'Joueur 1') INTO v_wd_id;
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);

  PERFORM public.admin_process_withdrawal(v_wd_id, true);
  SELECT balance_ar INTO v_bal FROM public.profiles WHERE id = v_p1;
  IF v_bal <> 0 THEN
    RAISE EXCEPTION 'FAIL T3 retrait approuvé : solde attendu 0, obtenu %', v_bal;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.transactions WHERE ref_id = v_wd_id AND type = 'balance_reset' AND amount = -5000) THEN
    RAISE EXCEPTION 'FAIL T3 : transaction balance_reset de -5000 non trouvée';
  END IF;
  RAISE NOTICE 'PASS T3 — retrait approuvé remet le solde à 0 + trace balance_reset';

  -- ================================================================
  -- T4 : Retrait avec solde insuffisant → erreur
  -- ================================================================
  UPDATE public.profiles SET balance_ar = 100 WHERE id = v_p2;
  PERFORM set_config('request.jwt.claim.sub', v_p2::text, true);
  v_ok := false;
  BEGIN
    PERFORM public.request_withdrawal(5000, 'mvola', '0340000001', 'Joueur 2');
  EXCEPTION WHEN OTHERS THEN
    v_ok := true;
    v_err := SQLERRM;
  END;
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  IF NOT v_ok THEN
    RAISE EXCEPTION 'FAIL T4 : request_withdrawal aurait dû échouer (solde insuffisant)';
  END IF;
  RAISE NOTICE 'PASS T4 — retrait refusé si solde insuffisant (%)', v_err;

  -- ================================================================
  -- T5 : Ludo finish_game → gagnant reçoit pot * (1 - commission)
  -- ================================================================
  UPDATE public.profiles SET balance_ar = 0 WHERE id = v_p1;
  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, status, mode)
    VALUES (v_p1, 2, 1000, 2000, 'playing', 'classic')
    RETURNING id, commission_pct INTO v_game, v_cpct;
  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name, is_bot)
    VALUES (v_game, v_p1, 0, 'red', 'Joueur 1', false),
           (v_game, v_p2, 1, 'green','Joueur 2', false);

  PERFORM public.finish_game(v_game, v_p1);
  SELECT balance_ar INTO v_bal FROM public.profiles WHERE id = v_p1;
  v_net := 2000 * (100 - v_cpct) / 100.0;
  IF v_bal <> v_net THEN
    RAISE EXCEPTION 'FAIL T5 Ludo payout : attendu %, obtenu % (commission % pct)', v_net, v_bal, v_cpct;
  END IF;
  RAISE NOTICE 'PASS T5 — Ludo : gagnant reçoit pot net = %', v_net;

  -- ================================================================
  -- T6 : Échecs — victoire → gagnant reçoit pot * (1 - commission)
  -- ================================================================
  UPDATE public.profiles SET balance_ar = 0 WHERE id IN (v_p1, v_p2);
  INSERT INTO public.chess_games(host_id, white_id, black_id, stake, pot, status, mode)
    VALUES (v_p1, v_p1, v_p2, 500, 1000, 'playing', 'stake')
    RETURNING id, commission_pct INTO v_game, v_cpct;

  PERFORM public._chess_payout(v_game, v_p1, false);
  SELECT balance_ar INTO v_bal FROM public.profiles WHERE id = v_p1;
  v_net := 1000 * (100 - v_cpct) / 100.0;
  IF v_bal <> v_net THEN
    RAISE EXCEPTION 'FAIL T6 Chess win : attendu %, obtenu %', v_net, v_bal;
  END IF;
  RAISE NOTICE 'PASS T6 — Échecs victoire : gagnant reçoit %', v_net;

  -- ================================================================
  -- T7 : Échecs — nul → chaque joueur reçoit pot * (1 - commission) / 2
  -- ================================================================
  UPDATE public.profiles SET balance_ar = 0 WHERE id IN (v_p1, v_p2);
  INSERT INTO public.chess_games(host_id, white_id, black_id, stake, pot, status, mode)
    VALUES (v_p1, v_p1, v_p2, 500, 1000, 'playing', 'stake')
    RETURNING id, commission_pct INTO v_game, v_cpct;

  PERFORM public._chess_payout(v_game, NULL, true);
  SELECT balance_ar INTO v_bal  FROM public.profiles WHERE id = v_p1;
  SELECT balance_ar INTO v_bal2 FROM public.profiles WHERE id = v_p2;
  v_net := 1000 * (100 - v_cpct) / 100.0 / 2;
  IF v_bal <> v_net OR v_bal2 <> v_net THEN
    RAISE EXCEPTION 'FAIL T7 Chess draw : attendu % chacun, obtenu % / %', v_net, v_bal, v_bal2;
  END IF;
  RAISE NOTICE 'PASS T7 — Échecs nul : chaque joueur reçoit %', v_net;

  -- ================================================================
  -- T8 : Domino finalize → gagnant reçoit pot * (1 - commission)
  -- ================================================================
  UPDATE public.profiles SET balance_ar = 0 WHERE id IN (v_p1, v_p2);
  INSERT INTO public.domino_games(host_id, max_players, stake, pot, status, mode, state)
    VALUES (v_p1, 2, 1500, 3000, 'playing', 'classic', '{}'::jsonb)
    RETURNING id, commission_pct INTO v_game, v_cpct;
  INSERT INTO public.domino_participants(game_id, user_id, slot, display_name, is_bot)
    VALUES (v_game, v_p1, 0, 'Joueur 1', false),
           (v_game, v_p2, 1, 'Joueur 2', false);

  PERFORM public._domino_finalize(v_game, 0);
  SELECT balance_ar INTO v_bal FROM public.profiles WHERE id = v_p1;
  v_net := 3000 * (100 - v_cpct) / 100;
  IF v_bal <> v_net THEN
    RAISE EXCEPTION 'FAIL T8 Domino : attendu %, obtenu %', v_net, v_bal;
  END IF;
  RAISE NOTICE 'PASS T8 — Domino : gagnant reçoit %', v_net;

  -- ================================================================
  -- T9 : Trigger commission — override du client sur INSERT
  -- ================================================================
  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, status, mode, commission_pct)
    VALUES (v_p1, 2, 0, 0, 'open', 'classic', 999) -- valeur bidon envoyée
    RETURNING commission_pct INTO v_cpct;
  IF v_cpct <> public.get_game_commission('ludo') THEN
    RAISE EXCEPTION 'FAIL T9 : trigger n''a pas écrasé commission_pct (=% au lieu de %)',
      v_cpct, public.get_game_commission('ludo');
  END IF;
  RAISE NOTICE 'PASS T9 — trigger écrase la commission client par le réglage serveur';

  RAISE NOTICE '======================================';
  RAISE NOTICE '   ✅ Tous les tests finance passent';
  RAISE NOTICE '======================================';
END
$tests$;

ROLLBACK;
