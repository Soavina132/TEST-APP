
-- ═══════════════════════════════════════════════════════════════════
-- Draft table for shuffle preview
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.tournament_shuffle_drafts (
  tournament_id uuid PRIMARY KEY REFERENCES public.tournaments(id) ON DELETE CASCADE,
  round_number  int  NOT NULL,
  phase         text NOT NULL,               -- 'normal' | 'third_place' | 'final'
  groups        jsonb NOT NULL DEFAULT '[]', -- [{ size: 2|3|4, players: [uuid,...], is_third_place?: bool }]
  meta          jsonb NOT NULL DEFAULT '{}', -- { finalists?: uuid[], winners?: uuid[] }
  created_by    uuid,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.tournament_shuffle_drafts TO authenticated;
GRANT ALL ON public.tournament_shuffle_drafts TO service_role;

ALTER TABLE public.tournament_shuffle_drafts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admins manage drafts" ON public.tournament_shuffle_drafts;
CREATE POLICY "admins manage drafts" ON public.tournament_shuffle_drafts
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public._touch_shuffle_draft() RETURNS trigger AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$ LANGUAGE plpgsql SET search_path = public;

DROP TRIGGER IF EXISTS trg_shuffle_draft_touch ON public.tournament_shuffle_drafts;
CREATE TRIGGER trg_shuffle_draft_touch BEFORE UPDATE ON public.tournament_shuffle_drafts
  FOR EACH ROW EXECUTE FUNCTION public._touch_shuffle_draft();

-- ═══════════════════════════════════════════════════════════════════
-- Helper : compute default proposal (same rules as shuffle_next_round)
-- Returns jsonb { phase, groups, meta }
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._tournament_compute_proposal(_tid uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_t public.tournaments%ROWTYPE;
  v_winners uuid[]; v_losers uuid[]; v_shuffled uuid[];
  v_total int;
  v_groups jsonb := '[]'::jsonb;
  v_size int; v_qualifiers int;
  v_i int; v_slice uuid[];
BEGIN
  SELECT * INTO v_t FROM public.tournaments WHERE id = _tid;
  IF v_t.id IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;

  -- Cas A : petite finale déjà jouée → grande finale
  IF v_t.pending_final AND v_t.finalists IS NOT NULL AND array_length(v_t.finalists,1) = 2 THEN
    v_groups := jsonb_build_array(jsonb_build_object(
      'size', 2, 'players', to_jsonb(v_t.finalists), 'is_third_place', false, 'is_final', true
    ));
    RETURN jsonb_build_object('phase','final','groups',v_groups,'meta', jsonb_build_object('finalists', to_jsonb(v_t.finalists)));
  END IF;

  -- Récupère les qualifiés du round courant
  SELECT array_agg(q) INTO v_winners
    FROM public.tournament_matches tm,
         LATERAL unnest(COALESCE(tm.qualifiers_ids,
                                 CASE WHEN tm.winner_id IS NOT NULL THEN ARRAY[tm.winner_id] ELSE ARRAY[]::uuid[] END)) AS q
    WHERE tm.tournament_id = _tid AND tm.round = v_t.current_round
      AND COALESCE(tm.is_third_place,false) = false;

  v_total := COALESCE(array_length(v_winners,1),0);
  IF v_total <= 1 THEN RAISE EXCEPTION 'Pas assez de qualifiés pour un round suivant'; END IF;

  -- Cas B : fin des demis → petite finale (2 perdants)
  IF v_total = 2 THEN
    SELECT array_agg(loser) INTO v_losers
      FROM (
        SELECT (SELECT p FROM unnest(m.player_ids) p WHERE p <> m.winner_id LIMIT 1) AS loser
          FROM public.tournament_matches m
         WHERE m.tournament_id = _tid AND m.round = v_t.current_round
           AND m.status IN ('finished','forfeit') AND m.is_bye = false
           AND COALESCE(m.is_third_place,false) = false
           AND array_length(m.player_ids,1) = 2 AND m.winner_id IS NOT NULL
      ) s WHERE loser IS NOT NULL;

    IF v_losers IS NOT NULL AND array_length(v_losers,1) = 2 THEN
      v_groups := jsonb_build_array(jsonb_build_object(
        'size', 2, 'players', to_jsonb(v_losers), 'is_third_place', true, 'is_final', false
      ));
      RETURN jsonb_build_object(
        'phase','third_place',
        'groups', v_groups,
        'meta', jsonb_build_object('finalists', to_jsonb(v_winners), 'losers', to_jsonb(v_losers))
      );
    END IF;
  END IF;

  -- Cas C : round normal — mélange aléatoire et découpe
  SELECT array_agg(uid ORDER BY random()) INTO v_shuffled FROM unnest(v_winners) AS uid;

  -- Taille par défaut selon jeu (Ludo peut 4, Chess/Domino/Fanorona/Rami = 2)
  IF v_t.game_slug = 'ludo' THEN v_size := LEAST(4, v_total); ELSE v_size := 2; END IF;
  IF v_size < 2 THEN v_size := 2; END IF;

  -- Découpe en groupes de v_size (le dernier peut être plus petit → sera ajusté)
  v_i := 1;
  WHILE v_i <= v_total LOOP
    v_slice := v_shuffled[v_i : LEAST(v_i + v_size - 1, v_total)];
    v_groups := v_groups || jsonb_build_array(jsonb_build_object(
      'size', array_length(v_slice,1),
      'players', to_jsonb(v_slice),
      'is_third_place', false,
      'is_final', false
    ));
    v_i := v_i + v_size;
  END LOOP;

  RETURN jsonb_build_object('phase','normal','groups',v_groups,'meta',jsonb_build_object('winners', to_jsonb(v_shuffled)));
END $$;

-- ═══════════════════════════════════════════════════════════════════
-- Preview shuffle — writes/refreshes the draft
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.admin_tournament_preview_shuffle(_tid uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_t public.tournaments%ROWTYPE;
  v_prop jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;

  SELECT * INTO v_t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF v_t.id IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;
  IF v_t.status <> 'running' THEN RAISE EXCEPTION 'Tournoi non en cours'; END IF;
  IF NOT v_t.pending_shuffle THEN RAISE EXCEPTION 'Aucun round en attente de mélange'; END IF;
  IF NOT v_t.round_validated THEN RAISE EXCEPTION 'Round non validé — cliquez d''abord sur "Valider le round"'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.tournament_matches
    WHERE tournament_id = _tid AND round = v_t.current_round
      AND status NOT IN ('finished','bye','forfeit')
  ) THEN RAISE EXCEPTION 'Certains matchs du round ne sont pas terminés'; END IF;

  v_prop := public._tournament_compute_proposal(_tid);

  INSERT INTO public.tournament_shuffle_drafts(tournament_id, round_number, phase, groups, meta, created_by)
    VALUES (_tid, v_t.current_round + 1, v_prop->>'phase', v_prop->'groups', v_prop->'meta', auth.uid())
  ON CONFLICT (tournament_id) DO UPDATE
    SET round_number = EXCLUDED.round_number,
        phase = EXCLUDED.phase,
        groups = EXCLUDED.groups,
        meta = EXCLUDED.meta,
        created_by = EXCLUDED.created_by,
        updated_at = now();

  RETURN jsonb_build_object('ok', true, 'draft', v_prop, 'round', v_t.current_round + 1);
END $$;

-- ═══════════════════════════════════════════════════════════════════
-- Update draft groups (admin edit)
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.admin_tournament_update_draft(_tid uuid, _groups jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_draft public.tournament_shuffle_drafts%ROWTYPE;
  v_all uuid[]; v_expected uuid[]; v_grp jsonb; v_players uuid[]; v_size int;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;

  SELECT * INTO v_draft FROM public.tournament_shuffle_drafts WHERE tournament_id = _tid FOR UPDATE;
  IF v_draft.tournament_id IS NULL THEN RAISE EXCEPTION 'Aucun brouillon actif'; END IF;

  -- Édition non autorisée pour finale / petite finale (règles auto)
  IF v_draft.phase IN ('final','third_place') THEN
    RAISE EXCEPTION 'Cette phase (%) est verrouillée — non modifiable', v_draft.phase;
  END IF;

  -- Valide chaque groupe
  v_all := ARRAY[]::uuid[];
  FOR v_grp IN SELECT * FROM jsonb_array_elements(_groups) LOOP
    SELECT array_agg((elem)::uuid) INTO v_players FROM jsonb_array_elements_text(v_grp->'players') elem;
    IF v_players IS NULL OR array_length(v_players,1) < 2 OR array_length(v_players,1) > 4 THEN
      RAISE EXCEPTION 'Chaque groupe doit contenir entre 2 et 4 joueurs';
    END IF;
    v_size := (v_grp->>'size')::int;
    IF v_size IS NULL OR v_size < 2 OR v_size > 4 THEN
      RAISE EXCEPTION 'Taille de groupe invalide (2, 3 ou 4)';
    END IF;
    IF v_size <> array_length(v_players,1) THEN
      RAISE EXCEPTION 'La taille (%) ne correspond pas au nombre de joueurs (%)', v_size, array_length(v_players,1);
    END IF;
    v_all := v_all || v_players;
  END LOOP;

  -- Vérifie doublons + ensemble complet
  IF (SELECT count(*) FROM unnest(v_all)) <> (SELECT count(DISTINCT x) FROM unnest(v_all) x) THEN
    RAISE EXCEPTION 'Un joueur apparaît dans plusieurs groupes';
  END IF;

  SELECT array_agg((elem)::uuid) INTO v_expected
    FROM jsonb_array_elements_text(v_draft.meta->'winners') elem;
  IF v_expected IS NOT NULL THEN
    IF (SELECT count(*) FROM (SELECT unnest(v_expected) EXCEPT SELECT unnest(v_all)) d) > 0
       OR (SELECT count(*) FROM (SELECT unnest(v_all) EXCEPT SELECT unnest(v_expected)) d) > 0 THEN
      RAISE EXCEPTION 'Tous les qualifiés doivent être placés (et uniquement eux)';
    END IF;
  END IF;

  UPDATE public.tournament_shuffle_drafts
    SET groups = _groups, updated_at = now()
    WHERE tournament_id = _tid;

  RETURN jsonb_build_object('ok', true);
END $$;

-- ═══════════════════════════════════════════════════════════════════
-- Discard draft
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.admin_tournament_discard_draft(_tid uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  DELETE FROM public.tournament_shuffle_drafts WHERE tournament_id = _tid;
  RETURN jsonb_build_object('ok', true);
END $$;

-- ═══════════════════════════════════════════════════════════════════
-- Apply draft — creates real matches + games + notifications
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.admin_tournament_apply_draft(_tid uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_t public.tournaments%ROWTYPE;
  v_draft public.tournament_shuffle_drafts%ROWTYPE;
  v_next_round int;
  v_grp jsonb; v_players uuid[]; v_size int;
  v_new_match_id uuid; v_game_id uuid; v_first uuid; v_color text;
  v_slot int; v_name text; v_pid uuid;
  v_is_third bool; v_is_final bool;
  v_qcount int;
  v_link text; v_notif_title text; v_notif_body text; v_notif_type text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;

  SELECT * INTO v_t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF v_t.id IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;

  SELECT * INTO v_draft FROM public.tournament_shuffle_drafts WHERE tournament_id = _tid FOR UPDATE;
  IF v_draft.tournament_id IS NULL THEN RAISE EXCEPTION 'Aucun brouillon à valider'; END IF;

  v_next_round := v_t.current_round + 1;
  v_link := '/tournaments/' || _tid::text;

  -- Mise à jour tournoi (états)
  IF v_draft.phase = 'final' THEN
    UPDATE public.tournaments
      SET current_round = v_next_round, pending_shuffle = false,
          pending_final = false, round_validated = false
      WHERE id = _tid;
  ELSIF v_draft.phase = 'third_place' THEN
    UPDATE public.tournaments
      SET current_round = v_next_round, pending_shuffle = false,
          pending_final = true, round_validated = false,
          finalists = ARRAY(SELECT (elem)::uuid FROM jsonb_array_elements_text(v_draft.meta->'finalists') elem)
      WHERE id = _tid;
  ELSE
    UPDATE public.tournaments
      SET current_round = v_next_round, pending_shuffle = false, round_validated = false
      WHERE id = _tid;
  END IF;

  -- Notifications pré-finale pour les finalistes en attente
  IF v_draft.phase = 'third_place' THEN
    FOR v_pid IN SELECT (elem)::uuid FROM jsonb_array_elements_text(v_draft.meta->'finalists') elem LOOP
      INSERT INTO public.notifications(user_id, kind, type, title, body, link, ref_id)
        VALUES (v_pid, 'tournament', 'tournament_awaiting_final',
                '🏆 Qualifié pour la finale',
                'Tu es qualifié pour la grande finale du tournoi « ' || COALESCE(v_t.name,'') || ' ». La finale démarrera après la petite finale.',
                v_link, _tid);
    END LOOP;
  END IF;

  -- Création des matchs à partir des groupes
  FOR v_grp IN SELECT * FROM jsonb_array_elements(v_draft.groups) LOOP
    SELECT array_agg((elem)::uuid) INTO v_players FROM jsonb_array_elements_text(v_grp->'players') elem;
    v_size := COALESCE(array_length(v_players,1), 2);
    v_is_third := COALESCE((v_grp->>'is_third_place')::bool, false);
    v_is_final := COALESCE((v_grp->>'is_final')::bool, false);

    -- Qualifiés par groupe : 1 en 1v1/3p, 2 en 4p (Ludo), 1 pour petite finale/finale
    IF v_is_third OR v_is_final THEN
      v_qcount := 1;
    ELSIF v_size >= 4 THEN
      v_qcount := 2;
    ELSE
      v_qcount := 1;
    END IF;

    INSERT INTO public.tournament_matches(
      tournament_id, round, player_ids, status, is_bye, is_third_place, qualifiers_count, admin_notes
    ) VALUES (
      _tid, v_next_round, v_players, 'pending', false, v_is_third, v_qcount,
      CASE WHEN v_is_third THEN '🥉 Petite finale — match pour la 3ᵉ place'
           WHEN v_is_final THEN '🏆 Grande finale'
           ELSE NULL END
    ) RETURNING id INTO v_new_match_id;

    IF v_t.game_slug = 'ludo' THEN
      v_first := v_players[1];
      INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, room_code, is_private, mode, tournament_match_id, status)
        VALUES (v_first, GREATEST(v_size,2), 0, 0, 0, NULL, TRUE, 'classic', v_new_match_id, 'open')
        RETURNING id INTO v_game_id;
      v_slot := 0;
      FOREACH v_pid IN ARRAY v_players LOOP
        v_color := (ARRAY['red','blue','green','yellow'])[v_slot+1];
        SELECT pseudo INTO v_name FROM public.profiles WHERE id = v_pid;
        INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
          VALUES (v_game_id, v_pid, v_slot, v_color, COALESCE(v_name,'Joueur'));
        v_slot := v_slot + 1;
      END LOOP;
      UPDATE public.tournament_matches SET game_id = v_game_id, status = 'running' WHERE id = v_new_match_id;
    END IF;

    -- Notifications par joueur
    IF v_is_final THEN
      v_notif_type := 'tournament_final';
      v_notif_title := '🏆 Grande finale !';
      v_notif_body := 'Tu es qualifié pour la finale du tournoi « ' || COALESCE(v_t.name,'') || ' ». Rejoins ta partie.';
    ELSIF v_is_third THEN
      v_notif_type := 'tournament_third_place';
      v_notif_title := '🥉 Petite finale';
      v_notif_body := 'Tu joues le match pour la 3ᵉ place du tournoi « ' || COALESCE(v_t.name,'') || ' ». Rejoins ta partie.';
    ELSE
      v_notif_type := 'tournament_next_round';
      v_notif_title := 'Round ' || v_next_round || ' — Tu joues !';
      v_notif_body := 'Ton prochain match du tournoi « ' || COALESCE(v_t.name,'') || ' » est prêt.';
    END IF;

    FOREACH v_pid IN ARRAY v_players LOOP
      INSERT INTO public.notifications(user_id, kind, type, title, body, link, ref_id)
        VALUES (v_pid, 'tournament', v_notif_type, v_notif_title, v_notif_body, v_link, _tid);
    END LOOP;
  END LOOP;

  -- Log
  BEGIN
    INSERT INTO public.admin_logs(admin_id, action, target_id, new_value)
      VALUES (auth.uid(), 'tournament_apply_draft', _tid,
              jsonb_build_object('round', v_next_round, 'phase', v_draft.phase, 'groups', v_draft.groups));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- Supprime le brouillon
  DELETE FROM public.tournament_shuffle_drafts WHERE tournament_id = _tid;

  RETURN jsonb_build_object('ok', true, 'phase', v_draft.phase, 'round', v_next_round);
END $$;

-- ═══════════════════════════════════════════════════════════════════
-- Get draft (admin utility)
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.admin_tournament_get_draft(_tid uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_d public.tournament_shuffle_drafts%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT * INTO v_d FROM public.tournament_shuffle_drafts WHERE tournament_id = _tid;
  IF v_d.tournament_id IS NULL THEN RETURN jsonb_build_object('exists', false); END IF;
  RETURN jsonb_build_object(
    'exists', true,
    'round', v_d.round_number,
    'phase', v_d.phase,
    'groups', v_d.groups,
    'meta', v_d.meta,
    'updated_at', v_d.updated_at
  );
END $$;

GRANT EXECUTE ON FUNCTION public.admin_tournament_preview_shuffle(uuid)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_tournament_update_draft(uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_tournament_apply_draft(uuid)     TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_tournament_discard_draft(uuid)   TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_tournament_get_draft(uuid)       TO authenticated;
