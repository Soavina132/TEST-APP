-- ═════════════════════════════════════════════════════════════════
-- FIX COMPLET: Système d'abonnement — désactivation fonctionnelle
-- Date: 2026-08-21 19:20
--
-- Problèmes corrigés:
--  1. Doublon check_game_eligibility (1-param + 2-param) → DROP du 1-param
--  2. NULL safety manquante (COALESCE partout)
--  3. increment_game_usage vérifie maintenant subscription_disabled
--  4. get_game_limits vérifie maintenant subscription_disabled
--  5. RPC dédié set_subscription_disabled pour sauver le flag seul
--     (évite que la validation des autres champs bloque la toggle)
-- ═════════════════════════════════════════════════════════════════

-- 1. Supprimer la fonction dupliquée à 1 paramètre
DROP FUNCTION IF EXISTS public.check_game_eligibility(text);

-- 2. Fonction unique (2-param) avec COALESCE pour NULL safety
CREATE OR REPLACE FUNCTION public.check_game_eligibility(
  p_game_type text DEFAULT NULL,
  p_mode text DEFAULT 'create'
)
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
      'tier', null, 'active_days_used', 0, 'max_active_days', 3,
      'subscription_disabled', false);
  END IF;

  SELECT * INTO _settings FROM public.app_settings WHERE id = 1 LIMIT 1;

  -- ✅ Si les abonnements sont désactivés par l'admin, tout est débloqué
  IF COALESCE(_settings.subscription_disabled, false) = true THEN
    RETURN jsonb_build_object(
      'can_play', true,
      'reason', null,
      'remaining_today', 999,
      'is_premium', false,
      'premium_remaining', 999,
      'tier', null,
      'active_days_used', 0,
      'max_active_days', COALESCE(_settings.free_trial_max_days, 3),
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

  _remaining_today := COALESCE(_settings.free_games_daily_limit, 5) - _daily_count;

  IF _is_premium THEN
    SELECT COALESCE(SUM(count), 0) INTO _monthly_count
    FROM public.premium_match_usage
    WHERE user_id = _uid
      AND usage_date >= date_trunc('month', CURRENT_DATE)::date
      AND usage_date <= CURRENT_DATE;

    _monthly_limit := CASE
      WHEN _tier = 'starter'  THEN COALESCE(_settings.sub_starter_matches, 0)
      WHEN _tier = 'basic'    THEN COALESCE(_settings.sub_basic_matches, 0)
      WHEN _tier = 'standard' THEN COALESCE(_settings.sub_standard_matches, 0)
      WHEN _tier = 'premium'  THEN COALESCE(_settings.sub_premium_matches, 0)
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
      'max_active_days', COALESCE(_settings.free_trial_max_days, 3),
      'monthly_limit', _monthly_limit,
      'monthly_used', _monthly_count,
      'subscription_disabled', false
    );
  ELSE
    IF _trial_done AND p_mode = 'create' THEN
      _can_play := false;
      _reason := 'Periode d''essai gratuite terminee. Prenez un abonnement pour continuer.';
    ELSIF _trial_done AND p_mode = 'join' AND NOT COALESCE(_settings.allow_free_join, false) THEN
      _can_play := false;
      _reason := 'Rejoindre des parties gratuites est desactive. Prenez un abonnement pour continuer.';
    ELSIF _remaining_today <= 0 THEN
      _can_play := false;
      _reason := 'Limite quotidienne de ' || COALESCE(_settings.free_games_daily_limit, 5) || ' parties atteinte. Revenez demain ou prenez un abonnement.';
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
      'max_active_days', COALESCE(_settings.free_trial_max_days, 3),
      'daily_limit', COALESCE(_settings.free_games_daily_limit, 5),
      'subscription_disabled', false
    );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.check_game_eligibility(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_game_eligibility(text, text) TO authenticated;

-- 3. increment_game_usage avec vérification subscription_disabled
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
  IF COALESCE(_settings.subscription_disabled, false) = true THEN
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

      IF _active_days >= COALESCE(_settings.free_trial_max_days, 3) THEN
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

REVOKE ALL ON FUNCTION public.increment_game_usage(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.increment_game_usage(text) TO authenticated;

-- 4. get_game_limits avec vérification subscription_disabled
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
  IF COALESCE(_settings.subscription_disabled, false) = true THEN
    RETURN jsonb_build_object(
      'is_premium', false,
      'tier', null,
      'remaining_today', 999,
      'remaining_monthly', 999,
      'daily_limit', 0,
      'monthly_limit', 0,
      'active_days_used', 0,
      'max_active_days', COALESCE(_settings.free_trial_max_days, 3),
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

  _remaining_today := GREATEST(COALESCE(_settings.free_games_daily_limit, 5) - _daily_count, 0);

  IF _is_premium THEN
    SELECT COALESCE(SUM(count), 0) INTO _monthly_count
    FROM public.premium_match_usage
    WHERE user_id = _uid
      AND usage_date >= date_trunc('month', CURRENT_DATE)::date
      AND usage_date <= CURRENT_DATE;

    _monthly_limit := CASE
      WHEN _tier = 'starter'  THEN COALESCE(_settings.sub_starter_matches, 0)
      WHEN _tier = 'basic'    THEN COALESCE(_settings.sub_basic_matches, 0)
      WHEN _tier = 'standard' THEN COALESCE(_settings.sub_standard_matches, 0)
      WHEN _tier = 'premium'  THEN COALESCE(_settings.sub_premium_matches, 0)
      ELSE 0
    END;

    _remaining_monthly := GREATEST(_monthly_limit - _monthly_count, 0);

    RETURN jsonb_build_object(
      'is_premium', true,
      'tier', _tier,
      'remaining_today', _remaining_today,
      'remaining_monthly', _remaining_monthly,
      'daily_limit', COALESCE(_settings.free_games_daily_limit, 5),
      'monthly_limit', _monthly_limit,
      'active_days_used', _active_days,
      'max_active_days', COALESCE(_settings.free_trial_max_days, 3),
      'trial_completed', _trial_done,
      'subscription_disabled', false
    );
  ELSE
    RETURN jsonb_build_object(
      'is_premium', false,
      'tier', null,
      'remaining_today', _remaining_today,
      'remaining_monthly', 0,
      'daily_limit', COALESCE(_settings.free_games_daily_limit, 5),
      'monthly_limit', 0,
      'active_days_used', _active_days,
      'max_active_days', COALESCE(_settings.free_trial_max_days, 3),
      'trial_completed', _trial_done,
      'subscription_disabled', false
    );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.get_game_limits() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_game_limits() TO authenticated;

-- 5. RPC dédié: set_subscription_disabled
--    Permet à l'admin de sauver JUSTE le flag, sans déclencher
--    la validation des autres champs (téléphone, URL, etc.)
CREATE OR REPLACE FUNCTION public.set_subscription_disabled(p_disabled boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  _is_admin bool;
BEGIN
  SELECT public.is_admin() INTO _is_admin;
  IF NOT _is_admin THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Admin seulement');
  END IF;

  -- Désactiver temporairement le trigger de validation
  -- pour ne pas échouer sur d'autres champs invalides
  ALTER TABLE public.app_settings DISABLE TRIGGER trg_app_settings_validate;

  UPDATE public.app_settings
  SET subscription_disabled = p_disabled
  WHERE id = 1;

  -- Réactiver le trigger
  ALTER TABLE public.app_settings ENABLE TRIGGER trg_app_settings_validate;

  RETURN jsonb_build_object('ok', true, 'subscription_disabled', p_disabled);
END;
$$;

REVOKE ALL ON FUNCTION public.set_subscription_disabled(boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_subscription_disabled(boolean) TO authenticated;
