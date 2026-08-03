-- Ajoute le flag referral_enabled à app_settings.
-- Quand false : tout le programme de parrainage est invisible côté utilisateur.
ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS referral_enabled BOOLEAN NOT NULL DEFAULT true;
