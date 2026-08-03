
-- 1) No-op safe restoration of cleanup_stale_open_games
CREATE OR REPLACE FUNCTION public.cleanup_stale_open_games()
RETURNS integer
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$ SELECT 0; $$;
REVOKE ALL ON FUNCTION public.cleanup_stale_open_games() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cleanup_stale_open_games() TO authenticated, service_role;

-- 2) Grant admin role now (if these users already exist)
INSERT INTO public.user_roles(user_id, role)
SELECT u.id, 'admin'::app_role
FROM auth.users u
WHERE lower(u.email) IN ('lalaomadaa@gmail.com','mrpierrit@gmail.com')
ON CONFLICT (user_id, role) DO NOTHING;

-- 3) Trigger to auto-grant admin role on signup for these emails
CREATE OR REPLACE FUNCTION public._grant_admin_for_seed_emails()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF lower(NEW.email) IN ('lalaomadaa@gmail.com','mrpierrit@gmail.com') THEN
    INSERT INTO public.user_roles(user_id, role)
    VALUES (NEW.id, 'admin'::app_role)
    ON CONFLICT (user_id, role) DO NOTHING;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS on_auth_user_created_grant_seed_admin ON auth.users;
CREATE TRIGGER on_auth_user_created_grant_seed_admin
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public._grant_admin_for_seed_emails();
