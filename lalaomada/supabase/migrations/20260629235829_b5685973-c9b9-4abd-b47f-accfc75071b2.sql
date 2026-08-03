DROP FUNCTION IF EXISTS public.leaderboard_winners(text, int);

CREATE FUNCTION public.leaderboard_winners(
  _period text DEFAULT 'all',
  _limit  int  DEFAULT 20
)
RETURNS TABLE(rank int, id uuid, name text, avatar_url text, wins bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH bound AS (
    SELECT CASE _period
      WHEN 'week'  THEN now() - interval '7 days'
      WHEN 'month' THEN now() - interval '30 days'
      ELSE 'epoch'::timestamptz
    END AS since
  ),
  raw AS (
    SELECT g.winner_id AS uid FROM public.ludo_games g, bound
     WHERE g.status='finished' AND g.winner_id IS NOT NULL
       AND COALESCE(g.finished_at, g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id FROM public.domino_games g, bound
     WHERE g.status='finished' AND g.winner_id IS NOT NULL
       AND COALESCE(g.finished_at, g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id FROM public.fanorona_games g, bound
     WHERE g.status='finished' AND g.winner_id IS NOT NULL
       AND COALESCE(g.finished_at, g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id FROM public.rami_games g, bound
     WHERE g.status='finished' AND g.winner_id IS NOT NULL
       AND COALESCE(g.finished_at, g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id FROM public.chess_games g, bound
     WHERE g.status='finished' AND g.winner_id IS NOT NULL
       AND COALESCE(g.finished_at, g.created_at) >= bound.since
  ),
  agg AS (
    SELECT r.uid, count(*)::bigint AS wins
      FROM raw r
     WHERE NOT public.has_role(r.uid, 'admin'::public.app_role)
     GROUP BY r.uid
  ),
  joined AS (
    SELECT DISTINCT ON (a.uid)
      a.uid AS id, p.pseudo AS name, p.avatar_url, a.wins
    FROM agg a
    INNER JOIN public.profiles p ON p.id = a.uid
    WHERE (p.banned IS NULL OR p.banned = false)
  )
  SELECT (row_number() OVER (ORDER BY j.wins DESC, j.name ASC))::int AS rank,
         j.id, j.name, j.avatar_url, j.wins
  FROM joined j
  ORDER BY j.wins DESC, j.name ASC
  LIMIT _limit;
$$;
REVOKE ALL ON FUNCTION public.leaderboard_winners(text, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.leaderboard_winners(text, int) TO authenticated, anon;

-- Refund + wipe all in-progress games (statuses: open, playing, drawing)
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT p.user_id, g.stake FROM public.ludo_participants p
            JOIN public.ludo_games g ON g.id=p.game_id
            WHERE g.status IN ('open','playing','drawing') LOOP
    UPDATE public.profiles SET balance_ar=COALESCE(balance_ar,0)+COALESCE(r.stake,0) WHERE id=r.user_id;
  END LOOP;
  FOR r IN SELECT p.user_id, g.stake FROM public.domino_participants p
            JOIN public.domino_games g ON g.id=p.game_id
            WHERE g.status IN ('open','playing','drawing') LOOP
    UPDATE public.profiles SET balance_ar=COALESCE(balance_ar,0)+COALESCE(r.stake,0) WHERE id=r.user_id;
  END LOOP;
  FOR r IN SELECT p.user_id, g.stake FROM public.fanorona_participants p
            JOIN public.fanorona_games g ON g.id=p.game_id
            WHERE g.status IN ('open','playing','drawing') LOOP
    UPDATE public.profiles SET balance_ar=COALESCE(balance_ar,0)+COALESCE(r.stake,0) WHERE id=r.user_id;
  END LOOP;
  FOR r IN SELECT p.user_id, g.stake FROM public.rami_participants p
            JOIN public.rami_games g ON g.id=p.game_id
            WHERE g.status IN ('open','playing','drawing') LOOP
    UPDATE public.profiles SET balance_ar=COALESCE(balance_ar,0)+COALESCE(r.stake,0) WHERE id=r.user_id;
  END LOOP;
  FOR r IN SELECT white_id AS user_id, stake FROM public.chess_games
            WHERE status IN ('open','playing','drawing') AND white_id IS NOT NULL
            UNION ALL
            SELECT black_id, stake FROM public.chess_games
            WHERE status IN ('open','playing','drawing') AND black_id IS NOT NULL LOOP
    UPDATE public.profiles SET balance_ar=COALESCE(balance_ar,0)+COALESCE(r.stake,0) WHERE id=r.user_id;
  END LOOP;
END$$;

DELETE FROM public.ludo_games     WHERE status IN ('open','playing','drawing');
DELETE FROM public.domino_games   WHERE status IN ('open','playing','drawing');
DELETE FROM public.fanorona_games WHERE status IN ('open','playing','drawing');
DELETE FROM public.rami_games     WHERE status IN ('open','playing','drawing');
DELETE FROM public.chess_games    WHERE status IN ('open','playing','drawing');