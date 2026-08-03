
ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS round_validated boolean NOT NULL DEFAULT false;

-- RPC : valider explicitement le round courant
CREATE OR REPLACE FUNCTION public.admin_validate_round(_tid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_t public.tournaments%ROWTYPE;
  v_pending int;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;

  SELECT * INTO v_t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF v_t.id IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;
  IF v_t.status <> 'running' THEN RAISE EXCEPTION 'Tournoi non en cours'; END IF;
  IF NOT v_t.pending_shuffle THEN RAISE EXCEPTION 'Aucun round en attente de validation'; END IF;

  SELECT count(*) INTO v_pending
    FROM public.tournament_matches
   WHERE tournament_id = _tid AND round = v_t.current_round
     AND status NOT IN ('finished','bye','forfeit');

  IF v_pending > 0 THEN
    RAISE EXCEPTION 'Il reste % match(s) non terminé(s) sur ce round', v_pending;
  END IF;

  UPDATE public.tournaments SET round_validated = true WHERE id = _tid;

  BEGIN
    INSERT INTO public.admin_logs(admin_id, action, target_id, new_value)
      VALUES (auth.uid(), 'tournament_validate_round', _tid,
              jsonb_build_object('round', v_t.current_round));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'round', v_t.current_round);
END $$;

GRANT EXECUTE ON FUNCTION public.admin_validate_round(uuid) TO authenticated;

