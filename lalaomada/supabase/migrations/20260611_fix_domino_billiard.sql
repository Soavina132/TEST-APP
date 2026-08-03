-- Migration: fix domino/billiard — add max_players + secure join_game_2p RPC

-- 1. Add missing max_players column to domino_games
ALTER TABLE domino_games ADD COLUMN IF NOT EXISTS max_players INTEGER NOT NULL DEFAULT 2;

-- 2. Add missing max_players column to billiard_games
ALTER TABLE billiard_games ADD COLUMN IF NOT EXISTS max_players INTEGER NOT NULL DEFAULT 2;

-- 3. Secure join RPC for 2-player games (domino & billiard)
--    Validates: game is open, not full, caller not already joined, sufficient balance.
--    Deducts stake from balance and adds to pot inside a single transaction.
CREATE OR REPLACE FUNCTION join_game_2p(
  _game_table TEXT,
  _part_table TEXT,
  _game_id    UUID
) RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _game    RECORD;
  _slot    INTEGER;
  _count   INTEGER;
  _already INTEGER;
  _user_id UUID := auth.uid();
BEGIN
  IF _user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Lock the game row to prevent race conditions
  EXECUTE format('SELECT * FROM %I WHERE id = $1 FOR UPDATE', _game_table)
    INTO _game USING _game_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'game_not_found'; END IF;
  IF _game.status <> 'open' THEN RAISE EXCEPTION 'game_not_open'; END IF;

  -- Prevent duplicate join
  EXECUTE format('SELECT COUNT(*) FROM %I WHERE game_id = $1 AND user_id = $2', _part_table)
    INTO _already USING _game_id, _user_id;
  IF _already > 0 THEN RAISE EXCEPTION 'already_joined'; END IF;

  -- Capacity check
  EXECUTE format('SELECT COUNT(*) FROM %I WHERE game_id = $1', _part_table)
    INTO _count USING _game_id;
  IF _count >= _game.max_players THEN RAISE EXCEPTION 'game_full'; END IF;

  -- Balance check + deduction
  IF _game.stake > 0 THEN
    IF (SELECT balance_ar FROM profiles WHERE id = _user_id) < _game.stake THEN
      RAISE EXCEPTION 'insufficient_balance';
    END IF;
    UPDATE profiles SET balance_ar = balance_ar - _game.stake WHERE id = _user_id;
    EXECUTE format('UPDATE %I SET pot = pot + $1 WHERE id = $2', _game_table)
      USING _game.stake, _game_id;
  END IF;

  -- Find next free slot
  EXECUTE format(
    'SELECT MIN(s) FROM generate_series(0, $1 - 1) s ' ||
    'WHERE s NOT IN (SELECT slot FROM %I WHERE game_id = $2)',
    _part_table
  ) INTO _slot USING _game.max_players, _game_id;

  IF _slot IS NULL THEN RAISE EXCEPTION 'game_full'; END IF;

  -- Insert participant
  EXECUTE format(
    'INSERT INTO %I (game_id, user_id, slot) VALUES ($1, $2, $3)',
    _part_table
  ) USING _game_id, _user_id, _slot;

  RETURN _slot;
END;
$$;

GRANT EXECUTE ON FUNCTION join_game_2p(TEXT, TEXT, UUID) TO authenticated;
