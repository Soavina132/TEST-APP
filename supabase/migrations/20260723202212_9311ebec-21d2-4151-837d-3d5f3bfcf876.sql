ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS tuto_url text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS update_url text NOT NULL DEFAULT '';