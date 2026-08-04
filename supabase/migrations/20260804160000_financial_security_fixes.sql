-- ============================================================
-- FINANCIAL SECURITY FIXES — 2026-08-04
-- Corrige les 6 vulnérabilités financières identifiées lors de l'audit
-- ============================================================

-- ============================================================
-- 1. CRITIQUE : chess_claim_win — Un joueur pouvait déclarer
--    n'importe qui gagnant. Maintenant seul l'adversaire peut
--    être déclaré gagnant (démission) ou un match nul.
-- ============================================================
CREATE OR REPLACE FUNCTION public.chess_claim_win(_game_id uuid, _winner uuid, _draw boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_g chess_games%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentification requise'; END IF;

  SELECT * INTO v_g FROM chess_games WHERE id = _game_id FOR UPDATE;
  IF v_g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_g.status <> 'playing' THEN RAISE EXCEPTION 'Partie non active'; END IF;

  -- L'appelant doit être un des deux joueurs
  IF v_uid <> v_g.white_id AND v_uid <> v_g.black_id THEN
    RAISE EXCEPTION 'Vous n''êtes pas un joueur de cette partie';
  END IF;

  -- En cas de démission : le gagnant doit être l'ADVERSAIRE de l'appelant
  -- (on ne peut pas se déclarer soi-même gagnant)
  IF NOT _draw THEN
    IF _winner = v_uid THEN
      RAISE EXCEPTION 'Vous ne pouvez pas vous déclarer gagnant';
    END IF;
    IF _winner <> v_g.white_id AND _winner <> v_g.black_id THEN
      RAISE EXCEPTION 'Gagnant invalide';
    END IF;
  END IF;

  PERFORM public._chess_payout(_game_id, _winner, _draw);
END $$;
-- Garder le GRANT mais la fonction est maintenant sécurisée
GRANT EXECUTE ON FUNCTION public.chess_claim_win(uuid, uuid, boolean) TO authenticated;

-- ============================================================
-- 2. CRITIQUE : _chess_payout — Pas de verrou sur la game
--    Ajout de FOR UPDATE pour empêcher le double-payout
-- ============================================================
CREATE OR REPLACE FUNCTION public._chess_payout(_game_id uuid, _winner uuid, _draw boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_g chess_games%ROWTYPE;
  v_net numeric;
  v_each numeric;
BEGIN
  -- FOR UPDATE verrouille la ligne pour empêcher les appels concurrents
  SELECT * INTO v_g FROM chess_games WHERE id = _game_id FOR UPDATE;
  IF v_g.id IS NULL THEN RETURN; END IF;
  IF v_g.status = 'finished' THEN RETURN; END IF;

  v_net := v_g.pot - (v_g.pot * v_g.commission_pct / 100.0);

  IF _draw THEN
    v_each := v_net / 2;
    IF v_g.white_id IS NOT NULL THEN
      UPDATE profiles SET balance_ar = balance_ar + v_each WHERE id = v_g.white_id;
      INSERT INTO transactions(user_id, type, amount, ref_id, note)
        VALUES (v_g.white_id, 'chess_payout', v_each, _game_id, 'Chess draw');
    END IF;
    IF v_g.black_id IS NOT NULL THEN
      UPDATE profiles SET balance_ar = balance_ar + v_each WHERE id = v_g.black_id;
      INSERT INTO transactions(user_id, type, amount, ref_id, note)
        VALUES (v_g.black_id, 'chess_payout', v_each, _game_id, 'Chess draw');
    END IF;
    UPDATE chess_games SET status = 'finished', draw = true, finished_at = now() WHERE id = _game_id;
  ELSE
    UPDATE profiles SET balance_ar = balance_ar + v_net WHERE id = _winner;
    INSERT INTO transactions(user_id, type, amount, ref_id, note)
      VALUES (_winner, 'chess_payout', v_net, _game_id, 'Chess win');
    UPDATE chess_games SET status = 'finished', winner_id = _winner, finished_at = now() WHERE id = _game_id;
  END IF;
END $$;

-- ============================================================
-- 3. CRITIQUE : claim_daily_bonus — Race condition (double-claim)
--    Ajout de FOR UPDATE sur la ligne profile
-- ============================================================
CREATE OR REPLACE FUNCTION public.claim_daily_bonus()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_profile record;
  v_settings record;
  v_today date := CURRENT_DATE;
  v_streak int;
  v_base_amount int;
  v_multiplier int := 1;
  v_amount int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;

  SELECT daily_bonus_enabled, daily_bonus_amount_ar, daily_bonus_streak_bonus
    INTO v_settings FROM public.app_settings WHERE id = 1;
  IF NOT COALESCE(v_settings.daily_bonus_enabled, true) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'bonus_disabled');
  END IF;

  -- FOR UPDATE verrouille la ligne contre les appels concurrents
  SELECT last_daily_claim, daily_streak INTO v_profile
  FROM public.profiles WHERE id = v_uid FOR UPDATE;

  IF v_profile.last_daily_claim = v_today THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_claimed', 'next_claim', (v_today + 1)::text);
  END IF;

  v_streak := CASE
    WHEN v_profile.last_daily_claim = v_today - 1 THEN COALESCE(v_profile.daily_streak, 0) + 1
    ELSE 1
  END;

  v_base_amount := COALESCE(v_settings.daily_bonus_amount_ar, 500);
  IF COALESCE(v_settings.daily_bonus_streak_bonus, true) THEN
    IF v_streak >= 14 THEN v_multiplier := 3;
    ELSIF v_streak >= 7 THEN v_multiplier := 2;
    END IF;
  END IF;

  v_amount := v_base_amount * v_multiplier;

  UPDATE public.profiles
     SET last_daily_claim = v_today,
         daily_streak = v_streak,
         balance_ar = COALESCE(balance_ar, 0) + v_amount
   WHERE id = v_uid;

  RETURN jsonb_build_object(
    'ok', true,
    'amount', v_amount,
    'streak', v_streak,
    'multiplier', v_multiplier,
    'next_claim', (v_today + 1)::text
  );
END $$;
GRANT EXECUTE ON FUNCTION public.claim_daily_bonus() TO authenticated;

-- ============================================================
-- 4. HAUT : ludo_set_finish_position — Pas de vérification
--    que l'appelant est le joueur concerné ou un participant
-- ============================================================
CREATE OR REPLACE FUNCTION public.ludo_set_finish_position(
  _game_id uuid,
  _user_id uuid,
  _position int
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentification requise'; END IF;
  -- L'appelant doit être le joueur lui-même ou un admin
  IF v_uid <> _user_id AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Vous ne pouvez enregistrer que votre propre position';
  END IF;
  -- Vérifier que le joueur participe bien à cette partie
  IF NOT EXISTS (
    SELECT 1 FROM public.ludo_participants
    WHERE game_id = _game_id AND user_id = _user_id
  ) THEN
    RAISE EXCEPTION 'Joueur non participant à cette partie';
  END IF;

  UPDATE public.ludo_participants
    SET finish_position = _position
    WHERE game_id = _game_id
      AND user_id = _user_id
      AND finish_position IS NULL;
END $$;
GRANT EXECUTE ON FUNCTION public.ludo_set_finish_position(uuid, uuid, int) TO authenticated;

-- ============================================================
-- 5. HAUT : referral_fraud_flags — INSERT/UPDATE ouverts à tous
--    Revoke INSERT/UPDATE d'authenticated, garder seulement service_role
-- ============================================================
REVOKE INSERT, UPDATE ON public.referral_fraud_flags FROM authenticated, anon, PUBLIC;
-- Le SELECT reste admin-only (via policy ref_fraud_admin qui limite à is_admin)
-- service_role garde tous les droits (déjà accordé)

-- ============================================================
-- 6. HAUT : _ludo_finish_team — Bug de double-paiement
--    Le gagnant recevait v_half + v_payout au lieu de v_payout
--    Aussi: COALESCE(balance_ar, balance) était incorrect (balance n'existe pas)
-- ============================================================
CREATE OR REPLACE FUNCTION public._ludo_finish_team(_game_id uuid, _winner_id uuid, _team int)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_game public.ludo_games%ROWTYPE;
  v_payout numeric;
  v_comm numeric;
  v_half numeric;
  v_mate uuid;
BEGIN
  -- FOR UPDATE pour empêcher les appels concurrents
  SELECT * INTO v_game FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF v_game.status = 'finished' THEN RETURN; END IF;

  v_comm := round(v_game.pot * v_game.commission_pct / 100.0, 0);
  v_payout := v_game.pot - v_comm;
  v_half := round(v_payout / 2.0, 0);

  -- Trouver le coéquipier humain
  SELECT user_id INTO v_mate FROM public.ludo_participants
    WHERE game_id = _game_id AND team = _team AND user_id <> _winner_id
    AND NOT is_bot LIMIT 1;

  -- Marquer la partie comme terminée
  UPDATE public.ludo_games
    SET status = 'finished', winner_id = _winner_id, finished_at = now()
    WHERE id = _game_id;

  IF v_mate IS NOT NULL THEN
    -- Cas normal : deux joueurs, chacun reçoit la moitié
    UPDATE public.profiles
      SET balance_ar = COALESCE(balance_ar, 0) + v_half
      WHERE id = _winner_id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (_winner_id, 'win', v_half, _game_id, 'Gain Ludo groupe (équipe ' || _team || ')');

    UPDATE public.profiles
      SET balance_ar = COALESCE(balance_ar, 0) + v_half
      WHERE id = v_mate;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_mate, 'win', v_half, _game_id, 'Gain Ludo groupe (équipe ' || _team || ', coéquipier)');
  ELSE
    -- Pas de coéquipier humain : le gagnant reçoit le pot complet (une seule fois)
    UPDATE public.profiles
      SET balance_ar = COALESCE(balance_ar, 0) + v_payout
      WHERE id = _winner_id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (_winner_id, 'win', v_payout, _game_id, 'Gain Ludo groupe (équipe ' || _team || ', pot complet)');
  END IF;
END $function$;
