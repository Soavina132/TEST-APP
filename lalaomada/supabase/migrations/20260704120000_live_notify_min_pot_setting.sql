-- Make the "big pot" threshold for the live-elimination toast
-- configurable from the admin panel instead of hardcoded client-side.
ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS live_notify_min_pot NUMERIC NOT NULL DEFAULT 3000;
