
-- 1) Attach missing trigger so every new auth user gets a profile row
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 2) Backfill profiles for existing users that are missing one
DO $$
DECLARE r RECORD; v_bonus NUMERIC; v_ref TEXT; v_uniq TEXT; v_pseudo TEXT;
BEGIN
  SELECT signup_bonus INTO v_bonus FROM public.app_settings WHERE id = 1;
  FOR r IN SELECT u.id, u.email, u.raw_user_meta_data
           FROM auth.users u LEFT JOIN public.profiles p ON p.id = u.id
           WHERE p.id IS NULL LOOP
    v_pseudo := COALESCE(r.raw_user_meta_data->>'pseudo', split_part(r.email,'@',1));
    v_ref := public.gen_referral_code();
    v_uniq := public.gen_unique_code();
    INSERT INTO public.profiles(id, pseudo, email, referral_code, balance_ar, unique_code)
    VALUES (r.id, v_pseudo, r.email, v_ref, COALESCE(v_bonus,0), v_uniq);
    INSERT INTO public.user_roles(user_id, role) VALUES (r.id, 'user') ON CONFLICT DO NOTHING;
  END LOOP;
END $$;
