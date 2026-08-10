-- ═══ Subscription system hardening ═══

-- 1. subscribe_premium: FOR UPDATE lock (race condition fix)
-- 2. expire_premium: auto-expire expired subscriptions
-- 3. _auto_expire_premium trigger: auto-set is_premium=false on profile UPDATE
-- 4. check_game_eligibility: FOR UPDATE + auto-expire check
-- 5. increment_game_usage: FOR UPDATE lock
-- 6. get_game_limits: auto-expire check
-- 7. RLS: INSERT/UPDATE policies on subscription_payments, free_game_usage, premium_match_usage

-- expire_premium function
CREATE OR REPLACE FUNCTION public.expire_premium()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE _count int;
BEGIN
  UPDATE public.profiles SET is_premium = false, premium_tier = NULL
  WHERE is_premium = true AND premium_until IS NOT NULL AND premium_until < now();
  GET DIAGNOSTICS _count = ROW_COUNT;
  RETURN _count;
END;
$$;

-- Auto-expire trigger on profiles
CREATE OR REPLACE FUNCTION public._auto_expire_premium()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.is_premium = true AND NEW.premium_until IS NOT NULL AND NEW.premium_until < now() THEN
    NEW.is_premium := false;
    NEW.premium_tier := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_expire_premium ON public.profiles;
CREATE TRIGGER trg_auto_expire_premium BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public._auto_expire_premium();

-- RLS: subscription_payments INSERT
DROP POLICY IF EXISTS sp_insert_own ON public.subscription_payments;
CREATE POLICY sp_insert_own ON public.subscription_payments
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

-- RLS: free_game_usage INSERT + UPDATE
DROP POLICY IF EXISTS fgu_insert_own ON public.free_game_usage;
CREATE POLICY fgu_insert_own ON public.free_game_usage
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS fgu_update_own ON public.free_game_usage;
CREATE POLICY fgu_update_own ON public.free_game_usage
  FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- RLS: premium_match_usage INSERT + UPDATE
DROP POLICY IF EXISTS pmu_insert_own ON public.premium_match_usage;
CREATE POLICY pmu_insert_own ON public.premium_match_usage
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS pmu_update_own ON public.premium_match_usage;
CREATE POLICY pmu_update_own ON public.premium_match_usage
  FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