-- Bloque le shuffle tant que round_validated = false, puis le reset après le shuffle
CREATE OR REPLACE FUNCTION public.admin_tournament_shuffle_next_round(_tid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_t public.tournaments%ROWTYPE;
  v_winners uuid[]; v_shuffled uuid[]; v_total int;
  v_losers uuid[];
  v_next_round int;
  m record; v_game_id uuid; v_first uuid; v_color text;
  v_slot int; v_name text; v_pid uuid; v_size int;
  v_new_match_id uuid;
  v_link text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;

  SELECT * INTO v_t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF v_t.id IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;
  IF v_t.status <> 'running' THEN RAISE EXCEPTION 'Tournoi non en cours'; END IF;
  IF NOT v_t.pending_shuffle THEN RAISE EXCEPTION 'Aucun round en attente de mélange'; END IF;

  IF EXISTS (
    SELECT 1 FROM public.tournament_matches
    WHERE tournament_id = _tid AND round = v_t.current_round
      AND status NOT IN ('finished','bye','forfeit')
  ) THEN
    RAISE EXCEPTION 'Certains matchs du round ne sont pas terminés';
  END IF;

  IF NOT v_t.round_validated THEN
    RAISE EXCEPTION 'Round non validé — cliquez d''abord sur "Valider le round"';
  END IF;

  -- ── CAS 1 : la petite finale vient d'être jouée, on lance la finale
  IF v_t.pending_final AND v_t.finalists IS NOT NULL AND array_length(v_t.finalists,1) = 2 THEN
    v_next_round := v_t.current_round + 1;

    UPDATE public.tournaments
      SET current_round = v_next_round,
          pending_shuffle = false,
          pending_final = false,
          round_validated = false
      WHERE id = _tid;

    INSERT INTO public.tournament_matches(tournament_id, round, player_ids, status, is_bye, qualifiers_count, admin_notes)
      VALUES (_tid, v_next_round, v_t.finalists, 'pending', false, 1, '🏆 Grande finale')
      RETURNING id INTO v_new_match_id;

    IF v_t.game_slug = 'ludo' THEN
      v_first := v_t.finalists[1];
      INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, room_code, is_private, mode, tournament_match_id, status)
        VALUES (v_first, 2, 0, 0, 0, NULL, TRUE, 'classic', v_new_match_id, 'open')
        RETURNING id INTO v_game_id;
      v_slot := 0;
      FOREACH v_pid IN ARRAY v_t.finalists LOOP
        v_color := (ARRAY['red','blue','green','yellow'])[v_slot+1];
        SELECT pseudo INTO v_name FROM public.profiles WHERE id = v_pid;
        INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
          VALUES (v_game_id, v_pid, v_slot, v_color, COALESCE(v_name,'Joueur'));
        v_slot := v_slot + 1;
      END LOOP;
      UPDATE public.tournament_matches SET game_id = v_game_id, status = 'running' WHERE id = v_new_match_id;
    END IF;

    v_link := '/tournaments/' || _tid::text;
    FOREACH v_pid IN ARRAY v_t.finalists LOOP
      INSERT INTO public.notifications(user_id, kind, type, title, body, link, ref_id)
        VALUES (v_pid, 'tournament', 'tournament_final',
                '🏆 Grande finale !',
                'Tu es qualifié pour la finale du tournoi « ' || COALESCE(v_t.name,'') || ' ». Rejoins ta partie.',
                v_link, _tid);
    END LOOP;

    RETURN jsonb_build_object('ok', true, 'phase', 'final', 'round', v_next_round, 'players', v_t.finalists);
  END IF;

  SELECT array_agg(q) INTO v_winners
    FROM public.tournament_matches tm,
         LATERAL unnest(COALESCE(tm.qualifiers_ids,
                                 CASE WHEN tm.winner_id IS NOT NULL THEN ARRAY[tm.winner_id] ELSE ARRAY[]::uuid[] END)) AS q
    WHERE tm.tournament_id = _tid AND tm.round = v_t.current_round
      AND COALESCE(tm.is_third_place,false) = false;

  v_total := COALESCE(array_length(v_winners,1),0);
  IF v_total <= 1 THEN RAISE EXCEPTION 'Pas assez de qualifiés pour un round suivant'; END IF;

  -- ── CAS 2 : fin des demi-finales → petite finale AVANT la grande finale
  IF v_total = 2 THEN
    SELECT array_agg(loser) INTO v_losers
      FROM (
        SELECT (SELECT p FROM unnest(m.player_ids) p WHERE p <> m.winner_id LIMIT 1) AS loser
          FROM public.tournament_matches m
         WHERE m.tournament_id = _tid
           AND m.round = v_t.current_round
           AND m.status IN ('finished','forfeit')
           AND m.is_bye = false
           AND COALESCE(m.is_third_place,false) = false
           AND array_length(m.player_ids,1) = 2
           AND m.winner_id IS NOT NULL
      ) s WHERE loser IS NOT NULL;

    IF v_losers IS NOT NULL AND array_length(v_losers,1) = 2 THEN
      v_next_round := v_t.current_round + 1;

      UPDATE public.tournaments
        SET current_round = v_next_round,
            pending_shuffle = false,
            pending_final = true,
            round_validated = false,
            finalists = v_winners
        WHERE id = _tid;

      INSERT INTO public.tournament_matches(
        tournament_id, round, player_ids, status, is_bye, is_third_place, qualifiers_count, admin_notes
      ) VALUES (
        _tid, v_next_round, v_losers, 'pending', false, true, 1,
        '🥉 Petite finale — match pour la 3ᵉ place'
      ) RETURNING id INTO v_new_match_id;

      IF v_t.game_slug = 'ludo' THEN
        v_first := v_losers[1];
        INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, room_code, is_private, mode, tournament_match_id, status)
          VALUES (v_first, 2, 0, 0, 0, NULL, TRUE, 'classic', v_new_match_id, 'open')
          RETURNING id INTO v_game_id;
        v_slot := 0;
        FOREACH v_pid IN ARRAY v_losers LOOP
          v_color := (ARRAY['red','blue','green','yellow'])[v_slot+1];
          SELECT pseudo INTO v_name FROM public.profiles WHERE id = v_pid;
          INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
            VALUES (v_game_id, v_pid, v_slot, v_color, COALESCE(v_name,'Joueur'));
          v_slot := v_slot + 1;
        END LOOP;
        UPDATE public.tournament_matches SET game_id = v_game_id, status = 'running' WHERE id = v_new_match_id;
      END IF;

      v_link := '/tournaments/' || _tid::text;
      FOREACH v_pid IN ARRAY v_losers LOOP
        INSERT INTO public.notifications(user_id, kind, type, title, body, link, ref_id)
          VALUES (v_pid, 'tournament', 'tournament_third_place',
                  '🥉 Petite finale',
                  'Tu joues le match pour la 3ᵉ place du tournoi « ' || COALESCE(v_t.name,'') || ' ». Rejoins ta partie.',
                  v_link, _tid);
      END LOOP;
      FOREACH v_pid IN ARRAY v_winners LOOP
        INSERT INTO public.notifications(user_id, kind, type, title, body, link, ref_id)
          VALUES (v_pid, 'tournament', 'tournament_awaiting_final',
                  '🏆 Qualifié pour la finale',
                  'Tu es qualifié pour la grande finale du tournoi « ' || COALESCE(v_t.name,'') || ' ». La finale démarrera après la petite finale.',
                  v_link, _tid);
      END LOOP;

      RETURN jsonb_build_object('ok', true, 'phase', 'third_place', 'round', v_next_round, 'players', v_losers, 'finalists', v_winners);
    END IF;
  END IF;

  -- ── CAS 3 : round normal
  SELECT array_agg(uid ORDER BY random()) INTO v_shuffled FROM unnest(v_winners) AS uid;
  v_next_round := v_t.current_round + 1;

  UPDATE public.tournaments
    SET current_round = v_next_round,
        pending_shuffle = false,
        round_validated = false
    WHERE id = _tid;

  PERFORM public._tournament_build_round(_tid, v_next_round, v_shuffled);

  FOR m IN SELECT * FROM public.tournament_matches
           WHERE tournament_id = _tid AND round = v_next_round AND status = 'pending'
           ORDER BY match_index LOOP
    v_first := m.player_ids[1];
    v_size := GREATEST(array_length(m.player_ids,1), 2);
    IF v_t.game_slug = 'ludo' THEN
      INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, room_code, is_private, mode, tournament_match_id, status)
        VALUES (v_first, v_size, 0, 0, 0, NULL, TRUE, 'classic', m.id, 'open')
        RETURNING id INTO v_game_id;
      v_slot := 0;
      FOREACH v_pid IN ARRAY m.player_ids LOOP
        v_color := (ARRAY['red','blue','green','yellow'])[v_slot+1];
        SELECT pseudo INTO v_name FROM public.profiles WHERE id = v_pid;
        INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
          VALUES (v_game_id, v_pid, v_slot, v_color, COALESCE(v_name,'Joueur'));
        v_slot := v_slot + 1;
      END LOOP;
      UPDATE public.tournament_matches SET game_id = v_game_id, status = 'running' WHERE id = m.id;
    END IF;

    v_link := '/tournaments/' || _tid::text;
    FOREACH v_pid IN ARRAY m.player_ids LOOP
      INSERT INTO public.notifications(user_id, kind, type, title, body, link, ref_id)
        VALUES (v_pid, 'tournament', 'tournament_next_round',
                'Round ' || v_next_round || ' — Tu joues !',
                'Ton prochain match du tournoi « ' || COALESCE(v_t.name,'') || ' » est prêt.',
                v_link, _tid);
    END LOOP;
  END LOOP;

  BEGIN
    INSERT INTO public.admin_logs(admin_id, action, target_id, new_value)
      VALUES (auth.uid(), 'tournament_shuffle_round', _tid,
              jsonb_build_object('round', v_next_round, 'players', v_shuffled));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'phase', 'normal', 'round', v_next_round, 'players', v_shuffled);
END $$;

GRANT EXECUTE ON FUNCTION public.admin_tournament_shuffle_next_round(uuid) TO authenticated;
