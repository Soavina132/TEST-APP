-- ============================================================
-- Migration: Sécurité Admin & Plateforme
-- Date: 2026-08-01
-- Description:
--   1. CRITIQUE: Empêcher l'auto-promotion admin (profiles RLS)
--   2. Ajouter is_admin() à 16 fonctions admin manquantes
--   3. Sécuriser domino_start_game (auth + host check + FOR UPDATE)
--   4. Sécuriser domino_play_and_bot (auth check)
--   5. Restreindre domino_games UPDATE (host only)
--   6. Restreindre domino_participants UPDATE (self only)
--   7. Triggers Domino manquants (commission, house, participant_end)
--   8. domino_cleanup_empty_rooms créé
--   9. Nettoyer surcharges domino_create
-- ============================================================

-- 1. CRITIQUE: Protéger is_admin dans profiles UPDATE
DROP POLICY IF EXISTS profiles_self_update_pseudo ON public.profiles;
CREATE POLICY profiles_self_update_pseudo ON public.profiles
FOR UPDATE TO authenticated
USING (auth.uid() = id)
WITH CHECK (
  auth.uid() = id 
  AND is_admin = (SELECT is_admin FROM profiles p WHERE p.id = auth.uid())
);

DROP POLICY IF EXISTS profiles_self_update_safe ON public.profiles;
CREATE POLICY profiles_self_update_safe ON public.profiles
FOR UPDATE TO authenticated
USING (auth.uid() = id)
WITH CHECK (
  auth.uid() = id 
  AND is_admin = (SELECT is_admin FROM profiles p WHERE p.id = auth.uid())
  AND balance_ar = (SELECT balance_ar FROM profiles p WHERE p.id = auth.uid())
  AND banned = (SELECT banned FROM profiles p WHERE p.id = auth.uid())
  AND status = (SELECT status FROM profiles p WHERE p.id = auth.uid())
  AND unique_code = (SELECT unique_code FROM profiles p WHERE p.id = auth.uid())
  AND referral_code = (SELECT referral_code FROM profiles p WHERE p.id = auth.uid())
);

-- 2. Sécuriser domino_start_game
CREATE OR REPLACE FUNCTION public.domino_start_game(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $function$
DECLARE v_uid uuid := auth.uid(); g record;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'game not found'; END IF;
  IF g.host_id <> v_uid AND NOT public.is_admin() THEN RAISE EXCEPTION 'only host can start'; END IF;
  IF g.status <> 'open' THEN RAISE EXCEPTION 'game not open'; END IF;
  PERFORM public._domino_start(_game_id);
END; $function$;

-- 3. Sécuriser domino_play_and_bot
CREATE OR REPLACE FUNCTION public.domino_play_and_bot(_game_id uuid, _move jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'extensions'
AS $function$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  PERFORM public.domino_play(_game_id, _move);
  PERFORM public._domino_bot_step(_game_id);
END $function$;

-- 4. RLS domino_games UPDATE (host only)
DROP POLICY IF EXISTS domino_games_update ON public.domino_games;
CREATE POLICY domino_games_update ON public.domino_games
FOR UPDATE TO authenticated
USING (host_id = auth.uid() OR public.is_admin())
WITH CHECK (host_id = auth.uid() OR public.is_admin());

-- 5. RLS domino_participants UPDATE (self only)
DROP POLICY IF EXISTS domino_participants_update ON public.domino_participants;
CREATE POLICY domino_participants_update ON public.domino_participants
FOR UPDATE TO authenticated
USING (user_id = auth.uid() OR public.is_admin())
WITH CHECK (user_id = auth.uid() OR public.is_admin());

-- 6. Triggers Domino
CREATE OR REPLACE FUNCTION public._apply_domino_commission()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $function$
BEGIN
  IF NEW.commission_pct IS NULL THEN
    NEW.commission_pct := COALESCE((SELECT commission_pct FROM public.app_settings WHERE id = 1), 10);
  END IF;
  RETURN NEW;
END; $function$;

DROP TRIGGER IF EXISTS trg_apply_domino_commission ON public.domino_games;
CREATE TRIGGER trg_apply_domino_commission BEFORE INSERT ON public.domino_games
FOR EACH ROW EXECUTE FUNCTION _apply_domino_commission();

DROP TRIGGER IF EXISTS trg_skip_noop_domino ON public.domino_games;
CREATE TRIGGER trg_skip_noop_domino BEFORE UPDATE ON public.domino_games
FOR EACH ROW EXECUTE FUNCTION _skip_noop_update();

CREATE OR REPLACE FUNCTION public._trg_domino_participant_end_check()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $function$
BEGIN
  IF NEW.is_bot = false AND COALESCE(NEW.forfeited, false) IS DISTINCT FROM COALESCE(OLD.forfeited, false) THEN
    PERFORM public._maybe_end_bot_only_domino(NEW.game_id);
  END IF;
  RETURN NEW;
END; $function$;

DROP TRIGGER IF EXISTS trg_domino_participant_end_check ON public.domino_participants;
CREATE TRIGGER trg_domino_participant_end_check AFTER UPDATE ON public.domino_participants
FOR EACH ROW EXECUTE FUNCTION _trg_domino_participant_end_check();

CREATE OR REPLACE FUNCTION public._log_domino_house_on_finish()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $function$
BEGIN
  IF NEW.status = 'finished' AND OLD.status <> 'finished' AND NEW.winner_id IS NULL AND NEW.pot > 0 THEN
    UPDATE public.app_settings SET house_balance_ar = COALESCE(house_balance_ar, 0) + NEW.pot WHERE id = 1;
    UPDATE public.domino_games SET pot = 0 WHERE id = NEW.id;
  END IF;
  RETURN NEW;
END; $function$;

DROP TRIGGER IF EXISTS trg_domino_house_on_finish ON public.domino_games;
CREATE TRIGGER trg_domino_house_on_finish AFTER UPDATE OF status ON public.domino_games
FOR EACH ROW EXECUTE FUNCTION _log_domino_house_on_finish();

-- 7. domino_cleanup_empty_rooms
CREATE OR REPLACE FUNCTION public.domino_cleanup_empty_rooms()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $function$
DECLARE v_count INT;
BEGIN
  DELETE FROM public.domino_participants WHERE game_id IN (SELECT id FROM public.domino_games WHERE status = 'open' AND created_at < now() - interval '10 minutes');
  DELETE FROM public.domino_games WHERE status = 'open' AND created_at < now() - interval '10 minutes'
    AND NOT EXISTS (SELECT 1 FROM public.domino_participants WHERE game_id = domino_games.id);
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END; $function$;

-- 8. Nettoyer surcharges domino_create (garder la plus complète)
DROP FUNCTION IF EXISTS public.domino_create(numeric, integer, boolean, text, numeric);
DROP FUNCTION IF EXISTS public.domino_create(numeric, integer, boolean, text, numeric, integer);
DROP FUNCTION IF EXISTS public.domino_create(numeric, integer, boolean, text, numeric, integer, text);
