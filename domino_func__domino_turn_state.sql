CREATE OR REPLACE FUNCTION public._domino_turn_state(_state jsonb, _turn_seconds integer)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'public'
AS $function$
  SELECT jsonb_set(
           jsonb_set(
             COALESCE(_state, '{}'::jsonb),
             '{turn_started_at}',
             to_jsonb(now()::text),
             true
           ),
           '{turn_duration_seconds}',
           to_jsonb(GREATEST(1, COALESCE(_turn_seconds, 60))),
           true
         );
$function$
