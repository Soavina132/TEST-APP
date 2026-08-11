-- Fix: _domino_notify_all function was missing, causing bot games to freeze
-- when the bot had no playable tile. The error was silently swallowed by
-- domino_tick_all's EXCEPTION handler.

CREATE OR REPLACE FUNCTION public._domino_notify_all(
  _game_id uuid,
  _slot integer,
  _kind text,
  _title text,
  _body text,
  _payload jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid;
BEGIN
  -- Notify all human participants of a domino game event (bot pass, etc.)
  FOR v_uid IN
    SELECT user_id FROM public.domino_participants
     WHERE game_id = _game_id
       AND user_id IS NOT NULL
       AND forfeited = false
  LOOP
    INSERT INTO public.notifications(user_id, kind, title, body, link, ref_id)
    VALUES (v_uid, _kind, _title, _body, '/jeux/domino/' || _game_id::text, _game_id);
  END LOOP;
END;
$function$;
