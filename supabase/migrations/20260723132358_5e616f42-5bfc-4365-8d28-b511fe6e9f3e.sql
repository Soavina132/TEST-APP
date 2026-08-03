DROP FUNCTION IF EXISTS public.admin_stats_daily(integer);

CREATE OR REPLACE FUNCTION public.admin_stats_daily(_days integer)
RETURNS TABLE(
  day date,
  deposits numeric,
  withdrawals numeric,
  wins numeric,
  commission numeric,
  stakes numeric,
  new_users bigint,
  active_users bigint,
  games_finished bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  RETURN QUERY
  WITH days AS (
    SELECT generate_series(
      (current_date - (_days-1) * interval '1 day')::date,
      current_date::date,
      interval '1 day'
    )::date AS d
  ),
  games_all AS (
    SELECT finished_at, pot, commission_pct FROM public.ludo_games WHERE status='finished'
    UNION ALL SELECT finished_at, pot, commission_pct FROM public.domino_games WHERE status='finished'
    UNION ALL SELECT finished_at, pot, commission_pct FROM public.chess_games WHERE status='finished'
    UNION ALL SELECT finished_at, pot, commission_pct FROM public.fanorona_games WHERE status='finished'
    UNION ALL SELECT finished_at, pot, commission_pct FROM public.rami_games WHERE status='finished'
  )
  SELECT d.d,
    COALESCE((SELECT SUM(amount) FROM public.deposits WHERE status='approved' AND processed_at::date = d.d),0)::numeric,
    COALESCE((SELECT SUM(amount) FROM public.withdrawals WHERE status='approved' AND processed_at::date = d.d),0)::numeric,
    COALESCE((SELECT SUM(amount) FROM public.transactions WHERE type='win' AND created_at::date = d.d),0)::numeric,
    COALESCE((SELECT SUM(pot * commission_pct / 100.0) FROM games_all WHERE finished_at::date = d.d),0)::numeric,
    COALESCE((SELECT SUM(-amount) FROM public.transactions WHERE type='stake' AND created_at::date = d.d),0)::numeric,
    COALESCE((SELECT COUNT(*) FROM public.profiles WHERE created_at::date = d.d),0)::bigint,
    COALESCE((SELECT COUNT(DISTINCT user_id) FROM public.transactions WHERE created_at::date = d.d),0)::bigint,
    COALESCE((SELECT COUNT(*) FROM games_all WHERE finished_at::date = d.d),0)::bigint
  FROM days d ORDER BY d.d DESC;
END $function$;

REVOKE ALL ON FUNCTION public.admin_stats_daily(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_stats_daily(integer) TO authenticated;