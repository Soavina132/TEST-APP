-- Ajout des colonnes de contact et textes légaux (plain text) dans app_settings
ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS contact_whatsapp  TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS contact_facebook  TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS contact_email     TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS terms_text        TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS privacy_text      TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS faq_text          TEXT NOT NULL DEFAULT '';

COMMENT ON COLUMN public.app_settings.contact_whatsapp IS 'Numéro WhatsApp affiché dans le footer/contact';
COMMENT ON COLUMN public.app_settings.contact_facebook  IS 'URL ou identifiant Facebook';
COMMENT ON COLUMN public.app_settings.contact_email     IS 'Adresse e-mail de contact';
COMMENT ON COLUMN public.app_settings.terms_text        IS 'Conditions d utilisation (texte brut)';
COMMENT ON COLUMN public.app_settings.privacy_text      IS 'Politique de confidentialite (texte brut)';
COMMENT ON COLUMN public.app_settings.faq_text          IS 'FAQ / Questions frequentes (texte brut)';
