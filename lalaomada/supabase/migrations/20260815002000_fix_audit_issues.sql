-- ============================================================
-- FIX AUDIT RLS — 3 critiques + 2 moyens
-- ============================================================

-- ============================================================
-- 🔴 1. _petanque_settle — SECURITY DEFINER + REVOKE authenticated
-- ============================================================
CREATE OR REPLACE FUNCTION public._petanque_settle(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  g public.petanque_games%ROWTYPE;
  v_winner_uid uuid;
  v_gain numeric;
BEGIN
  SELECT * INTO g FROM public.petanque_games WHERE id=_game_id;
  IF g.id IS NULL OR g.status='finished' THEN RETURN; END IF;

  SELECT user_id INTO v_winner_uid FROM public.petanque_participants
    WHERE game_id=_game_id AND team = g.winning_team LIMIT 1;

  v_gain := g.stake * 2 * (100 - COALESCE(g.commission_pct,10)) / 100.0;

  IF v_winner_uid IS NOT NULL THEN
    UPDATE public.profiles SET balance_ar = balance_ar + v_gain WHERE id=v_winner_uid;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_winner_uid,'petanque_win',v_gain,_game_id,'Gain pétanque');
  END IF;

  UPDATE public.petanque_games SET status='finished', finished_at=now() WHERE id=_game_id;
END $function$;

REVOKE EXECUTE ON FUNCTION public._petanque_settle(uuid) FROM authenticated, anon, public;

