ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS grace_period_secs int NOT NULL DEFAULT 300,
  ADD COLUMN IF NOT EXISTS auto_start_mins int NOT NULL DEFAULT 0;