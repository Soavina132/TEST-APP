CREATE OR REPLACE FUNCTION public.get_ai_assistant_settings()
RETURNS TABLE(enabled boolean, context text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(ai_assistant_enabled, true), ai_assistant_context
  FROM public.app_settings WHERE id = 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_ai_assistant_settings() TO anon, authenticated;