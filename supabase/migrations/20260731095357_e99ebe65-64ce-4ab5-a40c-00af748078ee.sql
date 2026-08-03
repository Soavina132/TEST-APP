CREATE OR REPLACE FUNCTION public._t_finish(_tid uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  t public.tournaments%ROWTYPE; v_net numeric; v_pcts numeric[]; r record; i int; v_amt numeric;
  v_final_loser uuid; v_tp_win uuid; v_tp_lose uuid;
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF t.status IN ('finished','cancelled') THEN RETURN; END IF;

  -- finaliste (perdant du dernier match 'final')
  SELECT x.eid INTO v_final_loser FROM (
    SELECT unnest(m.entrant_ids) eid, m.winner_entrant_id w, m.round
      FROM public.tournament_matches m
     WHERE m.tournament_id = _tid AND m.phase = 'final' AND m.status = 'finished'
       AND t.champion_entrant_id = ANY(m.entrant_ids)
     ORDER BY m.round DESC LIMIT 4) x
   WHERE x.eid IS DISTINCT FROM t.champion_entrant_id LIMIT 1;

  SELECT m.winner_entrant_id INTO v_tp_win FROM public.tournament_matches m
   WHERE m.tournament_id = _tid AND m.phase = 'third_place' AND m.status = 'finished' LIMIT 1;
  IF v_tp_win IS NOT NULL THEN
    SELECT x.eid INTO v_tp_lose FROM (
      SELECT unnest(m.entrant_ids) eid FROM public.tournament_matches m
       WHERE m.tournament_id = _tid AND m.phase = 'third_place' AND m.status = 'finished') x
     WHERE x.eid IS DISTINCT FROM v_tp_win LIMIT 1;
  END IF;

  WITH keyed AS (
    SELECT e.id,
           CASE
             WHEN e.id = t.champion_entrant_id THEN 0
             WHEN e.id = v_final_loser THEN 1
             WHEN e.id = v_tp_win THEN 2
             WHEN e.id = v_tp_lose THEN 3
             ELSE 10
           END AS k,
           e.eliminated_round, e.created_at
      FROM public.tournament_entrants e WHERE e.tournament_id = _tid
  ), ranked AS (
    SELECT id, row_number() OVER (ORDER BY k, eliminated_round DESC NULLS FIRST, created_at) AS rk
      FROM keyed
  )
  UPDATE public.tournament_entrants e SET final_rank = ranked.rk
    FROM ranked WHERE e.id = ranked.id;

  v_net := round(t.prize_pool_ar * (100 - t.platform_pct) / 100) + t.admin_prize_pool_ar;
  v_pcts := ARRAY[t.prize_1_pct, t.prize_2_pct, t.prize_3_pct];

  FOR r IN SELECT * FROM public.tournament_entrants
            WHERE tournament_id = _tid AND final_rank IS NOT NULL AND final_rank <= t.winners_count
            ORDER BY final_rank LOOP
    i := r.final_rank;
    v_amt := round(v_net * COALESCE(v_pcts[i],0) / 100);
    IF v_amt > 0 AND r.user_id IS NOT NULL AND NOT r.is_bot AND NOT t.is_simulation THEN
      PERFORM public.credit_user_balance(r.user_id, v_amt, 'tournament_prize', _tid,
        'Récompense tournoi: ' || t.name, jsonb_build_object('rank', i));
    END IF;
    PERFORM public._t_notify(r.id, '🏆 Tournoi terminé',
      'Vous terminez ' || i || 'e. Gain : ' || v_amt || ' Ar', '/tournaments/' || _tid);
  END LOOP;

  UPDATE public.tournaments SET status = 'finished', stage = 'done', finished_at = now() WHERE id = _tid;
END $function$;