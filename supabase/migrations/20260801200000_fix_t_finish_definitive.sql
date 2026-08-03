-- ============================================================
-- FIX DÉFINITIF: _t_finish — rangs séquentiels 1 à N, sans trous ni doublons
-- ============================================================

CREATE OR REPLACE FUNCTION public._t_finish(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  t public.tournaments%ROWTYPE;
  v_champion uuid;
  v_runner_up uuid;
  v_third_winner uuid;
  v_third_loser uuid;
  v_net numeric;
  v_p1 numeric; v_p2 numeric; v_p3 numeric;
  v_winner record;
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid;
  IF t.id IS NULL THEN RETURN; END IF;

  -- 1. Identifier les 4 finalistes
  v_champion := t.champion_entrant_id;

  SELECT CASE
    WHEN entrant_ids[1] = v_champion THEN entrant_ids[2]
    WHEN entrant_ids[2] = v_champion THEN entrant_ids[1]
  END INTO v_runner_up
  FROM public.tournament_matches
  WHERE tournament_id = _tid AND phase = 'final' AND status = 'finished'
  ORDER BY round DESC LIMIT 1;

  SELECT winner_entrant_id INTO v_third_winner
  FROM public.tournament_matches
  WHERE tournament_id = _tid AND phase = 'third_place' AND status = 'finished'
  LIMIT 1;

  SELECT CASE
    WHEN entrant_ids[1] = v_third_winner THEN entrant_ids[2]
    WHEN entrant_ids[2] = v_third_winner THEN entrant_ids[1]
  END INTO v_third_loser
  FROM public.tournament_matches
  WHERE tournament_id = _tid AND phase = 'third_place' AND status = 'finished'
  LIMIT 1;

  -- 2. Assigner rangs 1-4
  UPDATE public.tournament_entrants SET final_rank = 1 WHERE id = v_champion AND tournament_id = _tid;
  UPDATE public.tournament_entrants SET final_rank = 2 WHERE id = v_runner_up AND tournament_id = _tid;
  UPDATE public.tournament_entrants SET final_rank = 3 WHERE id = v_third_winner AND tournament_id = _tid;
  UPDATE public.tournament_entrants SET final_rank = 4 WHERE id = v_third_loser AND tournament_id = _tid;

  -- 3. Assigner rangs 5+ aux autres (séquentiel, par round d'élimination desc)
  WITH others AS (
    SELECT id, row_number() OVER (ORDER BY
      COALESCE(eliminated_round, 0) DESC NULLS LAST, created_at
    ) + 4 as rk
    FROM public.tournament_entrants
    WHERE tournament_id = _tid
      AND id NOT IN (
        COALESCE(v_champion, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(v_runner_up, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(v_third_winner, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(v_third_loser, '00000000-0000-0000-0000-000000000000'::uuid)
      )
  )
  UPDATE public.tournament_entrants e SET final_rank = o.rk
  FROM others o WHERE e.id = o.id AND e.tournament_id = _tid;

  -- 4. Distribuer les prix (seulement aux humains non-bots)
  v_net := t.prize_pool_ar * (100 - t.platform_pct) / 100 + t.admin_prize_pool_ar;
  v_p1 := round(v_net * t.prize_1_pct / 100);
  v_p2 := round(v_net * t.prize_2_pct / 100);
  v_p3 := round(v_net * t.prize_3_pct / 100);

  FOR v_winner IN
    SELECT e.user_id, e.display_name, e.is_bot, e.final_rank
    FROM public.tournament_entrants e
    WHERE e.tournament_id = _tid AND e.final_rank <= t.winners_count
      AND e.user_id IS NOT NULL AND e.is_bot = false
  LOOP
    DECLARE
      v_amount numeric := CASE v_winner.final_rank
        WHEN 1 THEN v_p1 WHEN 2 THEN v_p2 WHEN 3 THEN v_p3
        ELSE 0 END;
    BEGIN
      IF v_amount > 0 THEN
        PERFORM public.credit_user_balance(
          v_winner.user_id, v_amount, 'tournament_prize',
          _tid, 'Prix tournoi — rang ' || v_winner.final_rank,
          jsonb_build_object('rank', v_winner.final_rank, 'tournament', t.name)
        );
      END IF;
    END;
  END LOOP;

  -- 5. Marquer comme terminé
  UPDATE public.tournaments SET status = 'finished', stage = 'done', finished_at = now()
  WHERE id = _tid;
END $$;
