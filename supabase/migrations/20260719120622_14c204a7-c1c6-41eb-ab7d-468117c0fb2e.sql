
CREATE OR REPLACE FUNCTION public.run_finance_tests()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_admin uuid := gen_random_uuid();
  v_p1    uuid := gen_random_uuid();
  v_p2    uuid := gen_random_uuid();
  v_dep_id uuid; v_wd_id uuid; v_game uuid;
  v_cpct numeric; v_bal numeric; v_bal2 numeric; v_net numeric; v_debt numeric;
  v_ok boolean; v_err text;
  v_report text := '';
  v_saved_uid text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  v_saved_uid := current_setting('request.jwt.claim.sub', true);

  INSERT INTO auth.users(id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
  VALUES
    (v_admin,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','ftest-admin+'||v_admin::text||'@lovable.local','x',now(),now()),
    (v_p1,   '00000000-0000-0000-0000-000000000000','authenticated','authenticated','ftest-p1+'||v_p1::text||'@lovable.local','x',now(),now()),
    (v_p2,   '00000000-0000-0000-0000-000000000000','authenticated','authenticated','ftest-p2+'||v_p2::text||'@lovable.local','x',now(),now());

  INSERT INTO public.profiles(id, pseudo, email, balance_ar) VALUES
    (v_admin,'ftest_admin_'||substr(v_admin::text,1,8),'ftest-admin+'||v_admin::text||'@lovable.local',0),
    (v_p1,   'ftest_p1_'   ||substr(v_p1::text,1,8),   'ftest-p1+'   ||v_p1::text   ||'@lovable.local',0),
    (v_p2,   'ftest_p2_'   ||substr(v_p2::text,1,8),   'ftest-p2+'   ||v_p2::text   ||'@lovable.local',0);

  INSERT INTO public.user_roles(user_id, role) VALUES (v_admin, 'admin');
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);

  INSERT INTO public.deposits(user_id,amount,method,reference,user_phone,status)
    VALUES (v_p1,10000,'mvola','FT-1','0340000000','pending') RETURNING id INTO v_dep_id;
  PERFORM public.admin_process_deposit(v_dep_id,true);
  SELECT balance_ar INTO v_bal FROM public.profiles WHERE id=v_p1;
  IF v_bal<>10000 THEN RAISE EXCEPTION 'FAIL T1: %', v_bal; END IF;
  v_report := v_report || E'PASS T1 — Dépôt approuvé crédite le solde\n';

  INSERT INTO public.withdrawal_debts(user_id, amount_ar) VALUES (v_p2, 3000);
  INSERT INTO public.deposits(user_id,amount,method,reference,user_phone,status)
    VALUES (v_p2,5000,'mvola','FT-2','0340000001','pending') RETURNING id INTO v_dep_id;
  PERFORM public.admin_process_deposit(v_dep_id,true);
  SELECT balance_ar INTO v_bal FROM public.profiles WHERE id=v_p2;
  SELECT COALESCE(SUM(amount_ar),0) INTO v_debt FROM public.withdrawal_debts WHERE user_id=v_p2;
  IF v_bal<>2000 OR v_debt<>0 THEN RAISE EXCEPTION 'FAIL T2: solde=% dette=%', v_bal, v_debt; END IF;
  v_report := v_report || E'PASS T2 — Dépôt éponge la dette avant de créditer\n';

  UPDATE public.profiles SET balance_ar=20000 WHERE id=v_p1;
  PERFORM set_config('request.jwt.claim.sub', v_p1::text, true);
  SELECT public.request_withdrawal(15000,'mvola','0340000000','Joueur 1') INTO v_wd_id;
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM public.admin_process_withdrawal(v_wd_id,true);
  SELECT balance_ar INTO v_bal FROM public.profiles WHERE id=v_p1;
  IF v_bal<>0 THEN RAISE EXCEPTION 'FAIL T3: solde=%', v_bal; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.transactions WHERE ref_id=v_wd_id AND type='balance_reset' AND amount=-5000) THEN
    RAISE EXCEPTION 'FAIL T3: balance_reset -5000 introuvable';
  END IF;
  v_report := v_report || E'PASS T3 — Retrait approuvé remet à 0 + trace balance_reset\n';

  UPDATE public.profiles SET balance_ar=100 WHERE id=v_p2;
  PERFORM set_config('request.jwt.claim.sub', v_p2::text, true);
  v_ok := false;
  BEGIN PERFORM public.request_withdrawal(5000,'mvola','0340000001','Joueur 2');
  EXCEPTION WHEN OTHERS THEN v_ok:=true; v_err:=SQLERRM; END;
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  IF NOT v_ok THEN RAISE EXCEPTION 'FAIL T4: aurait dû échouer'; END IF;
  v_report := v_report || format(E'PASS T4 — Retrait refusé si solde insuffisant (%s)\n', v_err);

  UPDATE public.profiles SET balance_ar=0 WHERE id=v_p1;
  INSERT INTO public.ludo_games(host_id,max_players,stake,pot,status,mode)
    VALUES (v_p1,2,1000,2000,'playing','classic') RETURNING id, commission_pct INTO v_game, v_cpct;
  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name,is_bot)
    VALUES (v_game,v_p1,0,'red','Joueur 1',false),(v_game,v_p2,1,'green','Joueur 2',false);
  PERFORM public.finish_game(v_game, v_p1);
  SELECT balance_ar INTO v_bal FROM public.profiles WHERE id=v_p1;
  v_net := 2000 * (100 - v_cpct) / 100.0;
  IF v_bal<>v_net THEN RAISE EXCEPTION 'FAIL T5: attendu % obtenu %', v_net, v_bal; END IF;
  v_report := v_report || format(E'PASS T5 — Ludo victoire : gagnant reçoit %s Ar (commission %s pct)\n', v_net, v_cpct);

  UPDATE public.profiles SET balance_ar=0 WHERE id IN (v_p1,v_p2);
  INSERT INTO public.chess_games(host_id,white_id,black_id,stake,pot,status,mode)
    VALUES (v_p1,v_p1,v_p2,500,1000,'playing','stake') RETURNING id, commission_pct INTO v_game, v_cpct;
  PERFORM public._chess_payout(v_game, v_p1, false);
  SELECT balance_ar INTO v_bal FROM public.profiles WHERE id=v_p1;
  v_net := 1000 * (100 - v_cpct) / 100.0;
  IF v_bal<>v_net THEN RAISE EXCEPTION 'FAIL T6: %', v_bal; END IF;
  v_report := v_report || format(E'PASS T6 — Échecs victoire : gagnant reçoit %s Ar\n', v_net);

  UPDATE public.profiles SET balance_ar=0 WHERE id IN (v_p1,v_p2);
  INSERT INTO public.chess_games(host_id,white_id,black_id,stake,pot,status,mode)
    VALUES (v_p1,v_p1,v_p2,500,1000,'playing','stake') RETURNING id, commission_pct INTO v_game, v_cpct;
  PERFORM public._chess_payout(v_game, NULL, true);
  SELECT balance_ar INTO v_bal FROM public.profiles WHERE id=v_p1;
  SELECT balance_ar INTO v_bal2 FROM public.profiles WHERE id=v_p2;
  v_net := 1000 * (100 - v_cpct) / 100.0 / 2;
  IF v_bal<>v_net OR v_bal2<>v_net THEN RAISE EXCEPTION 'FAIL T7: % / %', v_bal, v_bal2; END IF;
  v_report := v_report || format(E'PASS T7 — Échecs nul : chaque joueur reçoit %s Ar\n', v_net);

  UPDATE public.profiles SET balance_ar=0 WHERE id IN (v_p1,v_p2);
  INSERT INTO public.domino_games(host_id,max_players,stake,pot,status,mode,state)
    VALUES (v_p1,2,1500,3000,'playing','classic','{}'::jsonb) RETURNING id, commission_pct INTO v_game, v_cpct;
  INSERT INTO public.domino_participants(game_id,user_id,slot,display_name,is_bot)
    VALUES (v_game,v_p1,0,'Joueur 1',false),(v_game,v_p2,1,'Joueur 2',false);
  PERFORM public._domino_finalize(v_game, 0);
  SELECT balance_ar INTO v_bal FROM public.profiles WHERE id=v_p1;
  v_net := 3000 * (100 - v_cpct) / 100;
  IF v_bal<>v_net THEN RAISE EXCEPTION 'FAIL T8: %', v_bal; END IF;
  v_report := v_report || format(E'PASS T8 — Domino victoire : gagnant reçoit %s Ar\n', v_net);

  INSERT INTO public.ludo_games(host_id,max_players,stake,pot,status,mode,commission_pct)
    VALUES (v_p1,2,0,0,'open','classic',999) RETURNING commission_pct INTO v_cpct;
  IF v_cpct <> public.get_game_commission('ludo') THEN
    RAISE EXCEPTION 'FAIL T9: % au lieu de %', v_cpct, public.get_game_commission('ludo');
  END IF;
  v_report := v_report || E'PASS T9 — Trigger écrase la commission client par le réglage serveur\n';

  DELETE FROM auth.users WHERE id IN (v_admin, v_p1, v_p2);
  PERFORM set_config('request.jwt.claim.sub', COALESCE(v_saved_uid,''), true);

  RETURN E'\n' || v_report || E'\n✅ Tous les tests finance passent.\n';

EXCEPTION WHEN OTHERS THEN
  BEGIN DELETE FROM auth.users WHERE id IN (v_admin, v_p1, v_p2); EXCEPTION WHEN OTHERS THEN NULL; END;
  RAISE;
END
$fn$;
