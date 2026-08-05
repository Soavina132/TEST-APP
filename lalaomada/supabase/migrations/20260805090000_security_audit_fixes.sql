-- ═══════════════════════════════════════════════════════════════════════════
-- AUDIT SÉCURITÉ FINANCIÈRE — CORRECTIONS COMPLÈTES
-- Date: 2026-08-05
-- Corrige: #1 request_withdrawal, #2 admin PIN, #3 frais retrait,
--          #4 update_game_state, #5 validation dépôts, #6 email admin,
--          #7 rate limit dépôts, #8 SUPPRESSION bonus quotidien,
--          #9 finish_game status, #10 enum method
-- ═══════════════════════════════════════════════════════════════════════════

-- pgcrypto pour le hashage du PIN admin
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ═══════════════════════════════════════════════════════════════════════════
-- #1 — CRÉER la fonction request_withdrawal (manquante en base)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.request_withdrawal(
  _amount        NUMERIC,
  _method        TEXT,
  _user_phone    TEXT,
  _recipient_name TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid            UUID := auth.uid();
  v_balance        NUMERIC;
  v_min_withdraw   NUMERIC;
  v_pending_count  INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _amount <= 0 THEN RAISE EXCEPTION 'Montant invalide'; END IF;
  IF _method IS NULL OR length(trim(_method)) = 0 THEN RAISE EXCEPTION 'Méthode requise'; END IF;
  IF _user_phone IS NULL OR length(trim(_user_phone)) = 0 THEN RAISE EXCEPTION 'Numéro requis'; END IF;

  -- Rate limit: max 3 retraits en attente
  SELECT count(*) INTO v_pending_count FROM public.withdrawals
  WHERE user_id = v_uid AND status = 'pending';
  IF v_pending_count >= 3 THEN RAISE EXCEPTION 'Trop de retraits en attente (max 3)'; END IF;

  -- Vérifier le minimum
  SELECT min_withdraw INTO v_min_withdraw FROM public.app_settings WHERE id = 1;
  IF v_min_withdraw IS NOT NULL AND _amount < v_min_withdraw THEN
    RAISE EXCEPTION 'Montant minimum: % Ar', v_min_withdraw;
  END IF;

  -- Vérifier le solde (avec verrou)
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance IS NULL THEN RAISE EXCEPTION 'Profil introuvable'; END IF;
  IF v_balance < _amount THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  -- Insérer la demande de retrait (méthode normalisée)
  INSERT INTO public.withdrawals(user_id, amount, method, user_phone, status, recipient_name)
  VALUES(v_uid, _amount, lower(trim(_method)), trim(_user_phone), 'pending'::public.tx_status, trim(_recipient_name));
END $$;

GRANT EXECUTE ON FUNCTION public.request_withdrawal(NUMERIC, TEXT, TEXT, TEXT) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.request_withdrawal(NUMERIC, TEXT, TEXT, TEXT) FROM anon;

-- ═══════════════════════════════════════════════════════════════════════════
-- #2 — Sécurité admin: PIN + lockout
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS admin_pin_hash        TEXT,
  ADD COLUMN IF NOT EXISTS admin_failed_attempts  INT    NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS admin_locked_until     TIMESTAMPTZ;

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
END $$;

GRANT EXECUTE ON FUNCTION public.admin_verify_pin(TEXT) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_verify_pin(TEXT) FROM anon;

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
END $$;

GRANT EXECUTE ON FUNCTION public.admin_set_pin(TEXT) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_set_pin(TEXT) FROM anon;

-- ═══════════════════════════════════════════════════════════════════════════
-- #3 — Appliquer les frais de retrait dans admin_process_withdrawal
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE public.withdrawals ADD COLUMN IF NOT EXISTS fee_amount NUMERIC DEFAULT 0;

