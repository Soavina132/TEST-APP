DROP FUNCTION IF EXISTS public.leaderboard_winners(text, int, text);
CREATE OR REPLACE FUNCTION public.leaderboard_winners(
  _period text DEFAULT 'all',
  _limit  int  DEFAULT 20,
  _slug   text DEFAULT NULL
)
RETURNS TABLE(rank int, user_id uuid, name text, avatar_url text, wins bigint, total_won numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
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
    WHERE NOT EXISTS (SELECT 1 FROM public.profiles pb WHERE pb.id = r.uid AND pb.is_bot = true)
  ),
  agg AS (
    SELECT uid,
           COUNT(*) AS wins,
           SUM(won) AS total_won,
           MAX(dn) AS dn
    FROM filtered
    GROUP BY uid
  )
  SELECT ROW_NUMBER() OVER (ORDER BY total_won DESC NULLS LAST, wins DESC)::int AS rank,
         a.uid AS user_id,
         COALESCE(a.dn, p.pseudo, 'Joueur') AS name,
         p.avatar_url,
         a.wins,
         a.total_won
    FROM agg a
    LEFT JOIN public.profiles p ON p.id = a.uid
    ORDER BY total_won DESC NULLS LAST, wins DESC
    LIMIT LEAST(COALESCE(_limit, 20), 100);
$$;
GRANT EXECUTE ON FUNCTION public.leaderboard_winners(text, int, text) TO anon, authenticated;