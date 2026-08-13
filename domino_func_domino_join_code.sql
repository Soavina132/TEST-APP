CREATE OR REPLACE FUNCTION public.domino_join_code(_code text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE g_id uuid;
BEGIN
  SELECT id INTO g_id FROM public.domino_games WHERE room_code = upper(_code) AND status = 'open';
  IF g_id IS NULL THEN RAISE EXCEPTION 'invalid code'; END IF;
  PERFORM public.domino_join(g_id);
  RETURN g_id;
END $function$
