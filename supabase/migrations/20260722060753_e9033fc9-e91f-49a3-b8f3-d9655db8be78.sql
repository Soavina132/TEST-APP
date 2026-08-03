
ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS prep_deadline TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.admin_tournament_apply_draft(_tid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  v_prep TIMESTAMPTZ;
  v_join TIMESTAMPTZ;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;

  SELECT * INTO v_t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF v_t.id IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;

  SELECT * INTO v_draft FROM public.tournament_shuffle_drafts WHERE tournament_id = _tid FOR UPDATE;
  IF v_draft.tournament_id IS NULL THEN RAISE EXCEPTION 'Aucun brouillon à valider'; END IF;

  v_next_round := v_t.current_round + 1;
  v_link := '/tournaments/' || _tid::text;
  v_prep := now() + interval '10 minutes';
  v_join := v_prep + interval '5 minutes';

  IF v_draft.phase = 'final' THEN
    UPDATE public.tournaments
      SET current_round = v_next_round, pending_shuffle = false,
          pending_final = false, round_validated = false,
          prep_deadline = v_prep
      WHERE id = _tid;
  ELSIF v_draft.phase = 'third_place' THEN
    UPDATE public.tournaments
      SET current_round = v_next_round, pending_shuffle = false,
          pending_final = true, round_validated = false,
          finalists = ARRAY(SELECT (elem)::uuid FROM jsonb_array_elements_text(v_draft.meta->'finalists') elem),
          prep_deadline = v_prep
      WHERE id = _tid;
  ELSE
    UPDATE public.tournaments
      SET current_round = v_next_round, pending_shuffle = false, round_validated = false,
          prep_deadline = v_prep
      WHERE id = _tid;
  END IF;

  IF v_draft.phase = 'third_place' THEN
    FOR v_pid IN SELECT (elem)::uuid FROM jsonb_array_elements_text(v_draft.meta->'finalists') elem LOOP
      INSERT INTO public.notifications(user_id, kind, type, title, body, link, ref_id)
        VALUES (v_pid, 'tournament', 'tournament_awaiting_final',
                '🏆 Qualifié pour la finale',
                'Tu es qualifié pour la grande finale du tournoi « ' || COALESCE(v_t.name,'') || ' ». La finale démarrera après la petite finale.',
                v_link, _tid);
    END LOOP;
  END IF;

  FOR v_grp IN SELECT * FROM jsonb_array_elements(v_draft.groups) LOOP
    SELECT array_agg((elem)::uuid) INTO v_players FROM jsonb_array_elements_text(v_grp->'players') elem;
    v_size := COALESCE(array_length(v_players,1), 2);
    v_is_third := COALESCE((v_grp->>'is_third_place')::bool, false);
    v_is_final := COALESCE((v_grp->>'is_final')::bool, false);

    IF v_is_third OR v_is_final THEN v_qcount := 1;
    ELSIF v_size >= 4 THEN v_qcount := 2;
    ELSE v_qcount := 1;
    END IF;

    INSERT INTO public.tournament_matches(
      tournament_id, round, player_ids, status, is_bye, is_third_place, qualifiers_count, admin_notes, join_deadline
    ) VALUES (
      _tid, v_next_round, v_players, 'pending', false, v_is_third, v_qcount,
      CASE WHEN v_is_third THEN '🥉 Petite finale — match pour la 3ᵉ place'
           WHEN v_is_final THEN '🏆 Grande finale'
           ELSE NULL END,
      v_join
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

    IF v_is_final THEN
      v_notif_type := 'tournament_final';
      v_notif_title := '🏆 Grande finale !';
      v_notif_body := 'Tu es qualifié pour la finale du tournoi « ' || COALESCE(v_t.name,'') || ' ». 10 min de préparation avant le match.';
    ELSIF v_is_third THEN
      v_notif_type := 'tournament_third_place';
      v_notif_title := '🥉 Petite finale';
      v_notif_body := 'Tu joues le match pour la 3ᵉ place. 10 min de préparation avant le match.';
    ELSE
      v_notif_type := 'tournament_next_round';
      v_notif_title := 'Round ' || v_next_round || ' — Tu joues !';
      v_notif_body := 'Ton prochain match du tournoi « ' || COALESCE(v_t.name,'') || ' » — 10 min de préparation.';
    END IF;

    FOREACH v_pid IN ARRAY v_players LOOP
      INSERT INTO public.notifications(user_id, kind, type, title, body, link, ref_id)
        VALUES (v_pid, 'tournament', v_notif_type, v_notif_title, v_notif_body, v_link, _tid);
    END LOOP;
  END LOOP;

  BEGIN
    INSERT INTO public.admin_logs(admin_id, action, target_id, new_value)
      VALUES (auth.uid(), 'tournament_apply_draft', _tid,
              jsonb_build_object('round', v_next_round, 'phase', v_draft.phase, 'groups', v_draft.groups,
                                 'prep_deadline', v_prep, 'join_deadline', v_join));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  DELETE FROM public.tournament_shuffle_drafts WHERE tournament_id = _tid;

  RETURN jsonb_build_object('ok', true, 'phase', v_draft.phase, 'round', v_next_round,
                            'prep_deadline', v_prep, 'join_deadline', v_join);
END $function$;

CREATE OR REPLACE FUNCTION public.admin_tournament_shuffle_next_round(_tid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_t public.tournaments%ROWTYPE;
  v_winners uuid[]; v_total int;
  v_losers uuid[];
  v_next_round int;
  v_game_id uuid; v_first uuid; v_color text;
  v_slot int; v_name text; v_pid uuid;
  v_new_match_id uuid;
  v_link text;
  v_prep TIMESTAMPTZ;
  v_join TIMESTAMPTZ;
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
  ) THEN RAISE EXCEPTION 'Certains matchs du round ne sont pas terminés'; END IF;

  IF NOT v_t.round_validated THEN
    RAISE EXCEPTION 'Round non validé — cliquez d''abord sur "Valider le round"';
  END IF;

  v_prep := now() + interval '10 minutes';
  v_join := v_prep + interval '5 minutes';
  v_link := '/tournaments/' || _tid::text;

  IF v_t.pending_final AND v_t.finalists IS NOT NULL AND array_length(v_t.finalists,1) = 2 THEN
    v_next_round := v_t.current_round + 1;

    UPDATE public.tournaments
      SET current_round = v_next_round,
          pending_shuffle = false,
          pending_final = false,
          round_validated = false,
          prep_deadline = v_prep
      WHERE id = _tid;

    INSERT INTO public.tournament_matches(tournament_id, round, player_ids, status, is_bye, qualifiers_count, admin_notes, join_deadline)
      VALUES (_tid, v_next_round, v_t.finalists, 'pending', false, 1, '🏆 Grande finale', v_join)
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

    FOREACH v_pid IN ARRAY v_t.finalists LOOP
      INSERT INTO public.notifications(user_id, kind, type, title, body, link, ref_id)
        VALUES (v_pid, 'tournament', 'tournament_final',
                '🏆 Grande finale !',
                'Tu es qualifié pour la finale — 10 min de préparation.',
                v_link, _tid);
    END LOOP;

    RETURN jsonb_build_object('ok', true, 'phase', 'final', 'round', v_next_round,
                              'players', v_t.finalists,
                              'prep_deadline', v_prep, 'join_deadline', v_join);
  END IF;

  SELECT array_agg(q) INTO v_winners
    FROM public.tournament_matches tm,
         LATERAL unnest(COALESCE(tm.qualifiers_ids,
                                 CASE WHEN tm.winner_id IS NOT NULL THEN ARRAY[tm.winner_id] ELSE ARRAY[]::uuid[] END)) AS q
    WHERE tm.tournament_id = _tid AND tm.round = v_t.current_round
      AND COALESCE(tm.is_third_place,false) = false;

  v_total := COALESCE(array_length(v_winners,1),0);
  IF v_total <= 1 THEN RAISE EXCEPTION 'Pas assez de qualifiés pour un round suivant'; END IF;

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
            finalists = v_winners,
            prep_deadline = v_prep
        WHERE id = _tid;

      INSERT INTO public.tournament_matches(
        tournament_id, round, player_ids, status, is_bye, is_third_place, qualifiers_count, admin_notes, join_deadline
      ) VALUES (
        _tid, v_next_round, v_losers, 'pending', false, true, 1,
        '🥉 Petite finale — match pour la 3ᵉ place', v_join
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

      FOREACH v_pid IN ARRAY v_losers LOOP
        INSERT INTO public.notifications(user_id, kind, type, title, body, link, ref_id)
          VALUES (v_pid, 'tournament', 'tournament_third_place',
                  '🥉 Petite finale',
                  'Match pour la 3ᵉ place — 10 min de préparation.',
                  v_link, _tid);
      END LOOP;

      FOREACH v_pid IN ARRAY v_winners LOOP
        INSERT INTO public.notifications(user_id, kind, type, title, body, link, ref_id)
          VALUES (v_pid, 'tournament', 'tournament_awaiting_final',
                  '🏆 Qualifié pour la finale',
                  'La finale démarrera après la petite finale.',
                  v_link, _tid);
      END LOOP;

      RETURN jsonb_build_object('ok', true, 'phase', 'third_place', 'round', v_next_round,
                                'players', v_losers, 'finalists', v_winners,
                                'prep_deadline', v_prep, 'join_deadline', v_join);
    END IF;
  END IF;

  RAISE EXCEPTION 'Cette fonction ne construit plus le round suivant directement ; utilisez le brouillon (admin_tournament_preview_shuffle + admin_tournament_apply_draft).';
END $function$;
