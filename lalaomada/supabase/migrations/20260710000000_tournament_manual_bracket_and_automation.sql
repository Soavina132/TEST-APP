-- =====================================================================
-- Migration : 4 fonctionnalités manquantes du système de tournois
--   1. Éditeur de bracket manuel (déplacer/échanger joueur, conversion
--      pool<->1v1, réduction pool de 4 -> 3, bye manuel, reshuffle round)
--   2. Règle anti-même-pool pour l'appariement du round suivant
--   3. Démarrage par lot (batch) de N matchs
--   4. Avancement de round entièrement automatique (option par tournoi)
-- =====================================================================

-- ══════════════════════════════════════════════════════════════
-- SECTION 0 : colonne pour activer/désactiver l'auto-avancement
-- ══════════════════════════════════════════════════════════════
ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS auto_advance_rounds boolean NOT NULL DEFAULT false;

-- ══════════════════════════════════════════════════════════════
-- SECTION 1 : logique cœur d'avancement de round, réutilisable
--   par l'action admin manuelle ET par le trigger automatique.
--   Ajoute la règle anti-même-pool + le support des pools (top-N
--   qualifiés via match_rankings) en plus du 1v1 classique.
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._tournament_advance_round_core(_tid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  trn           record;
  rec           record;
  v_qual_per    int;
  v_next_round  int;
  v_count       int;
  v_ids         uuid[] := '{}';
  v_src         uuid[] := '{}';
  v_ordered_ids uuid[];
  v_ordered_src uuid[];
  i             int;
  j             int;
  tmp_uid       uuid;
  tmp_src       uuid;
BEGIN
  SELECT * INTO trn FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF trn IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;
  IF trn.status <> 'running' THEN RAISE EXCEPTION 'Tournoi non en cours'; END IF;

  IF EXISTS (
    SELECT 1 FROM public.tournament_matches
    WHERE tournament_id = _tid
      AND round = trn.current_round
      AND status NOT IN ('finished','forfeit','cancelled')
      AND is_bye = false
  ) THEN
    RAISE EXCEPTION 'Des matchs du round actuel ne sont pas encore terminés';
  END IF;

  v_qual_per := GREATEST(COALESCE(trn.qualifiers_per_table, 2), 1);

  -- Collecter les qualifiés : joueur + match d'origine (= "pool")
  FOR rec IN
    SELECT m.id AS mid, m.player_ids, m.winner_id, m.match_rankings, m.is_bye,
           array_length(m.player_ids, 1) AS n
    FROM public.tournament_matches m
    WHERE m.tournament_id = _tid
      AND m.round = trn.current_round
      AND m.status IN ('finished','forfeit')
  LOOP
    IF rec.is_bye OR COALESCE(rec.n, 2) <= 2 THEN
      IF rec.winner_id IS NOT NULL THEN
        v_ids := v_ids || rec.winner_id;
        v_src := v_src || rec.mid;
      END IF;
    ELSE
      -- Pool (3+ joueurs) : prendre les N premiers du classement
      IF rec.match_rankings IS NOT NULL AND rec.match_rankings <> '{}'::jsonb THEN
        FOR i IN 1..LEAST(v_qual_per, rec.n - 1) LOOP
          IF rec.match_rankings ? i::text THEN
            v_ids := v_ids || (rec.match_rankings ->> i::text)::uuid;
            v_src := v_src || rec.mid;
          END IF;
        END LOOP;
      ELSIF rec.winner_id IS NOT NULL THEN
        v_ids := v_ids || rec.winner_id;
        v_src := v_src || rec.mid;
      END IF;
    END IF;
  END LOOP;

  v_count := COALESCE(array_length(v_ids, 1), 0);

  IF v_count <= 1 THEN
    -- Finale terminée → distribuer les gains
    UPDATE public.tournaments
      SET status = 'finished', winner_id = v_ids[1], finished_at = now()
      WHERE id = _tid;

    IF v_ids[1] IS NOT NULL THEN
      UPDATE public.profiles
        SET balance_ar = balance_ar + COALESCE(trn.prize_pool, 0)
        WHERE id = v_ids[1];

      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (v_ids[1], 'tournament_win', COALESCE(trn.prize_pool, 0), _tid,
                'Gains tournoi ' || COALESCE(trn.game_slug, 'multi'));
    END IF;

    RETURN jsonb_build_object('ok', true, 'finished', true, 'winner_id', v_ids[1]);
  END IF;

  -- ── Anti-même-pool : distribution en "peigne" par groupe d'origine,
  --    puis passe d'ajustement pour éviter deux joueurs de la même
  --    pool source dans un même match du round suivant.
  WITH shuffled AS (
    SELECT unnest(v_ids) AS uid, unnest(v_src) AS src, random() AS r
  ),
  grouped AS (
    SELECT uid, src, row_number() OVER (PARTITION BY src ORDER BY r) AS grp
    FROM shuffled
  )
  SELECT array_agg(uid ORDER BY grp, r), array_agg(src ORDER BY grp, r)
    INTO v_ordered_ids, v_ordered_src
    FROM grouped;

  i := 1;
  WHILE i < v_count LOOP
    IF v_ordered_src[i] = v_ordered_src[i + 1] THEN
      j := i + 2;
      WHILE j <= v_count LOOP
        IF v_ordered_src[j] <> v_ordered_src[i] THEN
          tmp_uid := v_ordered_ids[i + 1]; tmp_src := v_ordered_src[i + 1];
          v_ordered_ids[i + 1] := v_ordered_ids[j]; v_ordered_src[i + 1] := v_ordered_src[j];
          v_ordered_ids[j] := tmp_uid; v_ordered_src[j] := tmp_src;
          EXIT;
        END IF;
        j := j + 1;
      END LOOP;
    END IF;
    i := i + 2;
  END LOOP;

  v_next_round := trn.current_round + 1;
  UPDATE public.tournaments SET current_round = v_next_round WHERE id = _tid;

  i := 1;
  WHILE i + 1 <= v_count LOOP
    INSERT INTO public.tournament_matches(tournament_id, round, player_ids, status, is_bye)
      VALUES (_tid, v_next_round, ARRAY[v_ordered_ids[i], v_ordered_ids[i + 1]], 'pending', false);
    i := i + 2;
  END LOOP;

  IF v_count % 2 = 1 THEN
    INSERT INTO public.tournament_matches(tournament_id, round, player_ids, status, is_bye, winner_id, finished_at)
      VALUES (_tid, v_next_round, ARRAY[v_ordered_ids[v_count]], 'finished', true, v_ordered_ids[v_count], now());
  END IF;

  RETURN jsonb_build_object('ok', true, 'finished', false, 'next_round', v_next_round, 'qualifiers', v_count);
END;
$$;

-- admin_advance_tournament_round garde la même signature mais délègue
-- désormais à la logique cœur (pools + anti-même-pool inclus).
CREATE OR REPLACE FUNCTION public.admin_advance_tournament_round(_tid uuid)
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

  PERFORM public._tournament_advance_round_core(_tid);
END;
$$;

-- ══════════════════════════════════════════════════════════════
-- SECTION 2 : Avancement de round entièrement automatique
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.admin_set_tournament_auto_advance(_tid uuid, _enabled boolean)
RETURNS jsonb
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

  UPDATE public.tournaments SET auto_advance_rounds = _enabled WHERE id = _tid;

  INSERT INTO public.admin_logs(admin_id, action, target_id, new_value)
    VALUES (v_uid, 'tournament_set_auto_advance', _tid, jsonb_build_object('enabled', _enabled));

  RETURN jsonb_build_object('ok', true, 'auto_advance_rounds', _enabled);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_set_tournament_auto_advance(uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public._trg_tournament_match_auto_advance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  trn         record;
  v_remaining int;
BEGIN
  IF NEW.status NOT IN ('finished','forfeit','cancelled') THEN RETURN NEW; END IF;
  IF OLD.status = NEW.status THEN RETURN NEW; END IF;
  IF NEW.is_bye THEN RETURN NEW; END IF;

  SELECT * INTO trn FROM public.tournaments WHERE id = NEW.tournament_id;
  IF trn IS NULL OR trn.status <> 'running' OR NOT COALESCE(trn.auto_advance_rounds, false) THEN
    RETURN NEW;
  END IF;
  IF NEW.round <> trn.current_round THEN RETURN NEW; END IF;

  SELECT count(*) INTO v_remaining
    FROM public.tournament_matches
    WHERE tournament_id = NEW.tournament_id
      AND round = trn.current_round
      AND status NOT IN ('finished','forfeit','cancelled')
      AND is_bye = false;

  IF v_remaining = 0 THEN
    PERFORM public._tournament_advance_round_core(NEW.tournament_id);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tournament_match_auto_advance ON public.tournament_matches;
CREATE TRIGGER trg_tournament_match_auto_advance
  AFTER UPDATE ON public.tournament_matches
  FOR EACH ROW EXECUTE FUNCTION public._trg_tournament_match_auto_advance();

-- ══════════════════════════════════════════════════════════════
-- SECTION 3 : Démarrage par lot (batch) de matchs en attente
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.admin_tournament_start_batch(_tid uuid, _round int, _count int DEFAULT 5)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_is_admin boolean;
  trn        record;
  m          record;
  v_started  int := 0;
  v_failed   int := 0;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO trn FROM public.tournaments WHERE id = _tid;
  IF trn IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;

  FOR m IN
    SELECT * FROM public.tournament_matches
    WHERE tournament_id = _tid
      AND round = _round
      AND status = 'pending'
      AND is_bye = false
      AND game_id IS NULL
    ORDER BY match_index NULLS LAST, created_at
    LIMIT GREATEST(COALESCE(_count, 5), 1)
  LOOP
    BEGIN
      IF trn.game_slug = 'domino' THEN
        PERFORM public.domino_tournament_launch_game(m.id);
      ELSE
        PERFORM public.ludo_tournament_launch_game(m.id);
      END IF;
      v_started := v_started + 1;
    EXCEPTION WHEN OTHERS THEN
      v_failed := v_failed + 1;
    END;
  END LOOP;

  INSERT INTO public.admin_logs(admin_id, action, target_id, new_value)
    VALUES (v_uid, 'tournament_start_batch', _tid,
      jsonb_build_object('round', _round, 'requested', _count, 'started', v_started, 'failed', v_failed));

  RETURN jsonb_build_object('ok', true, 'started', v_started, 'failed', v_failed);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_tournament_start_batch(uuid, int, int) TO authenticated;

-- ══════════════════════════════════════════════════════════════
-- SECTION 4 : Éditeur de bracket manuel
-- ══════════════════════════════════════════════════════════════

-- 4a. Déplacer un joueur d'un match "pending" vers un autre (même round)
CREATE OR REPLACE FUNCTION public.admin_tournament_move_player(
  _from_match uuid, _to_match uuid, _user_id uuid, _reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_is_admin boolean;
  m_from     record;
  m_to       record;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO m_from FROM public.tournament_matches WHERE id = _from_match FOR UPDATE;
  SELECT * INTO m_to   FROM public.tournament_matches WHERE id = _to_match   FOR UPDATE;
  IF m_from IS NULL OR m_to IS NULL THEN RAISE EXCEPTION 'Match introuvable'; END IF;
  IF m_from.tournament_id <> m_to.tournament_id OR m_from.round <> m_to.round THEN
    RAISE EXCEPTION 'Les deux matchs doivent appartenir au même tournoi et round';
  END IF;
  IF m_from.status <> 'pending' OR m_to.status <> 'pending' THEN
    RAISE EXCEPTION 'Impossible : les deux matchs doivent être en attente (non démarrés)';
  END IF;
  IF NOT (_user_id = ANY(m_from.player_ids)) THEN
    RAISE EXCEPTION 'Ce joueur n''est pas dans le match source';
  END IF;

  UPDATE public.tournament_matches
    SET player_ids = array_remove(player_ids, _user_id), player_ready = '{}'
    WHERE id = _from_match;

  UPDATE public.tournament_matches
    SET player_ids  = array_append(player_ids, _user_id),
        player_ready = '{}',
        admin_notes  = COALESCE(admin_notes || ' | ', '') || 'Joueur déplacé : ' || COALESCE(_reason, 'édition manuelle admin')
    WHERE id = _to_match;

  INSERT INTO public.admin_logs(admin_id, action, target_user_id, new_value)
    VALUES (v_uid, 'tournament_move_player', _user_id,
      jsonb_build_object('from_match', _from_match, 'to_match', _to_match, 'reason', _reason));

  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_tournament_move_player(uuid, uuid, uuid, text) TO authenticated;

-- 4b. Échanger deux joueurs entre deux matchs "pending"
CREATE OR REPLACE FUNCTION public.admin_tournament_swap_players(
  _match_a uuid, _player_a uuid, _match_b uuid, _player_b uuid, _reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_is_admin boolean;
  m_a        record;
  m_b        record;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  IF _match_a = _match_b THEN RAISE EXCEPTION 'Les deux matchs doivent être différents'; END IF;

  SELECT * INTO m_a FROM public.tournament_matches WHERE id = _match_a FOR UPDATE;
  SELECT * INTO m_b FROM public.tournament_matches WHERE id = _match_b FOR UPDATE;
  IF m_a IS NULL OR m_b IS NULL THEN RAISE EXCEPTION 'Match introuvable'; END IF;
  IF m_a.status <> 'pending' OR m_b.status <> 'pending' THEN
    RAISE EXCEPTION 'Impossible : les deux matchs doivent être en attente';
  END IF;
  IF NOT (_player_a = ANY(m_a.player_ids)) OR NOT (_player_b = ANY(m_b.player_ids)) THEN
    RAISE EXCEPTION 'Joueur introuvable dans le match indiqué';
  END IF;

  UPDATE public.tournament_matches
    SET player_ids = array_append(array_remove(player_ids, _player_a), _player_b), player_ready = '{}'
    WHERE id = _match_a;

  UPDATE public.tournament_matches
    SET player_ids  = array_append(array_remove(player_ids, _player_b), _player_a),
        player_ready = '{}',
        admin_notes  = COALESCE(admin_notes || ' | ', '') || 'Échange joueurs : ' || COALESCE(_reason, 'édition manuelle admin')
    WHERE id = _match_b;

  INSERT INTO public.admin_logs(admin_id, action, target_id, new_value)
    VALUES (v_uid, 'tournament_swap_players', NULL,
      jsonb_build_object('match_a', _match_a, 'player_a', _player_a, 'match_b', _match_b, 'player_b', _player_b, 'reason', _reason));

  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_tournament_swap_players(uuid, uuid, uuid, uuid, text) TO authenticated;

-- 4c. Scinder une pool de 4 (pending) en deux matchs 1v1
CREATE OR REPLACE FUNCTION public.admin_tournament_split_pool(_mid uuid, _reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_is_admin boolean;
  m          record;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO m FROM public.tournament_matches WHERE id = _mid FOR UPDATE;
  IF m IS NULL THEN RAISE EXCEPTION 'Match introuvable'; END IF;
  IF m.status <> 'pending' THEN RAISE EXCEPTION 'Le match doit être en attente'; END IF;
  IF COALESCE(array_length(m.player_ids, 1), 0) <> 4 THEN
    RAISE EXCEPTION 'Cette conversion nécessite exactement 4 joueurs (pool)';
  END IF;

  DELETE FROM public.tournament_matches WHERE id = _mid;

  INSERT INTO public.tournament_matches(tournament_id, round, match_index, player_ids, status, is_bye, admin_notes)
    VALUES (m.tournament_id, m.round, m.match_index,
            ARRAY[m.player_ids[1], m.player_ids[2]], 'pending', false,
            'Pool scindée en 1v1 : ' || COALESCE(_reason, 'édition manuelle admin'));

  INSERT INTO public.tournament_matches(tournament_id, round, match_index, player_ids, status, is_bye, admin_notes)
    VALUES (m.tournament_id, m.round, COALESCE(m.match_index, 0) + 1000,
            ARRAY[m.player_ids[3], m.player_ids[4]], 'pending', false,
            'Pool scindée en 1v1 : ' || COALESCE(_reason, 'édition manuelle admin'));

  INSERT INTO public.admin_logs(admin_id, action, target_id, new_value)
    VALUES (v_uid, 'tournament_split_pool', _mid, jsonb_build_object('players', m.player_ids, 'reason', _reason));

  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_tournament_split_pool(uuid, text) TO authenticated;

-- 4d. Fusionner deux matchs 1v1 (pending) en une pool de 4
CREATE OR REPLACE FUNCTION public.admin_tournament_merge_to_pool(
  _match_a uuid, _match_b uuid, _reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_is_admin boolean;
  m_a        record;
  m_b        record;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  IF _match_a = _match_b THEN RAISE EXCEPTION 'Les deux matchs doivent être différents'; END IF;

  SELECT * INTO m_a FROM public.tournament_matches WHERE id = _match_a FOR UPDATE;
  SELECT * INTO m_b FROM public.tournament_matches WHERE id = _match_b FOR UPDATE;
  IF m_a IS NULL OR m_b IS NULL THEN RAISE EXCEPTION 'Match introuvable'; END IF;
  IF m_a.tournament_id <> m_b.tournament_id OR m_a.round <> m_b.round THEN
    RAISE EXCEPTION 'Les deux matchs doivent appartenir au même tournoi et round';
  END IF;
  IF m_a.status <> 'pending' OR m_b.status <> 'pending' THEN
    RAISE EXCEPTION 'Les deux matchs doivent être en attente';
  END IF;
  IF COALESCE(array_length(m_a.player_ids, 1), 0) <> 2 OR COALESCE(array_length(m_b.player_ids, 1), 0) <> 2 THEN
    RAISE EXCEPTION 'Cette fusion nécessite deux matchs 1v1 (2 joueurs chacun)';
  END IF;

  UPDATE public.tournament_matches
    SET player_ids  = m_a.player_ids || m_b.player_ids,
        player_ready = '{}',
        admin_notes  = 'Fusion 1v1 → pool de 4 : ' || COALESCE(_reason, 'édition manuelle admin')
    WHERE id = _match_a;

  DELETE FROM public.tournament_matches WHERE id = _match_b;

  INSERT INTO public.admin_logs(admin_id, action, target_id, new_value)
    VALUES (v_uid, 'tournament_merge_to_pool', _match_a,
      jsonb_build_object('merged_match', _match_b, 'reason', _reason));

  RETURN jsonb_build_object('ok', true, 'match_id', _match_a);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_tournament_merge_to_pool(uuid, uuid, text) TO authenticated;

-- 4e. Réduire une pool de 4 (pending) à 3 joueurs (ex : forfait avant lancement)
CREATE OR REPLACE FUNCTION public.admin_tournament_reduce_pool(
  _mid uuid, _remove_player_id uuid, _reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_is_admin boolean;
  m          record;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO m FROM public.tournament_matches WHERE id = _mid FOR UPDATE;
  IF m IS NULL THEN RAISE EXCEPTION 'Match introuvable'; END IF;
  IF m.status <> 'pending' THEN RAISE EXCEPTION 'Le match doit être en attente'; END IF;
  IF COALESCE(array_length(m.player_ids, 1), 0) <> 4 THEN
    RAISE EXCEPTION 'Le match doit être une pool de 4';
  END IF;
  IF NOT (_remove_player_id = ANY(m.player_ids)) THEN
    RAISE EXCEPTION 'Ce joueur n''est pas dans ce match';
  END IF;

  UPDATE public.tournament_matches
    SET player_ids   = array_remove(player_ids, _remove_player_id),
        player_ready = '{}',
        admin_notes  = COALESCE(admin_notes || ' | ', '') ||
                       'Pool réduite à 3 (retrait joueur) : ' || COALESCE(_reason, 'édition manuelle admin')
    WHERE id = _mid;

  INSERT INTO public.admin_logs(admin_id, action, target_user_id, new_value)
    VALUES (v_uid, 'tournament_reduce_pool', _remove_player_id,
      jsonb_build_object('match_id', _mid, 'reason', _reason));

  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_tournament_reduce_pool(uuid, uuid, text) TO authenticated;

-- 4f. Bye manuel : qualifier directement un joueur sans jouer le match
CREATE OR REPLACE FUNCTION public.admin_tournament_set_manual_bye(
  _mid uuid, _winner_id uuid, _reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_is_admin boolean;
  m          record;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO m FROM public.tournament_matches WHERE id = _mid FOR UPDATE;
  IF m IS NULL THEN RAISE EXCEPTION 'Match introuvable'; END IF;
  IF m.status IN ('finished','forfeit','cancelled') THEN RAISE EXCEPTION 'Match déjà terminé'; END IF;
  IF NOT (_winner_id = ANY(m.player_ids)) THEN
    RAISE EXCEPTION 'Ce joueur ne fait pas partie de ce match';
  END IF;

  UPDATE public.tournament_matches
    SET status      = 'finished',
        is_bye      = true,
        winner_id   = _winner_id,
        finished_at = now(),
        admin_notes = COALESCE(admin_notes || ' | ', '') || 'Bye manuel : ' || COALESCE(_reason, 'décision admin')
    WHERE id = _mid;

  INSERT INTO public.admin_logs(admin_id, action, target_user_id, new_value)
    VALUES (v_uid, 'tournament_manual_bye', _winner_id, jsonb_build_object('match_id', _mid, 'reason', _reason));

  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_tournament_set_manual_bye(uuid, uuid, text) TO authenticated;

-- 4g. Reshuffle complet d'un round tant qu'aucun match n'a démarré
CREATE OR REPLACE FUNCTION public.admin_tournament_reshuffle_round(
  _tid uuid, _round int, _reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_is_admin boolean;
  trn        record;
  v_ids      uuid[];
  v_count    int;
  v_size     int;
  i          int;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO trn FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF trn IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;

  IF EXISTS (
    SELECT 1 FROM public.tournament_matches
    WHERE tournament_id = _tid AND round = _round AND status <> 'pending'
  ) THEN
    RAISE EXCEPTION 'Reshuffle impossible : au moins un match de ce round a déjà démarré/terminé';
  END IF;

  SELECT array_agg(uid ORDER BY random())
    INTO v_ids
    FROM (
      SELECT unnest(player_ids) AS uid
      FROM public.tournament_matches
      WHERE tournament_id = _tid AND round = _round
    ) p;

  v_count := COALESCE(array_length(v_ids, 1), 0);
  IF v_count < 2 THEN RAISE EXCEPTION 'Pas assez de joueurs à mélanger'; END IF;

  v_size := GREATEST(2, LEAST(4, COALESCE(trn.players_per_table, 2)));

  DELETE FROM public.tournament_matches WHERE tournament_id = _tid AND round = _round;

  i := 1;
  WHILE i <= v_count LOOP
    IF i + v_size - 1 <= v_count THEN
      INSERT INTO public.tournament_matches(tournament_id, round, player_ids, status, is_bye)
        VALUES (_tid, _round, v_ids[i:i + v_size - 1], 'pending', false);
    ELSIF v_count - i + 1 = 1 THEN
      INSERT INTO public.tournament_matches(tournament_id, round, player_ids, status, is_bye, winner_id, finished_at)
        VALUES (_tid, _round, ARRAY[v_ids[i]], 'finished', true, v_ids[i], now());
    ELSE
      INSERT INTO public.tournament_matches(tournament_id, round, player_ids, status, is_bye)
        VALUES (_tid, _round, v_ids[i:v_count], 'pending', false);
    END IF;
    i := i + v_size;
  END LOOP;

  INSERT INTO public.admin_logs(admin_id, action, target_id, new_value)
    VALUES (v_uid, 'tournament_reshuffle_round', _tid,
      jsonb_build_object('round', _round, 'players', v_count, 'reason', _reason));

  RETURN jsonb_build_object('ok', true, 'round', _round, 'players_reshuffled', v_count);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_tournament_reshuffle_round(uuid, int, text) TO authenticated;

-- Permissions déjà accordées explicitement ci-dessus pour chaque nouvelle fonction.
GRANT EXECUTE ON FUNCTION public.admin_advance_tournament_round(uuid) TO authenticated;

-- ══════════════════════════════════════════════════════════════
-- SECTION 5 : exposer auto_advance_rounds dans le dashboard admin
--   (patch de admin_get_full_tournament_dashboard, définie dans
--   20260704200000_tournament_complete_coverage.sql)
-- ══════════════════════════════════════════════════════════════
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
    'open_tournaments', (
      SELECT jsonb_agg(jsonb_build_object(
        'id', t.id, 'name', t.name, 'game_slug', t.game_slug,
        'registered_count', (SELECT count(*) FROM public.tournament_registrations WHERE tournament_id = t.id),
        'max_players', t.max_players, 'stake', t.stake, 'is_free', t.is_free,
        'registration_closes_at', t.registration_closes_at
      ) ORDER BY t.created_at DESC)
      FROM public.tournaments t WHERE t.status = 'open'
    ),
    'running_tournaments', (
      SELECT jsonb_agg(jsonb_build_object(
        'id', t.id, 'name', t.name, 'game_slug', t.game_slug,
        'current_round', t.current_round, 'total_rounds', t.total_rounds,
        'auto_advance_rounds', COALESCE(t.auto_advance_rounds, false),
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
    'expired_matches_count', (
      SELECT count(*) FROM public.tournament_matches m
      WHERE m.is_bye = false AND m.status IN ('pending','waiting')
        AND m.join_deadline IS NOT NULL AND m.join_deadline < now()
    ),
    'pending_claims_count', (
      SELECT count(*) FROM public.tournament_claims WHERE status IN ('pending','reviewing')
    ),
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
