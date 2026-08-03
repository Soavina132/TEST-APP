
-- Distribution respectant winners_count : ne crédite/notifie que si part > 0
CREATE OR REPLACE FUNCTION public.admin_distribute_tournament_rewards(
  _tid uuid, _first_id uuid, _second_id uuid, _third_id uuid DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_is_admin boolean;
  trn record; dist jsonb;
  v_prize numeric; v_first_amt numeric; v_second_amt numeric; v_third_amt numeric; v_plat_amt numeric;
  v_wc int;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin,false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO trn FROM public.tournaments WHERE id = _tid;
  IF trn IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;
  IF trn.status NOT IN ('finished','running') THEN
    RAISE EXCEPTION 'Le tournoi doit être en cours ou terminé';
  END IF;
  IF trn.rewards_paid_at IS NOT NULL THEN
    RAISE EXCEPTION 'Les récompenses ont déjà été distribuées';
  END IF;

  v_prize := COALESCE(trn.prize_pool, 0);
  dist    := COALESCE(trn.reward_distribution, '{"first":60,"second":20,"third":10,"platform":10}'::jsonb);
  v_wc    := GREATEST(1, LEAST(3, COALESCE(trn.winners_count, 3)));

  -- Ignore les places au-delà de winners_count (sécurité serveur)
  IF v_wc < 2 THEN _second_id := NULL; END IF;
  IF v_wc < 3 THEN _third_id  := NULL; END IF;

  v_first_amt  := ROUND(v_prize * (dist->>'first')::numeric  / 100, 0);
  v_second_amt := ROUND(v_prize * (dist->>'second')::numeric / 100, 0);
  v_third_amt  := ROUND(v_prize * (dist->>'third')::numeric  / 100, 0);
  -- Si winners_count réduit, forcer 0 pour les places non attribuées
  IF v_wc < 2 THEN v_second_amt := 0; END IF;
  IF v_wc < 3 THEN v_third_amt  := 0; END IF;
  v_plat_amt   := v_prize - v_first_amt - v_second_amt - v_third_amt;

  IF _first_id IS NOT NULL AND v_first_amt > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar + v_first_amt WHERE id = _first_id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (_first_id, 'tournament_win', v_first_amt, _tid,
              '🥇 1er — Tournoi '||trn.name||' ('||(v_first_amt*100/NULLIF(v_prize,0))::int||'%)');
    INSERT INTO public.notifications(user_id, type, title, body, ref_id)
      VALUES (_first_id, 'tournament_reward', '🥇 Félicitations — Vous avez gagné !',
              'Gain de '||v_first_amt||' Ar crédité sur votre compte.', _tid)
      ON CONFLICT DO NOTHING;
  END IF;

  IF _second_id IS NOT NULL AND v_second_amt > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar + v_second_amt WHERE id = _second_id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (_second_id, 'tournament_win', v_second_amt, _tid,
              '🥈 2e — Tournoi '||trn.name);
    INSERT INTO public.notifications(user_id, type, title, body, ref_id)
      VALUES (_second_id, 'tournament_reward', '🥈 2e place — Bravo !',
              'Gain de '||v_second_amt||' Ar crédité sur votre compte.', _tid)
      ON CONFLICT DO NOTHING;
  END IF;

  IF _third_id IS NOT NULL AND v_third_amt > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar + v_third_amt WHERE id = _third_id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (_third_id, 'tournament_win', v_third_amt, _tid,
              '🥉 3e — Tournoi '||trn.name);
    INSERT INTO public.notifications(user_id, type, title, body, ref_id)
      VALUES (_third_id, 'tournament_reward', '🥉 3e place — Félicitations !',
              'Gain de '||v_third_amt||' Ar crédité sur votre compte.', _tid)
      ON CONFLICT DO NOTHING;
  END IF;

  UPDATE public.tournaments
    SET podium = jsonb_build_object('first',_first_id,'second',_second_id,'third',_third_id),
        winner_id = _first_id,
        status = 'finished',
        finished_at = COALESCE(finished_at, now()),
        rewards_paid_at = now(),
        platform_cut_ar = v_plat_amt
    WHERE id = _tid;

  BEGIN
    INSERT INTO public.admin_action_logs(admin_id, action, target_id, note)
      VALUES (v_uid, 'distribute_rewards', _tid,
              'wc='||v_wc||' 1er:'||v_first_amt||' 2e:'||v_second_amt||' 3e:'||v_third_amt||' Plateforme:'||v_plat_amt)
    ON CONFLICT DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object(
    'ok', true, 'winners_count', v_wc,
    'first_amount', v_first_amt, 'second_amount', v_second_amt,
    'third_amount', v_third_amt, 'platform_amount', v_plat_amt,
    'prize_pool', v_prize
  );
END; $$;
GRANT EXECUTE ON FUNCTION public.admin_distribute_tournament_rewards(uuid,uuid,uuid,uuid) TO authenticated;
