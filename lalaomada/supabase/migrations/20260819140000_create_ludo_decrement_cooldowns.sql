CREATE OR REPLACE FUNCTION public._ludo_decrement_cooldowns(st jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT CASE
    WHEN st ? 'cooldowns' AND jsonb_typeof(st->'cooldowns') = 'object'
    THEN (
      SELECT jsonb_set(st, '{cooldowns}', COALESCE(
        (
          SELECT jsonb_object_agg(key, GREATEST((value::int) - 1, 0))
          FROM jsonb_each(st->'cooldowns')
          WHERE (value::int) > 0
        ),
        '{}'::jsonb
      ))
    )
    ELSE st
  END
$function$;
