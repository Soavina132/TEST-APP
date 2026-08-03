
-- 1) Seed missing app_settings row so the app stops hanging on "Loading"
INSERT INTO public.app_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

-- 2) Backfill missing profile rows for existing auth users
INSERT INTO public.profiles (id, pseudo, email, balance_ar, referral_code, unique_code)
SELECT
  u.id,
  COALESCE(NULLIF(u.raw_user_meta_data->>'pseudo',''), split_part(u.email, '@', 1), 'Joueur'),
  COALESCE(u.email, ''),
  1,
  upper(substr(md5(u.id::text), 1, 8)),
  upper(substr(md5(u.id::text || 'u'), 1, 6))
FROM auth.users u
LEFT JOIN public.profiles p ON p.id = u.id
WHERE p.id IS NULL;

-- 3) Enable Realtime for every public table + REPLICA IDENTITY FULL
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT tablename FROM pg_tables WHERE schemaname = 'public'
  LOOP
    EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL', r.tablename);
    BEGIN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', r.tablename);
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;
  END LOOP;
END $$;
