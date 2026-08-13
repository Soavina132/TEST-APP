-- FIX: _domino_arm_bot_think stored bot_think_until in PostgreSQL text format
-- (e.g. "2026-08-13 00:28:44+00") but domino_tick parsed it as ISO 8601
-- (e.g. "2026-08-13T00:28:44Z"). The mismatch caused to_timestamp to return
-- NULL, so the bot never played at game start.

CREATE OR REPLACE FUNCTION public._domino_arm_bot_think(_game_id uuid, _slot integer, _state jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_is_bot boolean := false;
  v_delay_ms int;
BEGIN
  SELECT COALESCE(dp.is_bot, false) INTO v_is_bot
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id AND dp.slot = _slot AND dp.forfeited = false;

  IF v_is_bot THEN
    v_delay_ms := 3000 + (floor(random() * 2000))::int;
    _state := jsonb_set(_state, '{bot_locked_slot}', to_jsonb(_slot), true);
    -- Use ISO 8601 format (same as domino_maybe_schedule_bot) for consistency
    _state := jsonb_set(_state, '{bot_think_until}',
             to_jsonb(to_char(now() + make_interval(secs => v_delay_ms / 1000.0), 'YYYY-MM-DD"T"HH24:MI:SS"Z"')), true);
  ELSE
    _state := _state - 'bot_think_until' - 'bot_locked_slot';
  END IF;

  RETURN _state;
END;
$function$;
