
ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS pending_final boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS finalists uuid[] NULL;

-- Trigger: à la fin d'une partie liée à un match de tournoi
CREATE OR REPLACE FUNCTION public._tournament_on_game_finished()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_match public.tournament_matches%ROWTYPE;
  v_t public.tournaments%ROWTYPE;
  v_remaining int; v_winners uuid[]; v_total int;
  v_payout numeric; v_top3 jsonb; v_quals uuid[];
  v_third_id uuid;
  v_first_amt numeric; v_second_amt numeric; v_third_amt numeric; v_plat_amt numeric;
  v_prize numeric; dist jsonb;
  v_first_id uuid; v_second_id uuid;
BEGIN
  IF NEW.status <> 'finished' OR OLD.status = 'finished' THEN RETURN NEW; END IF;
  IF NEW.tournament_match_id IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_match FROM public.tournament_matches WHERE id = NEW.tournament_match_id FOR UPDATE;
  IF v_match.id IS NULL OR v_match.status = 'finished' THEN RETURN NEW; END IF;

  IF TG_TABLE_NAME = 'ludo_games' THEN
    SELECT COALESCE(array_agg(user_id ORDER BY finish_rank), ARRAY[]::uuid[])
      INTO v_quals
      FROM public.ludo_participants
      WHERE game_id = NEW.id AND finish_rank IS NOT NULL AND user_id IS NOT NULL
      LIMIT v_match.qualifiers_count;
  ELSE
    v_quals := CASE WHEN NEW.winner_id IS NOT NULL THEN ARRAY[NEW.winner_id] ELSE ARRAY[]::uuid[] END;
  END IF;

  IF (v_quals IS NULL OR array_length(v_quals,1) IS NULL) AND NEW.winner_id IS NOT NULL THEN
    v_quals := ARRAY[NEW.winner_id];
  END IF;

  IF array_length(v_quals,1) > v_match.qualifiers_count THEN
    v_quals := v_quals[1 : v_match.qualifiers_count];
  END IF;

  UPDATE public.tournament_matches
    SET status='finished', winner_id = COALESCE(NEW.winner_id, v_quals[1]),
        qualifiers_ids = v_quals, finished_at = now()
    WHERE id = v_match.id;

  SELECT * INTO v_t FROM public.tournaments WHERE id = v_match.tournament_id FOR UPDATE;

  UPDATE public.tournament_registrations
    SET eliminated_round = v_t.current_round
    WHERE tournament_id = v_t.id
      AND user_id = ANY(v_match.player_ids)
      AND NOT (user_id = ANY(COALESCE(v_quals, ARRAY[]::uuid[])))
      AND eliminated_round IS NULL;

  SELECT count(*) INTO v_remaining
    FROM public.tournament_matches
    WHERE tournament_id = v_t.id AND round = v_t.current_round AND status NOT IN ('finished','bye');
  IF v_remaining > 0 THEN RETURN NEW; END IF;

  -- Le round courant est terminé. Décidons de la suite.

  -- Cas A : le round courant est le match de la 3ᵉ place (seulement)
  IF EXISTS (
    SELECT 1 FROM public.tournament_matches
    WHERE tournament_id = v_t.id AND round = v_t.current_round
      AND COALESCE(is_third_place,false) = true
  ) AND NOT EXISTS (
    SELECT 1 FROM public.tournament_matches
    WHERE tournament_id = v_t.id AND round = v_t.current_round
      AND COALESCE(is_third_place,false) = false
  ) THEN
    -- 3ᵉ place terminée : on attend que l'admin lance la finale
    UPDATE public.tournaments SET pending_shuffle = true WHERE id = v_t.id;
    RETURN NEW;
  END IF;

  -- Collecte des qualifiés du round courant (hors 3ᵉ place)
  SELECT array_agg(q ORDER BY match_index, ord) INTO v_winners
    FROM (
      SELECT match_index, ord, q
      FROM public.tournament_matches tm,
           LATERAL unnest(COALESCE(tm.qualifiers_ids, CASE WHEN tm.winner_id IS NOT NULL THEN ARRAY[tm.winner_id] ELSE ARRAY[]::uuid[] END))
             WITH ORDINALITY AS u(q, ord)
      WHERE tm.tournament_id = v_t.id AND tm.round = v_t.current_round
        AND COALESCE(tm.is_third_place,false) = false
        AND (tm.winner_id IS NOT NULL OR tm.qualifiers_ids IS NOT NULL)
    ) s;
  v_total := COALESCE(array_length(v_winners,1),0);

  -- Cas B : finale terminée (1 seul qualifié restant)
  IF v_total <= 1 THEN
    v_first_id := v_winners[1];

    -- 2ᵉ = perdant de la finale
    SELECT (SELECT p FROM unnest(m.player_ids) p WHERE p <> m.winner_id LIMIT 1)
      INTO v_second_id
      FROM public.tournament_matches m
     WHERE m.tournament_id = v_t.id
       AND m.round = v_t.current_round
       AND COALESCE(m.is_third_place,false) = false
       AND m.is_bye = false
     ORDER BY m.finished_at DESC NULLS LAST
     LIMIT 1;

    -- 3ᵉ = gagnant de la petite finale (n'importe quel round)
    SELECT winner_id INTO v_third_id
      FROM public.tournament_matches
     WHERE tournament_id = v_t.id
       AND COALESCE(is_third_place,false) = true
     ORDER BY finished_at DESC NULLS LAST
     LIMIT 1;

    v_prize := COALESCE(v_t.prize_pool, 0);
    dist := COALESCE(v_t.reward_distribution, '{"first":60,"second":20,"third":10,"platform":10}'::jsonb);

    IF v_t.rewards_paid_at IS NULL AND v_prize > 0 AND (v_second_id IS NOT NULL OR v_third_id IS NOT NULL) THEN
      v_first_amt  := ROUND(v_prize * COALESCE((dist->>'first')::numeric, 60)  / 100, 0);
      v_second_amt := ROUND(v_prize * COALESCE((dist->>'second')::numeric, 20) / 100, 0);
      v_third_amt  := ROUND(v_prize * COALESCE((dist->>'third')::numeric, 10)  / 100, 0);
      v_plat_amt   := v_prize - v_first_amt - v_second_amt - v_third_amt;

      IF v_first_id IS NOT NULL AND v_first_amt > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + v_first_amt WHERE id = v_first_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (v_first_id, 'tournament_win', v_first_amt, v_t.id, '🥇 1er — Tournoi ' || COALESCE(v_t.name,''));
      END IF;
      IF v_second_id IS NOT NULL AND v_second_amt > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + v_second_amt WHERE id = v_second_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (v_second_id, 'tournament_win', v_second_amt, v_t.id, '🥈 2e — Tournoi ' || COALESCE(v_t.name,''));
      END IF;
      IF v_third_id IS NOT NULL AND v_third_amt > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + v_third_amt WHERE id = v_third_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (v_third_id, 'tournament_win', v_third_amt, v_t.id, '🥉 3e — Tournoi ' || COALESCE(v_t.name,''));
      END IF;

      UPDATE public.tournaments
        SET status='finished', finished_at=now(), winner_id = v_first_id,
            podium = jsonb_build_object('first', v_first_id, 'second', v_second_id, 'third', v_third_id),
            rewards_paid_at = now(), platform_cut_ar = v_plat_amt,
            pending_shuffle = false, pending_final = false
        WHERE id = v_t.id;
    ELSE
      UPDATE public.tournaments
        SET status='finished', finished_at=now(), winner_id = v_first_id,
            podium = jsonb_build_object('first', v_first_id, 'second', v_second_id, 'third', v_third_id),
            pending_shuffle = false, pending_final = false
        WHERE id = v_t.id;

      IF v_first_id IS NOT NULL AND v_t.rewards_paid_at IS NULL AND v_prize > 0 AND NOT v_t.is_free THEN
        v_payout := v_prize * (100 - COALESCE(v_t.commission_pct,0)) / 100.0;
        UPDATE public.profiles SET balance_ar = balance_ar + v_payout WHERE id = v_first_id;
        INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
          VALUES (v_first_id,'win', v_payout, v_t.id, 'Victoire tournoi: '||v_t.name);
        UPDATE public.tournaments SET rewards_paid_at = now() WHERE id = v_t.id;
      END IF;
    END IF;

    RETURN NEW;
  END IF;

  -- Sinon : on attend le mélange admin
  UPDATE public.tournaments SET pending_shuffle = true WHERE id = v_t.id;
  RETURN NEW;
END $$;

-- RPC admin : gère 3 cas
--   1) pending_final = true → créer UNIQUEMENT la finale entre finalists
--   2) sinon si v_total = 2 (fin des demis) → créer UNIQUEMENT la petite finale,
--      stocker les finalists, activer pending_final
--   3) sinon → round normal (mélange + construction)
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
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;

  SELECT * INTO v_t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF v_t.id IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;
  IF v_t.status <> 'running' THEN RAISE EXCEPTION 'Tournoi non en cours'; END IF;
  IF NOT v_t.pending_shuffle THEN RAISE EXCEPTION 'Aucun round en attente de mélange'; END IF;

  IF EXISTS (
    SELECT 1 FROM public.tournament_matches
    WHERE tournament_id = _tid AND round = v_t.current_round
      AND status NOT IN ('finished','bye')
  ) THEN
    RAISE EXCEPTION 'Certains matchs du round ne sont pas terminés';
  END IF;

  -- ── CAS 1 : la petite finale vient d'être jouée, on lance la finale
  IF v_t.pending_final AND v_t.finalists IS NOT NULL AND array_length(v_t.finalists,1) = 2 THEN
    v_next_round := v_t.current_round + 1;

    UPDATE public.tournaments
      SET current_round = v_next_round, pending_shuffle = false, pending_final = false
      WHERE id = _tid;

    INSERT INTO public.tournament_matches(tournament_id, round, player_ids, status, is_bye, qualifiers_count, admin_notes)
      VALUES (_tid, v_next_round, v_t.finalists, 'pending', false, 1, '🏆 Grande finale')
      RETURNING id INTO v_new_match_id;

    -- Créer la partie Ludo si tournoi Ludo
    IF v_t.game_slug = 'ludo' THEN
      v_first := v_t.finalists[1];
      SELECT pseudo INTO v_name FROM public.profiles WHERE id = v_first;
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

    RETURN jsonb_build_object('ok', true, 'phase', 'final', 'round', v_next_round, 'players', v_t.finalists);
  END IF;

  -- Récupère les qualifiés du round courant (hors 3ᵉ place)
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
    -- Récupère les 2 perdants des demis (matchs 2 joueurs)
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

    IF v_losers IS NULL OR array_length(v_losers,1) <> 2 THEN
      -- Pas de vraies demis (ex: forfaits multiples) → on tombe sur le comportement normal
      NULL;
    ELSE
      v_next_round := v_t.current_round + 1;

      UPDATE public.tournaments
        SET current_round = v_next_round,
            pending_shuffle = false,
            pending_final = true,
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

      RETURN jsonb_build_object('ok', true, 'phase', 'third_place', 'round', v_next_round, 'players', v_losers, 'finalists', v_winners);
    END IF;
  END IF;

  -- ── CAS 3 : round normal
  SELECT array_agg(uid ORDER BY random()) INTO v_shuffled FROM unnest(v_winners) AS uid;
  v_next_round := v_t.current_round + 1;

  UPDATE public.tournaments
    SET current_round = v_next_round, pending_shuffle = false
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
  END LOOP;

  BEGIN
    INSERT INTO public.admin_logs(admin_id, action, target_id, new_value)
      VALUES (auth.uid(), 'tournament_shuffle_round', _tid,
              jsonb_build_object('round', v_next_round, 'players', v_shuffled));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'phase', 'normal', 'round', v_next_round, 'players', v_shuffled);
END $$;

GRANT EXECUTE ON FUNCTION public.admin_tournament_shuffle_next_round(uuid) TO authenticated;
