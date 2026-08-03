CREATE OR REPLACE FUNCTION public.leaderboard_winners(_period text DEFAULT 'all', _limit int DEFAULT 20)
RETURNS TABLE(rank int, name text, avatar_url text, wins bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  WITH bound AS (
    SELECT CASE _period
      WHEN 'week'  THEN now() - interval '7 days'
      WHEN 'month' THEN now() - interval '30 days'
      ELSE 'epoch'::timestamptz
    END AS since
  ),
  raw AS (
    SELECT g.winner_id AS uid, NULLIF(trim(pp.display_name),'') AS dn
      FROM ludo_games g JOIN ludo_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE g.status='finished' AND g.winner_id IS NOT NULL AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL SELECT g.winner_id, NULLIF(trim(pp.display_name),'')
      FROM domino_games g JOIN domino_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE g.status='finished' AND g.winner_id IS NOT NULL AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL SELECT g.winner_id, NULLIF(trim(pp.display_name),'')
      FROM fanorona_games g JOIN fanorona_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE g.status='finished' AND g.winner_id IS NOT NULL AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL SELECT g.winner_id, NULLIF(trim(pp.display_name),'')
      FROM rami_games g JOIN rami_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE g.status='finished' AND g.winner_id IS NOT NULL AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL SELECT g.winner_id, NULL::text
      FROM chess_games g, bound
      WHERE g.status='finished' AND g.winner_id IS NOT NULL AND COALESCE(g.finished_at,g.created_at) >= bound.since
  ),
  -- exclude admin wins recorded under their real name (no display_name override)
  filtered AS (
    SELECT r.uid, r.dn FROM raw r
    WHERE r.dn IS NOT NULL OR NOT public.has_role(r.uid, 'admin')
  ),
  named AS (
    SELECT COALESCE(f.dn, p.pseudo, 'Joueur') AS name, f.uid
    FROM filtered f LEFT JOIN profiles p ON p.id=f.uid
  ),
  agg AS (
    SELECT name, (array_agg(uid))[1] AS uid, count(*)::bigint AS wins
    FROM named GROUP BY name
  )
  SELECT (row_number() OVER (ORDER BY a.wins DESC, a.name ASC))::int AS rank,
         a.name, p.avatar_url, a.wins
  FROM agg a LEFT JOIN profiles p ON p.id=a.uid
  ORDER BY a.wins DESC, a.name ASC
  LIMIT _limit;
$$;
REVOKE ALL ON FUNCTION public.leaderboard_winners(text,int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.leaderboard_winners(text,int) TO authenticated, anon;