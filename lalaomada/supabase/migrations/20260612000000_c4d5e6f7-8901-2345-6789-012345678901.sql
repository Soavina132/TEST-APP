-- Migration: add create_game_2p + update join_game_2p with balance deduction
-- Safe to re-apply (CREATE OR REPLACE, IF NOT EXISTS).

-- Ensure max_players column exists (idempotent)
ALTER TABLE domino_games  ADD COLUMN IF NOT EXISTS max_players INTEGER NOT NULL DEFAULT 2;
ALTER TABLE billiard_games ADD COLUMN IF NOT EXISTS max_players INTEGER NOT NULL DEFAULT 2;

-- ----------------------------------------------------------------
-- create_game_2p: create a domino/billiard game as host
--   • validates authenticated user
--   • deducts stake from host balance (if stake > 0)
--   • inserts game row + host as participant (slot 0)
--   • returns game UUID
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_game_2p(
  _game_table  TEXT,
  _part_table  TEXT,
  _stake       NUMERIC,
  _commission  NUMERIC,
  _is_private  BOOLEAN DEFAULT false,
  _room_code   TEXT    DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _user_id UUID := auth.uid();
  _game_id UUID;
BEGIN
  IF _user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  -- Balance check + deduction for host
  IF _stake > 0 THEN
    IF (SELECT balance_ar FROM profiles WHERE id = _user_id FOR UPDATE) < _stake THEN
      RAISE EXCEPTION 'insufficient_balance';
    END IF;
    UPDATE profiles SET balance_ar = balance_ar - _stake WHERE id = _user_id;
  END IF;

  -- Create game row (max_players defaults to 2 via column default)
  EXECUTE format(
    'INSERT INTO %I (host_id, stake, pot, commission_pct, is_private, room_code) '
    'VALUES ($1, $2, $3, $4, $5, $6) RETURNING id',
    _game_table
  ) INTO _game_id
    USING _user_id, _stake, _stake, _commission, _is_private, _room_code;

  -- Host joins as slot 0
  EXECUTE format(
    'INSERT INTO %I (game_id, user_id, slot) VALUES ($1, $2, 0)',
    _part_table
  ) USING _game_id, _user_id;

  RETURN _game_id;
END;
$$;

GRANT EXECUTE ON FUNCTION create_game_2p(TEXT, TEXT, NUMERIC, NUMERIC, BOOLEAN, TEXT) TO authenticated;

-- ----------------------------------------------------------------
-- join_game_2p: securely join an existing 2-player game as guest
--   • validates auth, game open, not full, not already joined
--   • deducts stake from joiner balance + adds to pot
--   • assigns the first free slot
-- ----------------------------------------------------------------
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
  IF _user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  -- Lock game row to prevent race conditions
  EXECUTE format('SELECT * FROM %I WHERE id = $1 FOR UPDATE', _game_table)
    INTO _game USING _game_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'game_not_found'; END IF;
  IF _game.status <> 'open' THEN RAISE EXCEPTION 'game_not_open'; END IF;

  -- Prevent duplicate join
  EXECUTE format('SELECT COUNT(*) FROM %I WHERE game_id = $1 AND user_id = $2', _part_table)
    INTO _already USING _game_id, _user_id;
  IF _already > 0 THEN RAISE EXCEPTION 'already_joined'; END IF;

  -- Capacity check (COALESCE handles missing max_players column via NULL)
  EXECUTE format('SELECT COUNT(*) FROM %I WHERE game_id = $1', _part_table)
    INTO _count USING _game_id;
  IF _count >= COALESCE(_game.max_players, 2) THEN RAISE EXCEPTION 'game_full'; END IF;

  -- Balance check + deduction
  IF _game.stake > 0 THEN
    IF (SELECT balance_ar FROM profiles WHERE id = _user_id FOR UPDATE) < _game.stake THEN
      RAISE EXCEPTION 'insufficient_balance';
    END IF;
    UPDATE profiles SET balance_ar = balance_ar - _game.stake WHERE id = _user_id;
    EXECUTE format('UPDATE %I SET pot = pot + $1 WHERE id = $2', _game_table)
      USING _game.stake, _game_id;
  END IF;

  -- Find next free slot
  EXECUTE format(
    'SELECT MIN(s) FROM generate_series(0, $1 - 1) s '
    'WHERE s NOT IN (SELECT slot FROM %I WHERE game_id = $2)',
    _part_table
  ) INTO _slot USING COALESCE(_game.max_players, 2), _game_id;
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
