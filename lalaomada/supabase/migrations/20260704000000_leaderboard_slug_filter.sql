-- Add _slug filter to leaderboard_winners
-- _slug = NULL or 'all' → toutes les parties confondues
-- _slug = 'ludo'|'domino'|'fanorona'|'chess'|'rami'|'poker' → un seul jeu

DROP FUNCTION IF EXISTS public.leaderboard_winners(text, int);

CREATE OR REPLACE FUNCTION public.leaderboard_winners(
  _period text DEFAULT 'all',
  _limit  int  DEFAULT 20,
  _slug   text DEFAULT NULL   -- NULL or 'all' = all games
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
    -- ludo
    SELECT g.winner_id AS uid, NULLIF(trim(pp.display_name),'') AS dn,
           g.pot * (1 - g.commission_pct/100.0) AS won
      FROM ludo_games g JOIN ludo_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'ludo')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    -- domino
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0)
      FROM domino_games g JOIN domino_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'domino')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    -- fanorona
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0)
      FROM fanorona_games g JOIN fanorona_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'fanorona')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    -- rami
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0)
      FROM rami_games g JOIN rami_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'rami')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    -- chess
    SELECT g.winner_id, NULL::text,
           g.stake * 2 * (1 - COALESCE((SELECT commission_pct FROM app_settings WHERE id=1),0)/100.0)
      FROM chess_games g, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'chess')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    -- poker
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0)
      FROM poker_games g JOIN poker_players pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'poker')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
  ),
  filtered AS (
    SELECT r.uid, r.dn, r.won FROM raw r
    WHERE NOT public.has_role(r.uid, 'admin'::public.app_role)
  ),
  named AS (
    SELECT COALESCE(f.dn, p.pseudo, 'Joueur') AS name,
           p.avatar_url, f.uid, f.won
    FROM filtered f LEFT JOIN public.profiles p ON p.id=f.uid
  ),
  agg AS (
    SELECT uid, name, (array_agg(avatar_url))[1] AS avatar_url,
           count(*)::bigint AS wins,
           COALESCE(sum(won), 0)::numeric AS total_won
    FROM named GROUP BY uid, name
  )
  SELECT (row_number() OVER (ORDER BY a.wins DESC, a.name ASC))::int AS rank,
         a.uid AS user_id, a.name, a.avatar_url, a.wins, a.total_won
  FROM agg a ORDER BY a.wins DESC, a.name ASC LIMIT _limit;
$$;

REVOKE ALL ON FUNCTION public.leaderboard_winners(text, int, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.leaderboard_winners(text, int, text) TO authenticated, anon;
