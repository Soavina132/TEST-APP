-- Fix: ludo_set_auto_move was setting state JSON key instead of the auto_move column
-- This meant _ludo_auto_move (which checks g.auto_move) never fired
CREATE OR REPLACE FUNCTION public.ludo_set_auto_move(_game_id uuid, _enabled boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $func$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  UPDATE ludo_games SET auto_move = _enabled WHERE id = _game_id;
END $func$;
