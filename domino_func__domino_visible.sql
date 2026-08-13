CREATE OR REPLACE FUNCTION public._domino_visible(_game_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS(
    SELECT 1 FROM public.domino_games g
    WHERE g.id = _game_id
      AND (
        (g.status IN ('open','playing') AND g.is_private = false)
        OR g.host_id = auth.uid()
        OR EXISTS(SELECT 1 FROM public.domino_participants p WHERE p.game_id = g.id AND p.user_id = auth.uid())
        OR public.is_admin()
      )
  )
$function$
