CREATE OR REPLACE FUNCTION public._domino_init_state()
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT '{"phase":"waiting","hands":{},"stock":[],"board":[],"left_end":null,"right_end":null,"passes":0,"scores":{}}'::jsonb
$function$
