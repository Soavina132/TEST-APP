CREATE OR REPLACE FUNCTION public._domino_slot_has_playable(_state jsonb, _slot integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  hand jsonb := COALESCE(_state -> 'hands' -> _slot::text, '[]'::jsonb);
  board_len integer := jsonb_array_length(COALESCE(_state -> 'board', '[]'::jsonb));
  first_dbl integer;
  first_rule text;
  le integer;
  re integer;
  t jsonb;
  a integer;
  b integer;
BEGIN
  IF jsonb_array_length(hand) = 0 THEN
    RETURN false;
  END IF;

  IF board_len = 0 THEN
    first_dbl := NULLIF(_state->>'first_move_double', 'null')::integer;
    first_rule := COALESCE(_state->>'first_tile_rule', 'libre');

    IF first_dbl IS NOT NULL THEN
      FOR t IN SELECT * FROM jsonb_array_elements(hand) LOOP
        a := (t->>0)::integer; b := (t->>1)::integer;
        IF a = first_dbl AND b = first_dbl THEN RETURN true; END IF;
      END LOOP;
      RETURN false;
    END IF;

    IF first_rule = 'under6' THEN
      FOR t IN SELECT * FROM jsonb_array_elements(hand) LOOP
        a := (t->>0)::integer; b := (t->>1)::integer;
        IF (a + b) < 6 THEN RETURN true; END IF;
      END LOOP;
      RETURN false;
    END IF;

    RETURN true;
  END IF;

  le := NULLIF(_state->>'left_end', 'null')::integer;
  re := NULLIF(_state->>'right_end', 'null')::integer;

  FOR t IN SELECT * FROM jsonb_array_elements(hand) LOOP
    a := (t->>0)::integer;
    b := (t->>1)::integer;
    IF a = le OR b = le OR a = re OR b = re THEN RETURN true; END IF;
  END LOOP;

  RETURN false;
END;
$function$
