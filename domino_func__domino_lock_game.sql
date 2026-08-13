CREATE OR REPLACE FUNCTION public._domino_lock_game(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(_game_id::text, 424242));
END $function$
