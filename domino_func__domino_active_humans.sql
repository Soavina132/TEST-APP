CREATE OR REPLACE FUNCTION public._domino_active_humans(_gid uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT count(*)::int FROM public.domino_participants
  WHERE game_id = _gid AND forfeited = false AND is_bot = false
$function$
