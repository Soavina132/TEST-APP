CREATE OR REPLACE FUNCTION public._t_pool_recompute(_pool_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE public.tournament_pool_entrants pe
     SET played = COALESCE(s.played, 0),
         wins   = COALESCE(s.wins, 0),
         points = COALESCE(s.points, 0)
    FROM (
      SELECT x.entrant_id,
             count(*) AS played,
             count(*) FILTER (WHERE x.won) AS wins,
             SUM(CASE WHEN x.won THEN 3 WHEN x.drew THEN 1 ELSE 0 END) AS points
        FROM (
          SELECT u.entrant_id,
                 (m.winner_entrant_id IS NOT NULL AND u.entrant_id = m.winner_entrant_id) AS won,
                 (m.winner_entrant_id IS NULL) AS drew
            FROM public.tournament_matches m
            CROSS JOIN LATERAL unnest(m.entrant_ids) AS u(entrant_id)
           WHERE m.pool_id = _pool_id AND m.status = 'finished'
        ) x
       GROUP BY x.entrant_id
    ) s
   WHERE pe.pool_id = _pool_id AND pe.entrant_id = s.entrant_id;

  UPDATE public.tournament_pool_entrants pe
     SET played = 0, wins = 0, points = 0
   WHERE pe.pool_id = _pool_id
     AND NOT EXISTS (
       SELECT 1 FROM public.tournament_matches m
        WHERE m.pool_id = _pool_id AND m.status = 'finished'
          AND pe.entrant_id = ANY(m.entrant_ids));
END $function$;