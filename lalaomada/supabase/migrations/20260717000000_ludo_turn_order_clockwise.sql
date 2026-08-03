-- Fix ludo turn order to follow the visual clockwise sequence
-- based on color start index (red=0 → green=13 → yellow=26 → blue=39),
-- i.e. visually: Vert (TL) → Jaune (TR) → Bleu (BR) → Rouge (BL).
-- This is independent of the slot number assigned to each color.

CREATE OR REPLACE FUNCTION public._ludo_next_slot(_game_id UUID, _from INT, _max INT)
RETURNS INT
LANGUAGE plpgsql STABLE
SET search_path = public
AS $$
DECLARE
  v_cur_start INT;
  v_next_slot INT;
BEGIN
  -- start_idx of the current player's color
  SELECT public._ludo_start_idx(
    CASE color WHEN 'red' THEN 0 WHEN 'green' THEN 1 WHEN 'yellow' THEN 2 WHEN 'blue' THEN 3 END
  )
  INTO v_cur_start
  FROM public.ludo_participants
  WHERE game_id = _game_id AND slot = _from;

  IF v_cur_start IS NULL THEN v_cur_start := 0; END IF;

  -- Next non-forfeited participant with a strictly greater start_idx (clockwise)
  SELECT slot INTO v_next_slot
  FROM public.ludo_participants
  WHERE game_id = _game_id
    AND forfeited = FALSE
    AND public._ludo_start_idx(
      CASE color WHEN 'red' THEN 0 WHEN 'green' THEN 1 WHEN 'yellow' THEN 2 WHEN 'blue' THEN 3 END
    ) > v_cur_start
  ORDER BY public._ludo_start_idx(
    CASE color WHEN 'red' THEN 0 WHEN 'green' THEN 1 WHEN 'yellow' THEN 2 WHEN 'blue' THEN 3 END
  ) ASC
  LIMIT 1;

  -- Wrap around: pick the smallest start_idx among remaining
  IF v_next_slot IS NULL THEN
    SELECT slot INTO v_next_slot
    FROM public.ludo_participants
    WHERE game_id = _game_id
      AND forfeited = FALSE
    ORDER BY public._ludo_start_idx(
      CASE color WHEN 'red' THEN 0 WHEN 'green' THEN 1 WHEN 'yellow' THEN 2 WHEN 'blue' THEN 3 END
    ) ASC
    LIMIT 1;
  END IF;

  RETURN COALESCE(v_next_slot, _from);
END $$;
