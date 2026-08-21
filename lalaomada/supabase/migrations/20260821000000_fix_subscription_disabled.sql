-- ═════════════════════════════════════════════════════════════════
-- FIX: Le flag subscription_disabled dans app_settings est enfin respecté
--
-- Problème : l'admin coche "Désactiver les abonnements" mais
-- check_game_eligibility ignore ce flag et continue de bloquer
-- les utilisateurs (limites quotidiennes, période d'essai, etc.)
--
-- Solution : check_game_eligibility et increment_game_usage
-- lisent subscription_disabled en premier. Si true → tout est
-- débloqué, can_play = true, pas de comptage.
-- ═════════════════════════════════════════════════════════════════

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

  -- ✅ Si les abonnements sont désactivés par l'admin, tout est débloqué
  IF COALESCE(_settings.subscription_disabled, false) THEN
    RETURN jsonb_build_object(
      'can_play', true,
      'reason', null,
      'remaining_today', 999,
      'is_premium', true,
      'premium_remaining', 999,
      'tier', 'premium',
      'active_days_used', 0,
      'max_active_days', _settings.free_trial_max_days,
      'subscription_disabled', true
    );
  END IF;

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
      'monthly_used', _monthly_count,
      'subscription_disabled', false
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
      'daily_limit', _settings.free_games_daily_limit,
      'subscription_disabled', false
    );
  END IF;
END;
$$;

-- Aussi: increment_game_usage ne compte plus quand subscription_disabled
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

  -- ✅ Si les abonnements sont désactivés, ne pas compter
  IF COALESCE(_settings.subscription_disabled, false) THEN
    RETURN;
  END IF;

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

-- Aussi: get_game_limits respecte le flag
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

  -- ✅ Si les abonnements sont désactivés, tout est illimité
  IF COALESCE(_settings.subscription_disabled, false) THEN
    RETURN jsonb_build_object(
      'is_premium', true,
      'tier', 'premium',
      'remaining_today', 999,
      'remaining_monthly', 999,
      'daily_limit', 0,
      'monthly_limit', 0,
      'active_days_used', 0,
      'max_active_days', _settings.free_trial_max_days,
      'trial_completed', false,
      'subscription_disabled', true
    );
  END IF;

  SELECT premium_until, premium_tier, free_trial_active_days, free_trial_completed
  INTO _premium_until, _tier, _active_days, _trial_done
  FROM public.profiles WHERE id = _uid;

  _is_premium := _premium_until IS NOT NULL AND _premium_until > now();

  SELECT COALESCE(SUM(count), 0) INTO _daily_count
  FROM public.free_game_usage
  WHERE user_id = _uid AND usage_date = CURRENT_DATE;

  _remaining_today := GREATEST(_settings.free_games_daily_limit - _daily_count, 0);

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
      'is_premium', true,
      'tier', _tier,
      'remaining_today', _remaining_today,
      'remaining_monthly', _remaining_monthly,
      'daily_limit', _settings.free_games_daily_limit,
      'monthly_limit', _monthly_limit,
      'active_days_used', _active_days,
      'max_active_days', _settings.free_trial_max_days,
      'trial_completed', _trial_done,
      'subscription_disabled', false
    );
  ELSE
    RETURN jsonb_build_object(
      'is_premium', false,
      'tier', null,
      'remaining_today', _remaining_today,
      'remaining_monthly', 0,
      'daily_limit', _settings.free_games_daily_limit,
      'monthly_limit', 0,
      'active_days_used', _active_days,
      'max_active_days', _settings.free_trial_max_days,
      'trial_completed', _trial_done,
      'subscription_disabled', false
    );
  END IF;
END;
$$;

-- Vérifier que la colonne subscription_disabled existe bien
-- (si elle n'existe pas, l'ajouter)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'app_settings' AND column_name = 'subscription_disabled'
  ) THEN
    ALTER TABLE public.app_settings ADD COLUMN subscription_disabled boolean DEFAULT false;
  END IF;
END $$;
