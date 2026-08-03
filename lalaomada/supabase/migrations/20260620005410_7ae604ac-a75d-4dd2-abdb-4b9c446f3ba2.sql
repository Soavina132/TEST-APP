
CREATE OR REPLACE FUNCTION public.get_public_help_texts()
RETURNS TABLE(signup_help text, reset_help text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT COALESCE(signup_help_html,''), COALESCE(password_reset_help_html,'')
  FROM public.app_settings WHERE id = 1;
$$;
GRANT EXECUTE ON FUNCTION public.get_public_help_texts() TO anon, authenticated;
