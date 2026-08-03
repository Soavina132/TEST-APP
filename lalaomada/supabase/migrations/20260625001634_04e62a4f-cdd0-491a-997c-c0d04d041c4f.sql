DROP FUNCTION IF EXISTS public.list_live_games();

CREATE OR REPLACE FUNCTION public.list_live_games()
RETURNS TABLE(
  id uuid,
  max_players integer,
  stake numeric,
  pot numeric,
  players_count integer,
  spectators_count integer,
  started_at timestamptz,
  mode text,
  game_type text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT g.id, g.max_players, g.stake, g.pot,
    (SELECT count(*)::int FROM public.ludo_participants p WHERE p.game_id=g.id),
    (SELECT count(*)::int FROM public.game_spectators s WHERE s.game_id=g.id),
    g.started_at, COALESCE(g.mode,'classic')::text, 'ludo'::text
  FROM public.ludo_games g WHERE g.status='playing'
  UNION ALL
  SELECT g.id, g.max_players, g.stake, g.pot,
    (SELECT count(*)::int FROM public.domino_participants p WHERE p.game_id=g.id),
    (SELECT count(*)::int FROM public.game_spectators s WHERE s.game_id=g.id),
    g.started_at, COALESCE(g.mode,'classic')::text, 'domino'::text
  FROM public.domino_games g WHERE g.status='playing'
  UNION ALL
  SELECT g.id, 2, g.stake, g.pot,
    2,
    (SELECT count(*)::int FROM public.game_spectators s WHERE s.game_id=g.id),
    g.started_at, 'classic'::text, 'chess'::text
  FROM public.chess_games g WHERE g.status='playing'
  UNION ALL
  SELECT g.id, 2, g.stake, g.pot,
    2,
    (SELECT count(*)::int FROM public.game_spectators s WHERE s.game_id=g.id),
    g.started_at, 'classic'::text, 'fanorona'::text
  FROM public.fanorona_games g WHERE g.status='playing'
  UNION ALL
  SELECT g.id, g.max_players, g.stake, g.pot,
    (SELECT count(*)::int FROM public.rami_participants p WHERE p.game_id=g.id),
    (SELECT count(*)::int FROM public.game_spectators s WHERE s.game_id=g.id),
    g.started_at, COALESCE(g.joker_mode,'classique')::text, 'rami'::text
  FROM public.rami_games g WHERE g.status='playing'
  ORDER BY 6 DESC, 7 ASC;
$function$;

GRANT EXECUTE ON FUNCTION public.list_live_games() TO anon, authenticated;
