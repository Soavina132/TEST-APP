CREATE OR REPLACE FUNCTION public.domino_generate_tiles()
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE SECURITY DEFINER
AS $function$
DECLARE _tiles jsonb := '[]'::jsonb; _i int; _j int;
BEGIN
  FOR _i IN 0..6 LOOP
    FOR _j IN _i..6 LOOP
      _tiles := _tiles || jsonb_build_array(jsonb_build_array(_i, _j));
    END LOOP;
  END LOOP;
  SELECT jsonb_agg(x) INTO _tiles FROM (SELECT x FROM jsonb_array_elements(_tiles) AS x ORDER BY random()) s;
  RETURN _tiles;
END;
$function$
