-- ============================================================
-- Contrainte : withdrawal_fee_pct doit être entre 0 et 100
-- ============================================================

ALTER TABLE public.app_settings
  ADD CONSTRAINT chk_withdrawal_fee_pct
  CHECK (withdrawal_fee_pct >= 0 AND withdrawal_fee_pct <= 100);

-- Mettre à jour admin_update_settings pour valider côté SQL aussi
-- (la fonction existante accepte NULL avec COALESCE, on ajoute juste la garde)
CREATE OR REPLACE FUNCTION public.admin_update_settings(
  _admin_phone          TEXT,
  _admin_label          TEXT,
  _signup_bonus         NUMERIC,
  _referral_pct         NUMERIC,
  _game_commission_pct  NUMERIC,
  _min_deposit          NUMERIC,
  _min_withdraw         NUMERIC,
  _mvola_phone          TEXT    DEFAULT NULL,
  _mvola_name           TEXT    DEFAULT NULL,
  _orange_phone         TEXT    DEFAULT NULL,
  _orange_name          TEXT    DEFAULT NULL,
  _airtel_phone         TEXT    DEFAULT NULL,
  _airtel_name          TEXT    DEFAULT NULL,
  _withdrawal_fee_pct   NUMERIC DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;

  -- Validation des frais de retrait
  IF _withdrawal_fee_pct IS NOT NULL AND (_withdrawal_fee_pct < 0 OR _withdrawal_fee_pct > 100) THEN
    RAISE EXCEPTION 'Le pourcentage de frais doit être compris entre 0 et 100';
  END IF;

  UPDATE public.app_settings SET
    admin_phone          = _admin_phone,
    admin_label          = _admin_label,
    signup_bonus         = _signup_bonus,
    referral_pct         = _referral_pct,
    game_commission_pct  = _game_commission_pct,
    min_deposit          = _min_deposit,
    min_withdraw         = _min_withdraw,
    mvola_phone          = COALESCE(_mvola_phone,        mvola_phone),
    mvola_name           = COALESCE(_mvola_name,         mvola_name),
    orange_phone         = COALESCE(_orange_phone,       orange_phone),
    orange_name          = COALESCE(_orange_name,        orange_name),
    airtel_phone         = COALESCE(_airtel_phone,       airtel_phone),
    airtel_name          = COALESCE(_airtel_name,        airtel_name),
    withdrawal_fee_pct   = COALESCE(_withdrawal_fee_pct, withdrawal_fee_pct),
    updated_at           = now()
  WHERE id = 1;
END $$;
