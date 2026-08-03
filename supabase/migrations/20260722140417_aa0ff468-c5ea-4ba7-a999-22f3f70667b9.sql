
-- Helper: finish games in which no active human remains (any bot wins if needed).
CREATE OR REPLACE FUNCTION public._end_bot_only_games()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE r RECORD; v_bot UUID;
BEGIN
  -- Ludo
  FOR r IN
    SELECT g.id FROM public.ludo_games g
    WHERE g.status = 'playing' AND COALESCE(g.is_solo,false)=false
      AND NOT EXISTS (SELECT 1 FROM public.ludo_participants p WHERE p.game_id=g.id AND p.is_bot=false AND COALESCE(p.forfeited,false)=false)
  LOOP
    UPDATE public.ludo_games SET status='finished', finished_at=now() WHERE id=r.id;
  END LOOP;

  -- Domino
  FOR r IN
    SELECT g.id FROM public.domino_games g
    WHERE g.status='playing'
      AND NOT EXISTS (SELECT 1 FROM public.domino_participants p WHERE p.game_id=g.id AND p.is_bot=false AND COALESCE(p.forfeited,false)=false)
  LOOP
    UPDATE public.domino_games SET status='finished', finished_at=now() WHERE id=r.id;
  END LOOP;

  -- Fanorona
  FOR r IN
    SELECT g.id FROM public.fanorona_games g
    WHERE g.status='playing'
      AND NOT EXISTS (SELECT 1 FROM public.fanorona_participants p WHERE p.game_id=g.id AND p.is_bot=false AND COALESCE(p.forfeited,false)=false)
  LOOP
    UPDATE public.fanorona_games SET status='finished', finished_at=now() WHERE id=r.id;
  END LOOP;

  -- Rami
  FOR r IN
    SELECT g.id FROM public.rami_games g
    WHERE g.status='playing'
      AND NOT EXISTS (SELECT 1 FROM public.rami_participants p WHERE p.game_id=g.id AND p.is_bot=false AND COALESCE(p.forfeited,false)=false)
  LOOP
    UPDATE public.rami_games SET status='finished', finished_at=now() WHERE id=r.id;
  END LOOP;
END $$;

GRANT EXECUTE ON FUNCTION public._end_bot_only_games() TO authenticated, service_role;

-- Update list_live_games to hide games with no active human participant.
CREATE OR REPLACE FUNCTION public.list_live_games()
RETURNS TABLE(id uuid, max_players integer, stake numeric, pot numeric, players_count integer, spectators_count integer, started_at timestamp with time zone, mode text, game_type text)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT g.id, g.max_players, g.stake, g.pot,
    (SELECT count(*)::int FROM public.ludo_participants p WHERE p.game_id=g.id),
    (SELECT count(*)::int FROM public.game_spectators s WHERE s.game_id=g.id),
    g.started_at, COALESCE(g.mode,'classic')::text, 'ludo'::text
  FROM public.ludo_games g
  WHERE g.status='playing' AND COALESCE(g.is_solo,false)=false
    AND EXISTS (SELECT 1 FROM public.ludo_participants p WHERE p.game_id=g.id AND p.is_bot=false AND COALESCE(p.forfeited,false)=false)
  UNION ALL
  SELECT g.id, g.max_players, g.stake, g.pot,
    (SELECT count(*)::int FROM public.domino_participants p WHERE p.game_id=g.id),
    (SELECT count(*)::int FROM public.game_spectators s WHERE s.game_id=g.id),
    g.started_at, COALESCE(g.mode,'classic')::text, 'domino'::text
  FROM public.domino_games g
  WHERE g.status='playing'
    AND EXISTS (SELECT 1 FROM public.domino_participants p WHERE p.game_id=g.id AND p.is_bot=false AND COALESCE(p.forfeited,false)=false)
    AND NOT EXISTS (SELECT 1 FROM public.domino_participants pp WHERE pp.game_id=g.id AND pp.is_bot=true AND pp.user_id=g.host_id)
  UNION ALL
  SELECT g.id, 2, g.stake, g.pot,
    2,
    (SELECT count(*)::int FROM public.game_spectators s WHERE s.game_id=g.id),
    g.started_at, 'classic'::text, 'chess'::text
  FROM public.chess_games g
  WHERE g.status='playing'
    AND g.white_id IS DISTINCT FROM g.black_id
  UNION ALL
  SELECT g.id, 2, g.stake, g.pot,
    2,
    (SELECT count(*)::int FROM public.game_spectators s WHERE s.game_id=g.id),
    g.started_at, 'classic'::text, 'fanorona'::text
  FROM public.fanorona_games g
  WHERE g.status='playing'
    AND EXISTS (SELECT 1 FROM public.fanorona_participants p WHERE p.game_id=g.id AND p.is_bot=false AND COALESCE(p.forfeited,false)=false)
    AND NOT EXISTS (SELECT 1 FROM public.fanorona_participants pp WHERE pp.game_id=g.id AND pp.is_bot=true AND pp.user_id=g.host_id)
  UNION ALL
  SELECT g.id, g.max_players, g.stake, g.pot,
    (SELECT count(*)::int FROM public.rami_participants p WHERE p.game_id=g.id),
    (SELECT count(*)::int FROM public.game_spectators s WHERE s.game_id=g.id),
    g.started_at, COALESCE(g.joker_mode,'classique')::text, 'rami'::text
  FROM public.rami_games g
  WHERE g.status='playing'
    AND EXISTS (SELECT 1 FROM public.rami_participants p WHERE p.game_id=g.id AND p.is_bot=false AND COALESCE(p.forfeited,false)=false)
    AND NOT EXISTS (SELECT 1 FROM public.rami_participants pp WHERE pp.game_id=g.id AND pp.is_bot=true AND pp.user_id=g.created_by)
  ORDER BY 6 DESC, 7 ASC;
$$;

-- Run once now to clean up any current bot-only games.
SELECT public._end_bot_only_games();

-- Schedule regular cleanup (every minute).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron') THEN
    PERFORM cron.unschedule('end_bot_only_games') FROM cron.job WHERE jobname='end_bot_only_games';
    PERFORM cron.schedule('end_bot_only_games', '* * * * *', $sql$SELECT public._end_bot_only_games();$sql$);
  END IF;
END $$;
