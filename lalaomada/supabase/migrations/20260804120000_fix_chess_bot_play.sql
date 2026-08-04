-- ============================================================
-- Migration: Fix chess_bot_play — critical bugs
--
-- Bugs fixed:
-- 1. Status check was 'active' instead of 'playing' → bots could NEVER play
-- 2. Tried to insert into non-existent columns (elapsed_ms, by_bot)
-- 3. Bot identification used pseudo LIKE 'Bot%' instead of white_is_bot/black_is_bot
-- 4. Didn't update ply, turn_deadline, white_time_ms/black_time_ms, draw_offered_by
-- ============================================================

CREATE OR REPLACE FUNCTION public.chess_bot_play(
  _id uuid,
  _uci text,
  _san text,
  _fen_after text,
  _elapsed_ms int DEFAULT 0
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_g record;
  v_bot_id uuid;
  v_new_ply int;
BEGIN
  SELECT * INTO v_g FROM chess_games WHERE id = _id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game not found'; END IF;
  
  -- FIX: was 'active', should be 'playing'
  IF v_g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  
  -- FIX: use white_is_bot/black_is_bot flags instead of pseudo LIKE 'Bot%'
  IF v_g.white_is_bot THEN
    v_bot_id := v_g.white_id;
  ELSIF v_g.black_is_bot THEN
    v_bot_id := v_g.black_id;
  ELSE
    RAISE EXCEPTION 'no bot in this game';
  END IF;

  -- FIX: use correct columns (by_user instead of by_bot, no elapsed_ms column)
  v_new_ply := v_g.ply + 1;
  INSERT INTO chess_moves(game_id, ply, san, uci, fen_after, by_user)
    VALUES (_id, v_new_ply, _san, _uci, _fen_after, v_bot_id);

  -- FIX: update ply, turn_deadline, clock, and clear draw_offered_by
  UPDATE chess_games SET
    fen = _fen_after,
    turn = CASE WHEN v_g.turn = 'w' THEN 'b' ELSE 'w' END,
    ply = v_new_ply,
    last_move_at = now(),
    turn_deadline = now() + (COALESCE(
      (SELECT turn_timer_seconds FROM public._game_cfg('chess')),
      30
    ) || ' seconds')::interval,
    white_time_ms = CASE WHEN v_g.turn = 'w' THEN greatest(0, v_g.white_time_ms - coalesce(_elapsed_ms, 0)) ELSE v_g.white_time_ms END,
    black_time_ms = CASE WHEN v_g.turn = 'b' THEN greatest(0, v_g.black_time_ms - coalesce(_elapsed_ms, 0)) ELSE v_g.black_time_ms END,
    draw_offered_by = CASE WHEN draw_offered_by = v_bot_id THEN NULL ELSE draw_offered_by END
  WHERE id = _id;
END $$;

-- Grant to authenticated users (they trigger bot moves via RPC)
REVOKE EXECUTE ON FUNCTION public.chess_bot_play(uuid, text, text, text, int) FROM anon;
GRANT EXECUTE ON FUNCTION public.chess_bot_play(uuid, text, text, text, int) TO authenticated;
