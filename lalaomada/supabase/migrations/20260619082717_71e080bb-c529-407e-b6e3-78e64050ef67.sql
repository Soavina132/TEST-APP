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
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  UPDATE public.domino_participants
     SET ready = _ready
   WHERE game_id = _game_id AND user_id = v_uid;

  SELECT status::text, max_players INTO v_status, v_max FROM public.domino_games WHERE id = _game_id;
  IF v_status <> 'open' THEN RETURN; END IF;

  SELECT count(*) INTO v_count FROM public.domino_participants WHERE game_id = _game_id;
  SELECT count(*) INTO v_ready_count FROM public.domino_participants WHERE game_id = _game_id AND ready = true;

  IF v_count = v_max AND v_ready_count = v_max THEN
    PERFORM public._domino_start(_game_id);
  END IF;
END;
$$;