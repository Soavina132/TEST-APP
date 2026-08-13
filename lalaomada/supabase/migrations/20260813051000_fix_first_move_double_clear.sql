-- FIX: first_move_double was never cleared when the first player timed out
-- This caused the next player (bot or human) to be unable to play any tile
-- unless they happened to have the required double. Now it's cleared in
-- domino_auto_timeout and domino_advance_turn when the board is empty.

CREATE OR REPLACE FUNCTION public.domino_auto_timeout(_game_id uuid, _part record)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  _state jsonb; _ts jsonb; _count int; _key text;
BEGIN
  SELECT state, turn_skips INTO _state, _ts FROM public.domino_games WHERE id = _game_id;
  _key := COALESCE(_part.user_id::text, 'bot_'||_part.slot);
  _ts := jsonb_set(_ts, ARRAY[_key], to_jsonb((_ts->>_key)::int + 1));
  IF (_ts->>_key)::int >= 5 THEN PERFORM public.domino_forfeit_internal(_game_id, _part); RETURN; END IF;
  _state := _state || jsonb_build_object('passes', (_state->>'passes')::int + 1, 'last_pass_by', _part.slot);
  -- If the board is empty, the first player didn't play their required double.
  -- Clear first_move_double so the next player can play any tile.
  IF jsonb_array_length(COALESCE(_state->'board', '[]'::jsonb)) = 0 THEN
    _state := _state - 'first_move_double';
  END IF;
  SELECT count(*) INTO _count FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  IF (_state->>'passes')::int >= _count THEN PERFORM public.domino_end_round(_game_id, null, true);
  ELSE PERFORM public.domino_advance_turn(_game_id, _state, _ts); END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.domino_advance_turn(_game_id uuid, _state jsonb, _turn_skips jsonb DEFAULT '{}'::jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  _next int; _part record; _count int; _delay interval;
BEGIN
  -- Clear stale bot_think state
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

  UPDATE public.domino_games SET
    state = _state,
    current_turn = _next,
    turn_skips = CASE WHEN _turn_skips != '{}'::jsonb THEN _turn_skips ELSE turn_skips END,
    turn_deadline = now() + _delay,
    updated_at = now()
  WHERE id = _game_id;
END;
$function$;
