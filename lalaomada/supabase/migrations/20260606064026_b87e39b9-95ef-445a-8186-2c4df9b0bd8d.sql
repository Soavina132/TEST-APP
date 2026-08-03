
-- 1) Protect phone verification code at column level
REVOKE SELECT (phone_verification_code) ON public.profiles FROM anon, authenticated;

-- 2) Guard admin_list_phone_requests + revoke from public/anon
CREATE OR REPLACE FUNCTION public.admin_list_phone_requests()
RETURNS TABLE(id uuid, pseudo text, phone text, code text, requested_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  RETURN QUERY
    SELECT p.id, p.pseudo, p.phone, p.phone_verification_code, p.phone_verification_requested_at
    FROM public.profiles p
    WHERE p.phone IS NOT NULL AND p.phone_verified = false AND p.phone_verification_code IS NOT NULL
    ORDER BY p.phone_verification_requested_at DESC;
END $$;
REVOKE EXECUTE ON FUNCTION public.admin_list_phone_requests() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_phone_requests() TO authenticated;

-- 3) Restrict tournament read policies to authenticated only
DROP POLICY IF EXISTS treg_read ON public.tournament_registrations;
CREATE POLICY treg_read ON public.tournament_registrations FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS tmatch_read ON public.tournament_matches;
CREATE POLICY tmatch_read ON public.tournament_matches FOR SELECT TO authenticated USING (true);

-- 4) Chat bucket: now private; add SELECT policy for authenticated users only
DROP POLICY IF EXISTS chat_authenticated_read ON storage.objects;
CREATE POLICY chat_authenticated_read ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'chat');
