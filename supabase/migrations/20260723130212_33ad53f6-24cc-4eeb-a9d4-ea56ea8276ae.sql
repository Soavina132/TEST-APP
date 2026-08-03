CREATE OR REPLACE FUNCTION public._is_valid_mg_phone(_raw text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path = public AS $$
DECLARE d text;
BEGIN
  IF _raw IS NULL OR btrim(_raw) = '' THEN RETURN TRUE; END IF;
  d := regexp_replace(_raw, '[\s\.\-]', '', 'g');
  RETURN d ~ '^\+261[0-9]{9}$' OR d ~ '^0[23][0-9]{8}$';
END;$$;

CREATE OR REPLACE FUNCTION public._is_valid_email(_raw text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT _raw IS NULL OR btrim(_raw) = '' OR btrim(_raw) ~ '^[^\s@]+@[^\s@]+\.[^\s@]+$';
$$;

CREATE OR REPLACE FUNCTION public._is_valid_http_url(_raw text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT _raw IS NULL OR btrim(_raw) = '' OR btrim(_raw) ~* '^https?://[^\s]+$';
$$;

CREATE OR REPLACE FUNCTION public._validate_app_settings(_row public.app_settings)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path = public AS $$
BEGIN
  IF NOT public._is_valid_mg_phone(_row.mvola_phone)      THEN RETURN 'Numéro MVola invalide (format attendu : +261 34 12 345 67 ou 034 12 345 67).'; END IF;
  IF NOT public._is_valid_mg_phone(_row.orange_phone)     THEN RETURN 'Numéro Orange Money invalide.'; END IF;
  IF NOT public._is_valid_mg_phone(_row.airtel_phone)     THEN RETURN 'Numéro Airtel Money invalide.'; END IF;
  IF NOT public._is_valid_mg_phone(_row.admin_phone)      THEN RETURN 'Numéro admin invalide.'; END IF;
  IF NOT public._is_valid_mg_phone(_row.contact_phone)    THEN RETURN 'Numéro de téléphone contact invalide.'; END IF;
  IF NOT public._is_valid_mg_phone(_row.contact_whatsapp) THEN RETURN 'Numéro WhatsApp invalide.'; END IF;
  IF _row.mvola_name  IS NOT NULL AND char_length(_row.mvola_name)  > 80 THEN RETURN 'Nom du titulaire MVola trop long (max 80).'; END IF;
  IF _row.orange_name IS NOT NULL AND char_length(_row.orange_name) > 80 THEN RETURN 'Nom du titulaire Orange trop long (max 80).'; END IF;
  IF _row.airtel_name IS NOT NULL AND char_length(_row.airtel_name) > 80 THEN RETURN 'Nom du titulaire Airtel trop long (max 80).'; END IF;
  IF NOT public._is_valid_email(_row.contact_email)       THEN RETURN 'Adresse email de contact invalide.'; END IF;
  IF NOT public._is_valid_http_url(_row.download_url)     THEN RETURN 'Lien de téléchargement invalide (doit commencer par https://).'; END IF;
  IF NOT public._is_valid_http_url(_row.contact_facebook) THEN RETURN 'URL Facebook invalide (doit commencer par https://).'; END IF;
  IF _row.signup_bonus IS NOT NULL AND _row.signup_bonus < 0                                          THEN RETURN 'Le bonus d''inscription doit être supérieur ou égal à 0.'; END IF;
  IF _row.min_deposit  IS NOT NULL AND _row.min_deposit  < 0                                          THEN RETURN 'Le dépôt minimum doit être supérieur ou égal à 0.'; END IF;
  IF _row.min_withdraw IS NOT NULL AND _row.min_withdraw < 0                                          THEN RETURN 'Le retrait minimum doit être supérieur ou égal à 0.'; END IF;
  IF _row.game_commission_pct IS NOT NULL AND (_row.game_commission_pct < 0 OR _row.game_commission_pct > 100) THEN RETURN 'La commission sur les parties doit être comprise entre 0 et 100.'; END IF;
  IF _row.referral_pct        IS NOT NULL AND (_row.referral_pct < 0        OR _row.referral_pct > 100)        THEN RETURN 'Le pourcentage de parrainage doit être compris entre 0 et 100.'; END IF;
  IF _row.withdrawal_fee_pct  IS NOT NULL AND (_row.withdrawal_fee_pct < 0  OR _row.withdrawal_fee_pct > 100)  THEN RETURN 'Le pourcentage de frais de retrait doit être compris entre 0 et 100.'; END IF;
  IF _row.max_spectators IS NOT NULL AND (_row.max_spectators < 0 OR _row.max_spectators > 1000)              THEN RETURN 'Le nombre max de spectateurs doit être compris entre 0 et 1000.'; END IF;
  IF _row.afk_t1_max IS NOT NULL AND (_row.afk_t1_max < 0 OR _row.afk_t1_max > 20)                            THEN RETURN 'Le seuil AFK T1 doit être compris entre 0 et 20.'; END IF;
  IF _row.afk_t2_max IS NOT NULL AND (_row.afk_t2_max < 0 OR _row.afk_t2_max > 20)                            THEN RETURN 'Le seuil AFK T2 doit être compris entre 0 et 20.'; END IF;
  RETURN NULL;
END;$$;

CREATE OR REPLACE FUNCTION public._app_settings_validate_trigger()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
DECLARE msg text;
BEGIN
  msg := public._validate_app_settings(NEW);
  IF msg IS NOT NULL THEN
    RAISE EXCEPTION '%', msg USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;$$;

DROP TRIGGER IF EXISTS trg_app_settings_validate ON public.app_settings;
CREATE TRIGGER trg_app_settings_validate
BEFORE INSERT OR UPDATE ON public.app_settings
FOR EACH ROW EXECUTE FUNCTION public._app_settings_validate_trigger();

CREATE OR REPLACE FUNCTION public.admin_update_settings(
  _admin_phone text, _admin_label text, _signup_bonus numeric,
  _referral_pct numeric, _game_commission_pct numeric,
  _min_deposit numeric, _min_withdraw numeric,
  _mvola_phone  text DEFAULT NULL, _mvola_name  text DEFAULT NULL,
  _orange_phone text DEFAULT NULL, _orange_name text DEFAULT NULL,
  _airtel_phone text DEFAULT NULL, _airtel_name text DEFAULT NULL,
  _withdrawal_fee_pct numeric DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE msg text; nxt public.app_settings%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;

  SELECT * INTO nxt FROM public.app_settings WHERE id = 1;
  nxt.admin_phone := _admin_phone;
  nxt.admin_label := _admin_label;
  nxt.signup_bonus := _signup_bonus;
  nxt.referral_pct := _referral_pct;
  nxt.game_commission_pct := _game_commission_pct;
  nxt.min_deposit := _min_deposit;
  nxt.min_withdraw := _min_withdraw;
  nxt.mvola_phone := _mvola_phone;
  nxt.mvola_name := _mvola_name;
  nxt.orange_phone := _orange_phone;
  nxt.orange_name := _orange_name;
  nxt.airtel_phone := _airtel_phone;
  nxt.airtel_name := _airtel_name;
  nxt.withdrawal_fee_pct := COALESCE(_withdrawal_fee_pct, nxt.withdrawal_fee_pct);

  msg := public._validate_app_settings(nxt);
  IF msg IS NOT NULL THEN RAISE EXCEPTION '%', msg USING ERRCODE = '22023'; END IF;

  UPDATE public.app_settings SET
    admin_phone = nxt.admin_phone, admin_label = nxt.admin_label,
    signup_bonus = nxt.signup_bonus, referral_pct = nxt.referral_pct,
    game_commission_pct = nxt.game_commission_pct,
    min_deposit = nxt.min_deposit, min_withdraw = nxt.min_withdraw,
    mvola_phone = nxt.mvola_phone, mvola_name = nxt.mvola_name,
    orange_phone = nxt.orange_phone, orange_name = nxt.orange_name,
    airtel_phone = nxt.airtel_phone, airtel_name = nxt.airtel_name,
    withdrawal_fee_pct = nxt.withdrawal_fee_pct
  WHERE id = 1;
END;$$;