CREATE OR REPLACE FUNCTION public.domino_set_ready(_game_id uuid, _ready boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_status text;
  v_count int;
  v_max int;
  v_ready_count int;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  UPDATE public.domino_participants
     SET ready = COALESCE(_ready, false)
   WHERE game_id = _game_id AND user_id = v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not a participant';
  END IF;

  SELECT status::text, max_players
    INTO v_status, v_max
    FROM public.domino_games
   WHERE id = _game_id
   FOR UPDATE;

  IF v_status <> 'open' THEN
    RETURN;
  END IF;

  SELECT count(*), count(*) FILTER (WHERE ready)
    INTO v_count, v_ready_count
    FROM public.domino_participants
   WHERE game_id = _game_id;

  IF v_count = v_max AND v_ready_count = v_max THEN
    PERFORM public._domino_start(_game_id);
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.domino_set_ready(uuid, boolean) TO authenticated;