CREATE OR REPLACE FUNCTION public._domino_arm_bot_think(_game_id uuid, _slot integer, _state jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_isbot boolean;
  v_state jsonb := COALESCE(_state, '{}'::jsonb);
BEGIN
  SELECT is_bot INTO v_isbot
    FROM public.domino_participants
   WHERE game_id = _game_id AND slot = _slot AND forfeited = false;

  IF NOT COALESCE(v_isbot, false) THEN
    RETURN (v_state - 'bot_think_until') - 'bot_locked_slot';
  END IF;

  -- Fenêtre de réflexion max 2s (auparavant 5s).
  v_state := jsonb_set(v_state - 'bot_think_until' - 'bot_locked_slot', '{bot_locked_slot}', to_jsonb(_slot), true);
  v_state := jsonb_set(v_state, '{bot_think_until}', to_jsonb((now() + interval '2 seconds')::text), true);
  RETURN v_state;
END;
$function$
