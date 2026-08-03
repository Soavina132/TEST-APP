CREATE OR REPLACE FUNCTION public.chess_join(_game_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_g chess_games%ROWTYPE;
  v_bal numeric;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id = _game_id AND status = 'open' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game not joinable'; END IF;
  IF v_g.white_id = v_uid OR v_g.black_id = v_uid THEN RETURN _game_id; END IF;
  IF v_g.white_id IS NOT NULL AND v_g.black_id IS NOT NULL THEN RAISE EXCEPTION 'full'; END IF;

  IF coalesce(v_g.stake,0) > 0 THEN
    SELECT balance_ar INTO v_bal FROM profiles WHERE id = v_uid FOR UPDATE;
    IF coalesce(v_bal,0) < v_g.stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;
    UPDATE profiles SET balance_ar = balance_ar - v_g.stake WHERE id = v_uid;
    INSERT INTO transactions(user_id, type, amount, meta)
      VALUES (v_uid, 'chess_stake', -v_g.stake, jsonb_build_object('kind','hold','game',_game_id));
  END IF;

  IF v_g.white_id IS NULL THEN
    UPDATE chess_games
      SET white_id = v_uid,
          pot = pot + coalesce(v_g.stake,0),
          status = 'playing',
          started_at = now(),
          last_move_at = now()
      WHERE id = _game_id;
  ELSE
    UPDATE chess_games
      SET black_id = v_uid,
          pot = pot + coalesce(v_g.stake,0),
          status = 'playing',
          started_at = now(),
          last_move_at = now()
      WHERE id = _game_id;
  END IF;

  RETURN _game_id;
END $$;

GRANT EXECUTE ON FUNCTION public.chess_join(uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';