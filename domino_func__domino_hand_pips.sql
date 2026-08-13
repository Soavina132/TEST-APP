CREATE OR REPLACE FUNCTION public._domino_hand_pips(_hand jsonb)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(SUM(((t->>0)::int + (t->>1)::int)), 0)::int
  FROM jsonb_array_elements(COALESCE(_hand,'[]'::jsonb)) t
$function$
