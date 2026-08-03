
CREATE OR REPLACE FUNCTION public.admin_leaderboard_list(_period text DEFAULT 'all'::text, _limit integer DEFAULT 50, _slug text DEFAULT NULL::text)
 RETURNS TABLE(user_id uuid, name text, avatar_url text, wins bigint, total_won numeric, hidden boolean, rank_override integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  RETURN QUERY
  WITH bound AS (
    SELECT CASE _period
      WHEN 'week'  THEN now() - interval '7 days'
      WHEN 'month' THEN now() - interval '30 days'
      ELSE 'epoch'::timestamptz
    END AS since
  ),
  raw AS (
    SELECT g.winner_id AS uid, NULLIF(trim(pp.display_name),'') AS dn,
           g.pot * (1 - g.commission_pct/100.0) AS won,
           COALESCE(g.finished_at, g.created_at) AS at
      FROM ludo_games g JOIN ludo_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'ludo')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0),
           COALESCE(g.finished_at, g.created_at)
      FROM domino_games g JOIN domino_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'domino')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0),
           COALESCE(g.finished_at, g.created_at)
      FROM fanorona_games g JOIN fanorona_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'fanorona')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0),
           COALESCE(g.finished_at, g.created_at)
      FROM rami_games g JOIN rami_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'rami')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULL::text,
           g.stake * 2 * (1 - COALESCE((SELECT commission_pct FROM app_settings WHERE id=1),0)/100.0),
           COALESCE(g.finished_at, g.created_at)
      FROM chess_games g, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'chess')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULLIF(trim(pp.bot_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0),
           COALESCE(g.finished_at, g.created_at)
      FROM poker_games g JOIN poker_players pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'poker')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
  ),
  filtered AS (
    SELECT r.uid, r.dn, r.won, r.at FROM raw r
    WHERE (NOT public.has_role(r.uid, 'admin'::public.app_role)
           OR EXISTS (
                SELECT 1 FROM public.admin_persona ap
                WHERE ap.admin_id = r.uid AND ap.is_active
              ))
  ),
  named AS (
    SELECT f.uid, f.won, f.at,
           COALESCE(p.pseudo, f.dn, 'Joueur') AS name,
           p.avatar_url
    FROM filtered f LEFT JOIN public.profiles p ON p.id=f.uid
  ),
  agg AS (
    SELECT uid, count(*)::bigint AS wins, COALESCE(sum(won), 0)::numeric AS total_won
    FROM named GROUP BY uid
  ),
  latest_name AS (
    SELECT DISTINCT ON (uid) uid, name, avatar_url
    FROM named ORDER BY uid, at DESC
  )
  SELECT a.uid AS user_id, ln.name, ln.avatar_url, a.wins, a.total_won,
         COALESCE(pr.leaderboard_hidden, false) AS hidden,
         pr.leaderboard_rank_override AS rank_override
  FROM agg a
  JOIN latest_name ln ON ln.uid = a.uid
  LEFT JOIN public.profiles pr ON pr.id = a.uid
  ORDER BY COALESCE(pr.leaderboard_rank_override, 2147483647) ASC, a.wins DESC, ln.name ASC
  LIMIT _limit;
END;
$function$;
