
CREATE OR REPLACE FUNCTION public.fanorona_play(_game_id uuid, _move jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_uid uuid := auth.uid(); my_slot int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT slot INTO my_slot FROM public.fanorona_participants
    WHERE game_id = _game_id AND user_id = v_uid;
  IF my_slot IS NULL THEN RAISE EXCEPTION 'not a participant'; END IF;
  PERFORM public._fanorona_apply_move(_game_id, my_slot, _move);
  -- Auto-play bot(s) if it's their turn now
  PERFORM public.fanorona_bot_play(_game_id);
END $function$;

-- Also let the tick / global-timeout path drive bots forward
CREATE OR REPLACE FUNCTION public.fanorona_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
  PERFORM public.fanorona_check_global_timeout(_game_id);
  PERFORM public.fanorona_bot_play(_game_id);
END $function$;
