REVOKE ALL ON FUNCTION public.domino_tick_all() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.domino_tick_all() FROM anon;
REVOKE ALL ON FUNCTION public.domino_tick_all() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.domino_tick_all() TO service_role;