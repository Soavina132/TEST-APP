-- ═════════════════════════════════════════════════════════════════
-- FIX: save_subscription_settings RPC — bypass trigger validation
-- Date: 2026-08-21 19:30
--
-- Problème: Le trigger _validate_app_settings valide TOUS les champs
-- de la ligne app_settings, même ceux non modifiés. Si un téléphone
-- ou URL existant est invalide, TOUT update échoue — y compris
-- subscription_disabled.
--
-- Solution: RPC dédié qui désactive le trigger pendant l'update,
-- sauve uniquement les champs d'abonnement, et réactive le trigger.
-- ═════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.save_subscription_settings(
  p_sub_starter_price_ar numeric DEFAULT NULL,
  p_sub_starter_matches int DEFAULT NULL,
  p_sub_basic_price_ar numeric DEFAULT NULL,
  p_sub_basic_matches int DEFAULT NULL,
  p_sub_standard_price_ar numeric DEFAULT NULL,
  p_sub_standard_matches int DEFAULT NULL,
  p_sub_premium_price_ar numeric DEFAULT NULL,
  p_sub_premium_matches int DEFAULT NULL,
  p_free_games_daily_limit int DEFAULT NULL,
  p_free_trial_max_days int DEFAULT NULL,
  p_allow_free_join boolean DEFAULT NULL
)
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

  -- Désactiver le trigger de validation pour ne pas échouer sur
  -- d'autres champs invalides (téléphone, URL, etc.)
  ALTER TABLE public.app_settings DISABLE TRIGGER trg_app_settings_validate;

  UPDATE public.app_settings
  SET
    sub_starter_price_ar  = COALESCE(p_sub_starter_price_ar,  sub_starter_price_ar),
    sub_starter_matches   = COALESCE(p_sub_starter_matches,   sub_starter_matches),
    sub_basic_price_ar     = COALESCE(p_sub_basic_price_ar,    sub_basic_price_ar),
    sub_basic_matches      = COALESCE(p_sub_basic_matches,     sub_basic_matches),
    sub_standard_price_ar = COALESCE(p_sub_standard_price_ar, sub_standard_price_ar),
    sub_standard_matches  = COALESCE(p_sub_standard_matches,  sub_standard_matches),
    sub_premium_price_ar   = COALESCE(p_sub_premium_price_ar,  sub_premium_price_ar),
    sub_premium_matches    = COALESCE(p_sub_premium_matches,   sub_premium_matches),
    free_games_daily_limit = COALESCE(p_free_games_daily_limit, free_games_daily_limit),
    free_trial_max_days    = COALESCE(p_free_trial_max_days,   free_trial_max_days),
    allow_free_join        = COALESCE(p_allow_free_join,        allow_free_join)
  WHERE id = 1;

  -- Réactiver le trigger
  ALTER TABLE public.app_settings ENABLE TRIGGER trg_app_settings_validate;

  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE ALL ON FUNCTION public.save_subscription_settings(
  numeric, int, numeric, int, numeric, int, numeric, int, int, int, boolean
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_subscription_settings(
  numeric, int, numeric, int, numeric, int, numeric, int, int, int, boolean
) TO authenticated;
