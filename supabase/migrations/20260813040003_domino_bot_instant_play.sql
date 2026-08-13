CREATE OR REPLACE FUNCTION public.domino_advance_turn(_game_id uuid, _state jsonb, _turn_skips jsonb DEFAULT '{}'::jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  _next int; _part record; _count int; _delay interval;
  _is_bot boolean := false;
BEGIN
  -- Clear stale bot state
  _state := _state - 'bot_think_until' - 'bot_locked_slot';

  -- If the board is empty, clear first_move_double so next player can play freely
  IF jsonb_array_length(COALESCE(_state->'board', '[]'::jsonb)) = 0 THEN
    _state := _state - 'first_move_double';
  END IF;

  SELECT current_turn INTO _next FROM public.domino_games WHERE id = _game_id;
  SELECT count(*) INTO _count FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  LOOP
    _next := (_next + 1) % GREATEST(_count, 1);
    SELECT * INTO _part FROM public.domino_participants WHERE game_id = _game_id AND slot = _next AND forfeited = false;
    EXIT WHEN FOUND;
  END LOOP;

  _delay := public._domino_turn_delay(_game_id, _next);
  _is_bot := COALESCE(_part.is_bot, false);

  UPDATE public.domino_games SET
    state = _state,
    current_turn = _next,
    turn_skips = CASE WHEN _turn_skips != '{}'::jsonb THEN _turn_skips ELSE turn_skips END,
    turn_deadline = now() + _delay,
    updated_at = now()
  WHERE id = _game_id;

  -- Bot plays immediately from the backend — no need to wait for frontend tick
  IF _is_bot THEN
    -- Small sleep so the UI can show the bot's turn briefly before it acts
    PERFORM pg_sleep(1 + random());
    PERFORM public.domino_bot_play(_game_id, _part);
  END IF;
END;
$function$;
