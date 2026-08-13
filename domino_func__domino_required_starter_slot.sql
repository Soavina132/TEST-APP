CREATE OR REPLACE FUNCTION public._domino_required_starter_slot(_game_id uuid, _state jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  first_dbl integer;
  p record;
  t jsonb;
BEGIN
  IF jsonb_array_length(COALESCE(_state->'board', '[]'::jsonb)) > 0 THEN
    RETURN NULL;
  END IF;

  first_dbl := NULLIF(_state->>'first_move_double', 'null')::integer;
  IF first_dbl IS NULL THEN
    RETURN NULL;
  END IF;

  FOR p IN
    SELECT slot
    FROM public.domino_participants
    WHERE game_id = _game_id
      AND forfeited = false
    ORDER BY slot
  LOOP
    FOR t IN SELECT * FROM jsonb_array_elements(COALESCE(_state->'hands'->p.slot::text, '[]'::jsonb)) LOOP
      IF (t->>0)::integer = first_dbl AND (t->>1)::integer = first_dbl THEN
        RETURN p.slot;
      END IF;
    END LOOP;
  END LOOP;

  RETURN NULL;
END;
$function$
