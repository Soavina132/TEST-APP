ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS tuto_url TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS update_url TEXT NOT NULL DEFAULT '';
UPDATE public.app_settings SET tuto_url = 'https://www.facebook.com/100094560312684/posts/764839300011407/?app=fbl' WHERE id = 1 AND (tuto_url IS NULL OR tuto_url = '');