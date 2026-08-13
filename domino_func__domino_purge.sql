CREATE OR REPLACE FUNCTION public._domino_purge(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  DELETE FROM public.chat_rooms WHERE game_id = _game_id;
  DELETE FROM public.game_spectators WHERE game_id = _game_id;
  DELETE FROM public.game_invitations WHERE game_id = _game_id;
  DELETE FROM public.domino_participants WHERE game_id = _game_id;
  DELETE FROM public.domino_games WHERE id = _game_id;
END $function$
