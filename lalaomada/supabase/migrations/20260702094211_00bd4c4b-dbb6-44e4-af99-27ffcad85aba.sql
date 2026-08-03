CREATE TABLE IF NOT EXISTS public.tournaments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS description text,
  ADD COLUMN IF NOT EXISTS game_slug text NOT NULL DEFAULT 'all',
  ADD COLUMN IF NOT EXISTS format text NOT NULL DEFAULT 'elimination',
  ADD COLUMN IF NOT EXISTS max_players int NOT NULL DEFAULT 8,
  ADD COLUMN IF NOT EXISTS players_per_match int NOT NULL DEFAULT 2,
  ADD COLUMN IF NOT EXISTS entry_fee_ar numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS stake numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS prize_pool numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS is_free boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS prize_1_pct numeric NOT NULL DEFAULT 60,
  ADD COLUMN IF NOT EXISTS prize_2_pct numeric NOT NULL DEFAULT 25,
  ADD COLUMN IF NOT EXISTS prize_3_pct numeric NOT NULL DEFAULT 15,
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'draft',
  ADD COLUMN IF NOT EXISTS current_round int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_rounds int NOT NULL DEFAULT 3,
  ADD COLUMN IF NOT EXISTS season int NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS winner_id uuid,
  ADD COLUMN IF NOT EXISTS runner_up_id uuid,
  ADD COLUMN IF NOT EXISTS third_place_id uuid,
  ADD COLUMN IF NOT EXISTS rewards_text text,
  ADD COLUMN IF NOT EXISTS registration_opens_at timestamptz,
  ADD COLUMN IF NOT EXISTS registration_closes_at timestamptz,
  ADD COLUMN IF NOT EXISTS starts_at timestamptz,
  ADD COLUMN IF NOT EXISTS finished_at timestamptz,
  ADD COLUMN IF NOT EXISTS join_timeout_secs int NOT NULL DEFAULT 300,
  ADD COLUMN IF NOT EXISTS disconnect_grace_secs int NOT NULL DEFAULT 120,
  ADD COLUMN IF NOT EXISTS move_timer_secs int NOT NULL DEFAULT 60,
  ADD COLUMN IF NOT EXISTS match_duration_min int NOT NULL DEFAULT 10,
  ADD COLUMN IF NOT EXISTS require_phone_verification boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS require_verified_account boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS bye_strategy text NOT NULL DEFAULT 'random',
  ADD COLUMN IF NOT EXISTS created_by uuid;
GRANT SELECT ON public.tournaments TO authenticated, anon;
GRANT INSERT, UPDATE ON public.tournaments TO authenticated;
GRANT ALL ON public.tournaments TO service_role;
CREATE INDEX IF NOT EXISTS tournaments_status_idx ON public.tournaments(status);
CREATE INDEX IF NOT EXISTS tournaments_game_slug_idx ON public.tournaments(game_slug);
ALTER TABLE public.tournaments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tournaments_public_read" ON public.tournaments;
CREATE POLICY "tournaments_public_read" ON public.tournaments FOR SELECT USING (true);
DROP POLICY IF EXISTS "tournaments_admin_write" ON public.tournaments;
CREATE POLICY "tournaments_admin_write" ON public.tournaments FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP FUNCTION IF EXISTS public.list_tournaments(text, text, int);
CREATE FUNCTION public.list_tournaments(_status text DEFAULT NULL, _game_slug text DEFAULT NULL, _limit int DEFAULT 100)
RETURNS SETOF public.tournaments LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM public.tournaments
  WHERE (_status IS NULL OR status = _status)
    AND (_game_slug IS NULL OR game_slug = _game_slug)
  ORDER BY created_at DESC LIMIT _limit;
$$;
GRANT EXECUTE ON FUNCTION public.list_tournaments(text, text, int) TO authenticated, anon;