-- FIX: domino_tick didn't handle the 'dealing' phase
-- When a game starts, _domino_start sets phase='dealing' with deal_until
-- But domino_tick returned early for any phase != 'playing' or 'break'
-- Result: the game was stuck in 'dealing' and the bot could never play
-- Now domino_tick transitions from 'dealing' to 'playing' via _domino_place_first

CREATE OR REPLACE FUNCTION public.domino_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  _g record; _state jsonb; _phase text; _part record; _think text; _bu timestamptz;
BEGIN
  SELECT * INTO _g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND OR _g.status != 'playing' THEN RETURN; END IF;
  _state := _g.state; _phase := _state->>'phase';

  -- Handle dealing phase: transition to playing after deal_until
  IF _phase = 'dealing' THEN
    _bu := (_state->>'deal_until')::timestamptz;
    IF now() >= _bu THEN
      PERFORM public._domino_place_first(_game_id);
    END IF;
    RETURN;
  END IF;

  IF _phase = 'break' THEN
    _bu := to_timestamp(_state->>'break_until', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
    IF now() >= _bu THEN PERFORM public.domino_start_new_round(_game_id); END IF;
    RETURN;
  END IF;
  IF _phase != 'playing' THEN RETURN; END IF;

  _think := _state->>'bot_think_until';
  IF _think IS NOT NULL THEN
    IF now() >= to_timestamp(_think, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') THEN
      SELECT * INTO _part FROM public.domino_participants 
        WHERE game_id = _game_id AND slot = _g.current_turn AND is_bot = true AND forfeited = false;
      IF FOUND THEN
        PERFORM public.domino_bot_play(_game_id, _part);
        RETURN;
      END IF;
      UPDATE public.domino_games SET
        state = state - 'bot_think_until' - 'bot_locked_slot',
        updated_at = now()
      WHERE id = _game_id;
    ELSE
      RETURN;
    END IF;
  END IF;

  IF _g.turn_deadline IS NOT NULL AND now() >= _g.turn_deadline THEN
    SELECT * INTO _part FROM public.domino_participants 
      WHERE game_id = _game_id AND slot = _g.current_turn AND forfeited = false;
    IF FOUND THEN
      IF _part.is_bot THEN PERFORM public.domino_bot_play(_game_id, _part);
      ELSE PERFORM public.domino_auto_timeout(_game_id, _part); END IF;
    END IF;
  END IF;
END;
$function$;
