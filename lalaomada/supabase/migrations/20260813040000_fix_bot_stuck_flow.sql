-- ═══════════════════════════════════════════════════════════
-- FIX: Bot stuck — bot_think_until never cleared for human turns
-- ═══════════════════════════════════════════════════════════
-- Bug 1: domino_maybe_schedule_bot ne nettoyait pas bot_think_until
--         quand le prochain joueur était un humain → stale value persistait
-- Bug 2: domino_tick faisait RETURN prématurément quand bot_think_until
--         était périmé, empêchant le timer humain de fonctionner
-- Bug 3: domino_advance_turn ne nettoyait pas bot_think_until de l'état

-- 1. domino_maybe_schedule_bot: clear bot_think_until when next player is human
CREATE OR REPLACE FUNCTION public.domino_maybe_schedule_bot(_game_id uuid, _slot integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE _part record; _delay float;
BEGIN
  SELECT * INTO _part FROM public.domino_participants
  WHERE game_id = _game_id AND slot = _slot AND is_bot = true AND forfeited = false;
  IF NOT FOUND THEN
    UPDATE public.domino_games SET
      state = state - 'bot_think_until' - 'bot_locked_slot',
      updated_at = now()
    WHERE id = _game_id;
    RETURN;
  END IF;
  _delay := 1.5 + random() * 2.5;
  UPDATE public.domino_games SET
    state = state || jsonb_build_object('bot_think_until', to_char(now() + make_interval(secs => _delay), 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
    updated_at = now()
  WHERE id = _game_id;
END;
$function$;

-- 2. domino_tick: don't RETURN when bot_think_until is stale and player is human
CREATE OR REPLACE FUNCTION public.domino_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  _g record; _state jsonb; _phase text; _part record; _think text; _bu timestamp;
BEGIN
  SELECT * INTO _g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND OR _g.status != 'playing' THEN RETURN; END IF;
  _state := _g.state; _phase := _state->>'phase';

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

-- 3. domino_advance_turn: clean bot_think_until from state before writing
CREATE OR REPLACE FUNCTION public.domino_advance_turn(_game_id uuid, _state jsonb, _turn_skips jsonb DEFAULT '{}'::jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE _game record; _next int; _part record; _count int;
BEGIN
  _state := _state - 'bot_think_until' - 'bot_locked_slot';
  
  SELECT current_turn INTO _next FROM public.domino_games WHERE id = _game_id;
  SELECT count(*) INTO _count FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  LOOP
    _next := (_next + 1) % GREATEST(_count, 1);
    SELECT * INTO _part FROM public.domino_participants WHERE game_id = _game_id AND slot = _next AND forfeited = false;
    EXIT WHEN FOUND;
  END LOOP;
  UPDATE public.domino_games SET
    state = _state, current_turn = _next,
    turn_skips = CASE WHEN _turn_skips != '{}'::jsonb THEN _turn_skips ELSE turn_skips END,
    turn_deadline = now() + interval '30 seconds',
    updated_at = now()
  WHERE id = _game_id;
  PERFORM public.domino_maybe_schedule_bot(_game_id, _next);
END;
$function$;

-- 4. Clean up stuck games: clear stale bot_think_until
UPDATE public.domino_games
SET state = state - 'bot_think_until' - 'bot_locked_slot',
    updated_at = now()
WHERE status = 'playing' AND state ? 'bot_think_until';
