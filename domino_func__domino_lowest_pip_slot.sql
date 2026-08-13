CREATE OR REPLACE FUNCTION public._domino_lowest_pip_slot(_game_id uuid, _state jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE p record; cur_sum integer; best_sum integer := 2147483647; best_slot integer := NULL; tie_count integer := 0;
BEGIN
  FOR p IN SELECT slot FROM public.domino_participants WHERE game_id=_game_id AND forfeited=false ORDER BY slot LOOP
    cur_sum := public._domino_hand_pips(COALESCE(_state->'hands'->p.slot::text, '[]'::jsonb));
    IF cur_sum < best_sum THEN best_sum := cur_sum; best_slot := p.slot; tie_count := 1;
    ELSIF cur_sum = best_sum THEN tie_count := tie_count + 1; END IF;
  END LOOP;
  IF tie_count > 1 THEN RETURN NULL; END IF;
  RETURN best_slot;
END; $function$