CREATE OR REPLACE FUNCTION public.admin_process_withdrawal(_id UUID, _approve BOOLEAN)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_w         public.withdrawals%ROWTYPE;
  v_balance   NUMERIC;
  v_fee_pct   NUMERIC;
  v_fee       NUMERIC;
  v_net       NUMERIC;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  SELECT * INTO v_w FROM public.withdrawals WHERE id=_id FOR UPDATE;
  IF v_w.id IS NULL OR v_w.status <> 'pending' THEN RAISE EXCEPTION 'Retrait non valide'; END IF;

  IF _approve THEN
    SELECT balance_ar INTO v_balance FROM public.profiles WHERE id=v_w.user_id FOR UPDATE;
    IF v_balance < v_w.amount THEN RAISE EXCEPTION 'Solde joueur insuffisant'; END IF;

    -- Calculer les frais
    SELECT withdrawal_fee_pct INTO v_fee_pct FROM public.app_settings WHERE id = 1;
    v_fee := ROUND(v_w.amount * COALESCE(v_fee_pct, 0) / 100.0, 0);
    v_net := v_w.amount - v_fee;

    -- Débiter le montant total
    UPDATE public.profiles SET balance_ar = balance_ar - v_w.amount WHERE id=v_w.user_id;
    UPDATE public.withdrawals
      SET status='approved', processed_at=now(), fee_amount = v_fee
      WHERE id=_id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_w.user_id,'withdraw',-v_w.amount,_id,
        'Retrait approuvé (' || v_w.amount || ' Ar — frais: ' || v_fee || ' Ar — net: ' || v_net || ' Ar)');
  ELSE
    UPDATE public.withdrawals SET status='rejected', processed_at=now() WHERE id=_id;
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- #4 — update_game_state: restreindre au joueur dont c'est le tour
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.update_game_state(_game_id UUID, _state JSONB, _current_turn INT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid          UUID := auth.uid();
  v_game         public.ludo_games%ROWTYPE;
  v_current_turn INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF v_game.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_game.status <> 'playing' THEN RAISE EXCEPTION 'Partie non en cours'; END IF;

  IF NOT EXISTS (SELECT 1 FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid)
     AND NOT EXISTS (SELECT 1 FROM public.ludo_games WHERE id=_game_id AND host_id=v_uid) THEN
    RAISE EXCEPTION 'Non participant';
  END IF;

  -- Seul le joueur actif peut modifier (sauf admin/hôte)
  v_current_turn := v_game.current_turn;
  IF NOT public.is_admin() AND v_uid != v_game.host_id THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.ludo_participants
      WHERE game_id=_game_id AND user_id=v_uid AND slot = v_current_turn
    ) THEN
      RAISE EXCEPTION 'Ce n''est pas votre tour';
    END IF;
  END IF;

  UPDATE public.ludo_games SET state = _state, current_turn = _current_turn
   WHERE id = _game_id AND status = 'playing';
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- #5 + #7 — Validation des dépôts: format référence + rate limiting
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._validate_deposit_insert()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_pending_count INT;
  v_min_deposit   NUMERIC;
BEGIN
  -- Rate limit: max 5 dépôts en attente
  SELECT count(*) INTO v_pending_count FROM public.deposits
  WHERE user_id = NEW.user_id AND status = 'pending';
  IF v_pending_count >= 5 THEN
    RAISE EXCEPTION 'Trop de dépôts en attente (max 5). Veuillez attendre la validation.';
  END IF;

  -- Valider la référence (min 6 caractères, alphanumérique)
  IF length(trim(NEW.reference)) < 6 THEN
    RAISE EXCEPTION 'Code de référence trop court (minimum 6 caractères)';
  END IF;
  IF NEW.reference !~ '^[A-Za-z0-9]+$' THEN
    RAISE EXCEPTION 'Référence invalide: caractères alphanumériques uniquement';
  END IF;

  -- Normaliser la méthode
  NEW.method := lower(trim(NEW.method));

  -- Valider le montant minimum
  SELECT min_deposit INTO v_min_deposit FROM public.app_settings WHERE id = 1;
  IF v_min_deposit IS NOT NULL AND NEW.amount < v_min_deposit THEN
    RAISE EXCEPTION 'Montant minimum: % Ar', v_min_deposit;
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_validate_deposit ON public.deposits;
CREATE TRIGGER trg_validate_deposit
  BEFORE INSERT ON public.deposits
  FOR EACH ROW EXECUTE FUNCTION public._validate_deposit_insert();

-- ═══════════════════════════════════════════════════════════════════════════
-- #6 — Supprimer l'email admin codé en dur du trigger handle_new_user
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_pseudo      TEXT;
  v_ref_code    TEXT;
  v_referred_by UUID;
  v_input_ref   TEXT;
  v_bonus       NUMERIC;
  v_unique      TEXT;
BEGIN
  v_pseudo   := COALESCE(NEW.raw_user_meta_data->>'pseudo', split_part(NEW.email,'@',1));
  v_input_ref := NEW.raw_user_meta_data->>'referral_code';
  v_ref_code := public.gen_referral_code();
  v_unique   := public.gen_unique_code();

  IF v_input_ref IS NOT NULL AND v_input_ref <> '' THEN
    SELECT id INTO v_referred_by FROM public.profiles WHERE referral_code = upper(v_input_ref);
  END IF;

  SELECT signup_bonus INTO v_bonus FROM public.app_settings WHERE id = 1;

  INSERT INTO public.profiles(id, pseudo, email, referral_code, referred_by, balance_ar, unique_code)
  VALUES(NEW.id, v_pseudo, NEW.email, v_ref_code, v_referred_by, COALESCE(v_bonus,0), v_unique);

  IF COALESCE(v_bonus,0) > 0 THEN
    INSERT INTO public.transactions(user_id,type,amount,note) VALUES (NEW.id,'bonus',v_bonus,'Bonus inscription');
  END IF;

  -- Tous les nouveaux utilisateurs sont 'user'. L'admin est promu manuellement.
  INSERT INTO public.user_roles(user_id, role) VALUES (NEW.id, 'user') ON CONFLICT DO NOTHING;

  RETURN NEW;
END $$;

