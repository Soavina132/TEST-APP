CREATE OR REPLACE FUNCTION public.chess_tick_all()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r record; n int := 0;
BEGIN
  FOR r IN SELECT id FROM chess_games WHERE status = 'playing' AND NOT coalesce(paused,false) LOOP
    PERFORM public.chess_tick(r.id);
    n := n + 1;
  END LOOP;
  RETURN n;
END $function$;