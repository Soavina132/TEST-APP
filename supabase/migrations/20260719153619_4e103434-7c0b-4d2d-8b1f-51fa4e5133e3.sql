
CREATE OR REPLACE FUNCTION public.chess_play(_id uuid, _uci text, _san text, _fen_after text, _elapsed_ms integer DEFAULT 0)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_g chess_games%ROWTYPE;
  v_new_turn text;
  v_my_color text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id=_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;

  IF v_g.white_id = v_uid THEN v_my_color := 'w';
  ELSIF v_g.black_id = v_uid THEN v_my_color := 'b';
  ELSE RAISE EXCEPTION 'not a participant'; END IF;

  IF v_g.turn <> v_my_color THEN RAISE EXCEPTION 'not your turn'; END IF;

  v_new_turn := CASE WHEN v_g.turn='w' THEN 'b' ELSE 'w' END;

  INSERT INTO chess_moves(game_id, ply, san, uci, fen_after, by_user)
    VALUES (_id, v_g.ply+1, _san, _uci, _fen_after, v_uid);

  UPDATE chess_games SET
    fen = _fen_after,
    turn = v_new_turn,
    ply = v_g.ply + 1,
    last_move_at = now(),
    white_time_ms = CASE WHEN v_my_color='w' THEN greatest(0, white_time_ms - coalesce(_elapsed_ms,0)) ELSE white_time_ms END,
    black_time_ms = CASE WHEN v_my_color='b' THEN greatest(0, black_time_ms - coalesce(_elapsed_ms,0)) ELSE black_time_ms END,
    draw_offered_by = CASE WHEN draw_offered_by IS NOT NULL AND draw_offered_by = v_uid THEN NULL ELSE draw_offered_by END
  WHERE id=_id;
END $function$;

CREATE OR REPLACE FUNCTION public.chess_bot_play(_id uuid, _uci text, _san text, _fen_after text, _elapsed_ms integer DEFAULT 0)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_g chess_games%ROWTYPE;
  v_bot uuid;
  v_bot_color text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id=_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.mode <> 'solo' THEN RAISE EXCEPTION 'not a solo game'; END IF;
  IF v_g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;

  IF v_g.white_id = v_uid AND v_g.black_is_bot THEN v_bot := v_g.black_id; v_bot_color := 'b';
  ELSIF v_g.black_id = v_uid AND v_g.white_is_bot THEN v_bot := v_g.white_id; v_bot_color := 'w';
  ELSE RAISE EXCEPTION 'not a solo-bot game'; END IF;

  IF v_g.turn <> v_bot_color THEN RAISE EXCEPTION 'not bot turn'; END IF;

  INSERT INTO chess_moves(game_id, ply, san, uci, fen_after, by_user)
    VALUES (_id, v_g.ply+1, _san, _uci, _fen_after, v_bot);

  UPDATE chess_games SET
    fen = _fen_after,
    turn = CASE WHEN v_g.turn='w' THEN 'b' ELSE 'w' END,
    ply = v_g.ply + 1,
    last_move_at = now(),
    white_time_ms = CASE WHEN v_bot_color='w' THEN greatest(0, white_time_ms - coalesce(_elapsed_ms,0)) ELSE white_time_ms END,
    black_time_ms = CASE WHEN v_bot_color='b' THEN greatest(0, black_time_ms - coalesce(_elapsed_ms,0)) ELSE black_time_ms END
  WHERE id=_id;
END $function$;

CREATE OR REPLACE FUNCTION public.chess_tick(_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_g chess_games%ROWTYPE;
  v_elapsed_ms int;
  v_remaining int;
  v_loser uuid;
  v_winner uuid;
BEGIN
  SELECT * INTO v_g FROM chess_games WHERE id=_id FOR UPDATE;
  IF NOT FOUND OR v_g.status <> 'playing' THEN RETURN; END IF;
  v_elapsed_ms := greatest(0, floor(extract(epoch FROM (now() - coalesce(v_g.last_move_at, v_g.started_at, now())))*1000)::int);
  IF v_g.turn = 'w' THEN
    v_remaining := v_g.white_time_ms - v_elapsed_ms;
    v_loser := v_g.white_id; v_winner := v_g.black_id;
  ELSE
    v_remaining := v_g.black_time_ms - v_elapsed_ms;
    v_loser := v_g.black_id; v_winner := v_g.white_id;
  END IF;
  IF v_remaining <= 0 THEN
    PERFORM public._chess_settle(_id, v_winner, false, 'timeout');
  END IF;
END $function$;
