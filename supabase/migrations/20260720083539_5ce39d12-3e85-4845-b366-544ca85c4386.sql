CREATE OR REPLACE FUNCTION public.chess_tick(_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_g chess_games%ROWTYPE;
  v_elapsed_ms int;
  v_remaining int;
  v_winner uuid;
BEGIN
  SELECT * INTO v_g FROM chess_games WHERE id=_id FOR UPDATE;
  IF NOT FOUND OR v_g.status <> 'playing' THEN RETURN; END IF;
  IF coalesce(v_g.paused, false) THEN RETURN; END IF;
  v_elapsed_ms := greatest(0, floor(extract(epoch FROM (now() - coalesce(v_g.last_move_at, v_g.started_at, now())))*1000)::int);
  IF v_g.turn = 'w' THEN
    v_remaining := v_g.white_time_ms - v_elapsed_ms;
    v_winner := v_g.black_id;
  ELSE
    v_remaining := v_g.black_time_ms - v_elapsed_ms;
    v_winner := v_g.white_id;
  END IF;
  IF v_remaining <= 0 THEN
    PERFORM public._chess_settle(_id, v_winner, false, 'timeout');
  END IF;
END $function$;