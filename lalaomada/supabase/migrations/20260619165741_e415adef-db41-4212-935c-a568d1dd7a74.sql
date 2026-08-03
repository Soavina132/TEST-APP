-- Enable pgcrypto for gen_random_bytes used by draw RPCs
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;

-- Ensure FULL replica identity so realtime payloads carry all columns
ALTER TABLE public.chess_games REPLICA IDENTITY FULL;
ALTER TABLE public.fanorona_games REPLICA IDENTITY FULL;
ALTER TABLE public.chess_moves REPLICA IDENTITY FULL;
ALTER TABLE public.fanorona_participants REPLICA IDENTITY FULL;

-- Add tables to the realtime publication (no-op if already present)
DO $$ BEGIN
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.chess_games; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.fanorona_games; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.chess_moves; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.fanorona_participants; EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;