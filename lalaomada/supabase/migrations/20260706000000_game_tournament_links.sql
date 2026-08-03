-- ============================================================
-- Migration: 20260706000000_game_tournament_links.sql
-- Corrections critiques :
--   1. domino_games → tournament_match_id + domino_tournament_launch_game
--   2. Trigger domino_games → mise à jour auto du match tournoi
--   3. Ludo 4 joueurs → finish_position + classement dans match_rankings
--   4. player_forfeit_match (abandon volontaire)
--   5. admin_apply_grace_period (délai de grâce)
--   6. admin_close_expired_registrations (fermeture auto)
-- ============================================================

-- ══════════════════════════════════════════════════════════════
-- SECTION 1 : domino_games — colonne tournament_match_id
-- ══════════════════════════════════════════════════════════════

ALTER TABLE public.domino_games
  ADD COLUMN IF NOT EXISTS tournament_match_id uuid
    REFERENCES public.tournament_matches(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_domino_games_tournament
  ON public.domino_games(tournament_match_id)
  WHERE tournament_match_id IS NOT NULL;

-- ══════════════════════════════════════════════════════════════
-- SECTION 2 : domino_tournament_launch_game(_mid)
-- Crée une partie Domino liée à un match de tournoi
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.domino_tournament_launch_game(_mid uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  m          record;
  v_game_id  uuid;
  v_slot     int := 0;
  uid_t      uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO m FROM public.tournament_matches WHERE id = _mid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Match introuvable'; END IF;
  IF m.status IN ('finished','forfeit','cancelled') THEN
    RAISE EXCEPTION 'Match déjà terminé';
  END IF;

  -- Réutiliser la partie existante si encore active
  IF m.game_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.domino_games
      WHERE id = m.game_id AND status IN ('open','playing')
    ) THEN
      RETURN jsonb_build_object('ok',true,'game_id',m.game_id,'already_exists',true);
    END IF;
  END IF;

  -- Créer la partie Domino
  INSERT INTO public.domino_games(
    host_id, status, stake, pot, commission_pct,
    is_private, room_code, tournament_match_id
  ) VALUES (
    m.player_ids[1], 'open', 0, 0, 0,
    true,
    upper(substring(md5(random()::text) from 1 for 6)),
    _mid
  ) RETURNING id INTO v_game_id;

  -- Ajouter les participants
  FOREACH uid_t IN ARRAY m.player_ids LOOP
    v_slot := v_slot + 1;
    INSERT INTO public.domino_participants(game_id, user_id, slot)
    VALUES (v_game_id, uid_t, v_slot)
    ON CONFLICT DO NOTHING;
  END LOOP;

  -- Lier le match à la partie
  UPDATE public.tournament_matches
    SET game_id = v_game_id,
        status  = 'running'
    WHERE id = _mid;

  -- Notifier les joueurs
  FOREACH uid_t IN ARRAY m.player_ids LOOP
    INSERT INTO public.notifications(user_id, type, title, body, ref_id)
    VALUES (
      uid_t, 'tournament_game_ready',
      '🁣 Partie Domino prête !',
      'Votre match de tournoi est prêt. Rejoignez maintenant !',
      v_game_id
    );
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true, 'game_id', v_game_id, 'match_id', _mid,
    'players', array_length(m.player_ids, 1)
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.domino_tournament_launch_game(uuid) TO authenticated;

-- ══════════════════════════════════════════════════════════════
-- SECTION 3 : Trigger domino_games → tournament_matches
-- Mise à jour automatique quand la partie Domino se termine
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._trg_domino_tournament_finished()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_match    record;
  v_rankings jsonb;
  v_rank     int;
  rec        record;
  v_n        int;
BEGIN
  -- Déclencher uniquement quand le jeu passe à 'finished'
  IF NEW.status <> 'finished' OR OLD.status = 'finished' THEN RETURN NEW; END IF;
  IF NEW.tournament_match_id IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_match FROM public.tournament_matches
    WHERE id = NEW.tournament_match_id
      AND status NOT IN ('finished','forfeit','cancelled');
  IF NOT FOUND THEN RETURN NEW; END IF;

  v_n := COALESCE(array_length(v_match.player_ids, 1), 2);

  IF v_n = 2 AND NEW.winner_id IS NOT NULL THEN
    -- Cas classique 1v1 : winner_id suffit
    UPDATE public.tournament_matches
      SET status      = 'finished',
          winner_id   = NEW.winner_id,
          finished_at = now()
      WHERE id = NEW.tournament_match_id;
  ELSE
    -- Cas multi-joueurs (ou égalité) : classement par score DESC
    v_rankings := '{}'::jsonb;
    v_rank     := 1;
    FOR rec IN
      SELECT dp.user_id
      FROM public.domino_participants dp
      WHERE dp.game_id = NEW.id
        AND dp.user_id IS NOT NULL
      ORDER BY dp.score DESC, dp.forfeited ASC, dp.slot ASC
    LOOP
      v_rankings := v_rankings
                 || jsonb_build_object(v_rank::text, rec.user_id::text);
      v_rank := v_rank + 1;
    END LOOP;

    -- Si égalité (scores identiques en tête) → laisser winner_id NULL pour rematch admin
    UPDATE public.tournament_matches
      SET status         = 'finished',
          winner_id      = NEW.winner_id,   -- peut être NULL si égalité
          match_rankings = v_rankings,
          finished_at    = now()
      WHERE id = NEW.tournament_match_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_domino_tournament_game_finished ON public.domino_games;
CREATE TRIGGER trg_domino_tournament_game_finished
  AFTER UPDATE ON public.domino_games
  FOR EACH ROW EXECUTE FUNCTION public._trg_domino_tournament_finished();

-- ══════════════════════════════════════════════════════════════
-- SECTION 4 : Ludo 4 joueurs — finish_position + trigger amélioré
-- ══════════════════════════════════════════════════════════════

-- 4a. Colonne finish_position sur ludo_participants
ALTER TABLE public.ludo_participants
  ADD COLUMN IF NOT EXISTS finish_position int;

-- 4b. Fonction appelée par le moteur Ludo quand un joueur finit ses pions
CREATE OR REPLACE FUNCTION public.ludo_set_finish_position(
  _game_id uuid,
  _user_id uuid,
  _position int
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.ludo_participants
    SET finish_position = _position
    WHERE game_id = _game_id
      AND user_id  = _user_id
      AND finish_position IS NULL;   -- ne pas écraser si déjà enregistré
END;
$$;
GRANT EXECUTE ON FUNCTION public.ludo_set_finish_position(uuid,uuid,int) TO authenticated;

-- 4c. Trigger Ludo amélioré : gère 1v1 ET 4 joueurs
CREATE OR REPLACE FUNCTION public._trg_ludo_tournament_finished()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_match    record;
  v_rankings jsonb;
  v_rank     int;
  rec        record;
  v_n        int;
BEGIN
  IF NEW.status <> 'finished' OR OLD.status = 'finished' THEN RETURN NEW; END IF;
  IF NEW.tournament_match_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.winner_id IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_match FROM public.tournament_matches
    WHERE id = NEW.tournament_match_id
      AND status NOT IN ('finished','forfeit','cancelled');
  IF NOT FOUND THEN RETURN NEW; END IF;

  v_n := COALESCE(array_length(v_match.player_ids, 1), 2);

  IF v_n <= 2 THEN
    -- Cas classique 1v1
    UPDATE public.tournament_matches
      SET status      = 'finished',
          winner_id   = NEW.winner_id,
          finished_at = now()
      WHERE id = NEW.tournament_match_id;
  ELSE
    -- Cas 4 joueurs : 1er = winner_id, puis classés par finish_position ASC
    -- Les joueurs sans finish_position (non éliminés) sont classés en dernier par slot
    v_rankings := jsonb_build_object('1', NEW.winner_id::text);
    v_rank := 2;

    FOR rec IN
      SELECT lp.user_id
      FROM public.ludo_participants lp
      WHERE lp.game_id  = NEW.id
        AND lp.user_id IS NOT NULL
        AND lp.user_id <> NEW.winner_id
        AND lp.is_bot   = false
      ORDER BY
        CASE WHEN lp.finish_position IS NOT NULL
             THEN lp.finish_position ELSE 9999 END ASC,
        lp.forfeited ASC,   -- forfeités en dernier
        lp.slot ASC
    LOOP
      v_rankings := v_rankings
                 || jsonb_build_object(v_rank::text, rec.user_id::text);
      v_rank := v_rank + 1;
    END LOOP;

    UPDATE public.tournament_matches
      SET status         = 'finished',
          winner_id      = NEW.winner_id,
          match_rankings = v_rankings,
          finished_at    = now()
      WHERE id = NEW.tournament_match_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ludo_tournament_game_finished ON public.ludo_games;
CREATE TRIGGER trg_ludo_tournament_game_finished
  AFTER UPDATE ON public.ludo_games
  FOR EACH ROW EXECUTE FUNCTION public._trg_ludo_tournament_finished();

-- ══════════════════════════════════════════════════════════════
-- SECTION 5 : player_forfeit_match — abandon volontaire
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.player_forfeit_match(_mid uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  m          record;
  v_uid      uuid := auth.uid();
  v_opponent uuid;
  v_prize    numeric;
  v_comm     numeric;
BEGIN
  SELECT * INTO m FROM public.tournament_matches WHERE id = _mid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Match introuvable'; END IF;
  IF m.status IN ('finished','forfeit','cancelled') THEN
    RAISE EXCEPTION 'Ce match est déjà terminé';
  END IF;
  IF NOT (v_uid = ANY(m.player_ids)) THEN
    RAISE EXCEPTION 'Vous ne faites pas partie de ce match';
  END IF;

  -- Adversaire (ou 1er autre joueur en multi)
  SELECT p INTO v_opponent
    FROM unnest(m.player_ids) p
    WHERE p <> v_uid
    LIMIT 1;

  -- Forfait
  UPDATE public.tournament_matches
    SET status      = 'forfeit',
        winner_id   = v_opponent,
        forfeit_ids = array_append(COALESCE(forfeit_ids,'{}'), v_uid),
        finished_at = now()
    WHERE id = _mid;

  -- Forcer la fin de la partie liée si elle est encore en cours
  IF m.game_id IS NOT NULL THEN
    UPDATE public.ludo_games
      SET status = 'finished', winner_id = v_opponent, finished_at = now()
      WHERE id = m.game_id AND status IN ('open','playing')
        AND tournament_match_id = _mid;
    UPDATE public.domino_games
      SET status = 'finished', winner_id = v_opponent, finished_at = now()
      WHERE id = m.game_id AND status IN ('open','playing')
        AND tournament_match_id = _mid;
  END IF;

  -- Notifier les deux joueurs
  INSERT INTO public.notifications(user_id, type, title, body, ref_id) VALUES
    (v_uid,      'match_forfeit',     '🏳️ Abandon enregistré',
     'Vous avez abandonné ce match. Votre adversaire remporte le point.', _mid),
    (v_opponent, 'match_forfeit_win', '🏆 Victoire par forfait',
     'Votre adversaire a abandonné. Vous passez au tour suivant !', _mid);

  RETURN jsonb_build_object('ok',true,'forfeit_by',v_uid,'winner',v_opponent);
END;
$$;
GRANT EXECUTE ON FUNCTION public.player_forfeit_match(uuid) TO authenticated;

-- ══════════════════════════════════════════════════════════════
-- SECTION 6 : admin_apply_grace_period
-- Applique le délai de grâce au 1er round : absent = forfait
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_apply_grace_period(_tid uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  t           record;
  m           record;
  v_present   uuid[];
  v_absent    uuid[];
  v_winner    uuid;
  v_count     int := 0;
  uid_t       uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO t FROM public.tournaments WHERE id = _tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;
  IF t.status <> 'running' THEN RAISE EXCEPTION 'Tournoi non en cours'; END IF;

  FOR m IN
    SELECT * FROM public.tournament_matches
    WHERE tournament_id = _tid
      AND status        = 'pending'
      AND round         = 1
      AND ready_deadline IS NOT NULL
      AND ready_deadline < now()
  LOOP
    -- Joueurs présents (ayant cliqué Prêt)
    SELECT ARRAY(
      SELECT uid FROM unnest(m.player_ids) uid
      WHERE COALESCE((m.player_ready->>uid::text)::boolean, false)
    ) INTO v_present;

    -- Joueurs absents
    SELECT ARRAY(
      SELECT uid FROM unnest(m.player_ids) uid
      WHERE NOT COALESCE((m.player_ready->>uid::text)::boolean, false)
    ) INTO v_absent;

    CONTINUE WHEN COALESCE(array_length(v_absent,1),0) = 0;

    -- Marquer les absents en forfait
    FOREACH uid_t IN ARRAY v_absent LOOP
      UPDATE public.tournament_matches
        SET forfeit_ids = array_append(COALESCE(forfeit_ids,'{}'), uid_t)
        WHERE id = m.id;
      INSERT INTO public.notifications(user_id, type, title, body, ref_id)
      VALUES (uid_t, 'match_forfeit', '⏰ Délai de grâce expiré',
        'Vous n''étiez pas prêt dans le délai imparti — match forfait.', m.id);
    END LOOP;

    IF COALESCE(array_length(v_present,1),0) = 1 THEN
      -- Un seul joueur présent → forfait pour les absents
      v_winner := v_present[1];
      UPDATE public.tournament_matches
        SET status = 'forfeit', winner_id = v_winner, finished_at = now()
        WHERE id = m.id;
      INSERT INTO public.notifications(user_id, type, title, body, ref_id)
      VALUES (v_winner, 'match_forfeit_win', '🏆 Victoire — adversaire absent',
        'Votre adversaire n''était pas là. Vous passez au tour suivant !', m.id);
      v_count := v_count + 1;

    ELSIF COALESCE(array_length(v_present,1),0) = 0 THEN
      -- Personne n'était là → match annulé
      UPDATE public.tournament_matches
        SET status = 'cancelled', finished_at = now()
        WHERE id = m.id;
      v_count := v_count + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('ok',true,'matches_resolved',v_count);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_apply_grace_period(uuid) TO authenticated;

-- ══════════════════════════════════════════════════════════════
-- SECTION 7 : admin_close_expired_registrations
-- Ferme automatiquement les inscriptions expirées
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_close_expired_registrations()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_count int := 0;
  t       record;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  FOR t IN
    SELECT id, title FROM public.tournaments
    WHERE status = 'open'
      AND registration_closes_at IS NOT NULL
      AND registration_closes_at < now()
  LOOP
    UPDATE public.tournaments
      SET status = 'registrations_closed'
      WHERE id = t.id;

    -- Notifier tous les inscrits confirmés
    INSERT INTO public.notifications(user_id, type, title, body, ref_id)
    SELECT user_id, 'tournament_update',
      '🔒 Inscriptions fermées',
      'Les inscriptions pour "' || t.title || '" sont désormais fermées. Le tournoi va bientôt démarrer.',
      t.id
    FROM public.tournament_registrations
    WHERE tournament_id = t.id AND status = 'confirmed';

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('ok',true,'tournaments_closed',v_count);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_close_expired_registrations() TO authenticated;

-- ══════════════════════════════════════════════════════════════
-- SECTION 8 : Vue admin_tournament_dashboard (enrichie)
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW public.admin_tournament_dashboard AS
SELECT
  t.id, t.title, t.game_type, t.status, t.format,
  t.max_players, t.players_per_table, t.qualifiers_per_table,
  t.entry_fee, t.prize_pool, t.reward_distribution,
  t.rewards_paid_at, t.archived_at,
  t.registration_opens_at, t.registration_closes_at,
  t.auto_start_mins, t.grace_period_secs,
  t.created_at, t.podium,
  (SELECT COUNT(*)::int FROM public.tournament_registrations r
   WHERE r.tournament_id = t.id AND r.status = 'confirmed')   AS confirmed_count,
  (SELECT COUNT(*)::int FROM public.tournament_matches m
   WHERE m.tournament_id = t.id)                              AS total_matches,
  (SELECT COUNT(*)::int FROM public.tournament_matches m
   WHERE m.tournament_id = t.id AND m.status = 'pending')     AS pending_matches,
  (SELECT COUNT(*)::int FROM public.tournament_matches m
   WHERE m.tournament_id = t.id AND m.status = 'running')     AS running_matches,
  (SELECT COUNT(*)::int FROM public.tournament_matches m
   WHERE m.tournament_id = t.id
     AND m.status IN ('finished','forfeit'))                   AS done_matches,
  (SELECT MAX(m.round) FROM public.tournament_matches m
   WHERE m.tournament_id = t.id)                              AS current_round,
  (SELECT COUNT(*)::int FROM public.tournament_matches m
   WHERE m.tournament_id = t.id AND m.winner_id IS NULL
     AND m.status = 'finished')                               AS tie_matches
FROM public.tournaments t
ORDER BY t.created_at DESC;
