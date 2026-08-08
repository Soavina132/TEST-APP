CREATE OR REPLACE FUNCTION public._rami_check_win(_state jsonb, _key text)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  _m jsonb; _t text; _total int := 0; _count int := 0;
BEGIN
  FOR _m IN SELECT * FROM jsonb_array_elements(COALESCE(_state->'melds','[]'::jsonb)) LOOP
    IF _m->>'player' = _key THEN
      _t := _m->>'type';
      IF _t NOT IN ('set','run','seven','carre','trio') THEN RETURN false; END IF;
      _total := _total + COALESCE(jsonb_array_length(_m->'cards'), 0);
      _count := _count + 1;
    END IF;
  END LOOP;
  RETURN _count >= 1 AND _total >= 13;
END $function$;
