CREATE OR REPLACE FUNCTION public._domino_normalize_board(_board jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  chain jsonb := '[]'::jsonb;
  entry jsonb;
  tile jsonb;
  placed jsonb;
  a int;
  b int;
  le int;
  re int;
  i int := 0;
BEGIN
  IF _board IS NULL OR jsonb_typeof(_board) <> 'array' OR jsonb_array_length(_board) = 0 THEN
    RETURN jsonb_build_object('board', '[]'::jsonb, 'left_end', NULL, 'right_end', NULL);
  END IF;

  FOR entry IN SELECT value FROM jsonb_array_elements(_board) AS value LOOP
    tile := CASE
      WHEN jsonb_typeof(entry) = 'array' THEN entry
      ELSE entry->'tile'
    END;

    IF tile IS NULL OR jsonb_typeof(tile) <> 'array' OR jsonb_array_length(tile) <> 2 THEN
      CONTINUE;
    END IF;

    a := (tile->>0)::int;
    b := (tile->>1)::int;

    IF i = 0 THEN
      chain := jsonb_build_array(jsonb_build_object('tile', jsonb_build_array(a, b), 'flipped', false));
      le := a;
      re := b;
    ELSE
      IF a = re THEN
        placed := jsonb_build_object('tile', jsonb_build_array(a, b), 'flipped', false);
        chain := chain || jsonb_build_array(placed);
        re := b;
      ELSIF b = re THEN
        placed := jsonb_build_object('tile', jsonb_build_array(b, a), 'flipped', false);
        chain := chain || jsonb_build_array(placed);
        re := a;
      ELSIF b = le THEN
        placed := jsonb_build_object('tile', jsonb_build_array(a, b), 'flipped', false);
        chain := jsonb_build_array(placed) || chain;
        le := a;
      ELSIF a = le THEN
        placed := jsonb_build_object('tile', jsonb_build_array(b, a), 'flipped', false);
        chain := jsonb_build_array(placed) || chain;
        le := b;
      ELSE
        -- Keep malformed legacy entries visible without changing endpoints.
        chain := chain || jsonb_build_array(jsonb_build_object('tile', jsonb_build_array(a, b), 'flipped', false));
      END IF;
    END IF;

    i := i + 1;
  END LOOP;

  IF jsonb_array_length(chain) = 0 THEN
    RETURN jsonb_build_object('board', '[]'::jsonb, 'left_end', NULL, 'right_end', NULL);
  END IF;

  RETURN jsonb_build_object('board', chain, 'left_end', le, 'right_end', re);
END;
$function$
