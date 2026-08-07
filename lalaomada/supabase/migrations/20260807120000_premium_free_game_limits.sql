-- ═══════════════════════════════════════════════════════════════════════════
-- FREE GAME LIMITS + PREMIUM SUBSCRIPTION SYSTEM (Two tiers)
--
-- Free: 5 games per game type per day per user
-- Basic: 5,000 Ar/month → 100 matches per game type + 2 free tournaments
-- Unlimited: 10,000 Ar/month → unlimited matches + 2 free tournaments
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Add premium columns to profiles ────────────────────────────────────
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS premium_until timestamptz DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS premium_tier text DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS premium_tournament_passes int NOT NULL DEFAULT 0;

-- ── 2. Add settings to app_settings ───────────────────────────────────────
ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS free_games_daily_limit int NOT NULL DEFAULT 5,
  ADD COLUMN IF NOT EXISTS premium_basic_price_ar numeric NOT NULL DEFAULT 5000,
  ADD COLUMN IF NOT EXISTS premium_unlimited_price_ar numeric NOT NULL DEFAULT 10000,
  ADD COLUMN IF NOT EXISTS premium_monthly_matches int NOT NULL DEFAULT 100,
  ADD COLUMN IF NOT EXISTS premium_tournament_passes int NOT NULL DEFAULT 2;

-- ── 3. Free game usage tracking table ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.free_game_usage (
  id          uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid         NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  game_type   text         NOT NULL,
  usage_date  date         NOT NULL DEFAULT CURRENT_DATE,
  count       int          NOT NULL DEFAULT 0,
  UNIQUE(user_id, game_type, usage_date)
);
CREATE INDEX IF NOT EXISTS fgu_user_date ON public.free_game_usage(user_id, usage_date);
ALTER TABLE public.free_game_usage ENABLE ROW LEVEL SECURITY;
CREATE POLICY fgu_own ON public.free_game_usage
  FOR SELECT USING (user_id = auth.uid());

-- ── 4. Premium match usage tracking ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.premium_match_usage (
  id          uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid         NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  game_type   text         NOT NULL,
  usage_date  date         NOT NULL DEFAULT CURRENT_DATE,
  count       int          NOT NULL DEFAULT 0,
  UNIQUE(user_id, game_type, usage_date)
);
CREATE INDEX IF NOT EXISTS pmu_user_date ON public.premium_match_usage(user_id, usage_date);
ALTER TABLE public.premium_match_usage ENABLE ROW LEVEL SECURITY;
CREATE POLICY pmu_own ON public.premium_match_usage
  FOR SELECT USING (user_id = auth.uid());

-- ── 5. Subscription payments table ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.subscription_payments (
  id              uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid         NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  amount_ar       numeric      NOT NULL DEFAULT 5000,
  months          int          NOT NULL DEFAULT 1,
  valid_until     timestamptz  NOT NULL,
  payment_method  text         DEFAULT 'balance',
  status          text         NOT NULL DEFAULT 'paid',
  created_at      timestamptz  NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS sp_user ON public.subscription_payments(user_id);
ALTER TABLE public.subscription_payments ENABLE ROW LEVEL SECURITY;
CREATE POLICY sp_own ON public.subscription_payments
  FOR SELECT USING (user_id = auth.uid());

-- ── 6. check_game_eligibility(p_game_type text) ───────────────────────────
-- Returns: can_play, reason, remaining_free, is_premium, premium_remaining, tier
-- tier: null=free, 'basic'=100 matches/month, 'unlimited'=unlimited
-- Applied live via Supabase Management API.

-- ── 7. increment_game_usage(p_game_type text) ─────────────────────────────
-- Increments daily free usage or monthly premium usage based on tier.
-- Applied live via Supabase Management API.

-- ── 8. subscribe_premium(p_months int, p_tier text) ────────────────────────
-- Charges user balance, sets premium_until + premium_tier, grants tournament passes.
-- Basic: 5,000 Ar/month, Unlimited: 10,000 Ar/month.
-- Applied live via Supabase Management API.

-- ── 9. get_game_limits() ──────────────────────────────────────────────────
-- Returns dashboard data: per-game usage, tier, limits, premium_until, tournament passes.
-- Applied live via Supabase Management API.

-- ── 10. Grants ────────────────────────────────────────────────────────────
GRANT SELECT ON public.free_game_usage TO authenticated;
GRANT SELECT ON public.premium_match_usage TO authenticated;
GRANT SELECT ON public.subscription_payments TO authenticated;
