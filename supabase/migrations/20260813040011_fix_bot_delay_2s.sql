CREATE OR REPLACE FUNCTION public._domino_turn_delay(_game_id uuid, _slot integer)
RETURNS interval
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_is_bot boolean := false;
  v_cfg record;
BEGIN
  SELECT COALESCE(dp.is_bot, false) INTO v_is_bot
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id AND dp.slot = _slot AND dp.forfeited = false;
  IF v_is_bot THEN
    RETURN make_interval(secs => 2);
  ELSE
    SELECT * INTO v_cfg FROM public._game_cfg('domino');
    RETURN (COALESCE(v_cfg.turn_timer_seconds, 30) || ' seconds')::interval;
  END IF;
END;
$function$;
