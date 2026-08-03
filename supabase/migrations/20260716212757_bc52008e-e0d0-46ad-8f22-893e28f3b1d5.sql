CREATE OR REPLACE FUNCTION public._ludo_next_slot(_game_id UUID, _from INT, _max INT)
RETURNS INT
LANGUAGE plpgsql STABLE
SET search_path = public
AS $$
DECLARE
  v_cur_start INT;
  v_next_slot INT;
BEGIN
  SELECT public._ludo_start_idx(
    CASE color WHEN 'red' THEN 0 WHEN 'green' THEN 1 WHEN 'yellow' THEN 2 WHEN 'blue' THEN 3 END
  )
  INTO v_cur_start
  FROM public.ludo_participants
  WHERE game_id = _game_id AND slot = _from;

  IF v_cur_start IS NULL THEN v_cur_start := 0; END IF;

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