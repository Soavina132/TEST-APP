CREATE OR REPLACE FUNCTION public._domino_deal(_n_players integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  tiles int[][] := ARRAY[]::int[][];
  a int; b int;
  shuffled jsonb;
  arr jsonb := '[]'::jsonb;
  i int;
BEGIN
  FOR a IN 0..6 LOOP
    FOR b IN a..6 LOOP
      arr := arr || jsonb_build_array(jsonb_build_array(a,b));
    END LOOP;
  END LOOP;
  -- shuffle in SQL
  SELECT jsonb_agg(value ORDER BY random()) INTO shuffled FROM jsonb_array_elements(arr);
  RETURN shuffled;
END $function$
