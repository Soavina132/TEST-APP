-- === admin_announcement_delete ===
CREATE OR REPLACE FUNCTION public.admin_announcement_delete(_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  DELETE FROM public.announcements WHERE id = _id;
END;
$$;GRANT EXECUTE ON FUNCTION public.admin_announcement_delete(UUID) TO authenticated;

-- === admin_banner_delete ===
CREATE OR REPLACE FUNCTION public.admin_banner_delete(_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  DELETE FROM public.banners WHERE id = _id;
END;
$$;GRANT  EXECUTE ON FUNCTION public.admin_banner_delete(UUID) TO authenticated;

-- === admin_banner_upsert ===
CREATE OR REPLACE FUNCTION public.admin_banner_upsert(
  _id          UUID,
  _title       TEXT,
  _subtitle    TEXT        DEFAULT NULL,
  _image_url   TEXT        DEFAULT NULL,
  _button_text TEXT        DEFAULT NULL,
  _button_link TEXT        DEFAULT NULL,
  _bg_gradient TEXT        DEFAULT NULL,
  _starts_at   TIMESTAMPTZ DEFAULT NULL,
  _ends_at     TIMESTAMPTZ DEFAULT NULL,
  _active      BOOLEAN     DEFAULT TRUE,
  _sort_order  INT         DEFAULT 0
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;

  IF _id IS NULL THEN
    INSERT INTO public.banners (title, subtitle, image_url, button_text, button_link, bg_gradient, starts_at, ends_at, active, sort_order)
    VALUES (trim(_title), _subtitle, _image_url, _button_text, _button_link, _bg_gradient, _starts_at, _ends_at, COALESCE(_active, TRUE), COALESCE(_sort_order, 0))
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.banners SET
      title       = COALESCE(trim(_title), title),
      subtitle    = _subtitle,
      image_url   = _image_url,
      button_text = _button_text,
      button_link = _button_link,
      bg_gradient = _bg_gradient,
      starts_at   = _starts_at,
      ends_at     = _ends_at,
      active      = COALESCE(_active, active),
      sort_order  = COALESCE(_sort_order, sort_order),
      updated_at  = now()
    WHERE id = _id;
    v_id := _id;
  END IF;

  RETURN v_id;
END;
$$;GRANT  EXECUTE ON FUNCTION public.admin_banner_upsert(UUID,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TIMESTAMPTZ,TIMESTAMPTZ,BOOLEAN,INT) TO authenticated;

-- === admin_get_bot_config ===
CREATE OR REPLACE FUNCTION public.admin_get_bot_config(_participant_id uuid)
RETURNS TABLE(intelligence int, win_bias int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  RETURN QUERY
    SELECT bot_intelligence, bot_win_bias
    FROM public.ludo_participants
    WHERE id = _participant_id AND is_bot = true;
END $$;GRANT EXECUTE ON FUNCTION public.admin_get_bot_config(uuid) TO authenticated;

-- === admin_rename_bot ===
CREATE OR REPLACE FUNCTION public.admin_rename_bot(_participant_id UUID, _name TEXT)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  UPDATE public.ludo_participants SET bot_name=_name, display_name=_name
    WHERE id=_participant_id AND is_bot=TRUE;
END $$;

-- === admin_season_close ===
CREATE OR REPLACE FUNCTION public.admin_season_close(_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  UPDATE public.seasons
    SET status = 'closed', ended_at = COALESCE(ended_at, now())
    WHERE id = _id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Saison introuvable'; END IF;
END;
$$;GRANT EXECUTE ON FUNCTION public.admin_season_close(UUID) TO authenticated;

-- === admin_season_upsert ===
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
$$;GRANT  EXECUTE ON FUNCTION public.admin_season_upsert(UUID,TEXT,TIMESTAMPTZ,TIMESTAMPTZ,TEXT,NUMERIC) TO authenticated;

-- === admin_set_pin ===
CREATE OR REPLACE FUNCTION public.admin_set_pin(_pin TEXT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  IF length(_pin) < 4 THEN RAISE EXCEPTION 'PIN trop court (min 4 caractères)'; END IF;
  UPDATE public.app_settings
    SET admin_pin_hash = encode(digest(_pin || 'lalao_mada_salt_2026', 'sha256'), 'hex'),
        admin_failed_attempts = 0,
        admin_locked_until = NULL
    WHERE id = 1;
END $$;REVOKE EXECUTE ON FUNCTION public.admin_set_pin(TEXT) FROM anon;

-- === admin_update_bot ===
CREATE OR REPLACE FUNCTION public.admin_update_bot(_participant_id UUID, _intelligence INT, _win_bias INT)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  UPDATE public.ludo_participants SET
    bot_intelligence=GREATEST(0,LEAST(100,_intelligence)),
    bot_win_bias=GREATEST(0,LEAST(100,_win_bias))
    WHERE id=_participant_id AND is_bot=TRUE;
END $$;

-- === admin_verify_pin ===
CREATE OR REPLACE FUNCTION public.admin_verify_pin(_pin TEXT)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid          UUID := auth.uid();
  v_is_admin     BOOLEAN;
  v_stored       TEXT;
  v_input_hash   TEXT;
  v_attempts     INT;
  v_locked_until TIMESTAMPTZ;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT public.is_admin() INTO v_is_admin;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT admin_pin_hash, admin_failed_attempts, admin_locked_until
    INTO v_stored, v_attempts, v_locked_until
  FROM public.app_settings WHERE id = 1;

  -- Si aucun PIN configuré, on autorise (première configuration)
  IF v_stored IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'reason', 'no_pin_set');
  END IF;

  -- Vérifier le lockout
  IF v_locked_until IS NOT NULL AND v_locked_until > now() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'locked',
      'locked_until', v_locked_until);
  END IF;

  -- Hasher l'input (SHA-256 + sel)
  v_input_hash := encode(digest(_pin || 'lalao_mada_salt_2026', 'sha256'), 'hex');

  IF v_input_hash = v_stored THEN
    UPDATE public.app_settings SET admin_failed_attempts = 0, admin_locked_until = NULL WHERE id = 1;
    RETURN jsonb_build_object('ok', true);
  ELSE
    v_attempts := COALESCE(v_attempts, 0) + 1;
    IF v_attempts >= 5 THEN
      UPDATE public.app_settings
        SET admin_failed_attempts = v_attempts,
            admin_locked_until = now() + interval '15 minutes'
        WHERE id = 1;
      RETURN jsonb_build_object('ok', false, 'reason', 'locked',
        'locked_until', now() + interval '15 minutes');
    ELSE
      UPDATE public.app_settings SET admin_failed_attempts = v_attempts WHERE id = 1;
      RETURN jsonb_build_object('ok', false, 'reason', 'wrong_pin',
        'attempts', v_attempts, 'remaining', 5 - v_attempts);
    END IF;
  END IF;
END $$;REVOKE EXECUTE ON FUNCTION public.admin_verify_pin(TEXT) FROM anon;

-- === check_game_eligibility ===
CREATE OR REPLACE FUNCTION public.check_game_eligibility(p_game_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
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
    IF _trial_done THEN
      _can_play := false;
      _reason := 'Periode d''essai gratuite terminee. Prenez un abonnement pour continuer.';
    ELSIF _remaining_today <= 0 THEN
      _can_play := false;
      _reason := 'Limite quotidienne de 10 parties atteinte. Revenez demain ou prenez un abonnement.';
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

-- === create_deposit ===
CREATE OR REPLACE FUNCTION public.create_deposit(
  _amount numeric,
  _method text,
  _user_phone text DEFAULT NULL,
  _user_reference text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_deposit_id uuid;
  v_last_deposit timestamptz;
  v_pending_count int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _amount IS NULL OR _amount <= 0 THEN RAISE EXCEPTION 'Montant invalide'; END IF;
  IF _method IS NULL THEN RAISE EXCEPTION 'Méthode requise'; END IF;
  IF _user_phone IS NULL OR length(trim(_user_phone)) < 8 THEN
    RAISE EXCEPTION 'Numéro de téléphone requis';
  END IF;
  IF _user_reference IS NULL OR length(trim(_user_reference)) < 3 THEN
    RAISE EXCEPTION 'Référence de transaction requise (Ref pour MVola, Trans ID pour Orange Money)';
  END IF;

  -- 1 seule demande par 5 minutes
  SELECT max(created_at) INTO v_last_deposit
    FROM public.deposits
    WHERE user_id = v_uid;
  IF v_last_deposit IS NOT NULL AND now() - v_last_deposit < interval '5 minutes' THEN
    RAISE EXCEPTION 'Vous ne pouvez faire qu''une seule demande de dépôt toutes les 5 minutes.';
  END IF;

  -- Max 3 dépôts en attente (aligné avec le trigger)
  SELECT count(*) INTO v_pending_count
    FROM public.deposits
    WHERE user_id = v_uid AND status = 'pending';
  IF v_pending_count >= 3 THEN
    RAISE EXCEPTION 'Vous avez trop de dépôts en attente. Attendez leur validation.';
  END IF;

  INSERT INTO public.deposits(user_id, amount, method, user_phone, user_reference, status, reference)
    VALUES (v_uid, _amount, _method, trim(_user_phone), trim(_user_reference),
            'pending'::public.tx_status, 'deposit_' || gen_random_uuid()::text)
    RETURNING id INTO v_deposit_id;

  RETURN v_deposit_id;
END $$;REVOKE EXECUTE ON FUNCTION public.create_deposit(NUMERIC, TEXT, TEXT, TEXT) FROM anon;

-- === create_withdrawal ===
CREATE OR REPLACE FUNCTION public.create_withdrawal(
  _amount              NUMERIC,
  _method              TEXT,
  _bank_name           TEXT DEFAULT NULL,
  _bank_account_number TEXT DEFAULT NULL,
  _phone_number        TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid            UUID := auth.uid();
  v_balance        NUMERIC;
  v_min_withdraw   NUMERIC;
  v_pending_count  INT;
  v_withdrawal_id  UUID;
  v_method         TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _amount IS NULL OR _amount <= 0 THEN RAISE EXCEPTION 'Montant invalide'; END IF;
  IF _method IS NULL OR length(trim(_method)) = 0 THEN RAISE EXCEPTION 'Méthode requise'; END IF;

  v_method := lower(trim(_method));

  -- Valider selon la méthode
  IF v_method = 'bank' THEN
    IF _bank_name IS NULL OR length(trim(_bank_name)) = 0 THEN
      RAISE EXCEPTION 'Nom de la banque requis';
    END IF;
    IF _bank_account_number IS NULL OR length(trim(_bank_account_number)) = 0 THEN
      RAISE EXCEPTION 'Numéro de compte bancaire requis';
    END IF;
  ELSE
    IF _phone_number IS NULL OR length(trim(_phone_number)) < 8 THEN
      RAISE EXCEPTION 'Numéro de téléphone requis';
    END IF;
  END IF;

  -- Rate limit: max 3 retraits en attente
  SELECT count(*) INTO v_pending_count FROM public.withdrawals
  WHERE user_id = v_uid AND status = 'pending';
  IF v_pending_count >= 3 THEN
    RAISE EXCEPTION 'Trop de retraits en attente (max 3)';
  END IF;

  -- Vérifier le minimum
  SELECT min_withdraw INTO v_min_withdraw FROM public.app_settings WHERE id = 1;
  IF v_min_withdraw IS NOT NULL AND _amount < v_min_withdraw THEN
    RAISE EXCEPTION 'Montant minimum: % Ar', v_min_withdraw;
  END IF;

  -- Vérifier le solde AVEC verrou (Bug 3 fix: on débite immédiatement)
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance IS NULL THEN RAISE EXCEPTION 'Profil introuvable'; END IF;
  IF v_balance < _amount THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  -- RÉSERVER le montant: débit immédiat (Bug 3 fix)
  UPDATE public.profiles SET balance_ar = balance_ar - _amount WHERE id = v_uid;

  -- Insérer la demande de retrait
  INSERT INTO public.withdrawals(
    user_id, amount, method, user_phone, status,
    recipient_name, bank_name, bank_account_number
  )
  VALUES(
    v_uid, _amount, v_method,
    CASE WHEN v_method = 'bank' THEN NULL ELSE trim(_phone_number) END,
    'pending'::public.tx_status,
    NULL,
    CASE WHEN v_method = 'bank' THEN trim(_bank_name) ELSE NULL END,
    CASE WHEN v_method = 'bank' THEN trim(_bank_account_number) ELSE NULL END
  )
  RETURNING id INTO v_withdrawal_id;

  -- Logger la transaction
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
  VALUES(v_uid, 'withdraw', -_amount, v_withdrawal_id, 'Retrait demandé (solde réservé)');

  RETURN v_withdrawal_id;
END $$;REVOKE EXECUTE ON FUNCTION public.create_withdrawal(NUMERIC, TEXT, TEXT, TEXT, TEXT) FROM anon;

-- === disable_totp ===
CREATE OR REPLACE FUNCTION public.disable_totp()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  DELETE FROM public.user_totp_secrets WHERE user_id = auth.uid();
  UPDATE public.profiles SET two_factor_enabled = false WHERE id = auth.uid();
END $$;GRANT EXECUTE ON FUNCTION public.disable_totp() TO authenticated;

-- === fanorona_create_solo ===
CREATE OR REPLACE FUNCTION public.fanorona_create_solo(
  _stake numeric DEFAULT 0,
  _variant text DEFAULT 'tsivy',
  _mandatory_capture boolean DEFAULT true,
  _bot_intelligence int DEFAULT 3
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
  v_name text;
  v_cols int; v_rows int;
  v_bot_name text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'invalid stake'; END IF;
  CASE _variant
    WHEN 'telo'  THEN v_cols := 3; v_rows := 3;
    WHEN 'dimy'  THEN v_cols := 5; v_rows := 5;
    WHEN 'tsivy' THEN v_cols := 9; v_rows := 5;
    ELSE v_cols := 9; v_rows := 5; _variant := 'tsivy';
  END CASE;
  SELECT pseudo INTO v_name FROM public.profiles WHERE id = v_uid;
  v_bot_name := CASE _bot_intelligence WHEN 1 THEN 'Debutant' WHEN 2 THEN 'Amateur' WHEN 3 THEN 'Confirme' WHEN 4 THEN 'Expert' ELSE 'Maitre' END;
  INSERT INTO public.fanorona_games(host_id, max_players, stake, pot, commission_pct, is_private, room_code,
    state, cols, rows, variant, mandatory_capture, bot_intelligence, status, started_at)
  VALUES (v_uid, 2, 0, 0, 0, true, null,
    jsonb_build_object('phase','playing','board', public._fanorona_init_board(v_cols, v_rows),'chain_from',null,'chain_dirs','[]'::jsonb,'move_count',0,'visited','[]'::jsonb,'last_axis',null),
    v_cols, v_rows, _variant, COALESCE(_mandatory_capture, true), COALESCE(_bot_intelligence, 3), 'playing', now())
  RETURNING id INTO v_id;
  INSERT INTO public.fanorona_participants(game_id, user_id, slot, color, display_name, is_bot)
  VALUES (v_id, v_uid, 0, 'white', COALESCE(v_name, 'Joueur'), false);
  INSERT INTO public.fanorona_participants(game_id, user_id, slot, color, display_name, is_bot, bot_intelligence)
  VALUES (v_id, NULL, 1, 'black', 'Bot ' || v_bot_name, true, COALESCE(_bot_intelligence, 3));
  UPDATE public.fanorona_games SET current_turn = 0,
    turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')), 60) || ' seconds')::interval
    WHERE id = v_id;
  RETURN v_id;
END $$;

-- === get_game_limits ===
CREATE OR REPLACE FUNCTION public.get_game_limits()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
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
      WHEN _tier = 'basic' THEN _settings.sub_basic_matches
      WHEN _tier = 'standard' THEN _settings.sub_standard_matches
      WHEN _tier = 'premium' THEN _settings.sub_premium_matches
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

-- === get_pending_phone_verification ===
CREATE OR REPLACE FUNCTION public.get_pending_phone_verification()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_uid uuid := auth.uid();
  v_phone text; v_code text; v_requested timestamptz;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  
  SELECT phone, phone_verification_code, phone_verification_requested_at
    INTO v_phone, v_code, v_requested
    FROM public.profiles WHERE id = v_uid;
  
  IF v_code IS NULL THEN
    RETURN jsonb_build_object('pending', false);
  END IF;
  
  -- Expiration: 10 minutes
  IF v_requested IS NULL OR v_requested < now() - interval '10 minutes' THEN
    UPDATE public.profiles 
      SET phone_verification_code = NULL, phone_verification_requested_at = NULL
      WHERE id = v_uid AND phone_verified = false;
    RETURN jsonb_build_object('pending', false, 'expired', true);
  END IF;
  
  RETURN jsonb_build_object(
    'pending', true,
    'phone', v_phone,
    'code', v_code,
    'requested_at', to_char(v_requested AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'expires_at', to_char((v_requested + interval '10 minutes') AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  );
END $$;REVOKE EXECUTE ON FUNCTION public.get_pending_phone_verification() FROM anon;

-- === increment_game_usage ===
CREATE OR REPLACE FUNCTION public.increment_game_usage(p_game_type text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
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
    -- Track premium monthly usage (all types combined via 'all' key)
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
    -- Free user: track per game type, but limit is across all types
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

    -- If first game of the day, increment active days
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

-- === ludo_bot_play ===
CREATE OR REPLACE FUNCTION public.ludo_bot_play(_game_id UUID)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_slot INT; v_isbot BOOLEAN;
  v_intel INT; v_bias INT; v_dice INT; arr jsonb; pawn jsonb;
  i INT; k INT; best INT := -1; best_score INT := -1; sc INT;
  pstate TEXT; pstep INT; abs_cell INT; start_idx INT;
  other_slot INT; op jsonb; op_step INT; op_start INT; would_capture BOOLEAN;
  candidates INT[] := ARRAY[]::INT[];
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;
  SELECT is_bot, bot_intelligence, bot_win_bias INTO v_isbot, v_intel, v_bias
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot THEN RETURN st; END IF;

  IF NOT (st->>'must_move')::BOOLEAN THEN
    v_dice := 1 + (floor(random()*6))::INT;
    IF COALESCE(v_bias,0) > 0 AND (random()*100) < v_bias THEN v_dice := 6; END IF;
    st := jsonb_set(st,'{dice}', to_jsonb(v_dice));
    st := jsonb_set(st,'{must_move}','true'::jsonb);
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('bot_roll:'||v_dice));
    UPDATE public.ludo_games SET state=st WHERE id=_game_id;
  ELSE
    v_dice := (st->>'dice')::INT;
  END IF;

  arr := st->'pawns'->v_slot::text;
  start_idx := public._ludo_start_idx(v_slot);
  FOR i IN 0..3 LOOP
    pawn := arr->i; pstate := pawn->>'s'; pstep := (pawn->>'k')::INT;
    IF pstate='finished' THEN CONTINUE; END IF;
    IF pstate='yard' THEN
      IF v_dice = 6 THEN candidates := candidates || i; END IF;
    ELSE
      IF pstep + v_dice <= 56 THEN candidates := candidates || i; END IF;
    END IF;
  END LOOP;

  IF array_length(candidates,1) IS NULL THEN
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('bot:pass'));
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
    RETURN st;
  END IF;

  IF (random()*100) < COALESCE(v_intel,70) THEN
    FOREACH i IN ARRAY candidates LOOP
      pawn := arr->i; pstate := pawn->>'s'; pstep := (pawn->>'k')::INT;
      IF pstate='yard' THEN sc := 60;
      ELSIF pstep + v_dice = 56 THEN sc := 80;
      ELSE
        would_capture := FALSE;
        IF pstep + v_dice <= 50 THEN
          abs_cell := (start_idx + pstep + v_dice) % 52;
          IF NOT public._ludo_is_safe(abs_cell) THEN
            FOR other_slot IN 0..g.max_players-1 LOOP
              IF other_slot <> v_slot THEN
                op_start := public._ludo_start_idx(other_slot);
                FOR k IN 0..3 LOOP
                  op := st->'pawns'->other_slot::text->k;
                  IF op->>'s' = 'track' THEN
                    op_step := (op->>'k')::INT;
                    IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
                      would_capture := TRUE;
                    END IF;
                  END IF;
                END LOOP;
              END IF;
            END LOOP;
          END IF;
        END IF;
        sc := pstep + v_dice + CASE WHEN would_capture THEN 100 ELSE 0 END;
      END IF;
      IF sc > best_score THEN best_score := sc; best := i; END IF;
    END LOOP;
  ELSE
    best := candidates[1 + (floor(random()*array_length(candidates,1)))::INT];
  END IF;

  RETURN public.ludo_move(_game_id, best);
END $$;

-- === ludo_join_team ===
CREATE OR REPLACE FUNCTION public.ludo_join_team(_game_id uuid, _team int)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_game public.ludo_games%ROWTYPE;
  v_count int;
  v_existing_team int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _team NOT IN (1, 2) THEN RAISE EXCEPTION 'Équipe invalide (1 ou 2)'; END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_game.status NOT IN ('open', 'waiting') THEN RAISE EXCEPTION 'Partie déjà commencée'; END IF;
  IF v_game.match_type <> 'groupe' THEN RAISE EXCEPTION 'Cette partie n''est pas en mode groupe'; END IF;

  -- Check player is a participant
  SELECT team INTO v_existing_team FROM public.ludo_participants
    WHERE game_id=_game_id AND user_id=v_uid;
  IF v_existing_team IS NULL THEN RAISE EXCEPTION 'Non participant'; END IF;

  -- Check team isn't full (max 2 per team)
  SELECT count(*) INTO v_count FROM public.ludo_participants
    WHERE game_id=_game_id AND team=_team;
  IF v_count >= 2 AND v_existing_team <> _team THEN
    RAISE EXCEPTION 'Groupe % complet', _team;
  END IF;

  -- Update team
  UPDATE public.ludo_participants SET team=_team
    WHERE game_id=_game_id AND user_id=v_uid;
END $function$;GRANT EXECUTE ON FUNCTION public.ludo_join_team(uuid, int) TO authenticated;

-- === poker_create ===
CREATE OR REPLACE FUNCTION public.poker_create(
  _stake numeric, _max int DEFAULT 6, _private boolean DEFAULT false, _commission numeric DEFAULT 10
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_gid uuid;
  v_code text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _max < 2 OR _max > 9 THEN RAISE EXCEPTION 'Nombre de joueurs invalide (2-9)'; END IF;
  -- Check balance
  IF _stake > 0 AND (SELECT balance_ar FROM public.profiles WHERE id=v_uid) < _stake THEN
    RAISE EXCEPTION 'Solde insuffisant';
  END IF;
  -- Deduct stake
  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar=balance_ar-_stake WHERE id=v_uid;
    INSERT INTO public.transactions(user_id,type,amount,note) VALUES(v_uid,'stake',-_stake,'Mise Poker');
  END IF;
  -- Generate code
  IF _private THEN v_code := upper(substring(md5(random()::text),1,6)); END IF;
  -- Create game
  INSERT INTO public.poker_games(stake,commission_pct,max_players,is_private,room_code,created_by,state)
  VALUES(_stake,_commission,_max,_private,v_code,v_uid,'{}')
  RETURNING id INTO v_gid;
  -- Add creator as player (seat 0)
  DECLARE v_chips numeric := GREATEST(_stake * 100, 10000);
  BEGIN
    INSERT INTO public.poker_players(game_id,user_id,seat,chips,status,is_ready)
    VALUES(v_gid,v_uid,0,v_chips,'waiting',false);
  END;
  RETURN v_gid;
END;
$$;GRANT EXECUTE ON FUNCTION public.poker_create TO authenticated;

-- === poker_request_refund ===
CREATE OR REPLACE FUNCTION public.poker_request_refund(_game_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_uid uuid := auth.uid();
  g public.poker_games%ROWTYPE;
  cnt int;
BEGIN
  SELECT * INTO g FROM public.poker_games WHERE id=_game_id FOR UPDATE;
  IF g.status != 'waiting' THEN RAISE EXCEPTION 'Remboursement impossible'; END IF;
  IF g.created_by != v_uid THEN RAISE EXCEPTION 'Seul le créateur peut annuler'; END IF;
  SELECT count(*) INTO cnt FROM public.poker_players WHERE game_id=_game_id;
  IF cnt > 1 THEN RAISE EXCEPTION 'Des joueurs ont rejoint, annulation impossible'; END IF;
  -- Refund stake
  IF g.stake > 0 THEN
    UPDATE public.profiles SET balance_ar=balance_ar+g.stake WHERE id=v_uid;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note) VALUES(v_uid,'refund',g.stake,_game_id,'Remboursement Poker');
  END IF;
  UPDATE public.poker_games SET status='cancelled', updated_at=now() WHERE id=_game_id;
END;
$$;GRANT EXECUTE ON FUNCTION public.poker_request_refund TO authenticated;

-- === rami_claim_seven ===
CREATE OR REPLACE FUNCTION public.rami_claim_seven(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public AS $$
DECLARE
  _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _melds jsonb; _m jsonb; _total_cards int := 0; _found boolean := false;
  _refunded jsonb; _action_log jsonb;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;

  _state := _g.state;
  _refunded := COALESCE(_state->'refunded','{}'::jsonb);
  IF _refunded ? _uid::text THEN RAISE EXCEPTION 'deja remboursé'; END IF;

  -- Check if player has melds totaling exactly 7 cards
  _melds := COALESCE(_state->'melds','[]'::jsonb);
  FOR _m IN SELECT * FROM jsonb_array_elements(_melds) LOOP
    IF _m->>'player' = _uid::text THEN
      _total_cards := _total_cards + COALESCE(jsonb_array_length(_m->'cards'), 0);
      IF _m->>'type' = 'seven' THEN _found := true; END IF;
    END IF;
  END LOOP;

  IF NOT _found AND _total_cards < 7 THEN
    RAISE EXCEPTION 'tu dois poser 7 cartes valides';
  END IF;

  -- Refund stake
  IF _g.stake > 0 THEN
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) + _g.stake WHERE id=_uid;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (_uid,'rami_seven_refund',_g.stake,_game_id,'7 Cartes refund');
  END IF;

  _refunded := _refunded || jsonb_build_object(_uid::text, true);
  _state := jsonb_set(_state, '{refunded}', _refunded);
  _action_log := COALESCE(_state->'action_log','[]'::jsonb) ||
    jsonb_build_object('t','seven','p',_uid::text,'ts',extract(epoch from now())::bigint);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
END $$;GRANT EXECUTE ON FUNCTION public.rami_claim_seven(uuid) TO authenticated;

-- === rami_spectate ===
CREATE OR REPLACE FUNCTION public.rami_spectate(_game_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public AS $$
DECLARE
  _g public.rami_games;
  _state jsonb;
  _sanitized jsonb;
  _participants jsonb;
  _count int;
  _max int;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id = _game_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Game not found'; END IF;
  IF _g.status NOT IN ('playing', 'paused') THEN
    RAISE EXCEPTION 'Game not in progress';
  END IF;
  SELECT COALESCE(max_spectators, 50) INTO _max FROM public.app_settings WHERE id = 1;
  SELECT count(*) INTO _count FROM public.game_spectators WHERE game_id = _game_id;
  IF _count >= _max THEN
    RAISE EXCEPTION 'Spectator limit reached';
  END IF;
  INSERT INTO public.game_spectators(game_id, user_id)
    VALUES (_game_id, auth.uid()) ON CONFLICT DO NOTHING;
  _state := _g.state;
  _sanitized := jsonb_build_object(
    'deck_count', jsonb_array_length(COALESCE(_state->'deck', '[]'::jsonb)),
    'melds', COALESCE(_state->'melds', '[]'::jsonb),
    'discards', COALESCE(_state->'discards', '{}'::jsonb),
    'last_discard_by', COALESCE(_state->'last_discard_by', ''::text),
    'action_log', COALESCE(_state->'action_log', '[]'::jsonb)
  );
  SELECT jsonb_agg(jsonb_build_object(
    'user_id', p.user_id, 'display_name', p.display_name, 'slot', p.slot,
    'hand_count', p.hand_count, 'is_bot', p.is_bot, 'forfeited', p.forfeited
  )) INTO _participants
  FROM public.rami_participants p WHERE p.game_id = _game_id ORDER BY p.slot;
  RETURN jsonb_build_object(
    'game', jsonb_build_object(
      'id', _g.id, 'status', _g.status, 'current_turn', _g.current_turn,
      'turn_phase', _g.turn_phase, 'stake', _g.stake, 'pot', _g.pot,
      'joker_mode', _g.joker_mode, 'game_mode', _g.game_mode,
      'winner_id', _g.winner_id, 'state', _sanitized
    ),
    'participants', COALESCE(_participants, '[]'::jsonb)
  );
END;
$$;GRANT EXECUTE ON FUNCTION public.rami_spectate(uuid) TO authenticated;

-- === rami_spectate_leave ===
CREATE OR REPLACE FUNCTION public.rami_spectate_leave(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public AS $$
BEGIN
  DELETE FROM public.game_spectators WHERE game_id = _game_id AND user_id = auth.uid();
END;
$$;GRANT EXECUTE ON FUNCTION public.rami_spectate_leave(uuid) TO authenticated;

-- === rami_unmeld ===
CREATE OR REPLACE FUNCTION public.rami_unmeld(_game_id uuid, _meld_index integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _melds jsonb; _m jsonb; _cards int[]; _hand int[]; _new_melds jsonb := '[]'::jsonb;
  _i int; _stake numeric; _refunded jsonb; _bal numeric;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour de jouer'; END IF;

  _state := public._rami_normalize_state(_g.state);
  _melds := _state->'melds';
  IF _meld_index < 0 OR _meld_index >= jsonb_array_length(_melds) THEN
    RAISE EXCEPTION 'combinaison introuvable';
  END IF;
  _m := _melds->_meld_index;
  IF _m->>'player' <> _uid::text THEN RAISE EXCEPTION 'ce n''est pas ta combinaison'; END IF;

  _cards := public._rami_jarr(_m->'cards');
  _hand  := public._rami_jarr(_state->'hands'->_uid::text) || _cards;

  FOR _i IN 0..jsonb_array_length(_melds)-1 LOOP
    IF _i <> _meld_index THEN _new_melds := _new_melds || jsonb_build_array(_melds->_i); END IF;
  END LOOP;

  -- Annule le remboursement « 7 cartes » si c'était cette combinaison
  IF COALESCE(_m->>'type','') = 'seven' THEN
    _refunded := COALESCE(_state->'refunded','{}'::jsonb);
    IF jsonb_typeof(_refunded) <> 'object' THEN _refunded := '{}'::jsonb; END IF;
    IF _refunded ? _uid::text THEN
      _stake := COALESCE(_g.stake,0);
      IF _stake > 0 THEN
        SELECT balance_ar INTO _bal FROM public.profiles WHERE id=_uid FOR UPDATE;
        IF COALESCE(_bal,0) < _stake THEN
          RAISE EXCEPTION 'solde insuffisant pour annuler le retour de mise';
        END IF;
        UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id=_uid;
        INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
        VALUES (_uid,'rami_refund_cancel',-_stake,_game_id,'Annulation du retour de mise — 7 cartes cassées');
        UPDATE public.rami_games SET pot = pot + _stake WHERE id=_game_id;
      END IF;
      _state := jsonb_set(_state,'{refunded}', _refunded - _uid::text, true);
      _state := _state - 'last_seven';
    END IF;
  END IF;

  _state := jsonb_set(_state, '{melds}', _new_melds, true);
  _state := jsonb_set(_state, ARRAY['hands',_uid::text], public._rami_jset(_hand), true);

  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_hand,1),0)
    WHERE game_id=_game_id AND user_id=_uid;
END $$;

-- === set_totp_secret ===
CREATE OR REPLACE FUNCTION public.set_totp_secret(_secret text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.user_totp_secrets (user_id, totp_secret, enabled)
    VALUES (auth.uid(), _secret, true)
    ON CONFLICT (user_id) DO UPDATE
      SET totp_secret = EXCLUDED.totp_secret, enabled = true;
  -- Also set the flag on profiles (for client to know 2FA is on)
  UPDATE public.profiles SET two_factor_enabled = true WHERE id = auth.uid();
END $$;GRANT EXECUTE ON FUNCTION public.set_totp_secret(text) TO authenticated;

-- === subscribe_premium ===
CREATE OR REPLACE FUNCTION public.subscribe_premium(p_months int, p_tier text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _uid uuid := auth.uid();
  _settings record;
  _price numeric;
  _total numeric;
  _balance numeric;
  _current_until timestamptz;
  _new_until timestamptz;
BEGIN
  IF _uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifie');
  END IF;

  IF p_months < 1 OR p_months > 12 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Nombre de mois invalide (1-12)');
  END IF;

  IF p_tier NOT IN ('basic', 'standard', 'premium') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Tier invalide');
  END IF;

  SELECT * INTO _settings FROM public.app_settings WHERE id = 1 LIMIT 1;

  _price := CASE
    WHEN p_tier = 'basic' THEN _settings.sub_basic_price_ar
    WHEN p_tier = 'standard' THEN _settings.sub_standard_price_ar
    WHEN p_tier = 'premium' THEN _settings.sub_premium_price_ar
  END;

  _total := _price * p_months;

  SELECT COALESCE(balance_ar, 0) INTO _balance
  FROM public.profiles WHERE id = _uid;

  IF _balance < _total THEN
    RETURN jsonb_build_object('success', false, 'error',
      'Solde insuffisant. Vous avez ' || _balance || ' Ar, besoin de ' || _total || ' Ar');
  END IF;

  SELECT premium_until INTO _current_until FROM public.profiles WHERE id = _uid;
  _new_until := GREATEST(COALESCE(_current_until, now()), now()) + (p_months || ' month')::interval;

  UPDATE public.profiles
  SET balance_ar = balance_ar - _total,
      premium_tier = p_tier,
      premium_until = _new_until,
      is_premium = true
  WHERE id = _uid;

  INSERT INTO public.subscription_payments (user_id, amount_ar, months, valid_until, payment_method, status)
  VALUES (_uid, _total, p_months, _new_until, 'balance', 'paid');

  INSERT INTO public.transactions (user_id, type, amount, note)
  VALUES (_uid, 'subscription', -_total, 'Abonnement ' || p_tier || ' x' || p_months || ' mois');

  RETURN jsonb_build_object('success', true, 'tier', p_tier, 'amount', _total, 'months', p_months);
END;
$$;

-- === transfer_balance ===
CREATE OR REPLACE FUNCTION public.transfer_balance(
  _recipient text,
  _amount numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  _sender uuid := auth.uid();
  _sender_name text;
  _sender_phone text;
  _recipient_id uuid;
  _recipient_name text;
  _sender_bal numeric;
  _final_amount numeric;
  _min_transfer numeric := 100;
  _max_transfer numeric := 500000;
  _fee numeric := 0;
BEGIN
  IF _sender IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;

  IF _amount < _min_transfer THEN
    RAISE EXCEPTION 'Montant minimum: % Ar', _min_transfer;
  END IF;
  IF _amount > _max_transfer THEN
    RAISE EXCEPTION 'Montant maximum: % Ar', _max_transfer;
  END IF;

  SELECT pseudo, phone, balance_ar INTO _sender_name, _sender_phone, _sender_bal
    FROM public.profiles WHERE id = _sender;
  IF _sender_name IS NULL THEN RAISE EXCEPTION 'Profil introuvable'; END IF;

  IF COALESCE((SELECT is_banned FROM public.profiles WHERE id = _sender), false) THEN
    RAISE EXCEPTION 'Compte banni';
  END IF;

  IF _sender_bal < _amount THEN
    RAISE EXCEPTION 'Solde insuffisant. Votre solde: % Ar', _sender_bal;
  END IF;

  SELECT id, pseudo INTO _recipient_id, _recipient_name
    FROM public.profiles
    WHERE phone = _recipient
       OR phone_number = _recipient
       OR pseudo = _recipient
       OR unique_code = _recipient
    LIMIT 1;

  IF _recipient_id IS NULL THEN
    RAISE EXCEPTION 'Destinataire introuvable. Vérifiez le numéro de téléphone ou le pseudo.';
  END IF;

  IF _recipient_id = _sender THEN
    RAISE EXCEPTION 'Vous ne pouvez pas transférer à vous-même';
  END IF;

  IF COALESCE((SELECT is_banned FROM public.profiles WHERE id = _recipient_id), false) THEN
    RAISE EXCEPTION 'Le destinataire est banni';
  END IF;

  _final_amount := _amount - _fee;

  UPDATE public.profiles
    SET balance_ar = balance_ar - _amount
    WHERE id = _sender;

  UPDATE public.profiles
    SET balance_ar = balance_ar + _final_amount
    WHERE id = _recipient_id;

  INSERT INTO public.transactions(user_id, type, amount, ref_id, note, meta)
    VALUES (_sender, 'transfer_sent', -_amount, _recipient_id,
      'Transfert à ' || _recipient_name,
      jsonb_build_object('to', _recipient_id, 'to_name', _recipient_name));

  INSERT INTO public.transactions(user_id, type, amount, ref_id, note, meta)
    VALUES (_recipient_id, 'transfer_received', _final_amount, _sender,
      'Transfert de ' || _sender_name,
      jsonb_build_object('from', _sender, 'from_name', _sender_name));

  RETURN jsonb_build_object(
    'success', true,
    'amount', _amount,
    'recipient', _recipient_name,
    'new_balance', _sender_bal - _amount
  );
END $function$;
-- 4 truly missing functions (not in any migration file)

-- === chess_forfeit ===
-- Frontend calls: supabase.rpc("chess_forfeit", { _id: game.id })
-- Context: called from chess waiting room to leave/cancel
CREATE OR REPLACE FUNCTION public.chess_forfeit(_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_game public.chess_games%ROWTYPE;
  v_stake numeric;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT * INTO v_game FROM public.chess_games WHERE id = _id FOR UPDATE;
  IF v_game.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;

  -- If game already finished, nothing to do
  IF v_game.status = 'finished' THEN RETURN; END IF;

  -- If game is still open (waiting room), just remove the player
  IF v_game.status = 'open' THEN
    -- Refund stake if player had paid
    IF v_game.stake > 0 THEN
      IF v_game.white_id = v_uid OR v_game.black_id = v_uid THEN
        UPDATE public.profiles SET balance_ar = balance_ar + v_game.stake WHERE id = v_uid;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (v_uid, 'chess_refund', v_game.stake, _id, 'Chess forfeit (waiting)');
      END IF;
    END IF;
    -- Remove the player from the seat
    UPDATE public.chess_games SET
      white_id = CASE WHEN white_id = v_uid THEN NULL ELSE white_id END,
      black_id = CASE WHEN black_id = v_uid THEN NULL ELSE black_id END
    WHERE id = _id;
    -- If no players left, cancel the game
    IF NOT EXISTS (
      SELECT 1 FROM public.chess_games WHERE id = _id AND (white_id IS NOT NULL OR black_id IS NOT NULL)
    ) THEN
      UPDATE public.chess_games SET status = 'cancelled', finished_at = now() WHERE id = _id;
    END IF;
    RETURN;
  END IF;

  -- If game is playing, treat as resignation
  IF v_game.status = 'playing' THEN
    -- Determine the winner (the other player)
    IF v_game.white_id = v_uid THEN
      UPDATE public.chess_games SET
        status = 'finished', winner_id = v_game.black_id,
        end_reason = 'forfeit', finished_at = now()
      WHERE id = _id;
      PERFORM public._chess_payout(_id);
    ELSIF v_game.black_id = v_uid THEN
      UPDATE public.chess_games SET
        status = 'finished', winner_id = v_game.white_id,
        end_reason = 'forfeit', finished_at = now()
      WHERE id = _id;
      PERFORM public._chess_payout(_id);
    END IF;
  END IF;
END $$;

REVOKE ALL ON FUNCTION public.chess_forfeit(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.chess_forfeit(uuid) TO authenticated;

-- === game_online_counts_all ===
-- Frontend calls: supabase.rpc("game_online_counts_all")
-- Returns: {slug, online_count} per game type
CREATE OR REPLACE FUNCTION public.game_online_counts_all()
RETURNS TABLE(slug text, online_count bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT 'ludo'::text,
    (SELECT count(*) FROM public.ludo_participants p
     JOIN public.ludo_games g ON g.id = p.game_id
     WHERE g.status = 'playing' AND p.user_id IS NOT NULL AND p.is_bot = false)
  UNION ALL
  SELECT 'domino',
    (SELECT count(*) FROM public.domino_participants p
     JOIN public.domino_games g ON g.id = p.game_id
     WHERE g.status = 'playing' AND p.user_id IS NOT NULL AND p.is_bot = false)
  UNION ALL
  SELECT 'fanorona',
    (SELECT count(*) FROM public.fanorona_participants p
     JOIN public.fanorona_games g ON g.id = p.game_id
     WHERE g.status = 'playing' AND p.user_id IS NOT NULL AND p.is_bot = false)
  UNION ALL
  SELECT 'chess',
    (SELECT count(*) FROM public.chess_games g
     WHERE g.status = 'playing'
       AND (g.white_id IS NOT NULL OR g.black_id IS NOT NULL)
       AND COALESCE(g.white_is_bot, false) = false)
  UNION ALL
  SELECT 'rami',
    (SELECT count(*) FROM public.rami_participants p
     JOIN public.rami_games g ON g.id = p.game_id
     WHERE g.status = 'playing' AND p.user_id IS NOT NULL AND p.is_bot = false)
  UNION ALL
  SELECT 'poker',
    (SELECT count(*) FROM public.poker_players p
     JOIN public.poker_games g ON g.id = p.game_id
     WHERE g.status = 'playing' AND p.user_id IS NOT NULL AND p.is_bot = false);
$$;

REVOKE ALL ON FUNCTION public.game_online_counts_all() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.game_online_counts_all() TO authenticated;

-- === list_all_open_games ===
-- Frontend calls: supabase.rpc("list_all_open_games")
-- Returns: {game_id, slug, stake, pot, created_at, max_players, players_count, host_id, host_name, target_score}
CREATE OR REPLACE FUNCTION public.list_all_open_games()
RETURNS TABLE(
  game_id uuid, slug text, stake numeric, pot numeric,
  created_at timestamptz, max_players int, players_count int,
  host_id uuid, host_name text, target_score numeric
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT g.id, 'ludo'::text, g.stake, g.pot, g.created_at,
    g.max_players,
    (SELECT count(*)::int FROM public.ludo_participants p WHERE p.game_id = g.id),
    g.host_id, COALESCE(h.pseudo, 'Joueur'), NULL::numeric
  FROM public.ludo_games g
  LEFT JOIN public.profiles h ON h.id = g.host_id
  WHERE g.status = 'open' AND g.is_private = false

  UNION ALL
  SELECT g.id, 'domino', g.stake, g.pot, g.created_at,
    g.max_players,
    (SELECT count(*)::int FROM public.domino_participants p WHERE p.game_id = g.id),
    g.host_id, COALESCE(h.pseudo, 'Joueur'), NULL::numeric
  FROM public.domino_games g
  LEFT JOIN public.profiles h ON h.id = g.host_id
  WHERE g.status = 'open' AND g.is_private = false

  UNION ALL
  SELECT g.id, 'fanorona', g.stake, g.pot, g.created_at,
    2,
    (SELECT count(*)::int FROM public.fanorona_participants p WHERE p.game_id = g.id),
    g.host_id, COALESCE(h.pseudo, 'Joueur'), NULL::numeric
  FROM public.fanorona_games g
  LEFT JOIN public.profiles h ON h.id = g.host_id
  WHERE g.status = 'open' AND g.is_private = false

  UNION ALL
  SELECT g.id, 'chess', g.stake, g.pot, g.created_at,
    2,
    ((CASE WHEN g.white_id IS NOT NULL THEN 1 ELSE 0 END) +
     (CASE WHEN g.black_id IS NOT NULL THEN 1 ELSE 0 END)),
    COALESCE(g.white_id, g.black_id),
    COALESCE(hw.pseudo, hb.pseudo, 'Joueur'),
    NULL::numeric
  FROM public.chess_games g
  LEFT JOIN public.profiles hw ON hw.id = g.white_id
  LEFT JOIN public.profiles hb ON hb.id = g.black_id
  WHERE g.status = 'open' AND g.is_private = false

  UNION ALL
  SELECT g.id, 'rami', g.stake, g.pot, g.created_at,
    g.max_players,
    (SELECT count(*)::int FROM public.rami_participants p WHERE p.game_id = g.id),
    g.created_by, COALESCE(h.pseudo, 'Joueur'), NULL::numeric
  FROM public.rami_games g
  LEFT JOIN public.profiles h ON h.id = g.created_by
  WHERE g.status = 'open' AND g.is_private = false

  UNION ALL
  SELECT g.id, 'poker', g.stake, g.pot, g.created_at,
    g.max_players,
    (SELECT count(*)::int FROM public.poker_players p WHERE p.game_id = g.id),
    g.host_id, COALESCE(h.pseudo, 'Joueur'), NULL::numeric
  FROM public.poker_games g
  LEFT JOIN public.profiles h ON h.id = g.host_id
  WHERE g.status = 'open' AND g.is_private = false

  ORDER BY created_at DESC;
$$;

REVOKE ALL ON FUNCTION public.list_all_open_games() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_all_open_games() TO authenticated;

-- === refund_game ===
-- Frontend calls: supabase.rpc("refund_game", { _game_id: id })
-- Context: admin panel, refunds all players of any game type
CREATE OR REPLACE FUNCTION public.refund_game(_game_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_stake numeric;
  v_found boolean := false;
  p RECORD;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;

  -- Try ludo
  BEGIN
    SELECT stake INTO v_stake FROM public.ludo_games WHERE id = _game_id AND status IN ('open','playing','waiting');
    IF v_stake IS NOT NULL THEN
      v_found := true;
      FOR p IN SELECT user_id FROM public.ludo_participants WHERE game_id = _game_id AND user_id IS NOT NULL AND is_bot = false
      LOOP
        UPDATE public.profiles SET balance_ar = balance_ar + v_stake WHERE id = p.user_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (p.user_id, 'refund', v_stake, _game_id, 'Admin refund (ludo)');
      END LOOP;
      UPDATE public.ludo_games SET status = 'refunded', finished_at = now() WHERE id = _game_id;
    END IF;
  END;

  -- Try domino
  IF NOT v_found THEN BEGIN
    SELECT stake INTO v_stake FROM public.domino_games WHERE id = _game_id AND status IN ('open','playing','waiting');
    IF v_stake IS NOT NULL THEN
      v_found := true;
      FOR p IN SELECT user_id FROM public.domino_participants WHERE game_id = _game_id AND user_id IS NOT NULL AND is_bot = false
      LOOP
        UPDATE public.profiles SET balance_ar = balance_ar + v_stake WHERE id = p.user_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (p.user_id, 'refund', v_stake, _game_id, 'Admin refund (domino)');
      END LOOP;
      UPDATE public.domino_games SET status = 'refunded', finished_at = now() WHERE id = _game_id;
    END IF;
  END; END IF;

  -- Try fanorona
  IF NOT v_found THEN BEGIN
    SELECT stake INTO v_stake FROM public.fanorona_games WHERE id = _game_id AND status IN ('open','playing','waiting');
    IF v_stake IS NOT NULL THEN
      v_found := true;
      FOR p IN SELECT user_id FROM public.fanorona_participants WHERE game_id = _game_id AND user_id IS NOT NULL AND is_bot = false
      LOOP
        UPDATE public.profiles SET balance_ar = balance_ar + v_stake WHERE id = p.user_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (p.user_id, 'refund', v_stake, _game_id, 'Admin refund (fanorona)');
      END LOOP;
      UPDATE public.fanorona_games SET status = 'refunded', finished_at = now() WHERE id = _game_id;
    END IF;
  END; END IF;

  -- Try chess
  IF NOT v_found THEN BEGIN
    SELECT stake INTO v_stake FROM public.chess_games WHERE id = _game_id AND status IN ('open','playing','waiting');
    IF v_stake IS NOT NULL THEN
      v_found := true;
      IF v_stake > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + v_stake
          WHERE id IN (SELECT white_id FROM public.chess_games WHERE id = _game_id AND white_id IS NOT NULL
                       UNION SELECT black_id FROM public.chess_games WHERE id = _game_id AND black_id IS NOT NULL);
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          SELECT white_id, 'refund', v_stake, _game_id, 'Admin refund (chess)'
          FROM public.chess_games WHERE id = _game_id AND white_id IS NOT NULL;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          SELECT black_id, 'refund', v_stake, _game_id, 'Admin refund (chess)'
          FROM public.chess_games WHERE id = _game_id AND black_id IS NOT NULL;
      END IF;
      UPDATE public.chess_games SET status = 'refunded', finished_at = now() WHERE id = _game_id;
    END IF;
  END; END IF;

  -- Try rami
  IF NOT v_found THEN BEGIN
    SELECT stake INTO v_stake FROM public.rami_games WHERE id = _game_id AND status IN ('open','playing','waiting');
    IF v_stake IS NOT NULL THEN
      v_found := true;
      FOR p IN SELECT user_id FROM public.rami_participants WHERE game_id = _game_id AND user_id IS NOT NULL AND is_bot = false
      LOOP
        UPDATE public.profiles SET balance_ar = balance_ar + v_stake WHERE id = p.user_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (p.user_id, 'refund', v_stake, _game_id, 'Admin refund (rami)');
      END LOOP;
      UPDATE public.rami_games SET status = 'refunded', finished_at = now() WHERE id = _game_id;
    END IF;
  END; END IF;

  -- Try poker
  IF NOT v_found THEN BEGIN
    SELECT stake INTO v_stake FROM public.poker_games WHERE id = _game_id AND status IN ('open','playing','waiting');
    IF v_stake IS NOT NULL THEN
      v_found := true;
      FOR p IN SELECT user_id FROM public.poker_players WHERE game_id = _game_id AND user_id IS NOT NULL AND is_bot = false
      LOOP
        UPDATE public.profiles SET balance_ar = balance_ar + v_stake WHERE id = p.user_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (p.user_id, 'refund', v_stake, _game_id, 'Admin refund (poker)');
      END LOOP;
      UPDATE public.poker_games SET status = 'refunded', finished_at = now() WHERE id = _game_id;
    END IF;
  END; END IF;

  IF NOT v_found THEN RAISE EXCEPTION 'Partie introuvable dans aucune table'; END IF;

  INSERT INTO public.admin_logs(admin_id, action) VALUES (v_uid, 'refund_game');
END $$;

REVOKE ALL ON FUNCTION public.refund_game(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refund_game(uuid) TO authenticated;
