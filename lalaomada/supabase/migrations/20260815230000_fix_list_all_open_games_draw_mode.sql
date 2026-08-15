-- Fix: add draw_mode to list_all_open_games return
-- Domino games store draw_mode inside the state JSONB column (state->>'draw_mode')
-- Values: 'with' or 'without'
-- Other game types return NULL (draw_mode is domino-only)

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
  target_score numeric,
  draw_mode text
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
    COALESCE(g.target_score, 0)::numeric,
    g.state->>'draw_mode'
  FROM public.domino_games g
  LEFT JOIN public.profiles h ON h.id = g.host_id
  WHERE g.status = 'open' AND g.is_private = false

  UNION ALL
  -- Ludo
  SELECT g.id, 'ludo'::text, g.stake, g.pot, g.created_at,
    g.max_players,
    (SELECT count(*)::int FROM public.ludo_participants p WHERE p.game_id = g.id),
    g.host_id, COALESCE(h.pseudo, 'Joueur'),
    0::numeric,
    NULL::text
  FROM public.ludo_games g
  LEFT JOIN public.profiles h ON h.id = g.host_id
  WHERE g.status = 'open' AND g.is_private = false

  UNION ALL
  -- Fanorona
  SELECT g.id, 'fanorona'::text, g.stake, g.pot, g.created_at,
    2,
    (SELECT count(*)::int FROM public.fanorona_participants p WHERE p.game_id = g.id),
    g.host_id, COALESCE(h.pseudo, 'Joueur'),
    0::numeric,
    NULL::text
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
    0::numeric,
    NULL::text
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
    0::numeric,
    NULL::text
  FROM public.rami_games g
  LEFT JOIN public.profiles h ON h.id = g.created_by
  WHERE g.status = 'open' AND g.is_private = false

  UNION ALL
  -- Poker
  SELECT g.id, 'poker'::text, g.stake, g.pot, g.created_at,
    g.max_players,
    (SELECT count(*)::int FROM public.poker_players p WHERE p.game_id = g.id),
    g.host_id, COALESCE(h.pseudo, 'Joueur'),
    0::numeric,
    NULL::text
  FROM public.poker_games g
  LEFT JOIN public.profiles h ON h.id = g.host_id
  WHERE g.status = 'open' AND g.is_private = false

  ORDER BY created_at DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.list_all_open_games() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_all_open_games() TO authenticated;
