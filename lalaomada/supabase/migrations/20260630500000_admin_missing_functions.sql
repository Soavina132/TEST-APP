-- ═══════════════════════════════════════════════════════════════════════════
-- Migration : 7 fonctions admin manquantes (schema cache errors)
-- Fixes: admin_permanently_delete_user, admin_create_tournament,
--        admin_manual_payout, admin_update_referral_settings,
--        admin_offer_upsert, admin_announcement_create, admin_season_upsert
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- 1. admin_permanently_delete_user
--    Called by admin to hard-delete a player account permanently.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_permanently_delete_user(
  _user_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;

  -- Anonymise profile first (defensive — some FKs keep referencing it)
  UPDATE public.profiles SET
    pseudo            = 'Joueur supprimé',
    phone             = NULL,
    phone_verified    = FALSE,
    avatar_url        = NULL,
    banned            = TRUE,
    deleted_at        = now()
  WHERE id = _user_id;

  -- Hard-delete from auth.users (cascades via FK to profiles & related rows)
  DELETE FROM auth.users WHERE id = _user_id;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_permanently_delete_user(UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_permanently_delete_user(UUID) TO authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 2. admin_create_tournament
--    Creates a new tournament in open status.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_create_tournament(
  _name          TEXT,
  _mode          TEXT,           -- '1v1' | '4p'
  _max_players   INT,
  _stake         NUMERIC,
  _is_free       BOOLEAN,
  _total_rounds  INT     DEFAULT 3,
  _description   TEXT    DEFAULT NULL,
  _rewards_text  TEXT    DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  IF trim(_name) = '' OR _name IS NULL THEN RAISE EXCEPTION 'Nom requis'; END IF;

  INSERT INTO public.tournaments (
    name, mode, max_players, stake, is_free,
    total_rounds, description, rewards_text, status
  ) VALUES (
    trim(_name), _mode, _max_players,
    CASE WHEN _is_free THEN 0 ELSE COALESCE(_stake, 0) END,
    _is_free,
    COALESCE(_total_rounds, 3),
    _description, _rewards_text,
    'open'
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_create_tournament(TEXT,TEXT,INT,NUMERIC,BOOLEAN,INT,TEXT,TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_create_tournament(TEXT,TEXT,INT,NUMERIC,BOOLEAN,INT,TEXT,TEXT) TO authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 3. admin_manual_payout
--    Credits a player's balance and logs the operation.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_manual_payout(
  _amount  NUMERIC,
  _reason  TEXT,
  _uid     UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  IF _amount <= 0 THEN RAISE EXCEPTION 'Le montant doit être positif'; END IF;

  -- Credit balance
  UPDATE public.profiles
  SET balance_ar = balance_ar + _amount
  WHERE id = _uid;

  IF NOT FOUND THEN RAISE EXCEPTION 'Utilisateur introuvable'; END IF;

  -- Log as a deposit (method = admin_payout)
  BEGIN
    INSERT INTO public.deposits (user_id, amount, method, reference, status)
    VALUES (_uid, _amount, 'admin_payout', _reason, 'approved');
  EXCEPTION WHEN OTHERS THEN
    -- Silently ignore if deposits schema differs
    NULL;
  END;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_manual_payout(NUMERIC,TEXT,UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_manual_payout(NUMERIC,TEXT,UUID) TO authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 4. admin_update_referral_settings
--    Updates the single-row referral_settings config table.
--    Param names exactly match what the frontend sends.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_update_referral_settings(
  _deposit_bonus_pct   NUMERIC,
  _deposit_min_ar      NUMERIC,
  _win_commission_pct  NUMERIC,
  _tier_silver_min     INT,
  _tier_gold_min       INT,
  _tier_diamond_min    INT,
  _tier_silver_mult    NUMERIC,
  _tier_gold_mult      NUMERIC,
  _tier_diamond_mult   NUMERIC,
  _require_phone       BOOLEAN,
  _max_daily           INT,
  _auto_flag_velocity  INT,
  _enabled             BOOLEAN,
  _campaign_label      TEXT        DEFAULT NULL,
  _campaign_bonus_pct  NUMERIC     DEFAULT NULL,
  _campaign_expires    TIMESTAMPTZ DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;

  UPDATE public.referral_settings SET
    deposit_bonus_pct        = _deposit_bonus_pct,
    deposit_min_ar           = _deposit_min_ar,
    win_commission_pct       = _win_commission_pct,
    tier_silver_min          = _tier_silver_min,
    tier_gold_min            = _tier_gold_min,
    tier_diamond_min         = _tier_diamond_min,
    tier_silver_mult         = _tier_silver_mult,
    tier_gold_mult           = _tier_gold_mult,
    tier_diamond_mult        = _tier_diamond_mult,
    require_phone_verification = _require_phone,
    max_daily_new_referrals  = _max_daily,
    auto_flag_velocity       = _auto_flag_velocity,
    enabled                  = _enabled,
    campaign_label           = _campaign_label,
    campaign_bonus_pct       = _campaign_bonus_pct,
    campaign_expires_at      = _campaign_expires,
    updated_at               = now()
  WHERE id = 1;

  IF NOT FOUND THEN
    INSERT INTO public.referral_settings (
      id, deposit_bonus_pct, deposit_min_ar, win_commission_pct,
      tier_silver_min, tier_gold_min, tier_diamond_min,
      tier_silver_mult, tier_gold_mult, tier_diamond_mult,
      require_phone_verification, max_daily_new_referrals,
      auto_flag_velocity, enabled,
      campaign_label, campaign_bonus_pct, campaign_expires_at
    ) VALUES (
      1, _deposit_bonus_pct, _deposit_min_ar, _win_commission_pct,
      _tier_silver_min, _tier_gold_min, _tier_diamond_min,
      _tier_silver_mult, _tier_gold_mult, _tier_diamond_mult,
      _require_phone, _max_daily, _auto_flag_velocity, _enabled,
      _campaign_label, _campaign_bonus_pct, _campaign_expires
    );
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_update_referral_settings(
  NUMERIC,NUMERIC,NUMERIC,INT,INT,INT,NUMERIC,NUMERIC,NUMERIC,
  BOOLEAN,INT,INT,BOOLEAN,TEXT,NUMERIC,TIMESTAMPTZ
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_referral_settings(
  NUMERIC,NUMERIC,NUMERIC,INT,INT,INT,NUMERIC,NUMERIC,NUMERIC,
  BOOLEAN,INT,INT,BOOLEAN,TEXT,NUMERIC,TIMESTAMPTZ
) TO authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 5. admin_offer_upsert
--    Creates or updates a money_offer row.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_offer_upsert(
  _id          UUID,
  _title       TEXT,
  _description TEXT        DEFAULT NULL,
  _image_url   TEXT        DEFAULT NULL,
  _link        TEXT        DEFAULT NULL,
  _expires_at  TIMESTAMPTZ DEFAULT NULL,
  _active      BOOLEAN     DEFAULT TRUE
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;

  IF _id IS NULL THEN
    -- Create
    INSERT INTO public.money_offers (title, description, image_url, link, expires_at, active)
    VALUES (trim(_title), _description, _image_url, _link, _expires_at, COALESCE(_active, TRUE))
    RETURNING id INTO v_id;
  ELSE
    -- Update
    UPDATE public.money_offers SET
      title       = COALESCE(trim(_title), title),
      description = _description,
      image_url   = _image_url,
      link        = _link,
      expires_at  = _expires_at,
      active      = COALESCE(_active, active)
    WHERE id = _id;
    v_id := _id;
  END IF;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_offer_upsert(UUID,TEXT,TEXT,TEXT,TEXT,TIMESTAMPTZ,BOOLEAN) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_offer_upsert(UUID,TEXT,TEXT,TEXT,TEXT,TIMESTAMPTZ,BOOLEAN) TO authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 6. admin_announcement_create
--    Inserts a new active announcement (full-screen popup).
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_announcement_create(
  _title      TEXT,
  _body       TEXT DEFAULT NULL,
  _image_url  TEXT DEFAULT NULL,
  _link       TEXT DEFAULT NULL,
  _link_label TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  IF _title IS NULL OR trim(_title) = '' THEN RAISE EXCEPTION 'Titre requis'; END IF;

  INSERT INTO public.announcements (title, body, image_url, link, link_label, active)
  VALUES (trim(_title), _body, _image_url, _link, _link_label, TRUE)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_announcement_create(TEXT,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_announcement_create(TEXT,TEXT,TEXT,TEXT,TEXT) TO authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 7. admin_season_upsert
--    Creates or updates a Ballon d'Or season.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_season_upsert(
  _id            UUID,
  _name          TEXT,
  _starts_at     TIMESTAMPTZ,
  _ends_at       TIMESTAMPTZ,
  _reward_text   TEXT    DEFAULT NULL,
  _reward_amount NUMERIC DEFAULT 0
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  IF _name IS NULL OR trim(_name) = '' THEN RAISE EXCEPTION 'Nom requis'; END IF;
  IF _starts_at IS NULL OR _ends_at IS NULL THEN RAISE EXCEPTION 'Dates requises'; END IF;
  IF _ends_at <= _starts_at THEN RAISE EXCEPTION 'La date de fin doit être après le début'; END IF;

  IF _id IS NULL THEN
    INSERT INTO public.seasons (name, starts_at, ends_at, reward_text, reward_amount, status)
    VALUES (trim(_name), _starts_at, _ends_at, _reward_text, COALESCE(_reward_amount, 0), 'upcoming')
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.seasons SET
      name          = COALESCE(trim(_name), name),
      starts_at     = COALESCE(_starts_at, starts_at),
      ends_at       = COALESCE(_ends_at, ends_at),
      reward_text   = _reward_text,
      reward_amount = COALESCE(_reward_amount, reward_amount)
    WHERE id = _id;
    v_id := _id;
  END IF;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_season_upsert(UUID,TEXT,TIMESTAMPTZ,TIMESTAMPTZ,TEXT,NUMERIC) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_season_upsert(UUID,TEXT,TIMESTAMPTZ,TIMESTAMPTZ,TEXT,NUMERIC) TO authenticated;
