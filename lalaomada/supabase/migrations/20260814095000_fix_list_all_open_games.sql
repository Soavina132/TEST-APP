-- Fix: list_all_open_games was missing domino and ludo games
-- This meant open public domino/ludo games never appeared in the
-- "Parties ouvertes" section on the home page.
-- Now includes ALL 6 game types: domino, ludo, fanorona, chess, rami, poker

CREATE OR REPLACE FUNCTION public.list_all_open_games()
RETURNS TABLE (
  game_id uuid,
  slug text,
  stake numeric,
  pot numeric,
  created_at timestamptz,
  max_players integer,
  players_count integer,
  host_id uuid,
  host_name text,
  target_score numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = 'public'
AS $function$
BEGIN
  RETURN QUERY
  -- Domino
  SELECT g.id, 'domino'::text, g.stake, g.pot, g.created_at,
    g.max_players,
    (SELECT count(*)::int FROM public.domino_participants p WHERE p.game_id = g.id),
    g.host_id, COALESCE(h.pseudo, 'Joueur'),
    COALESCE(g.target_score, 0)::numeric
  FROM public.domino_games g
  LEFT JOIN public.profiles h ON h.id = g.host_id
  WHERE g.status = 'open' AND g.is_private = false

  UNION ALL
  -- Ludo
  SELECT g.id, 'ludo'::text, g.stake, g.pot, g.created_at,
    g.max_players,
    (SELECT count(*)::int FROM public.ludo_participants p WHERE p.game_id = g.id),
    g.host_id, COALESCE(h.pseudo, 'Joueur'),
    0::numeric
  FROM public.ludo_games g
  LEFT JOIN public.profiles h ON h.id = g.host_id
  WHERE g.status = 'open' AND g.is_private = false

  UNION ALL
  -- Fanorona
  SELECT g.id, 'fanorona'::text, g.stake, g.pot, g.created_at,
    2,
    (SELECT count(*)::int FROM public.fanorona_participants p WHERE p.game_id = g.id),
    g.host_id, COALESCE(h.pseudo, 'Joueur'),
    0::numeric
  FROM public.fanorona_games g
  LEFT JOIN public.profiles h ON h.id = g.host_id
  WHERE g.status = 'open' AND g.is_private = false

  UNION ALL
  -- Chess
  SELECT g.id, 'chess'::text, g.stake, g.pot, g.created_at,
    2,
    ((CASE WHEN g.white_id IS NOT NULL THEN 1 ELSE 0 END) +
     (CASE WHEN g.black_id IS NOT NULL THEN 1 ELSE 0 END)),
    COALESCE(g.white_id, g.black_id),
    COALESCE(hw.pseudo, hb.pseudo, 'Joueur'),
    0::numeric
  FROM public.chess_games g
  LEFT JOIN public.profiles hw ON hw.id = g.white_id
  LEFT JOIN public.profiles hb ON hb.id = g.black_id
  WHERE g.status = 'open' AND g.is_private = false

  UNION ALL
  -- Rami
  SELECT g.id, 'rami'::text, g.stake, g.pot, g.created_at,
    g.max_players,
    (SELECT count(*)::int FROM public.rami_participants p WHERE p.game_id = g.id),
    g.created_by, COALESCE(h.pseudo, 'Joueur'),
    0::numeric
  FROM public.rami_games g
  LEFT JOIN public.profiles h ON h.id = g.created_by
  WHERE g.status = 'open' AND g.is_private = false

  UNION ALL
  -- Poker
  SELECT g.id, 'poker'::text, g.stake, g.pot, g.created_at,
    g.max_players,
    (SELECT count(*)::int FROM public.poker_players p WHERE p.game_id = g.id),
    g.host_id, COALESCE(h.pseudo, 'Joueur'),
    0::numeric
  FROM public.poker_games g
  LEFT JOIN public.profiles h ON h.id = g.host_id
  WHERE g.status = 'open' AND g.is_private = false

  ORDER BY created_at DESC;
END;
$function$;
