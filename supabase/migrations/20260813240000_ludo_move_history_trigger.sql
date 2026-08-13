-- Migration: Trigger pour log automatique des moves dans ludo_move_history
-- Au lieu de modifier chaque fonction RPC, on utilise un trigger sur ludo_games

CREATE OR REPLACE FUNCTION public._ludo_log_state_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_old_event TEXT;
  v_new_event TEXT;
  v_slot INT;
  v_dice INT;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.status = 'playing' THEN
    v_old_event := COALESCE(OLD.state->>'last_event', '');
    v_new_event := COALESCE(NEW.state->>'last_event', '');
    
    -- Only log if the event changed (skip redundant updates)
    IF v_new_event = v_old_event OR v_new_event = 'init' OR v_new_event IS NULL THEN
      RETURN NEW;
    END IF;
    
    v_slot := COALESCE((NEW.state->>'turn_slot')::int, 0);
    v_dice := NULLIF(NEW.state->>'dice', '')::int;
    
    INSERT INTO public.ludo_move_history(game_id, slot, action, dice, from_state, to_state)
    VALUES (
      NEW.id,
      v_slot,
      v_new_event,
      v_dice,
      OLD.state,
      NEW.state
    );
  END IF;
  
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_ludo_move_history ON public.ludo_games;
CREATE TRIGGER trg_ludo_move_history
  AFTER UPDATE ON public.ludo_games
  FOR EACH ROW
  EXECUTE FUNCTION public._ludo_log_state_change();
