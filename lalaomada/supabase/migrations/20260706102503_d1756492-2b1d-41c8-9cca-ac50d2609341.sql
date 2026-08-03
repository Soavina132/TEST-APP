
-- 1. game_configs badge column + covers
ALTER TABLE public.game_configs ADD COLUMN IF NOT EXISTS badge TEXT DEFAULT NULL;
ALTER TABLE public.game_configs DROP CONSTRAINT IF EXISTS game_configs_badge_check;
ALTER TABLE public.game_configs ADD CONSTRAINT game_configs_badge_check
  CHECK (badge IS NULL OR badge IN ('new', 'coming_soon', 'hot'));

UPDATE public.game_configs SET cover_url = '/covers/cover_ludo.png'     WHERE slug = 'ludo'     AND (cover_url IS NULL OR cover_url = '');
UPDATE public.game_configs SET cover_url = '/covers/cover_domino.png'   WHERE slug = 'domino'   AND (cover_url IS NULL OR cover_url = '');
UPDATE public.game_configs SET cover_url = '/covers/cover_fanorona.png' WHERE slug = 'fanorona' AND (cover_url IS NULL OR cover_url = '');
UPDATE public.game_configs SET cover_url = '/covers/cover_chess.png'    WHERE slug = 'chess'    AND (cover_url IS NULL OR cover_url = '');
UPDATE public.game_configs SET cover_url = '/covers/cover_rami.png'     WHERE slug = 'rami'     AND (cover_url IS NULL OR cover_url = '');
UPDATE public.game_configs SET cover_url = '/covers/cover_poker.png'    WHERE slug = 'poker'    AND (cover_url IS NULL OR cover_url = '');

-- 2. domino/billiard max_players (idempotent)
ALTER TABLE public.domino_games ADD COLUMN IF NOT EXISTS max_players INTEGER NOT NULL DEFAULT 2;

-- 3. billiard tables (may not exist yet)
CREATE TABLE IF NOT EXISTS public.billiard_games (
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
  max_players INTEGER NOT NULL DEFAULT 2,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  started_at TIMESTAMPTZ,
  finished_at TIMESTAMPTZ
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.billiard_games TO authenticated;
GRANT ALL ON public.billiard_games TO service_role;
ALTER TABLE public.billiard_games ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "billiard_games_select" ON public.billiard_games;
DROP POLICY IF EXISTS "billiard_games_insert" ON public.billiard_games;
DROP POLICY IF EXISTS "billiard_games_update" ON public.billiard_games;
CREATE POLICY "billiard_games_select" ON public.billiard_games FOR SELECT TO authenticated USING (true);
CREATE POLICY "billiard_games_insert" ON public.billiard_games FOR INSERT TO authenticated WITH CHECK (auth.uid() = host_id);
CREATE POLICY "billiard_games_update" ON public.billiard_games FOR UPDATE TO authenticated USING (true);

CREATE TABLE IF NOT EXISTS public.billiard_participants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id UUID NOT NULL REFERENCES public.billiard_games(id) ON DELETE CASCADE,
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
GRANT SELECT, INSERT, UPDATE, DELETE ON public.billiard_participants TO authenticated;
GRANT ALL ON public.billiard_participants TO service_role;
ALTER TABLE public.billiard_participants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "billiard_participants_select" ON public.billiard_participants;
DROP POLICY IF EXISTS "billiard_participants_insert" ON public.billiard_participants;
DROP POLICY IF EXISTS "billiard_participants_update" ON public.billiard_participants;
CREATE POLICY "billiard_participants_select" ON public.billiard_participants FOR SELECT TO authenticated USING (true);
CREATE POLICY "billiard_participants_insert" ON public.billiard_participants FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "billiard_participants_update" ON public.billiard_participants FOR UPDATE TO authenticated USING (true);

-- 4. player_game_stats
CREATE TABLE IF NOT EXISTS public.player_game_stats (
  user_id        UUID    NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  game_mode      TEXT    NOT NULL,
  wins           INTEGER NOT NULL DEFAULT 0,
  losses         INTEGER NOT NULL DEFAULT 0,
  total_winnings NUMERIC NOT NULL DEFAULT 0,
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, game_mode)
);
GRANT SELECT ON public.player_game_stats TO authenticated;
GRANT ALL    ON public.player_game_stats TO service_role;
ALTER TABLE public.player_game_stats ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pgstats_select ON public.player_game_stats;
CREATE POLICY pgstats_select ON public.player_game_stats FOR SELECT TO authenticated USING (true);

-- 5. ai_assistant_enabled on app_settings (idempotent)
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS ai_assistant_enabled boolean DEFAULT false;
