-- Real-time pseudo (username) availability check for the signup form.
-- Runs as SECURITY DEFINER so anonymous visitors can check availability
-- without being granted broader SELECT access to the profiles table.

CREATE OR REPLACE FUNCTION public.check_pseudo_available(p_pseudo TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT NOT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE lower(pseudo) = lower(trim(p_pseudo))
  );
$$;

GRANT EXECUTE ON FUNCTION public.check_pseudo_available(TEXT) TO anon, authenticated;
