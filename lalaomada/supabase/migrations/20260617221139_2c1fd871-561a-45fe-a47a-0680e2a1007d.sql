
-- 1. Seed app_settings row 1 (Accueil/Live attendent cette ligne)
INSERT INTO public.app_settings(id) VALUES (1) ON CONFLICT (id) DO NOTHING;

-- 2. Attacher le trigger handle_new_user à auth.users (manquant)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 3. Backfill : créer un profil pour chaque user existant sans profil
INSERT INTO public.profiles(id, pseudo, email, referral_code, unique_code, balance_ar)
SELECT
  u.id,
  COALESCE(u.raw_user_meta_data->>'pseudo', split_part(u.email,'@',1)),
  u.email,
  public.gen_referral_code(),
  public.gen_unique_code(),
  COALESCE((SELECT signup_bonus FROM public.app_settings WHERE id=1), 0)
FROM auth.users u
LEFT JOIN public.profiles p ON p.id = u.id
WHERE p.id IS NULL;

-- 4. Backfill rôle par défaut + auto-admin pour soavinapierrit@gmail.com
INSERT INTO public.user_roles(user_id, role)
SELECT u.id,
       CASE WHEN lower(u.email) = 'soavinapierrit@gmail.com' THEN 'admin'::app_role
            ELSE 'user'::app_role END
FROM auth.users u
WHERE NOT EXISTS (SELECT 1 FROM public.user_roles r WHERE r.user_id = u.id);

-- 5. S'assurer que si soavinapierrit@gmail.com existe déjà (même avec un autre rôle), il a admin
INSERT INTO public.user_roles(user_id, role)
SELECT u.id, 'admin'::app_role FROM auth.users u
WHERE lower(u.email) = 'soavinapierrit@gmail.com'
ON CONFLICT (user_id, role) DO NOTHING;
