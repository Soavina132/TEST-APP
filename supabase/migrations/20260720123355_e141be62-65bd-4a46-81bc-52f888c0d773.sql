DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='poker_games') THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.poker_games';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='poker_players') THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.poker_players';
  END IF;
END$$;

ALTER TABLE public.poker_games REPLICA IDENTITY FULL;
ALTER TABLE public.poker_players REPLICA IDENTITY FULL;
ALTER TABLE public.ludo_games REPLICA IDENTITY FULL;
ALTER TABLE public.ludo_participants REPLICA IDENTITY FULL;
ALTER TABLE public.domino_games REPLICA IDENTITY FULL;
ALTER TABLE public.domino_participants REPLICA IDENTITY FULL;
ALTER TABLE public.rami_games REPLICA IDENTITY FULL;
ALTER TABLE public.rami_participants REPLICA IDENTITY FULL;
ALTER TABLE public.fanorona_games REPLICA IDENTITY FULL;
ALTER TABLE public.fanorona_participants REPLICA IDENTITY FULL;
ALTER TABLE public.chess_games REPLICA IDENTITY FULL;