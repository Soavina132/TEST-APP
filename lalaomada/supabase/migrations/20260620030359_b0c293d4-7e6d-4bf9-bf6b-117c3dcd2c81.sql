ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS ai_assistant_enabled boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS ai_assistant_context text;

UPDATE public.app_settings SET ai_assistant_enabled = true WHERE id = 1;