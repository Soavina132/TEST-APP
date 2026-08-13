CREATE OR REPLACE FUNCTION public._domino_start(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
  UPDATE public.domino_games
     SET status = 'playing',
         started_at = COALESCE(started_at, now()),
         turn_skips = '{}'::jsonb,
         scores = COALESCE(scores, '{}'::jsonb)
   WHERE id = _game_id
     AND status = 'open';

  IF NOT FOUND THEN RETURN; END IF;

  PERFORM public._domino_next_round(_game_id);
END;
$function$
