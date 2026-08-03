
-- 1) Inscription joueur
CREATE OR REPLACE FUNCTION public.tournament_register(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_t public.tournaments%ROWTYPE; v_count int; v_balance numeric;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth requise'; END IF;
  SELECT * INTO v_t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF v_t.id IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;
  IF v_t.status <> 'open' THEN RAISE EXCEPTION 'Inscriptions fermées'; END IF;
  SELECT count(*) INTO v_count FROM public.tournament_registrations WHERE tournament_id = _tid;
  IF v_count >= v_t.max_players THEN RAISE EXCEPTION 'Tournoi complet'; END IF;
  IF EXISTS(SELECT 1 FROM public.tournament_registrations WHERE tournament_id = _tid AND user_id = v_uid) THEN
    RAISE EXCEPTION 'Déjà inscrit'; END IF;
  IF NOT v_t.is_free AND v_t.stake > 0 THEN
    SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid;
    IF COALESCE(v_balance,0) < v_t.stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
  END IF;
  INSERT INTO public.tournament_registrations(tournament_id, user_id) VALUES (_tid, v_uid);
END $$;
REVOKE ALL ON FUNCTION public.tournament_register(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tournament_register(uuid) TO authenticated;

-- 2) Désinscription joueur
CREATE OR REPLACE FUNCTION public.tournament_unregister(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_status text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth requise'; END IF;
  SELECT status INTO v_status FROM public.tournaments WHERE id = _tid;
  IF v_status <> 'open' THEN RAISE EXCEPTION 'Tournoi déjà démarré'; END IF;
  DELETE FROM public.tournament_registrations WHERE tournament_id = _tid AND user_id = v_uid;
END $$;
REVOKE ALL ON FUNCTION public.tournament_unregister(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tournament_unregister(uuid) TO authenticated;

-- 3) Prêt (wrapper vers tournament_match_ready)
CREATE OR REPLACE FUNCTION public.tournament_mark_ready(_mid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.tournament_match_ready(_mid);
END $$;
REVOKE ALL ON FUNCTION public.tournament_mark_ready(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tournament_mark_ready(uuid) TO authenticated;

-- 4) Annulation admin avec raison + remboursement
CREATE OR REPLACE FUNCTION public.admin_cancel_tournament(_tid uuid, _reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_refunded int := 0;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  PERFORM public.tournament_cancel(_tid);
  SELECT count(*) INTO v_refunded FROM public.tournament_registrations WHERE tournament_id = _tid;
  INSERT INTO public.tournament_audit_logs(tournament_id, event_type, actor_id, reason)
    VALUES (_tid, 'cancel', auth.uid(), _reason);
  RETURN jsonb_build_object('ok', true, 'refunded_players', v_refunded);
END $$;
REVOKE ALL ON FUNCTION public.admin_cancel_tournament(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_cancel_tournament(uuid, text) TO authenticated;

-- 5) Démarrage forcé
CREATE OR REPLACE FUNCTION public.admin_force_start_tournament(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  PERFORM public.tournament_start(_tid);
  INSERT INTO public.tournament_audit_logs(tournament_id, event_type, actor_id)
    VALUES (_tid, 'force_start', auth.uid());
END $$;
REVOKE ALL ON FUNCTION public.admin_force_start_tournament(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_force_start_tournament(uuid) TO authenticated;

-- 6) Liste enrichie des matchs pour l'admin
CREATE OR REPLACE FUNCTION public.admin_list_tournament_matches(_tid uuid)
RETURNS TABLE(
  id uuid, round int, match_index int, is_bye boolean, status text,
  player_ids uuid[], player_names text[], winner_id uuid, game_id uuid,
  join_deadline timestamptz, player_ready jsonb, is_final boolean, is_third_place boolean
)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT m.id, m.round, m.match_index, m.is_bye, m.status,
    m.player_ids,
    ARRAY(
      SELECT COALESCE(p.pseudo, 'Joueur')
      FROM unnest(m.player_ids) WITH ORDINALITY AS u(uid, ord)
      LEFT JOIN public.profiles p ON p.id = u.uid
      ORDER BY u.ord
    ) AS player_names,
    m.winner_id, m.game_id, m.join_deadline, m.player_ready, m.is_final, m.is_third_place
  FROM public.tournament_matches m
  WHERE m.tournament_id = _tid AND public.is_admin()
  ORDER BY m.round, m.match_index;
$$;
REVOKE ALL ON FUNCTION public.admin_list_tournament_matches(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_tournament_matches(uuid) TO authenticated;

-- 7) Disqualification joueur (wrapper vers remove_participant + forfait match en cours)
CREATE OR REPLACE FUNCTION public.admin_tournament_disqualify(_tid uuid, _user_id uuid, _reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_match_id uuid; v_forfeited boolean := false;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  -- Trouver un éventuel match en cours contenant ce joueur
  SELECT id INTO v_match_id FROM public.tournament_matches
    WHERE tournament_id = _tid AND status IN ('pending','playing','ready') AND _user_id = ANY(player_ids)
    ORDER BY round DESC LIMIT 1;
  IF v_match_id IS NOT NULL THEN
    UPDATE public.tournament_matches
       SET status='forfeit',
           winner_id = (SELECT unnest(player_ids) FROM public.tournament_matches WHERE id=v_match_id LIMIT 1 OFFSET
                        (CASE WHEN player_ids[1]=_user_id THEN 1 ELSE 0 END)),
           finished_at = now(),
           winner_source = 'admin_disqualify'
     WHERE id = v_match_id;
    v_forfeited := true;
  END IF;
  PERFORM public.admin_tournament_remove_participant(_tid, _user_id);
  INSERT INTO public.tournament_audit_logs(tournament_id, event_type, actor_id, user_id, reason, match_id)
    VALUES (_tid, 'disqualify', auth.uid(), _user_id, _reason, v_match_id);
  RETURN jsonb_build_object('ok', true, 'match_forfeited', v_forfeited);
END $$;
REVOKE ALL ON FUNCTION public.admin_tournament_disqualify(uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_tournament_disqualify(uuid, uuid, text) TO authenticated;

-- 8) Correction de résultat (wrapper force_winner)
CREATE OR REPLACE FUNCTION public.admin_tournament_override_match(_match_id uuid, _winner_id uuid, _reason text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_tid uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  PERFORM public.admin_tournament_force_winner(_match_id, _winner_id, _reason);
  SELECT tournament_id INTO v_tid FROM public.tournament_matches WHERE id = _match_id;
  INSERT INTO public.tournament_audit_logs(tournament_id, match_id, event_type, actor_id, user_id, reason)
    VALUES (v_tid, _match_id, 'override_match', auth.uid(), _winner_id, _reason);
END $$;
REVOKE ALL ON FUNCTION public.admin_tournament_override_match(uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_tournament_override_match(uuid, uuid, text) TO authenticated;

-- 9) Rematch (wrapper vers replay_match)
CREATE OR REPLACE FUNCTION public.admin_tournament_rematch(_match_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_tid uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  PERFORM public.admin_tournament_replay_match(_match_id);
  SELECT tournament_id INTO v_tid FROM public.tournament_matches WHERE id = _match_id;
  INSERT INTO public.tournament_audit_logs(tournament_id, match_id, event_type, actor_id)
    VALUES (v_tid, _match_id, 'rematch', auth.uid());
END $$;
REVOKE ALL ON FUNCTION public.admin_tournament_rematch(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_tournament_rematch(uuid) TO authenticated;
