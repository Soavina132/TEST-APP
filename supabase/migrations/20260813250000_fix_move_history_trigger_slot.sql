-- Fix trigger: use OLD turn_slot (the acting slot) instead of NEW (the next slot)
CREATE OR REPLACE FUNCTION public._ludo_log_state_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_old_event TEXT;
  v_new_event TEXT;
  v_acting_slot INT;
  v_dice INT;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.status = 'playing' THEN
    v_old_event := COALESCE(OLD.state->>'last_event', '');
    v_new_event := COALESCE(NEW.state->>'last_event', '');
    
    IF v_new_event = v_old_event OR v_new_event = 'init' OR v_new_event IS NULL THEN
      RETURN NEW;
    END IF;
    
    -- Use OLD turn_slot (the slot that performed the action)
    v_acting_slot := COALESCE((OLD.state->>'turn_slot')::int, 0);
    v_dice := NULLIF(NEW.state->>'dice', '')::int;
    -- For roll events, extract dice from the event string "roll:N"
    IF v_new_event LIKE 'roll:%' THEN
      v_dice := NULLIF(split_part(v_new_event, ':', 2), '')::int;
      -- Handle "roll:N:no_move" format
      v_dice := NULLIF(split_part(v_dice::text, ':', 1), '')::int;
    END IF;
    
    INSERT INTO public.ludo_move_history(game_id, slot, action, dice, from_state, to_state)
    VALUES (
      NEW.id,
      v_acting_slot,
      v_new_event,
      v_dice,
      OLD.state,
      NEW.state
    );
  END IF;
  
  RETURN NEW;
END;
$function$;
