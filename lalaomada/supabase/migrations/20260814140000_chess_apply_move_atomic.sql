-- Function to atomically insert a move and update the game
-- Prevents duplicate key race condition by using FOR UPDATE lock
CREATE OR REPLACE FUNCTION public._chess_apply_move(
  _game_id uuid,
  _fen_after text,
  _turn text,
  _san text,
  _uci text,
  _by_user uuid,
  _elapsed_ms int DEFAULT 0,
  _mover_color text DEFAULT 'w',
  _clear_draw_offer uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $body$
DECLARE
  g record;
  new_ply int;
BEGIN
  -- Lock the game row to prevent concurrent moves
  SELECT * INTO g FROM chess_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL THEN RAISE EXCEPTION 'game not found'; END IF;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;

  new_ply := g.ply + 1;

  -- Insert the move atomically
  INSERT INTO chess_moves (game_id, ply, san, uci, fen_after, by_user)
  VALUES (_game_id, new_ply, _san, _uci, _fen_after, _by_user);

  -- Update the game
  UPDATE chess_games SET
    fen = _fen_after,
    turn = _turn,
    ply = new_ply,
    last_move_at = now(),
    white_time_ms = CASE WHEN _mover_color = 'w' THEN GREATEST(0, g.white_time_ms - _elapsed_ms) ELSE g.white_time_ms END,
    black_time_ms = CASE WHEN _mover_color = 'b' THEN GREATEST(0, g.black_time_ms - _elapsed_ms) ELSE g.black_time_ms END,
    draw_offered_by = CASE WHEN _clear_draw_offer IS NOT NULL AND _clear_draw_offer = g.draw_offered_by THEN NULL ELSE g.draw_offered_by END
  WHERE id = _game_id;

  RETURN jsonb_build_object('ply', new_ply);
END;
$body$;

-- Revoke execute from anon/authenticated (only service role can call)
REVOKE EXECUTE ON FUNCTION public._chess_apply_move(uuid, text, text, text, text, uuid, int, text, uuid) FROM anon, authenticated;
