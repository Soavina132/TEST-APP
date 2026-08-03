ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS reward_distribution jsonb NOT NULL DEFAULT '{"first":60,"second":20,"third":10,"platform":10}'::jsonb,
  ADD COLUMN IF NOT EXISTS entry_fee numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS players_per_table integer NOT NULL DEFAULT 2,
  ADD COLUMN IF NOT EXISTS qualifiers_per_table integer NOT NULL DEFAULT 1;