-- Migration: add ai_assistant_enabled + domino/billiard game tables

-- 1. Add ai_assistant_enabled to app_settings
ALTER TABLE app_settings ADD COLUMN IF NOT EXISTS ai_assistant_enabled boolean DEFAULT false;

-- 2. domino_games
CREATE TABLE IF NOT EXISTS domino_games (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id UUID NOT NULL REFERENCES auth.users(id),
  status TEXT NOT NULL DEFAULT 'open',
  stake NUMERIC NOT NULL DEFAULT 0,
  pot NUMERIC NOT NULL DEFAULT 0,
  commission_pct INTEGER NOT NULL DEFAULT 10,
  is_private BOOLEAN NOT NULL DEFAULT false,
  room_code TEXT,
  state JSONB NOT NULL DEFAULT '{}',
  winner_id UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  started_at TIMESTAMPTZ,
  finished_at TIMESTAMPTZ
);

ALTER TABLE domino_games ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "domino_games_select" ON domino_games;
DROP POLICY IF EXISTS "domino_games_insert" ON domino_games;
DROP POLICY IF EXISTS "domino_games_update" ON domino_games;
CREATE POLICY "domino_games_select" ON domino_games FOR SELECT TO authenticated USING (true);
CREATE POLICY "domino_games_insert" ON domino_games FOR INSERT TO authenticated WITH CHECK (auth.uid() = host_id);
CREATE POLICY "domino_games_update" ON domino_games FOR UPDATE TO authenticated USING (true);

-- 3. domino_participants
CREATE TABLE IF NOT EXISTS domino_participants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id UUID NOT NULL REFERENCES domino_games(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  slot INTEGER NOT NULL,
  ready BOOLEAN NOT NULL DEFAULT false,
  forfeited BOOLEAN NOT NULL DEFAULT false,
  score INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(game_id, slot),
  UNIQUE(game_id, user_id)
);

ALTER TABLE domino_participants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "domino_participants_select" ON domino_participants;
DROP POLICY IF EXISTS "domino_participants_insert" ON domino_participants;
DROP POLICY IF EXISTS "domino_participants_update" ON domino_participants;
CREATE POLICY "domino_participants_select" ON domino_participants FOR SELECT TO authenticated USING (true);
CREATE POLICY "domino_participants_insert" ON domino_participants FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "domino_participants_update" ON domino_participants FOR UPDATE TO authenticated USING (true);

-- 4. billiard_games
CREATE TABLE IF NOT EXISTS billiard_games (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id UUID NOT NULL REFERENCES auth.users(id),
  status TEXT NOT NULL DEFAULT 'open',
  stake NUMERIC NOT NULL DEFAULT 0,
  pot NUMERIC NOT NULL DEFAULT 0,
  commission_pct INTEGER NOT NULL DEFAULT 10,
  is_private BOOLEAN NOT NULL DEFAULT false,
  room_code TEXT,
  state JSONB NOT NULL DEFAULT '{}',
  winner_id UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  started_at TIMESTAMPTZ,
  finished_at TIMESTAMPTZ
);

ALTER TABLE billiard_games ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "billiard_games_select" ON billiard_games;
DROP POLICY IF EXISTS "billiard_games_insert" ON billiard_games;
DROP POLICY IF EXISTS "billiard_games_update" ON billiard_games;
CREATE POLICY "billiard_games_select" ON billiard_games FOR SELECT TO authenticated USING (true);
CREATE POLICY "billiard_games_insert" ON billiard_games FOR INSERT TO authenticated WITH CHECK (auth.uid() = host_id);
CREATE POLICY "billiard_games_update" ON billiard_games FOR UPDATE TO authenticated USING (true);

-- 5. billiard_participants
CREATE TABLE IF NOT EXISTS billiard_participants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id UUID NOT NULL REFERENCES billiard_games(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  slot INTEGER NOT NULL,
  ready BOOLEAN NOT NULL DEFAULT false,
  forfeited BOOLEAN NOT NULL DEFAULT false,
  score INTEGER NOT NULL DEFAULT 0,
  ball_type TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(game_id, slot),
  UNIQUE(game_id, user_id)
);

ALTER TABLE billiard_participants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "billiard_participants_select" ON billiard_participants;
DROP POLICY IF EXISTS "billiard_participants_insert" ON billiard_participants;
DROP POLICY IF EXISTS "billiard_participants_update" ON billiard_participants;
CREATE POLICY "billiard_participants_select" ON billiard_participants FOR SELECT TO authenticated USING (true);
CREATE POLICY "billiard_participants_insert" ON billiard_participants FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "billiard_participants_update" ON billiard_participants FOR UPDATE TO authenticated USING (true);

-- 6. Debit/credit helpers (reuse profiles.balance_ar)
-- Winners get pot*(100-commission)/100 added to their balance
-- No server RPC needed: the client updates balance after game ends via existing transaction system.
