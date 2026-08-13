CREATE OR REPLACE FUNCTION public._domino_playable_tiles(_state jsonb, _slot integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  hand jsonb;
  board jsonb;
  left_end INT;
  right_end INT;
  i INT;
  tile jsonb;
  a INT; b INT;
  result jsonb := '[]'::jsonb;
  first_move_double INT;
  first_tile_rule TEXT;
  board_len INT;
BEGIN
  hand := _state->'hands'->_slot::text;
  board := _state->'board';
  IF hand IS NULL THEN RETURN '[]'::jsonb; END IF;

  board_len := COALESCE(jsonb_array_length(board), 0);
  left_end := NULLIF(_state->>'left_end','')::INT;
  right_end := NULLIF(_state->>'right_end','')::INT;
  first_move_double := NULLIF(_state->>'first_move_double','')::INT;
  first_tile_rule := COALESCE(_state->>'first_tile_rule', 'libre');

  FOR i IN 0..jsonb_array_length(hand)-1 LOOP
    tile := hand->i;
    a := (tile->>0)::INT;
    b := (tile->>1)::INT;

    IF board_len = 0 THEN
      -- First tile rules
      IF first_move_double IS NOT NULL THEN
        IF a = first_move_double AND b = first_move_double THEN
          result := result || to_jsonb(i);
        END IF;
      ELSIF first_tile_rule = 'under6' THEN
        IF a + b < 6 THEN result := result || to_jsonb(i); END IF;
      ELSE
        result := result || to_jsonb(i);
      END IF;
    ELSE
      IF a = left_end OR b = left_end OR a = right_end OR b = right_end THEN
        result := result || to_jsonb(i);
      END IF;
    END IF;
  END LOOP;

  RETURN result;
END $function$
