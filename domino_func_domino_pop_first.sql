CREATE OR REPLACE FUNCTION public.domino_pop_first(_arr jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE SECURITY DEFINER
AS $function$
DECLARE _result jsonb;
BEGIN
  SELECT jsonb_agg(x) INTO _result
  FROM (SELECT x FROM jsonb_array_elements(_arr) WITH ORDINALITY AS ord(x, rn) WHERE rn > 1 ORDER BY rn) s;
  RETURN COALESCE(_result, '[]'::jsonb);
END;
$function$
