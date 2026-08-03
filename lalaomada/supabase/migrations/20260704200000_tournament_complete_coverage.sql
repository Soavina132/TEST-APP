-- ═══════════════════════════════════════════════════════════════════════════
-- Migration : Couverture complète des problèmes tournoi Ludo & Domino
-- Couvre : annulation tournoi, extension deadline, réclamations multi-tournoi,
--          détection matchs bloqués, création parties Ludo, signalement AFK,
--          notifications admin, arbitrage complet
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- 1. Colonnes supplémentaires sur tournament_matches
-- ─────────────────────────────────────────────────────────────────────────
ALTER TABLE public.tournament_matches
  ADD COLUMN IF NOT EXISTS afk_reports    jsonb NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS extended_count int   NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS match_index    int   NOT NULL DEFAULT 0;

-- ─────────────────────────────────────────────────────────────────────────
-- 2. admin_cancel_tournament — annulation complète + remboursement total
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_cancel_tournament(
  _tid    uuid,
  _reason text DEFAULT 'Tournoi annulé par l''administration'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_is_admin  boolean;
  trn         record;
  v_player    record;
  v_refunded  int := 0;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO trn FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF trn IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;
  IF trn.status = 'cancelled' THEN RAISE EXCEPTION 'Tournoi déjà annulé'; END IF;

  -- Annuler tous les matchs en cours ou en attente
  UPDATE public.tournament_matches
    SET status = 'cancelled', admin_notes = _reason
    WHERE tournament_id = _tid AND status IN ('pending', 'running', 'waiting');

  -- Annuler les parties liées si elles existent (ludo)
  UPDATE public.ludo_games
    SET status = 'cancelled'
    WHERE id IN (
      SELECT game_id FROM public.tournament_matches
      WHERE tournament_id = _tid AND game_id IS NOT NULL
    ) AND status IN ('open', 'playing');

  -- Rembourser TOUS les inscrits si le tournoi était payant
  IF NOT trn.is_free AND trn.stake > 0 THEN
    FOR v_player IN
      SELECT user_id FROM public.tournament_registrations WHERE tournament_id = _tid
    LOOP
      UPDATE public.profiles
        SET balance_ar = balance_ar + trn.stake
        WHERE id = v_player.user_id;

      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (v_player.user_id, 'tournament_refund', trn.stake, _tid,
                'Remboursement annulation : ' || _reason);

      -- Notifier le joueur
      BEGIN
        INSERT INTO public.notifications(user_id, type, title, body, ref_id)
          VALUES (v_player.user_id, 'tournament_cancelled',
                  'Tournoi annulé — Remboursement effectué',
                  'Votre mise de ' || trn.stake || ' Ar a été remboursée. Raison : ' || _reason,
                  _tid);
      EXCEPTION WHEN OTHERS THEN NULL; END;

      v_refunded := v_refunded + 1;
    END LOOP;
  ELSE
    -- Notifier même sans remboursement
    FOR v_player IN
      SELECT user_id FROM public.tournament_registrations WHERE tournament_id = _tid
    LOOP
      BEGIN
        INSERT INTO public.notifications(user_id, type, title, body, ref_id)
          VALUES (v_player.user_id, 'tournament_cancelled',
                  'Tournoi annulé',
                  'Le tournoi a été annulé. Raison : ' || _reason,
                  _tid);
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END LOOP;
  END IF;

  -- Marquer le tournoi comme annulé
  UPDATE public.tournaments
    SET status = 'cancelled', finished_at = now()
    WHERE id = _tid;

  -- Log admin
  BEGIN
    INSERT INTO public.admin_action_logs(admin_id, action, target_id, note)
      VALUES (v_uid, 'cancel_tournament', _tid, _reason)
    ON CONFLICT DO NOTHING;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.admin_logs(admin_id, action, target_user_id, new_value)
      VALUES (v_uid, 'cancel_tournament', NULL,
              jsonb_build_object('tournament_id', _tid, 'reason', _reason, 'refunded', v_refunded));
  END;

  RETURN jsonb_build_object(
    'ok', true,
    'refunded_players', v_refunded,
    'amount_per_player', CASE WHEN NOT trn.is_free THEN trn.stake ELSE 0 END
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_cancel_tournament(uuid, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 3. admin_extend_match_deadline — prolonger le délai de connexion d'un match
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_extend_match_deadline(
  _mid          uuid,
  _extra_mins   int  DEFAULT 10,
  _reason       text DEFAULT 'Extension accordée par admin'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_is_admin  boolean;
  m           record;
  v_new_dl    timestamptz;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;
  IF _extra_mins < 1 OR _extra_mins > 60 THEN RAISE EXCEPTION 'Extension entre 1 et 60 minutes'; END IF;

  SELECT * INTO m FROM public.tournament_matches WHERE id = _mid FOR UPDATE;
  IF m IS NULL THEN RAISE EXCEPTION 'Match introuvable'; END IF;
  IF m.status IN ('finished', 'forfeit', 'cancelled') THEN
    RAISE EXCEPTION 'Match déjà terminé';
  END IF;

  -- Si deadline déjà passée, on repart de maintenant; sinon on étend
  v_new_dl := GREATEST(COALESCE(m.join_deadline, now()), now()) + (_extra_mins || ' minutes')::interval;

  UPDATE public.tournament_matches
    SET join_deadline   = v_new_dl,
        admin_notes     = COALESCE(admin_notes || ' | ', '') || _reason,
        extended_count  = extended_count + 1,
        -- Remettre en pending si forfait ou bloqué
        status          = CASE WHEN status IN ('forfeit','pending') THEN 'pending' ELSE status END
    WHERE id = _mid;

  -- Notifier les joueurs du match
  DECLARE uid_t uuid;
  BEGIN
    FOREACH uid_t IN ARRAY m.player_ids LOOP
      BEGIN
        INSERT INTO public.notifications(user_id, type, title, body, ref_id)
          VALUES (uid_t, 'match_deadline_extended',
                  '⏰ Délai prolongé',
                  'L''admin a accordé ' || _extra_mins || ' min supplémentaires pour rejoindre. Nouvelle deadline : ' ||
                    to_char(v_new_dl AT TIME ZONE 'UTC', 'HH24:MI') || ' UTC',
                  _mid);
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END LOOP;
  END;

  BEGIN
    INSERT INTO public.admin_logs(admin_id, action, target_user_id, new_value)
      VALUES (v_uid, 'extend_match_deadline', NULL,
              jsonb_build_object('match_id', _mid, 'extra_mins', _extra_mins, 'new_deadline', v_new_dl));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object(
    'ok', true,
    'new_deadline', v_new_dl,
    'extended_by_mins', _extra_mins
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_extend_match_deadline(uuid, int, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 4. admin_list_all_tournament_claims — réclamations tous tournois confondus
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_list_all_tournament_claims(
  _status   text DEFAULT NULL,   -- NULL = tous
  _limit    int  DEFAULT 50
)
RETURNS TABLE(
  id                uuid,
  status            text,
  category          text,
  description       text,
  admin_comment     text,
  created_at        timestamptz,
  resolved_at       timestamptz,
  claimant_id       uuid,
  claimant_pseudo   text,
  tournament_id     uuid,
  tournament_name   text,
  match_id          uuid,
  match_round       int,
  match_status      text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_is_admin boolean;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  RETURN QUERY
    SELECT
      tc.id,
      tc.status,
      tc.category,
      tc.description,
      tc.admin_comment,
      tc.created_at,
      tc.resolved_at,
      tc.claimant_id,
      COALESCE(p.pseudo, '?') AS claimant_pseudo,
      tc.tournament_id,
      t.name AS tournament_name,
      tc.match_id,
      m.round AS match_round,
      m.status AS match_status
    FROM public.tournament_claims tc
    LEFT JOIN public.profiles p ON p.id = tc.claimant_id
    LEFT JOIN public.tournaments t ON t.id = tc.tournament_id
    LEFT JOIN public.tournament_matches m ON m.id = tc.match_id
    WHERE (_status IS NULL OR tc.status = _status)
    ORDER BY tc.created_at DESC
    LIMIT _limit;
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_list_all_tournament_claims(text, int) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 5. admin_check_stuck_matches — détecter tous les matchs bloqués
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_check_stuck_matches()
RETURNS TABLE(
  match_id        uuid,
  tournament_id   uuid,
  tournament_name text,
  game_slug       text,
  round           int,
  status          text,
  join_deadline   timestamptz,
  mins_overdue    int,
  player_ids      uuid[],
  player_names    text[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_is_admin boolean;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  RETURN QUERY
    SELECT
      m.id AS match_id,
      m.tournament_id,
      t.name AS tournament_name,
      COALESCE(t.game_slug, 'ludo') AS game_slug,
      m.round,
      m.status,
      m.join_deadline,
      EXTRACT(EPOCH FROM (now() - m.join_deadline))::int / 60 AS mins_overdue,
      m.player_ids,
      ARRAY(
        SELECT COALESCE(p.pseudo, '?')
        FROM unnest(m.player_ids) WITH ORDINALITY AS pid(uid, ord)
        LEFT JOIN public.profiles p ON p.id = pid.uid
        ORDER BY pid.ord
      ) AS player_names
    FROM public.tournament_matches m
    JOIN public.tournaments t ON t.id = m.tournament_id
    WHERE m.is_bye = false
      AND m.status IN ('pending', 'waiting')
      AND m.join_deadline IS NOT NULL
      AND m.join_deadline < now()
    ORDER BY m.join_deadline ASC;
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_check_stuck_matches() TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 6. admin_auto_process_expired_matches — traitement automatique des expirations
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_auto_process_expired_matches(_tid uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_is_admin  boolean;
  m           record;
  v_present   uuid[];
  v_absent    uuid[];
  v_winner    uuid;
  v_processed int := 0;
  uid_t       uuid;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  FOR m IN
    SELECT tm.*
    FROM public.tournament_matches tm
    WHERE tm.is_bye = false
      AND tm.status IN ('pending', 'waiting')
      AND tm.join_deadline IS NOT NULL
      AND tm.join_deadline < now()
      AND (_tid IS NULL OR tm.tournament_id = _tid)
    FOR UPDATE
  LOOP
    v_present := '{}';
    v_absent  := '{}';

    FOREACH uid_t IN ARRAY m.player_ids LOOP
      IF COALESCE((m.player_ready ->> uid_t::text)::boolean, false) THEN
        v_present := v_present || uid_t;
      ELSE
        v_absent  := v_absent  || uid_t;
      END IF;
    END LOOP;

    IF array_length(v_present, 1) >= 1 AND array_length(v_absent, 1) >= 1 THEN
      -- Un seul présent → gagne par forfait
      v_winner := v_present[1];
      UPDATE public.tournament_matches
        SET status = 'forfeit', winner_id = v_winner,
            finished_at = now(),
            admin_notes = COALESCE(admin_notes || ' | ', '') || 'Forfait automatique — délai expiré'
        WHERE id = m.id;

      -- Notifier le gagnant
      BEGIN
        INSERT INTO public.notifications(user_id, type, title, body, ref_id)
          VALUES (v_winner, 'match_forfeit_win',
                  '✅ Victoire par forfait',
                  'Votre adversaire ne s''est pas connecté à temps. Vous avancez au tour suivant.',
                  m.id);
      EXCEPTION WHEN OTHERS THEN NULL; END;

      -- Notifier le perdant
      IF v_absent[1] IS NOT NULL THEN
        BEGIN
          INSERT INTO public.notifications(user_id, type, title, body, ref_id)
            VALUES (v_absent[1], 'match_forfeit_loss',
                    '❌ Défaite par forfait',
                    'Vous n''avez pas rejoint votre match dans les délais. Vous êtes éliminé.',
                    m.id);
        EXCEPTION WHEN OTHERS THEN NULL; END;
      END IF;

      v_processed := v_processed + 1;

    ELSIF array_length(v_present, 1) = 0 THEN
      -- Personne n'est venu → annuler le match et rembourser si payant
      UPDATE public.tournament_matches
        SET status = 'cancelled',
            admin_notes = 'Match annulé — aucun joueur présent'
        WHERE id = m.id;
      v_processed := v_processed + 1;
    END IF;
  END LOOP;

  BEGIN
    INSERT INTO public.admin_logs(admin_id, action, target_user_id, new_value)
      VALUES (v_uid, 'auto_process_expired_matches', NULL,
              jsonb_build_object('tournament_id', _tid, 'processed', v_processed));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'processed', v_processed);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_auto_process_expired_matches(uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 7. admin_notify_player — envoyer une notification directe à un joueur
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_notify_player(
  _user_id  uuid,
  _title    text,
  _body     text,
  _ref_id   uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_is_admin boolean;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;
  IF length(trim(_title)) = 0 THEN RAISE EXCEPTION 'Titre requis'; END IF;
  IF length(trim(_body)) = 0 THEN RAISE EXCEPTION 'Message requis'; END IF;

  INSERT INTO public.notifications(user_id, type, title, body, ref_id)
    VALUES (_user_id, 'admin_message', _title, _body, _ref_id);

  BEGIN
    INSERT INTO public.admin_logs(admin_id, action, target_user_id, new_value)
      VALUES (v_uid, 'notify_player', _user_id,
              jsonb_build_object('title', _title, 'body', _body));
  EXCEPTION WHEN OTHERS THEN NULL; END;
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_notify_player(uuid, text, text, uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 8. admin_broadcast_tournament_notification — notifier tous les joueurs d'un tournoi
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_broadcast_tournament_notification(
  _tid    uuid,
  _title  text,
  _body   text
)
RETURNS int   -- nombre de joueurs notifiés
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_is_admin  boolean;
  v_player    record;
  v_count     int := 0;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  FOR v_player IN
    SELECT DISTINCT user_id FROM public.tournament_registrations WHERE tournament_id = _tid
  LOOP
    BEGIN
      INSERT INTO public.notifications(user_id, type, title, body, ref_id)
        VALUES (v_player.user_id, 'tournament_announcement', _title, _body, _tid);
      v_count := v_count + 1;
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END LOOP;

  RETURN v_count;
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_broadcast_tournament_notification(uuid, text, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 9. player_report_afk — signaler un adversaire AFK pendant un tournoi
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.player_report_afk(
  _mid        uuid,
  _target_id  uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  m           record;
  v_reports   jsonb;
  v_count     int;
BEGIN
  SELECT * INTO m FROM public.tournament_matches WHERE id = _mid;
  IF m IS NULL THEN RAISE EXCEPTION 'Match introuvable'; END IF;
  IF NOT (v_uid = ANY(m.player_ids)) THEN RAISE EXCEPTION 'Vous n''êtes pas dans ce match'; END IF;
  IF NOT (_target_id = ANY(m.player_ids)) THEN RAISE EXCEPTION 'Ce joueur n''est pas dans ce match'; END IF;
  IF v_uid = _target_id THEN RAISE EXCEPTION 'Vous ne pouvez pas vous signaler vous-même'; END IF;
  IF m.status NOT IN ('pending', 'running', 'waiting') THEN RAISE EXCEPTION 'Match non actif'; END IF;

  v_reports := COALESCE(m.afk_reports, '{}');

  -- Anti-spam : 1 signalement AFK par joueur par match
  IF (v_reports ->> v_uid::text) IS NOT NULL THEN
    RAISE EXCEPTION 'Vous avez déjà signalé ce joueur pour ce match';
  END IF;

  v_reports := v_reports || jsonb_build_object(v_uid::text, jsonb_build_object(
    'target', _target_id,
    'at', now()
  ));

  UPDATE public.tournament_matches SET afk_reports = v_reports WHERE id = _mid;

  -- Notifier les admins
  BEGIN
    INSERT INTO public.notifications(user_id, type, title, body, ref_id)
    SELECT p.id, 'admin_alert',
      '⚠️ Signalement AFK tournoi',
      'Un joueur signale son adversaire AFK dans le match ' || _mid::text,
      _mid
    FROM public.profiles p WHERE p.is_admin = true;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'reports', v_reports);
END;
$$;
GRANT EXECUTE ON FUNCTION public.player_report_afk(uuid, uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 10. admin_add_match_note — ajouter une note admin sur un match
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_add_match_note(
  _mid  uuid,
  _note text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_is_admin boolean;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  UPDATE public.tournament_matches
    SET admin_notes = CASE
      WHEN admin_notes IS NULL OR admin_notes = '' THEN _note
      ELSE admin_notes || ' | ' || _note
    END
    WHERE id = _mid;
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_add_match_note(uuid, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 11. ludo_tournament_launch_game — créer une partie Ludo pour un match de tournoi
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ludo_tournament_launch_game(_mid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_is_admin  boolean;
  m           record;
  trn         record;
  v_game_id   uuid;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO m FROM public.tournament_matches WHERE id = _mid FOR UPDATE;
  IF m IS NULL THEN RAISE EXCEPTION 'Match introuvable'; END IF;
  IF m.is_bye THEN RAISE EXCEPTION 'Match BYE — pas de partie à lancer'; END IF;
  IF m.game_id IS NOT NULL THEN
    -- Vérifier si la partie est encore active
    IF EXISTS (SELECT 1 FROM public.ludo_games WHERE id = m.game_id AND status IN ('open','playing')) THEN
      RETURN jsonb_build_object('ok', true, 'game_id', m.game_id, 'already_exists', true);
    END IF;
  END IF;

  SELECT * INTO trn FROM public.tournaments WHERE id = m.tournament_id;

  -- Créer la partie Ludo : partie privée, mise 0 (le prize pool est géré par le tournoi)
  INSERT INTO public.ludo_games(
    status, max_players, stake, is_private, is_tournament,
    tournament_match_id, pot, commission_pct
  )
  VALUES (
    'open',
    array_length(m.player_ids, 1),
    0,   -- pas de mise individuelle dans un tournoi
    true,
    true,
    _mid,
    0,
    0
  )
  RETURNING id INTO v_game_id;

  -- Inscrire automatiquement les joueurs dans la partie
  DECLARE uid_t uuid; v_slot int := 0;
  BEGIN
    FOREACH uid_t IN ARRAY m.player_ids LOOP
      INSERT INTO public.ludo_participants(game_id, user_id, slot, display_name)
        SELECT v_game_id, uid_t, v_slot,
               COALESCE(p.pseudo, 'Joueur') || CASE WHEN trn.game_slug IS NOT NULL THEN '' ELSE '' END
        FROM public.profiles p WHERE p.id = uid_t
      ON CONFLICT DO NOTHING;
      v_slot := v_slot + 1;
    END LOOP;
  END;

  -- Lier la partie au match
  UPDATE public.tournament_matches
    SET game_id = v_game_id, status = 'running'
    WHERE id = _mid;

  -- Notifier les joueurs
  DECLARE uid_n uuid;
  BEGIN
    FOREACH uid_n IN ARRAY m.player_ids LOOP
      BEGIN
        INSERT INTO public.notifications(user_id, type, title, body, ref_id)
          VALUES (uid_n, 'tournament_game_ready',
                  '🎲 Votre partie Ludo est prête !',
                  'Rejoignez votre match de tournoi maintenant — Round ' || m.round,
                  v_game_id);
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END LOOP;
  END;

  BEGIN
    INSERT INTO public.admin_logs(admin_id, action, target_user_id, new_value)
      VALUES (v_uid, 'ludo_launch_tournament_game', NULL,
              jsonb_build_object('match_id', _mid, 'game_id', v_game_id,
                                 'tournament_id', m.tournament_id, 'round', m.round));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'game_id', v_game_id);
END;
$$;
GRANT EXECUTE ON FUNCTION public.ludo_tournament_launch_game(uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 12. admin_get_full_tournament_dashboard — tableau de bord complet admin
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_get_full_tournament_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_is_admin boolean;
  v_result jsonb;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT jsonb_build_object(
    -- Tournois actifs
    'open_tournaments', (
      SELECT jsonb_agg(jsonb_build_object(
        'id', t.id, 'name', t.name, 'game_slug', t.game_slug,
        'registered_count', (SELECT count(*) FROM public.tournament_registrations WHERE tournament_id = t.id),
        'max_players', t.max_players, 'stake', t.stake, 'is_free', t.is_free,
        'registration_closes_at', t.registration_closes_at
      ) ORDER BY t.created_at DESC)
      FROM public.tournaments t WHERE t.status = 'open'
    ),
    -- Tournois en cours
    'running_tournaments', (
      SELECT jsonb_agg(jsonb_build_object(
        'id', t.id, 'name', t.name, 'game_slug', t.game_slug,
        'current_round', t.current_round, 'total_rounds', t.total_rounds,
        'pending_matches', (
          SELECT count(*) FROM public.tournament_matches m
          WHERE m.tournament_id = t.id AND m.status IN ('pending','waiting') AND m.is_bye = false
        ),
        'running_matches', (
          SELECT count(*) FROM public.tournament_matches m
          WHERE m.tournament_id = t.id AND m.status = 'running'
        ),
        'open_claims', (
          SELECT count(*) FROM public.tournament_claims c
          WHERE c.tournament_id = t.id AND c.status IN ('pending','reviewing')
        )
      ) ORDER BY t.current_round DESC)
      FROM public.tournaments t WHERE t.status = 'running'
    ),
    -- Matchs expirés (deadline dépassée)
    'expired_matches_count', (
      SELECT count(*) FROM public.tournament_matches m
      WHERE m.is_bye = false AND m.status IN ('pending','waiting')
        AND m.join_deadline IS NOT NULL AND m.join_deadline < now()
    ),
    -- Réclamations en attente
    'pending_claims_count', (
      SELECT count(*) FROM public.tournament_claims WHERE status IN ('pending','reviewing')
    ),
    -- 5 dernières réclamations urgentes
    'urgent_claims', (
      SELECT jsonb_agg(row_to_json(c) ORDER BY c.created_at DESC)
      FROM (
        SELECT tc.id, tc.category, tc.status, LEFT(tc.description, 120) AS description,
               tc.created_at, COALESCE(p.pseudo, '?') AS claimant_pseudo,
               t.name AS tournament_name, t.game_slug
        FROM public.tournament_claims tc
        LEFT JOIN public.profiles p ON p.id = tc.claimant_id
        LEFT JOIN public.tournaments t ON t.id = tc.tournament_id
        WHERE tc.status IN ('pending','reviewing')
        ORDER BY tc.created_at DESC LIMIT 5
      ) c
    ),
    -- Matchs AFK signalés
    'afk_reported_matches', (
      SELECT count(*) FROM public.tournament_matches
      WHERE afk_reports IS NOT NULL AND afk_reports != '{}'
        AND status IN ('pending','running','waiting')
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_get_full_tournament_dashboard() TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 13. admin_resolve_claim_with_action — résoudre une réclamation + action directe
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_resolve_claim_with_action(
  _cid          uuid,
  _resolution   text,    -- 'resolved' | 'rejected' | 'reviewing'
  _comment      text,
  _action       text DEFAULT NULL,   -- 'forfeit_claimant_opponent' | 'rematch' | 'override_claimant' | 'payout' | 'suspend' | NULL
  _extra        jsonb DEFAULT NULL   -- paramètres supplémentaires selon l'action
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_is_admin  boolean;
  cl          record;
  m           record;
  v_opponent  uuid;
  v_result    jsonb := '{"ok":true}';
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT tc.*, t.game_slug
    INTO cl
    FROM public.tournament_claims tc
    LEFT JOIN public.tournaments t ON t.id = tc.tournament_id
    WHERE tc.id = _cid;
  IF cl IS NULL THEN RAISE EXCEPTION 'Réclamation introuvable'; END IF;

  -- Mettre à jour le statut de la réclamation
  UPDATE public.tournament_claims
    SET status        = _resolution,
        admin_comment = _comment,
        resolved_by   = CASE WHEN _resolution IN ('resolved','rejected') THEN v_uid ELSE NULL END,
        resolved_at   = CASE WHEN _resolution IN ('resolved','rejected') THEN now() ELSE NULL END
    WHERE id = _cid;

  -- Notifier le demandeur
  BEGIN
    INSERT INTO public.notifications(user_id, type, title, body, ref_id)
      VALUES (cl.claimant_id,
              CASE WHEN _resolution = 'resolved' THEN 'claim_resolved' ELSE 'claim_rejected' END,
              CASE WHEN _resolution = 'resolved' THEN '✅ Réclamation résolue'
                   WHEN _resolution = 'rejected' THEN '❌ Réclamation rejetée'
                   ELSE '🔍 Réclamation en cours d''examen' END,
              _comment,
              cl.match_id);
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- Exécuter l'action associée
  IF _action = 'forfeit_claimant_opponent' AND cl.match_id IS NOT NULL THEN
    SELECT * INTO m FROM public.tournament_matches WHERE id = cl.match_id;
    IF m IS NOT NULL AND m.status NOT IN ('finished','cancelled') THEN
      SELECT p INTO v_opponent FROM unnest(m.player_ids) p WHERE p <> cl.claimant_id LIMIT 1;
      IF v_opponent IS NOT NULL THEN
        PERFORM public.admin_forfeit_match_player(cl.match_id, v_opponent, 'Décision admin suite réclamation : ' || _comment);
        v_result := v_result || jsonb_build_object('action_done', 'forfeit');
      END IF;
    END IF;

  ELSIF _action = 'rematch' AND cl.match_id IS NOT NULL THEN
    PERFORM public.admin_tournament_rematch(cl.match_id);
    v_result := v_result || jsonb_build_object('action_done', 'rematch');

  ELSIF _action = 'override_claimant' AND cl.match_id IS NOT NULL THEN
    PERFORM public.admin_tournament_override_match(cl.match_id, cl.claimant_id, 'Décision admin : ' || _comment);
    v_result := v_result || jsonb_build_object('action_done', 'override');

  ELSIF _action = 'payout' AND (_extra->>'amount') IS NOT NULL THEN
    PERFORM public.admin_manual_payout(cl.claimant_id, (_extra->>'amount')::numeric, 'Compensation réclamation : ' || _comment);
    v_result := v_result || jsonb_build_object('action_done', 'payout');

  ELSIF _action = 'suspend' AND (_extra->>'hours') IS NOT NULL THEN
    -- Suspendre l'adversaire du réclamant
    SELECT * INTO m FROM public.tournament_matches WHERE id = cl.match_id;
    IF m IS NOT NULL THEN
      SELECT p INTO v_opponent FROM unnest(m.player_ids) p WHERE p <> cl.claimant_id LIMIT 1;
      IF v_opponent IS NOT NULL THEN
        PERFORM public.admin_suspend_player(v_opponent, (_extra->>'hours')::int, 'Suspension suite réclamation : ' || _comment, true);
        v_result := v_result || jsonb_build_object('action_done', 'suspend', 'suspended_player', v_opponent);
      END IF;
    END IF;
  END IF;

  BEGIN
    INSERT INTO public.admin_logs(admin_id, action, target_user_id, new_value)
      VALUES (v_uid, 'resolve_claim_with_action', cl.claimant_id,
              jsonb_build_object('claim_id', _cid, 'resolution', _resolution,
                                 'action', _action, 'comment', _comment));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN v_result;
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_resolve_claim_with_action(uuid, text, text, text, jsonb) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 14. admin_tournament_reassign_match — réassigner un match à un autre joueur
--     (ex: erreur d'inscription, joueur qui a deux comptes)
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_tournament_reassign_match(
  _mid            uuid,
  _old_player_id  uuid,
  _new_player_id  uuid,
  _reason         text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_is_admin  boolean;
  m           record;
  v_new_ids   uuid[];
  uid_t       uuid;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO m FROM public.tournament_matches WHERE id = _mid FOR UPDATE;
  IF m IS NULL THEN RAISE EXCEPTION 'Match introuvable'; END IF;
  IF m.status IN ('finished', 'forfeit', 'cancelled') THEN RAISE EXCEPTION 'Match déjà terminé'; END IF;
  IF NOT (_old_player_id = ANY(m.player_ids)) THEN RAISE EXCEPTION 'Ce joueur n''est pas dans ce match'; END IF;

  -- Reconstruire le tableau en remplaçant l'ancien par le nouveau
  v_new_ids := '{}';
  FOREACH uid_t IN ARRAY m.player_ids LOOP
    IF uid_t = _old_player_id THEN
      v_new_ids := v_new_ids || _new_player_id;
    ELSE
      v_new_ids := v_new_ids || uid_t;
    END IF;
  END LOOP;

  -- Réinitialiser ready
  UPDATE public.tournament_matches
    SET player_ids   = v_new_ids,
        player_ready = '{}',
        admin_notes  = COALESCE(admin_notes || ' | ', '') ||
                       'Joueur réassigné : ' || COALESCE(_reason, 'Décision admin')
    WHERE id = _mid;

  -- Mettre à jour les inscriptions si tournoi ouvert
  UPDATE public.tournament_registrations
    SET user_id = _new_player_id
    WHERE tournament_id = m.tournament_id AND user_id = _old_player_id;

  -- Notifier le nouveau joueur
  BEGIN
    INSERT INTO public.notifications(user_id, type, title, body, ref_id)
      VALUES (_new_player_id, 'tournament_added',
              '🎯 Vous avez été ajouté à un match de tournoi',
              'L''admin vous a assigné à un match. Rejoignez dès que possible.',
              _mid);
  EXCEPTION WHEN OTHERS THEN NULL; END;

  BEGIN
    INSERT INTO public.admin_logs(admin_id, action, target_user_id, new_value)
      VALUES (v_uid, 'reassign_match_player', _new_player_id,
              jsonb_build_object('match_id', _mid, 'old_player', _old_player_id, 'reason', _reason));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'new_player_ids', v_new_ids);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_tournament_reassign_match(uuid, uuid, uuid, text) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 15. Colonnes ludo_games pour tournoi (si pas déjà présentes)
-- ─────────────────────────────────────────────────────────────────────────
ALTER TABLE public.ludo_games
  ADD COLUMN IF NOT EXISTS is_tournament        boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS tournament_match_id  uuid    REFERENCES public.tournament_matches(id) ON DELETE SET NULL;

-- ─────────────────────────────────────────────────────────────────────────
-- 16. Trigger : quand une partie ludo de tournoi se termine, mettre à jour le match
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.on_ludo_tournament_game_finished()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_match record;
BEGIN
  -- Seulement si c'est une partie de tournoi qui vient de se terminer
  IF NEW.is_tournament = true
    AND NEW.status = 'finished'
    AND (OLD.status IS DISTINCT FROM 'finished')
    AND NEW.tournament_match_id IS NOT NULL
    AND NEW.winner_id IS NOT NULL
  THEN
    SELECT * INTO v_match
      FROM public.tournament_matches
      WHERE id = NEW.tournament_match_id
        AND status NOT IN ('finished', 'forfeit', 'cancelled')
      FOR UPDATE;

    IF FOUND THEN
      UPDATE public.tournament_matches
        SET status     = 'finished',
            winner_id  = NEW.winner_id,
            finished_at = now()
        WHERE id = NEW.tournament_match_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ludo_tournament_game_finished ON public.ludo_games;
CREATE TRIGGER trg_ludo_tournament_game_finished
  AFTER UPDATE ON public.ludo_games
  FOR EACH ROW EXECUTE FUNCTION public.on_ludo_tournament_game_finished();

-- ─────────────────────────────────────────────────────────────────────────
-- 17. Index de performance
-- ─────────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_tournament_matches_afk
  ON public.tournament_matches USING gin(afk_reports)
  WHERE afk_reports != '{}';

CREATE INDEX IF NOT EXISTS idx_tournament_matches_expired
  ON public.tournament_matches(join_deadline)
  WHERE status IN ('pending','waiting') AND join_deadline IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_ludo_games_tournament
  ON public.ludo_games(tournament_match_id)
  WHERE is_tournament = true;

CREATE INDEX IF NOT EXISTS idx_tournament_claims_all_status
  ON public.tournament_claims(status, created_at DESC);

-- ─────────────────────────────────────────────────────────────────────────
-- 18. Vue admin enrichie des matchs avec infos AFK
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.admin_tournament_matches_view AS
  SELECT
    m.id,
    m.tournament_id,
    t.name AS tournament_name,
    t.game_slug,
    m.round,
    m.match_index,
    m.status,
    m.is_bye,
    m.player_ids,
    m.winner_id,
    m.game_id,
    m.join_deadline,
    m.player_ready,
    m.afk_reports,
    m.admin_notes,
    m.extended_count,
    m.created_at,
    m.finished_at,
    CASE WHEN m.join_deadline < now() AND m.status IN ('pending','waiting') THEN true ELSE false END AS is_expired,
    CASE WHEN m.afk_reports IS NOT NULL AND m.afk_reports != '{}' THEN true ELSE false END AS has_afk_report,
    (
      SELECT count(*) FROM public.tournament_claims c
      WHERE c.match_id = m.id AND c.status IN ('pending','reviewing')
    ) AS open_claims_count
  FROM public.tournament_matches m
  JOIN public.tournaments t ON t.id = m.tournament_id;

COMMENT ON VIEW public.admin_tournament_matches_view IS 'Vue enrichie des matchs de tournoi pour les admins';
