
-- Combined "my ongoing games" across all game types + 7-day weekly top winners

CREATE OR REPLACE FUNCTION public.my_ongoing_all()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_uid uuid := auth.uid(); v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.created_at DESC), '[]'::jsonb) INTO v_result FROM (
    SELECT g.id, 'ludo'::text AS game_type, g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at,
      (SELECT count(*) FROM ludo_participants pp WHERE pp.game_id=g.id) AS players_count
    FROM ludo_games g JOIN ludo_participants p ON p.game_id=g.id
    WHERE p.user_id=v_uid AND g.status IN ('open','playing') AND p.forfeited=false
    UNION ALL
    SELECT g.id, 'domino', g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at,
      (SELECT count(*) FROM domino_participants pp WHERE pp.game_id=g.id)
    FROM domino_games g JOIN domino_participants p ON p.game_id=g.id
    WHERE p.user_id=v_uid AND g.status IN ('open','playing') AND p.forfeited=false
    UNION ALL
    SELECT g.id, 'fanorona', g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at,
      (SELECT count(*) FROM fanorona_participants pp WHERE pp.game_id=g.id)
    FROM fanorona_games g JOIN fanorona_participants p ON p.game_id=g.id
    WHERE p.user_id=v_uid AND g.status IN ('open','playing') AND p.forfeited=false
    UNION ALL
    SELECT g.id, 'rami', g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at,
      (SELECT count(*) FROM rami_participants pp WHERE pp.game_id=g.id)
    FROM rami_games g JOIN rami_participants p ON p.game_id=g.id
    WHERE p.user_id=v_uid AND g.status IN ('open','playing') AND p.forfeited=false
    UNION ALL
    SELECT g.id, 'chess', g.status, 2 AS max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at,
      (CASE WHEN g.black_id IS NULL THEN 1 ELSE 2 END)::bigint
    FROM chess_games g
    WHERE (g.white_id=v_uid OR g.black_id=v_uid) AND g.status IN ('open','playing')
  ) t;
  RETURN v_result;
END $$;

GRANT EXECUTE ON FUNCTION public.my_ongoing_all() TO authenticated;

CREATE OR REPLACE FUNCTION public.weekly_top_winners(_limit int DEFAULT 10)
RETURNS TABLE(user_id uuid, pseudo text, avatar_url text, wins bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH wins AS (
    SELECT winner_id AS uid FROM domino_games WHERE status='finished' AND winner_id IS NOT NULL AND COALESCE(finished_at, created_at) >= now() - interval '7 days'
    UNION ALL
    SELECT winner_id FROM fanorona_games WHERE status='finished' AND winner_id IS NOT NULL AND COALESCE(finished_at, created_at) >= now() - interval '7 days'
    UNION ALL
    SELECT winner_id FROM ludo_games WHERE status='finished' AND winner_id IS NOT NULL AND COALESCE(finished_at, created_at) >= now() - interval '7 days'
    UNION ALL
    SELECT winner_id FROM rami_games WHERE status='finished' AND winner_id IS NOT NULL AND COALESCE(finished_at, created_at) >= now() - interval '7 days'
    UNION ALL
    SELECT winner_id FROM chess_games WHERE status='finished' AND winner_id IS NOT NULL AND COALESCE(finished_at, created_at) >= now() - interval '7 days'
  )
  SELECT p.id, p.pseudo, p.avatar_url, count(*)::bigint AS wins
  FROM wins w JOIN profiles p ON p.id = w.uid
  GROUP BY p.id, p.pseudo, p.avatar_url
  ORDER BY wins DESC, p.pseudo ASC
  LIMIT _limit;
$$;

GRANT EXECUTE ON FUNCTION public.weekly_top_winners(int) TO authenticated, anon;
