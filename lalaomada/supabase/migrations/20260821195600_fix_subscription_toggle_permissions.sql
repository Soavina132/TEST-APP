-- ============================================================
-- Migration: Fix "Désactiver les abonnements" checkbox not working
-- Date: 2026-08-21
--
-- Problème: L'admin coche "Désactiver les abonnements" dans /admin,
-- clique Enregistrer, mais rien ne se passe — la valeur reste false
-- en base et aucun effet visible.
--
-- Cause racine (2 bugs cumulés):
-- 1. RLS: la table app_settings n'avait qu'une policy SELECT, pas
--    de policy UPDATE/INSERT → tout UPDATE depuis le client (rôle
--    "authenticated") était silencieusement bloqué par RLS.
-- 2. GRANT: même après avoir ajouté la policy UPDATE, un trigger
--    de validation (_app_settings_validate_trigger) appelle la
--    fonction _validate_app_settings(), qui elle-même appelle
--    _is_valid_mg_phone/_is_valid_email/_is_valid_http_url.
--    Aucune de ces fonctions n'avait de GRANT EXECUTE pour le rôle
--    "authenticated" (seulement service_role/postgres) → l'UPDATE
--    échouait avec "permission denied for function
--    _validate_app_settings".
-- 3. Bonus: la fonction RPC check_game_eligibility(p_game_type,
--    p_mode) — celle réellement utilisée pour bloquer/autoriser
--    la création/jointure de partie — ne vérifiait PAS le flag
--    subscription_disabled (seule la variante à 1 paramètre, non
--    utilisée pour la vérification réelle, le faisait).
--
-- Fix:
-- - RLS UPDATE/INSERT pour les admins sur app_settings
-- - GRANT EXECUTE sur les fonctions de validation pour "authenticated"
-- - check_game_eligibility(p_game_type, p_mode) court-circuite
--   maintenant toutes les limites quand subscription_disabled = true
-- ============================================================

-- 1. RLS: autoriser les admins à modifier app_settings
DROP POLICY IF EXISTS "settings_update_admin" ON public.app_settings;
CREATE POLICY "settings_update_admin" ON public.app_settings
  FOR UPDATE
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "settings_insert_admin" ON public.app_settings;
CREATE POLICY "settings_insert_admin" ON public.app_settings
  FOR INSERT
  WITH CHECK (public.is_admin());

-- 2. GRANT: le trigger de validation doit pouvoir s'exécuter pour
--    n'importe quel utilisateur authentifié qui update la ligne
--    (le trigger tourne avec les droits de l'appelant, pas en
--    SECURITY DEFINER)
GRANT EXECUTE ON FUNCTION public._validate_app_settings(app_settings) TO authenticated;
GRANT EXECUTE ON FUNCTION public._is_valid_mg_phone(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public._is_valid_email(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public._is_valid_http_url(text) TO authenticated;

-- 3. check_game_eligibility(p_game_type, p_mode): ajouter le
--    court-circuit subscription_disabled (manquant dans cette
--    variante, présent seulement dans la variante à 1 paramètre)
CREATE OR REPLACE FUNCTION public.check_game_eligibility(p_game_type text DEFAULT NULL::text, p_mode text DEFAULT 'create'::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
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
      'tier', null, 'active_days_used', 0, 'max_active_days', 3);
  END IF;

  SELECT * INTO _settings FROM public.app_settings WHERE id = 1 LIMIT 1;

  -- Si le système d'abonnement est désactivé, tout le monde joue sans limite
  IF _settings.subscription_disabled = true THEN
    RETURN jsonb_build_object('can_play', true, 'reason', null,
      'remaining_today', 999, 'is_premium', true, 'premium_remaining', 999,
      'tier', 'all', 'active_days_used', 0, 'max_active_days', _settings.free_trial_max_days);
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
      WHEN _tier = 'starter' THEN _settings.sub_starter_matches
      WHEN _tier = 'basic' THEN _settings.sub_basic_matches
      WHEN _tier = 'standard' THEN _settings.sub_standard_matches
      WHEN _tier = 'premium' THEN _settings.sub_premium_matches
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
    IF _trial_done AND p_mode = 'create' THEN
      _can_play := false;
      _reason := 'Periode d''essai gratuite terminee. Prenez un abonnement pour continuer.';
    ELSIF _trial_done AND p_mode = 'join' AND NOT _settings.allow_free_join THEN
      _can_play := false;
      _reason := 'Rejoindre des parties gratuites est desactive. Prenez un abonnement pour continuer.';
    ELSIF _remaining_today <= 0 THEN
      _can_play := false;
      _reason := 'Limite quotidienne de ' || _settings.free_games_daily_limit || ' parties atteinte. Revenez demain ou prenez un abonnement.';
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
$function$;
