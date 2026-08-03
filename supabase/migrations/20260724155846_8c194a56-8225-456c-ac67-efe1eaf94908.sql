CREATE OR REPLACE FUNCTION public.domino_play(_game_id uuid, _move jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_slot integer;
  v_turn_secs integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'auth required';
  END IF;

  SELECT slot INTO v_slot
    FROM public.domino_participants
   WHERE game_id = _game_id
     AND user_id = v_uid
     AND COALESCE(forfeited, false) = false;

  IF v_slot IS NULL THEN
    RAISE EXCEPTION 'not a player';
  END IF;

  PERFORM public._domino_play_as(_game_id, v_slot, _move);

  IF COALESCE(_move->>'action', '') = 'draw' THEN
    SELECT COALESCE(turn_timer_seconds, 30) INTO v_turn_secs
      FROM public.game_configs
     WHERE slug = 'domino';

    UPDATE public.domino_games
       SET turn_deadline = now() + (COALESCE(v_turn_secs, 30) || ' seconds')::interval
     WHERE id = _game_id
       AND status = 'playing'
       AND current_turn = v_slot;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.domino_play(uuid, jsonb) TO authenticated;