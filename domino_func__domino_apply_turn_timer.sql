CREATE OR REPLACE FUNCTION public._domino_apply_turn_timer()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  seconds_left integer;
BEGIN
  IF NEW.turn_deadline IS NULL THEN
    NEW.state := COALESCE(NEW.state, '{}'::jsonb) - 'turn_started_at' - 'turn_duration_seconds';
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' OR OLD.turn_deadline IS DISTINCT FROM NEW.turn_deadline THEN
    seconds_left := GREATEST(1, CEIL(EXTRACT(EPOCH FROM (NEW.turn_deadline - now())))::integer);
    NEW.state := jsonb_set(COALESCE(NEW.state, '{}'::jsonb), '{turn_started_at}', to_jsonb(now()::text), true);
    NEW.state := jsonb_set(NEW.state, '{turn_duration_seconds}', to_jsonb(seconds_left), true);
  END IF;
  RETURN NEW;
END;
$function$
