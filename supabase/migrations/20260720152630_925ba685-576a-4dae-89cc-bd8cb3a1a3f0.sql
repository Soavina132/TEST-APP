
ALTER TABLE public.tournaments REPLICA IDENTITY FULL;
ALTER TABLE public.tournament_matches REPLICA IDENTITY FULL;
ALTER TABLE public.tournament_registrations REPLICA IDENTITY FULL;

DO $$ BEGIN
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.tournament_payouts; EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;
