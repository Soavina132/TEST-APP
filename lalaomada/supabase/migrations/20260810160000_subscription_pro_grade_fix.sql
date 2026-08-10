-- ═══════════════════════════════════════════════════════════════════════════
-- SUBSCRIPTION SYSTEM — PRO-GRADE FIX
--
-- Fixes:
--  1. Add "starter" tier support to subscribe_premium + check_game_eligibility
--  2. Add FOR UPDATE lock to subscribe_premium (race condition fix)
--  3. Add SET search_path TO 'public' to ALL SECURITY DEFINER functions
--  4. Schedule expire_premium via pg_cron (every 5 minutes)
--  5. Add idempotency guard: prevent double-subscribe race
--  6. Add balance negative guard
-- ═══════════════════════════════════════════════════════════════════════════

-- ═══ 1. subscribe_premium — COMPLETE REWRITE (atomic, locked, hardened) ═══
CREATE OR REPLACE FUNCTION public.subscribe_premium(p_months int, p_tier text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  _uid uuid := auth.uid();
  _settings record;
  _price numeric;
  _total numeric;
  _balance numeric;
  _current_until timestamptz;
  _new_until timestamptz;
  _current_tier text;
BEGIN
  IF _uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifie');
  END IF;

  IF p_months < 1 OR p_months > 12 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Nombre de mois invalide (1-12)');
  END IF;

  IF p_tier NOT IN ('starter', 'basic', 'standard', 'premium') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Tier invalide');
  END IF;

  SELECT * INTO _settings FROM public.app_settings WHERE id = 1 LIMIT 1;

  _price := CASE
    WHEN p_tier = 'starter'  THEN _settings.sub_starter_price_ar
    WHEN p_tier = 'basic'    THEN _settings.sub_basic_price_ar
    WHEN p_tier = 'standard' THEN _settings.sub_standard_price_ar
    WHEN p_tier = 'premium'  THEN _settings.sub_premium_price_ar
  END;

  IF _price IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Prix introuvable pour ce tier');
  END IF;

  _total := _price * p_months;

  -- ATOMIC: Lock the row, read balance, check, debit in one transaction
  SELECT balance_ar, premium_until, premium_tier
  INTO _balance, _current_until, _current_tier
  FROM public.profiles
  WHERE id = _uid
  FOR UPDATE;

  IF _balance IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Profil introuvable');
  END IF;

  IF _balance < _total THEN
    RETURN jsonb_build_object('success', false, 'error',
      'Solde insuffisant. Vous avez ' || _balance || ' Ar, besoin de ' || _total || ' Ar');
  END IF;

  _new_until := GREATEST(COALESCE(_current_until, now()), now()) + (p_months || ' month')::interval;

  UPDATE public.profiles
  SET balance_ar = balance_ar - _total,
      premium_tier = p_tier,
      premium_until = _new_until,
      is_premium = true
  WHERE id = _uid AND balance_ar >= _total;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Solde insuffisant au moment du paiement');
  END IF;

  INSERT INTO public.subscription_payments (user_id, amount_ar, months, valid_until, payment_method, status)
  VALUES (_uid, _total, p_months, _new_until, 'balance', 'paid');

  INSERT INTO public.transactions (user_id, type, amount, note)
  VALUES (_uid, 'subscription', -_total, 'Abonnement ' || p_tier || ' x' || p_months || ' mois');

  RETURN jsonb_build_object(
    'success', true,
    'tier', p_tier,
    'amount', _total,
    'months', p_months,
    'premium_until', _new_until
  );
END;
$$;

-- ═══ 2. check_game_eligibility — Add starter tier + SET search_path ═══
CREATE OR REPLACE FUNCTION public.check_game_eligibility(p_game_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  _uid uuid := auth.uid();
  _settings record;
  _daily_count int;
  _active_days int;
  _trial_done bool;
  _is_premium bool;
  _tier text;
  _premium_until timestamptz;
  _monthly_count int;
  _monthly_limit int;
  _remaining_today int;
  _remaining_monthly int;
  _reason text;
  _can_play bool;
BEGIN
  IF _uid IS NULL THEN
    RETURN jsonb_build_object('can_play', false, 'reason', 'Non authentifie',
      'remaining_today', 0, 'is_premium', false, 'premium_remaining', 0,
      'tier', null, 'active_days_used', 0, 'max_active_days', 5);
  END IF;

  SELECT * INTO _settings FROM public.app_settings WHERE id = 1 LIMIT 1;

  SELECT premium_until, premium_tier, free_trial_active_days, free_trial_completed
  INTO _premium_until, _tier, _active_days, _trial_done
  FROM public.profiles WHERE id = _uid;

  _is_premium := _premium_until IS NOT NULL AND _premium_until > now();

  SELECT COALESCE(SUM(count), 0) INTO _daily_count
  FROM public.free_game_usage
  WHERE user_id = _uid AND usage_date = CURRENT_DATE;

  _remaining_today := _settings.free_games_daily_limit - _daily_count;

  IF _is_premium THEN
    SELECT COALESCE(SUM(count), 0) INTO _monthly_count
    FROM public.premium_match_usage
    WHERE user_id = _uid
      AND usage_date >= date_trunc('month', CURRENT_DATE)::date
      AND usage_date <= CURRENT_DATE;

    _monthly_limit := CASE
      WHEN _tier = 'starter'  THEN _settings.sub_starter_matches
      WHEN _tier = 'basic'    THEN _settings.sub_basic_matches
      WHEN _tier = 'standard' THEN _settings.sub_standard_matches
      WHEN _tier = 'premium'  THEN _settings.sub_premium_matches
      ELSE 0
    END;

    _remaining_monthly := GREATEST(_monthly_limit - _monthly_count, 0);

    IF _remaining_monthly > 0 THEN
      _can_play := true;
      _reason := null;
    ELSE
      _can_play := false;
      _reason := 'Limite mensuelle atteinte pour votre abonnement';
    END IF;

    RETURN jsonb_build_object(
      'can_play', _can_play,
      'reason', _reason,
      'remaining_today', _remaining_today,
      'is_premium', true,
      'premium_remaining', _remaining_monthly,
      'tier', _tier,
      'active_days_used', _active_days,
      'max_active_days', _settings.free_trial_max_days,
      'monthly_limit', _monthly_limit,
      'monthly_used', _monthly_count
    );
  ELSE
    IF _trial_done THEN
      _can_play := false;
      _reason := 'Periode d''essai gratuite terminee. Prenez un abonnement pour continuer.';
    ELSIF _remaining_today <= 0 THEN
      _can_play := false;
      _reason := 'Limite quotidienne de parties gratuites atteinte. Revenez demain ou prenez un abonnement.';
    ELSE
      _can_play := true;
      _reason := null;
    END IF;

    RETURN jsonb_build_object(
      'can_play', _can_play,
      'reason', _reason,
      'remaining_today', GREATEST(_remaining_today, 0),
      'is_premium', false,
      'premium_remaining', 0,
      'tier', null,
      'active_days_used', _active_days,
      'max_active_days', _settings.free_trial_max_days,
      'daily_limit', _settings.free_games_daily_limit
    );
  END IF;
END;
$$;

-- ═══ 3. increment_game_usage — Add SET search_path + starter support ═══
CREATE OR REPLACE FUNCTION public.increment_game_usage(p_game_type text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  _uid uuid := auth.uid();
  _settings record;
  _is_premium bool;
  _premium_until timestamptz;
  _tier text;
  _existing_count int;
  _daily_total int;
  _active_days int;
  _trial_done bool;
BEGIN
  IF _uid IS NULL THEN RETURN; END IF;

  SELECT * INTO _settings FROM public.app_settings WHERE id = 1 LIMIT 1;

  SELECT premium_until, premium_tier INTO _premium_until, _tier
  FROM public.profiles WHERE id = _uid;

  _is_premium := _premium_until IS NOT NULL AND _premium_until > now();

  IF _is_premium THEN
    SELECT count INTO _existing_count
    FROM public.premium_match_usage
    WHERE user_id = _uid AND game_type = 'all'
      AND usage_date = date_trunc('month', CURRENT_DATE)::date;

    IF _existing_count IS NULL THEN
      INSERT INTO public.premium_match_usage (user_id, game_type, usage_date, count)
      VALUES (_uid, 'all', date_trunc('month', CURRENT_DATE)::date, 1);
    ELSE
      UPDATE public.premium_match_usage
      SET count = count + 1
      WHERE user_id = _uid AND game_type = 'all'
        AND usage_date = date_trunc('month', CURRENT_DATE)::date;
    END IF;
  ELSE
    SELECT COALESCE(SUM(count), 0) INTO _daily_total
    FROM public.free_game_usage
    WHERE user_id = _uid AND usage_date = CURRENT_DATE;

    SELECT count INTO _existing_count
    FROM public.free_game_usage
    WHERE user_id = _uid AND game_type = p_game_type AND usage_date = CURRENT_DATE;

    IF _existing_count IS NULL THEN
      INSERT INTO public.free_game_usage (user_id, game_type, usage_date, count)
      VALUES (_uid, p_game_type, CURRENT_DATE, 1);
    ELSE
      UPDATE public.free_game_usage SET count = count + 1
      WHERE user_id = _uid AND game_type = p_game_type AND usage_date = CURRENT_DATE;
    END IF;

    IF _daily_total = 0 THEN
      SELECT free_trial_active_days, free_trial_completed
      INTO _active_days, _trial_done
      FROM public.profiles WHERE id = _uid;

      _active_days := _active_days + 1;

      IF _active_days >= _settings.free_trial_max_days THEN
        UPDATE public.profiles
        SET free_trial_active_days = _active_days,
            free_trial_completed = true
        WHERE id = _uid;
      ELSE
        UPDATE public.profiles
        SET free_trial_active_days = _active_days
        WHERE id = _uid;
      END IF;
    END IF;
  END IF;
END;
$$;

-- ═══ 4. get_game_limits — Add SET search_path + starter tier ═══
CREATE OR REPLACE FUNCTION public.get_game_limits()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  _uid uuid := auth.uid();
  _settings record;
  _is_premium bool;
  _tier text;
  _premium_until timestamptz;
  _daily_count int;
  _monthly_count int;
  _monthly_limit int;
  _active_days int;
  _trial_done bool;
  _remaining_today int;
  _remaining_monthly int;
BEGIN
  IF _uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifie');
  END IF;

  SELECT * INTO _settings FROM public.app_settings WHERE id = 1 LIMIT 1;

  SELECT premium_until, premium_tier, free_trial_active_days, free_trial_completed
  INTO _premium_until, _tier, _active_days, _trial_done
  FROM public.profiles WHERE id = _uid;

  _is_premium := _premium_until IS NOT NULL AND _premium_until > now();

  SELECT COALESCE(SUM(count), 0) INTO _daily_count
  FROM public.free_game_usage
  WHERE user_id = _uid AND usage_date = CURRENT_DATE;

  _remaining_today := _settings.free_games_daily_limit - _daily_count;

  IF _is_premium THEN
    SELECT COALESCE(SUM(count), 0) INTO _monthly_count
    FROM public.premium_match_usage
    WHERE user_id = _uid
      AND usage_date >= date_trunc('month', CURRENT_DATE)::date
      AND usage_date <= CURRENT_DATE;

    _monthly_limit := CASE
      WHEN _tier = 'starter'  THEN _settings.sub_starter_matches
      WHEN _tier = 'basic'    THEN _settings.sub_basic_matches
      WHEN _tier = 'standard' THEN _settings.sub_standard_matches
      WHEN _tier = 'premium'  THEN _settings.sub_premium_matches
      ELSE 0
    END;

    _remaining_monthly := GREATEST(_monthly_limit - _monthly_count, 0);

    RETURN jsonb_build_object(
      'is_premium', true, 'tier', _tier, 'premium_until', _premium_until,
      'monthly_limit', _monthly_limit, 'monthly_used', _monthly_count,
      'remaining_monthly', _remaining_monthly, 'remaining_today', _remaining_today,
      'active_days_used', _active_days, 'max_active_days', _settings.free_trial_max_days
    );
  ELSE
    RETURN jsonb_build_object(
      'is_premium', false, 'tier', null,
      'daily_limit', _settings.free_games_daily_limit,
      'daily_used', _daily_count,
      'remaining_today', GREATEST(_remaining_today, 0),
      'active_days_used', _active_days,
      'max_active_days', _settings.free_trial_max_days,
      'trial_completed', _trial_done
    );
  END IF;
END;
$$;

-- ═══ 5. Schedule expire_premium via pg_cron (every 5 minutes) ═══
DO $$
DECLARE j bigint;
BEGIN
  SELECT jobid INTO j FROM cron.job WHERE jobname = 'expire_premium';
  IF j IS NOT NULL THEN PERFORM cron.unschedule(j); END IF;
END $$;
SELECT cron.schedule('expire_premium', '*/5 * * * *', $$SELECT public.expire_premium();$$);

-- ═══ 6. Ensure sub_starter columns exist in app_settings ═══
ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS sub_starter_price_ar numeric NOT NULL DEFAULT 500,
  ADD COLUMN IF NOT EXISTS sub_starter_matches int NOT NULL DEFAULT 50;

-- ═══ 7. Re-grant execution (in case functions were recreated) ═══
GRANT EXECUTE ON FUNCTION public.check_game_eligibility(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.increment_game_usage(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.subscribe_premium(int, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_game_limits() TO authenticated;