-- Fonction pour promouvoir un utilisateur en admin
CREATE OR REPLACE FUNCTION public.admin_promote_user(_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  INSERT INTO public.user_roles(user_id, role) VALUES (_user_id, 'admin')
  ON CONFLICT (user_id, role) DO NOTHING;
  INSERT INTO public.admin_logs(admin_id, action, target_user_id)
    VALUES (auth.uid(), 'promote_admin', _user_id);
END $$;

GRANT EXECUTE ON FUNCTION public.admin_promote_user(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_promote_user(UUID) FROM anon;

-- ═══════════════════════════════════════════════════════════════════════════
-- #8 — SUPPRESSION COMPLÈTE du bonus quotidien
-- ═══════════════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.claim_daily_bonus() CASCADE;
DROP FUNCTION IF EXISTS public.get_daily_bonus_status() CASCADE;
DROP FUNCTION IF EXISTS public.admin_set_daily_bonus(boolean, integer, boolean) CASCADE;

ALTER TABLE public.app_settings
  DROP COLUMN IF EXISTS daily_bonus_enabled,
  DROP COLUMN IF EXISTS daily_bonus_amount_ar,
  DROP COLUMN IF EXISTS daily_bonus_streak_bonus;

ALTER TABLE public.profiles
  DROP COLUMN IF EXISTS last_daily_claim,
  DROP COLUMN IF EXISTS daily_streak;

-- Recréer la vue sans daily_streak
DROP VIEW IF EXISTS public.v_player_stats;
CREATE OR REPLACE VIEW public.v_player_stats AS
SELECT
  p.id, p.pseudo, p.avatar_url,
  COALESCE(p.total_wins, 0)  AS total_wins,
  COALESCE(p.total_games, 0) AS total_games,
  COALESCE(p.player_level, 1) AS player_level
FROM public.profiles p
WHERE p.banned = false OR p.banned IS NULL;

-- ═══════════════════════════════════════════════════════════════════════════
-- #9 — finish_game: vérifier que la partie est en cours
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.finish_game(_game_id uuid, _winner_id uuid)
RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_game       public.ludo_games%ROWTYPE;
  v_payout     NUMERIC;
  v_referrer   UUID;
  v_ref_pct    NUMERIC;
  v_ref_amount NUMERIC;
  v_caller     uuid := auth.uid();
BEGIN
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_game.status = 'finished' THEN RETURN 0; END IF;

  -- NOUVEAU: la partie doit être en cours
  IF v_game.status <> 'playing' THEN RAISE EXCEPTION 'La partie n''est pas en cours'; END IF;

  -- Auth guard
  IF v_caller IS NOT NULL
     AND v_caller <> v_game.host_id
     AND NOT public._is_game_participant(_game_id, v_caller)
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Non autorisé';
  END IF;

  IF _winner_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.ludo_participants WHERE game_id=_game_id AND user_id=_winner_id AND is_bot=FALSE
  ) THEN
    RAISE EXCEPTION 'Gagnant invalide';
  END IF;

  v_payout := v_game.pot * (100 - v_game.commission_pct) / 100.0;
  UPDATE public.ludo_games SET status='finished', winner_id=_winner_id, finished_at=now() WHERE id=_game_id;

  IF _winner_id IS NOT NULL THEN
    UPDATE public.profiles SET balance_ar = balance_ar + v_payout WHERE id=_winner_id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (_winner_id,'win',v_payout,_game_id,'Gain partie');

    SELECT referred_by INTO v_referrer FROM public.profiles WHERE id=_winner_id;
    IF v_referrer IS NOT NULL THEN
      SELECT referral_pct INTO v_ref_pct FROM public.app_settings WHERE id=1;
      v_ref_amount := v_payout * COALESCE(v_ref_pct,0) / 100.0;
      IF v_ref_amount > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + v_ref_amount WHERE id=v_referrer;
        INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
          VALUES (v_referrer,'referral',v_ref_amount,_game_id,'Bonus parrainage');
      END IF;
    END IF;
  END IF;

  RETURN v_payout;
END $$;

REVOKE EXECUTE ON FUNCTION public.finish_game(uuid,uuid) FROM PUBLIC, anon, authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- #10 — Normaliser les méthodes de paiement + contrainte CHECK
-- ═══════════════════════════════════════════════════════════════════════════
UPDATE public.deposits    SET method = 'mvola'  WHERE method ILIKE '%mvola%';
UPDATE public.deposits    SET method = 'orange' WHERE method ILIKE '%orange%';
UPDATE public.deposits    SET method = 'airtel' WHERE method ILIKE '%airtel%';
UPDATE public.withdrawals SET method = 'mvola'  WHERE method ILIKE '%mvola%';
UPDATE public.withdrawals SET method = 'orange' WHERE method ILIKE '%orange%';
UPDATE public.withdrawals SET method = 'airtel' WHERE method ILIKE '%airtel%';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'chk_deposit_method' AND table_name = 'deposits'
  ) THEN
    ALTER TABLE public.deposits
      ADD CONSTRAINT chk_deposit_method CHECK (method IN ('mvola', 'orange', 'airtel'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'chk_withdrawal_method' AND table_name = 'withdrawals'
  ) THEN
    ALTER TABLE public.withdrawals
      ADD CONSTRAINT chk_withdrawal_method CHECK (method IN ('mvola', 'orange', 'airtel'));
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Constraint skip: %', SQLERRM;
END $$;
