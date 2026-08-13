CREATE OR REPLACE FUNCTION public._domino_next_playable_slot(_game_id uuid, _from_slot integer, _state jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  slots integer[];
  total integer;
  start_idx integer := 1;
  step integer;
  idx integer;
  candidate integer;
  draw_mode text := COALESCE(_state->>'draw_mode', 'with');
  stock_len integer := jsonb_array_length(COALESCE(_state -> 'stock', '[]'::jsonb));
BEGIN
  SELECT array_agg(slot ORDER BY slot)
    INTO slots
    FROM public.domino_participants
   WHERE game_id = _game_id AND forfeited = false;

  total := COALESCE(array_length(slots, 1), 0);
  IF total = 0 THEN
    RETURN NULL;
  END IF;

  FOR idx IN 1..total LOOP
    IF slots[idx] = _from_slot THEN
      start_idx := idx;
      EXIT;
    END IF;
  END LOOP;

  FOR step IN 1..total LOOP
    idx := ((start_idx - 1 + step) % total) + 1;
    candidate := slots[idx];

    IF public._domino_slot_has_playable(_state, candidate)
       OR (draw_mode = 'with' AND stock_len > 0) THEN
      RETURN candidate;
    END IF;
  END LOOP;

  RETURN NULL;
END;
$function$
