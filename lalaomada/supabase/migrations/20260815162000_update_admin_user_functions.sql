-- Update admin_search_users and admin_list_users_sorted to return full user info

-- Drop old versions first (return type changed)
DROP FUNCTION IF EXISTS public.admin_search_users(text);
DROP FUNCTION IF EXISTS public.admin_list_users_sorted(text);

-- ── 1. admin_search_users: full user info ──
CREATE OR REPLACE FUNCTION public.admin_search_users(_q text)
RETURNS TABLE(
  id uuid, pseudo text, email text, balance_ar numeric, unique_code text,
  banned boolean, status text, created_at timestamptz, is_admin boolean,
  phone text, phone_verified boolean, two_factor_enabled boolean
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  RETURN QUERY
    SELECT p.id, p.pseudo, p.email, p.balance_ar, p.unique_code,
      p.banned, p.status, p.created_at,
      EXISTS(SELECT 1 FROM public.user_roles r WHERE r.user_id=p.id AND r.role='admin'),
      p.phone, p.phone_verified,
      COALESCE(p.two_factor_enabled, false)
    FROM public.profiles p
    WHERE _q IS NULL OR _q = '' OR
      p.pseudo ILIKE '%'||_q||'%' OR p.email ILIKE '%'||_q||'%' OR p.unique_code ILIKE '%'||_q||'%' OR p.id::text = _q
    ORDER BY p.created_at DESC LIMIT 100;
END $$;
REVOKE ALL ON FUNCTION public.admin_search_users(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_search_users(text) TO authenticated;

-- ── 2. admin_list_users_sorted: full user info ──
CREATE OR REPLACE FUNCTION public.admin_list_users_sorted(_sort text)
RETURNS TABLE(
  id uuid, pseudo text, email text, balance_ar numeric, created_at timestamptz,
  is_admin boolean, phone_verified boolean,
  phone text, two_factor_enabled boolean, banned boolean, unique_code text, status text
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  RETURN QUERY
    SELECT p.id, p.pseudo, p.email, p.balance_ar, p.created_at,
      EXISTS(SELECT 1 FROM public.user_roles r WHERE r.user_id=p.id AND r.role='admin'),
      p.phone_verified,
      p.phone, COALESCE(p.two_factor_enabled, false), p.banned, p.unique_code, p.status
    FROM public.profiles p
    ORDER BY
      CASE WHEN _sort='balance' THEN p.balance_ar END DESC NULLS LAST,
      CASE WHEN _sort='pseudo' THEN p.pseudo END ASC,
      CASE WHEN _sort='recent' OR _sort IS NULL OR _sort='' THEN p.created_at END DESC;
END $$;
REVOKE ALL ON FUNCTION public.admin_list_users_sorted(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_users_sorted(text) TO authenticated;