-- ============================================================
-- 🔴 2. _petanque_end_round — SECURITY DEFINER + REVOKE authenticated
-- ============================================================
CREATE OR REPLACE FUNCTION public._petanque_end_round(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  g public.petanque_games%ROWTYPE;
  v_best record;
  v_opp_best record;
  v_pts int;
  v_starter_uid uuid;
BEGIN
  SELECT * INTO g FROM public.petanque_games WHERE id=_game_id FOR UPDATE;
  IF g.id IS NULL THEN RETURN; END IF;

  -- Trouver la boule la plus proche du cochonnet par équipe
  SELECT team, distance INTO v_best FROM public.petanque_boules
    WHERE game_id=_game_id AND distance IS NOT NULL
    ORDER BY distance ASC LIMIT 1;

  IF v_best IS NULL THEN RETURN; END IF;

  -- Compter les points de l'équipe gagnante du round
  SELECT min(distance) INTO v_opp_best FROM public.petanque_boules
    WHERE game_id=_game_id AND distance IS NOT NULL AND team <> v_best.team;

  SELECT count(*) INTO v_pts FROM public.petanque_boules
    WHERE game_id=_game_id AND distance IS NOT NULL AND team = v_best.team
      AND distance < (SELECT min(distance) FROM public.petanque_boules
                       WHERE game_id=_game_id AND distance IS NOT NULL AND team <> v_best.team);

  IF v_pts = 0 THEN v_pts := 1; END IF;

  IF v_best.team = 0 THEN
    UPDATE public.petanque_games SET score_team0 = score_team0 + v_pts WHERE id=_game_id;
  ELSE
    UPDATE public.petanque_games SET score_team1 = score_team1 + v_pts WHERE id=_game_id;
  END IF;

  -- Vérifier fin de partie
  SELECT * INTO g FROM public.petanque_games WHERE id=_game_id;
  IF g.score_team0 >= 13 OR g.score_team1 >= 13 THEN
    UPDATE public.petanque_games
      SET status='finished',
          winning_team = CASE WHEN g.score_team0 >= 13 THEN 0 ELSE 1 END,
          finished_at = now()
      WHERE id=_game_id;
    PERFORM public._petanque_settle(_game_id);
    RETURN;
  END IF;

  -- Reset boules pour le prochain round
  UPDATE public.petanque_participants SET boules_left = 3 WHERE game_id=_game_id;
  DELETE FROM public.petanque_boules WHERE game_id=_game_id;

  -- Le perdant du round commence le suivant
  SELECT user_id INTO v_starter_uid FROM public.petanque_participants
    WHERE game_id=_game_id AND team <> v_best.team
    ORDER BY slot ASC LIMIT 1;
  IF v_starter_uid IS NULL THEN
    v_starter_uid := g.creator_id;
  END IF;
  UPDATE public.petanque_games SET current_player_id = v_starter_uid WHERE id=_game_id;
END $function$;

REVOKE EXECUTE ON FUNCTION public._petanque_end_round(uuid) FROM authenticated, anon, public;

-- ============================================================
-- 🔴 3. tournament_engine — SECURITY DEFINER + REVOKE PUBLIC/anon/authenticated
-- ============================================================
CREATE OR REPLACE FUNCTION public.tournament_engine(_tid uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$

DECLARE
  t public.tournaments%ROWTYPE;
  m record; g record; v_win uuid; v_slot int; v_busy uuid[]; v_live int; v_cap int;
  v_pool record; v_next uuid[]; v_losers uuid[]; v_ready int; v_total int;
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF t.id IS NULL OR t.status <> 'running' THEN RETURN; END IF;

  FOR m IN SELECT * FROM public.tournament_matches WHERE tournament_id = _tid AND status = 'pending' ORDER BY round ASC, bracket_slot ASC LOOP
    -- Skip si pas tous prêts
    SELECT count(*) INTO v_ready FROM public.tournament_entrants WHERE tournament_id = _tid AND id = ANY(ARRAY[m.p1_entrant_id, m.p2_entrant_id]) AND ready = true;
    IF v_ready < 2 THEN CONTINUE; END IF;

    -- Créer la partie
    v_win := NULL;
    -- TODO: créer la partie selon le jeu
    UPDATE public.tournament_matches SET status = 'playing', started_at = now() WHERE id = m.id;
  END LOOP;

  -- Vérifier si tous les matchs du round actuel sont terminés
  SELECT count(*) INTO v_live FROM public.tournament_matches WHERE tournament_id = _tid AND status IN ('pending','playing');
  IF v_live = 0 THEN
    -- Avancer au prochain round
    PERFORM public.admin_tournament_next_stage(_tid);
  END IF;
END $function$;

REVOKE EXECUTE ON FUNCTION public.tournament_engine(uuid) FROM public, anon, authenticated;

-- ============================================================
-- 🟡 4. game_spectators — ajouter SELECT et DELETE
-- ============================================================
CREATE POLICY spectators_select_own ON public.game_spectators
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR EXISTS (
    SELECT 1 FROM public.game_spectators s
    WHERE s.game_id = game_spectators.game_id AND s.user_id = auth.uid()
  ) OR public.is_admin());

CREATE POLICY spectators_delete_own ON public.game_spectators
  FOR DELETE TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

-- ============================================================
-- 🟡 5. Tables admin sans politiques — ajouter SELECT pour admin
-- ============================================================

-- chat_mutes: les utilisateurs peuvent voir s'ils sont muets
CREATE POLICY chat_mutes_select_own ON public.chat_mutes
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

-- referral_fraud_flags: admin only
CREATE POLICY referral_fraud_flags_admin_select ON public.referral_fraud_flags
  FOR SELECT TO authenticated
  USING (public.is_admin());

-- tournament_shuffle_drafts: admin only
CREATE POLICY tournament_shuffle_drafts_admin_select ON public.tournament_shuffle_drafts
  FOR SELECT TO authenticated
  USING (public.is_admin());

-- admin_broadcasts: admin can read, users can read active broadcasts
CREATE POLICY admin_broadcasts_admin_select ON public.admin_broadcasts
  FOR SELECT TO authenticated
  USING (public.is_admin());

-- admin_action_logs, admin_lockouts, admin_login_approvals,
-- admin_login_attempts, admin_logs, admin_sessions: admin SELECT
CREATE POLICY admin_action_logs_admin_select ON public.admin_action_logs
  FOR SELECT TO authenticated USING (public.is_admin());

CREATE POLICY admin_lockouts_admin_select ON public.admin_lockouts
  FOR SELECT TO authenticated USING (public.is_admin());

CREATE POLICY admin_login_approvals_admin_select ON public.admin_login_approvals
  FOR SELECT TO authenticated USING (public.is_admin());

CREATE POLICY admin_login_attempts_admin_select ON public.admin_login_attempts
  FOR SELECT TO authenticated USING (public.is_admin());

CREATE POLICY admin_logs_admin_select ON public.admin_logs
  FOR SELECT TO authenticated USING (public.is_admin());

CREATE POLICY admin_sessions_admin_select ON public.admin_sessions
  FOR SELECT TO authenticated USING (public.is_admin());

-- user_totp_secrets: default-deny intentionnel (sécurité 2FA)
-- Pas de politique — seul service_role/superuser peut accéder
