-- Ajout des colonnes points_* et tpoints_* manquantes dans app_settings
ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS points_capture numeric DEFAULT 0,
  ADD COLUMN IF NOT EXISTS points_home numeric DEFAULT 0,
  ADD COLUMN IF NOT EXISTS points_first numeric DEFAULT 0,
  ADD COLUMN IF NOT EXISTS points_second numeric DEFAULT 0,
  ADD COLUMN IF NOT EXISTS points_third numeric DEFAULT 0,
  ADD COLUMN IF NOT EXISTS tpoints_first numeric DEFAULT 0,
  ADD COLUMN IF NOT EXISTS tpoints_second numeric DEFAULT 0,
  ADD COLUMN IF NOT EXISTS tpoints_third numeric DEFAULT 0;
