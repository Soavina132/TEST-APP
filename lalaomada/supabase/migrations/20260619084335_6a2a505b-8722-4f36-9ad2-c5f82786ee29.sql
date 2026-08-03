CREATE OR REPLACE FUNCTION public.rami_set_ready(_game_id uuid, _ready boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_g public.rami_games;
  v_total int;
  v_ready int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;

  SELECT * INTO v_g FROM public.rami_games WHERE id = _game_id FOR UPDATE;
  IF v_g.id IS NULL THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status <> 'waiting' THEN RETURN; END IF;

  UPDATE public.rami_participants
     SET ready = COALESCE(_ready, false)
   WHERE game_id = _game_id AND user_id = v_uid;

  IF NOT FOUND THEN RAISE EXCEPTION 'not a participant'; END IF;

  SELECT count(*), count(*) FILTER (WHERE ready)
    INTO v_total, v_ready
    FROM public.rami_participants
   WHERE game_id = _game_id;

  IF v_total = v_g.max_players AND v_ready = v_total THEN
    PERFORM public.rami_start(_game_id);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.fanorona_set_ready(_game_id uuid, _ready boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_total int;
  v_ready int;
  v_status text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;

  SELECT status::text INTO v_status FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF v_status IS NULL THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_status <> 'open' THEN RETURN; END IF;

  UPDATE public.fanorona_participants
     SET ready = COALESCE(_ready, false)
   WHERE game_id = _game_id AND user_id = v_uid;

  IF NOT FOUND THEN RAISE EXCEPTION 'not a participant'; END IF;

  SELECT count(*), count(*) FILTER (WHERE ready)
    INTO v_total, v_ready
    FROM public.fanorona_participants
   WHERE game_id = _game_id;

  IF v_total = 2 AND v_ready = 2 THEN
    UPDATE public.fanorona_games
       SET status = 'playing',
           started_at = now(),
           state = jsonb_set(state, '{phase}', '"playing"'::jsonb),
           current_turn = 0
     WHERE id = _game_id AND status = 'open';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.chess_set_ready(_game_id uuid, _ready boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_g public.chess_games%ROWTYPE;
  _cfg record;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;

  SELECT * INTO v_g FROM public.chess_games WHERE id = _game_id FOR UPDATE;
  IF v_g.id IS NULL THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status <> 'open' THEN RETURN; END IF;

  IF v_uid = v_g.white_id THEN
    UPDATE public.chess_games SET ready_white = COALESCE(_ready, false) WHERE id = _game_id;
  ELSIF v_uid = v_g.black_id THEN
    UPDATE public.chess_games SET ready_black = COALESCE(_ready, false) WHERE id = _game_id;
  ELSE
    RAISE EXCEPTION 'not a player';
  END IF;

  SELECT * INTO v_g FROM public.chess_games WHERE id = _game_id;
  IF v_g.white_id IS NOT NULL AND v_g.black_id IS NOT NULL AND v_g.ready_white AND v_g.ready_black THEN
    SELECT * INTO _cfg FROM public._game_cfg('chess');
    UPDATE public.chess_games
       SET status = 'playing',
           started_at = now(),
           turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval
     WHERE id = _game_id AND status = 'open';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rami_set_ready(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fanorona_set_ready(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chess_set_ready(uuid, boolean) TO authenticated;