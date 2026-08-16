-- ════════════════════════════════════════════════════════════════════════
-- Fix: Add penalty to list_all_open_games and my_ongoing_all
-- Bug: Penalty games were invisible in the open games list and "Mes parties"
-- ════════════════════════════════════════════════════════════════════════

-- 1. list_all_open_games: Add penalty games
CREATE OR REPLACE FUNCTION public.list_all_open_games()
RETURNS TABLE(
  game_id uuid, slug text, stake numeric, pot numeric,
  created_at timestamptz, max_players int, players_count int,
  host_id uuid, host_name text, target_score numeric
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = 'public' AS $$
  SELECT g.id, 'ludo'::text, g.stake, g.pot, g.created_at,
    g.max_players,
    (SELECT count(*)::int FROM public.ludo_participants p WHERE p.game_id = g.id),
    g.host_id, COALESCE(h.pseudo, 'Joueur'), NULL::numeric
  FROM public.ludo_games g
  LEFT JOIN public.profiles h ON h.id = g.host_id
  WHERE g.status = 'open' AND g.is_private = false

  UNION ALL
  SELECT g.id, 'domino', g.stake, g.pot, g.created_at,
    g.max_players,
    (SELECT count(*)::int FROM public.domino_participants p WHERE p.game_id = g.id),
    g.host_id, COALESCE(h.pseudo, 'Joueur'), NULL::numeric
  FROM public.domino_games g
  LEFT JOIN public.profiles h ON h.id = g.host_id
  WHERE g.status = 'open' AND g.is_private = false

  UNION ALL
  SELECT g.id, 'fanorona', g.stake, g.pot, g.created_at,
    2,
    (SELECT count(*)::int FROM public.fanorona_participants p WHERE p.game_id = g.id),
    g.host_id, COALESCE(h.pseudo, 'Joueur'), NULL::numeric
  FROM public.fanorona_games g
  LEFT JOIN public.profiles h ON h.id = g.host_id
  WHERE g.status = 'open' AND g.is_private = false

  UNION ALL
  SELECT g.id, 'chess', g.stake, g.pot, g.created_at,
    2,
    ((CASE WHEN g.white_id IS NOT NULL THEN 1 ELSE 0 END) +
     (CASE WHEN g.black_id IS NOT NULL THEN 1 ELSE 0 END)),
    COALESCE(g.white_id, g.black_id),
    COALESCE(hw.pseudo, hb.pseudo, 'Joueur'),
    NULL::numeric
  FROM public.chess_games g
  LEFT JOIN public.profiles hw ON hw.id = g.white_id
  LEFT JOIN public.profiles hb ON hb.id = g.black_id
  WHERE g.status = 'open' AND g.is_private = false

  UNION ALL
  SELECT g.id, 'rami', g.stake, g.pot, g.created_at,
    g.max_players,
    (SELECT count(*)::int FROM public.rami_participants p WHERE p.game_id = g.id),
    g.created_by, COALESCE(h.pseudo, 'Joueur'), NULL::numeric
  FROM public.rami_games g
  LEFT JOIN public.profiles h ON h.id = g.created_by
  WHERE g.status = 'open' AND g.is_private = false

  UNION ALL
  SELECT g.id, 'poker', g.stake, g.pot, g.created_at,
    g.max_players,
    (SELECT count(*)::int FROM public.poker_players p WHERE p.game_id = g.id),
    g.host_id, COALESCE(h.pseudo, 'Joueur'), NULL::numeric
  FROM public.poker_games g
  LEFT JOIN public.profiles h ON h.id = g.host_id
  WHERE g.status = 'open' AND g.is_private = false

  UNION ALL
  SELECT g.id, 'penalty', g.stake, g.pot, g.created_at,
    2,
    (CASE WHEN g.player2_id IS NOT NULL THEN 2 ELSE 1 END)::int,
    g.host_id, COALESCE(h.pseudo, 'Joueur'), NULL::numeric
  FROM public.penalty_games g
  LEFT JOIN public.profiles h ON h.id = g.host_id
  WHERE g.status = 'open' AND g.is_private = false

  ORDER BY created_at DESC;
$$;

REVOKE ALL ON FUNCTION public.list_all_open_games() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_all_open_games() TO authenticated;

-- 2. my_ongoing_all: Add penalty games
CREATE OR REPLACE FUNCTION public.my_ongoing_all()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
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
    UNION ALL
    SELECT g.id, 'poker', g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at,
      (SELECT count(*) FROM poker_players pp WHERE pp.game_id=g.id)
    FROM poker_games g JOIN poker_players p ON p.game_id=g.id
    WHERE p.user_id=v_uid AND g.status IN ('open','playing')
    UNION ALL
    SELECT g.id, 'penalty', g.status, 2 AS max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at,
      (CASE WHEN g.player2_id IS NOT NULL THEN 2 ELSE 1 END)::bigint
    FROM penalty_games g
    WHERE (g.player1_id=v_uid OR g.player2_id=v_uid) AND g.status IN ('open','playing')
  ) t;
  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.my_ongoing_all() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.my_ongoing_all() TO authenticated;
