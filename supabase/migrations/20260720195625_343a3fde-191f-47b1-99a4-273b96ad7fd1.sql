ALTER TABLE public.tournaments ALTER COLUMN players_per_match SET DEFAULT 2;
UPDATE public.tournaments SET players_per_match = 2 WHERE players_per_match IS NULL;