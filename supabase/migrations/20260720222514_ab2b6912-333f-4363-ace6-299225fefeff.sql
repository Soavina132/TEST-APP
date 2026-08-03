
DROP FUNCTION IF EXISTS public.list_public_open_games();

CREATE OR REPLACE FUNCTION public.list_public_open_games()
RETURNS TABLE(
  id uuid,
  game_slug text,
  max_players integer,
  stake numeric,
  pot numeric,
  room_code text,
  players_count integer,
  is_private boolean,
  created_at timestamptz
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT g.id, 'ludo'::text, g.max_players, g.stake, g.pot, g.room_code,
    (SELECT count(*)::int FROM public.ludo_participants p WHERE p.game_id=g.id),
    g.is_private, g.created_at
  FROM public.ludo_games g
  WHERE g.status='open' AND g.is_private=false
    AND (SELECT count(*) FROM public.ludo_participants p WHERE p.game_id=g.id) < g.max_players

  UNION ALL
  SELECT g.id, 'domino', g.max_players, g.stake, g.pot, g.room_code,
    (SELECT count(*)::int FROM public.domino_participants p WHERE p.game_id=g.id),
    g.is_private, g.created_at
  FROM public.domino_games g
  WHERE g.status='open' AND g.is_private=false
    AND (SELECT count(*) FROM public.domino_participants p WHERE p.game_id=g.id) < g.max_players

  UNION ALL
  SELECT g.id, 'fanorona', 2, g.stake, g.pot, g.room_code,
    (SELECT count(*)::int FROM public.fanorona_participants p WHERE p.game_id=g.id),
    g.is_private, g.created_at
  FROM public.fanorona_games g
  WHERE g.status='open' AND g.is_private=false
    AND (SELECT count(*) FROM public.fanorona_participants p WHERE p.game_id=g.id) < 2

  UNION ALL
  SELECT g.id, 'chess', 2, g.stake, g.pot, g.room_code,
    ((CASE WHEN g.white_id IS NULL THEN 0 ELSE 1 END) + (CASE WHEN g.black_id IS NULL THEN 0 ELSE 1 END)),
    g.is_private, g.created_at
  FROM public.chess_games g
  WHERE g.status='open' AND g.is_private=false
    AND (g.white_id IS NULL OR g.black_id IS NULL)

  UNION ALL
  SELECT g.id, 'rami', g.max_players, g.stake, g.pot, g.room_code,
    (SELECT count(*)::int FROM public.rami_participants p WHERE p.game_id=g.id),
    g.is_private, g.created_at
  FROM public.rami_games g
  WHERE g.status='open' AND g.is_private=false
    AND (SELECT count(*) FROM public.rami_participants p WHERE p.game_id=g.id) < g.max_players

  UNION ALL
  SELECT g.id, 'poker', g.max_players, g.stake, g.pot, g.room_code,
    (SELECT count(*)::int FROM public.poker_players p WHERE p.game_id=g.id),
    g.is_private, g.created_at
  FROM public.poker_games g
  WHERE g.status='open' AND g.is_private=false
    AND (SELECT count(*) FROM public.poker_players p WHERE p.game_id=g.id) < g.max_players

  ORDER BY created_at DESC;
$$;

GRANT EXECUTE ON FUNCTION public.list_public_open_games() TO anon, authenticated;
