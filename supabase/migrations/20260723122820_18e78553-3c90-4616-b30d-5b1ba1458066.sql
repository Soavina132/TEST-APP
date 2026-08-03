
CREATE OR REPLACE FUNCTION public.list_tournaments(_status text DEFAULT NULL)
RETURNS TABLE (
  id uuid, name text, mode text, max_players int, stake numeric, is_free boolean, season int,
  status text, current_round int, total_rounds int, prize_pool numeric, winner_id uuid,
  created_at timestamptz, finished_at timestamptz, registered_count bigint
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT t.id, t.name, t.mode, t.max_players, t.stake, t.is_free, t.season,
         t.status, t.current_round, t.total_rounds, t.prize_pool, t.winner_id,
         t.created_at, t.finished_at,
         (SELECT count(*) FROM public.tournament_registrations r WHERE r.tournament_id = t.id) AS registered_count
    FROM public.tournaments t
    WHERE (_status IS NULL OR t.status = _status)
      AND (COALESCE(t.is_test, false) = false OR public.is_admin())
    ORDER BY (CASE WHEN t.status='running' THEN 0 WHEN t.status='open' THEN 1 WHEN t.status='finished' THEN 2 ELSE 3 END),
             t.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.hall_of_fame()
RETURNS TABLE (
  id uuid, name text, mode text, season int, finished_at timestamptz,
  winner_id uuid, winner_pseudo text, top3 jsonb, prize_pool numeric
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT t.id, t.name, t.mode, t.season, t.finished_at,
         t.winner_id, p.pseudo AS winner_pseudo, t.top3, t.prize_pool
  FROM public.tournaments t
  LEFT JOIN public.profiles p ON p.id = t.winner_id
  WHERE t.status = 'finished'
    AND (COALESCE(t.is_test, false) = false OR public.is_admin())
  ORDER BY t.finished_at DESC;
$$;
