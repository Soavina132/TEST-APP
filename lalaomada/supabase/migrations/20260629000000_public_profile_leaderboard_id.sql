-- Update leaderboard_winners to include player id for profile links
CREATE OR REPLACE FUNCTION public.leaderboard_winners(_period text DEFAULT 'all', _limit int DEFAULT 20)
RETURNS TABLE(rank int, id uuid, name text, avatar_url text, wins bigint)
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
  filtered AS (
    SELECT r.uid, r.dn FROM raw r
    WHERE NOT public.has_role(r.uid, 'admin'::public.app_role)
  ),
  named AS (
    SELECT COALESCE(f.dn, p.pseudo, 'Joueur') AS name, p.avatar_url, f.uid, p.id
    FROM filtered f LEFT JOIN public.profiles p ON p.id=f.uid
  ),
  agg AS (
    SELECT name, (array_agg(avatar_url))[1] AS avatar_url, uid, (array_agg(id))[1] AS id, count(*)::bigint AS wins
    FROM named GROUP BY name, uid
  )
  SELECT (row_number() OVER (ORDER BY a.wins DESC, a.name ASC))::int AS rank,
         a.id,
         a.name, a.avatar_url, a.wins
  FROM agg a ORDER BY a.wins DESC, a.name ASC LIMIT _limit;
$$;
REVOKE ALL ON FUNCTION public.leaderboard_winners(text,int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.leaderboard_winners(text,int) TO authenticated, anon;

-- Public function to get a player's profile (non-sensitive fields only)
CREATE OR REPLACE FUNCTION public.get_public_profile(_id uuid)
RETURNS TABLE(
  id uuid, pseudo text, avatar_url text, unique_code text, created_at timestamptz,
  player_level int, total_wins int, total_games int, daily_streak int
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT
    p.id, p.pseudo, p.avatar_url, p.unique_code, p.created_at,
    COALESCE(p.player_level, 1),
    COALESCE(p.total_wins, 0),
    COALESCE(p.total_games, 0),
    COALESCE(p.daily_streak, 0)
  FROM public.profiles p
  WHERE p.id = _id
    AND (p.is_banned = false OR p.is_banned IS NULL);
$$;
GRANT EXECUTE ON FUNCTION public.get_public_profile(uuid) TO anon, authenticated;
