-- ============================================================
-- FIX TOURNOI — Bug concurrence + rangs dupliqués
-- ============================================================

-- ═══════════════════════════════════════════════════════════
-- BUG 1: Limite de matches simultanés non respectée
-- Ajout d'un verrou advisory pour empêcher 2 appels concurrents
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.tournament_engine(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  t public.tournaments%ROWTYPE;
  m record; g record; v_win uuid; v_slot int; v_busy uuid[]; v_live int;
  v_pool record; v_next uuid[]; v_losers uuid[]; v_ready int; v_total int;
BEGIN
  -- Verrou advisory: empêche 2 exécutions simultanées sur le même tournoi
  IF NOT pg_try_advisory_xact_lock(hashtext('tourney_engine_' || _tid::text)) THEN
    RETURN;
  END IF;

  SELECT * INTO t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF t.id IS NULL OR t.status <> 'running' THEN RETURN; END IF;

  PERFORM public._t_handle_expired_matches(_tid);

  -- 1) synchronisation des matchs en cours
  FOR m IN SELECT * FROM public.tournament_matches
            WHERE tournament_id = _tid AND status = 'running' AND game_id IS NOT NULL LOOP
    v_win := NULL;
    IF t.game_slug = 'ludo' THEN
      SELECT status::text AS st, winner_id INTO g FROM public.ludo_games WHERE id = m.game_id;
    ELSE
      SELECT status::text AS st, winner_id INTO g FROM public.domino_games WHERE id = m.game_id;
    END IF;
    CONTINUE WHEN g IS NULL;

    IF g.st = 'finished' THEN
      IF t.game_slug = 'ludo' THEN
        SELECT slot INTO v_slot FROM public.ludo_participants
         WHERE game_id = m.game_id
           AND ((g.winner_id IS NOT NULL AND user_id = g.winner_id) OR (g.winner_id IS NULL AND finish_rank = 1))
         LIMIT 1;
      ELSE
        SELECT slot INTO v_slot FROM public.domino_participants
         WHERE game_id = m.game_id
           AND ((g.winner_id IS NOT NULL AND user_id = g.winner_id) OR (g.winner_id IS NULL AND is_bot))
         LIMIT 1;
      END IF;
      v_win := m.entrant_ids[COALESCE(v_slot,0) + 1];
      PERFORM public._t_match_finish(m.id, v_win);

    ELSIF g.st = 'cancelled' THEN
      UPDATE public.tournament_matches SET status = 'scheduled', game_id = NULL, started_at = NULL, deadline_at = NULL
       WHERE id = m.id;

    ELSIF g.st = 'open' THEN
      IF t.game_slug = 'ludo' THEN
        SELECT count(*), count(*) FILTER (WHERE ready OR is_bot) INTO v_total, v_ready
          FROM public.ludo_participants WHERE game_id = m.game_id;
        IF v_total > 1 AND v_ready = v_total THEN
          UPDATE public.ludo_games SET status = 'playing', started_at = now(),
                 state = public._ludo_init_state(v_total) WHERE id = m.game_id AND status = 'open';
        END IF;
      ELSE
        SELECT count(*), count(*) FILTER (WHERE ready OR is_bot) INTO v_total, v_ready
          FROM public.domino_participants WHERE game_id = m.game_id;
        IF v_total > 1 AND v_ready = v_total THEN
          PERFORM public._domino_start(m.game_id);
        END IF;
      END IF;

      IF m.deadline_at < now() THEN
        IF t.game_slug = 'ludo' THEN
          SELECT slot INTO v_slot FROM public.ludo_participants
           WHERE game_id = m.game_id AND (ready OR is_bot) ORDER BY slot LIMIT 1;
          UPDATE public.ludo_games SET status = 'cancelled', finished_at = now() WHERE id = m.game_id;
        ELSE
          SELECT slot INTO v_slot FROM public.domino_participants
           WHERE game_id = m.game_id AND (ready OR is_bot) ORDER BY slot LIMIT 1;
          UPDATE public.domino_games SET status = 'cancelled', finished_at = now() WHERE id = m.game_id;
        END IF;
        PERFORM public._t_match_finish(m.id, m.entrant_ids[COALESCE(v_slot,0) + 1]);
      END IF;
    END IF;
  END LOOP;

  -- 2) clôture des poules terminées
  FOR v_pool IN SELECT p.* FROM public.tournament_pools p
                 WHERE p.tournament_id = _tid AND p.status = 'running'
                   AND NOT EXISTS (SELECT 1 FROM public.tournament_matches mm
                                    WHERE mm.pool_id = p.id AND mm.status IN ('scheduled','running')) LOOP
    UPDATE public.tournament_pool_entrants pe SET qualified = true
     WHERE pe.pool_id = v_pool.id
       AND pe.entrant_id IN (
         SELECT entrant_id FROM public.tournament_pool_entrants
          WHERE pool_id = v_pool.id ORDER BY points DESC, wins DESC, random()
          LIMIT (SELECT qualifiers_per_pool FROM public.tournaments WHERE id = _tid));
    UPDATE public.tournament_entrants e SET status = 'eliminated', eliminated_round = 1
      FROM public.tournament_pool_entrants pe
     WHERE pe.pool_id = v_pool.id AND pe.entrant_id = e.id AND NOT pe.qualified AND e.status = 'active';
    UPDATE public.tournament_pools SET status = 'finished' WHERE id = v_pool.id;
  END LOOP;

  -- 3) avancement d'étape
  IF NOT EXISTS (SELECT 1 FROM public.tournament_matches
                  WHERE tournament_id = _tid AND status IN ('scheduled','running')) THEN
    IF t.auto_advance THEN
      IF t.stage = 'pools' THEN
        SELECT array_agg(e.id ORDER BY random()) INTO v_next
          FROM public.tournament_entrants e WHERE e.tournament_id = _tid AND e.status = 'active';
        PERFORM public._t_build_round(_tid, 2, v_next);
      ELSIF t.stage = 'finals' THEN
        IF t.players_per_match = 2
           AND (SELECT count(*) FROM public.tournament_matches
                 WHERE tournament_id = _tid AND round = t.current_round AND phase = 'final') = 2
           AND NOT EXISTS (SELECT 1 FROM public.tournament_matches
                            WHERE tournament_id = _tid AND phase = 'third_place') THEN
          SELECT array_agg(x.eid) INTO v_losers FROM (
            SELECT unnest(mm.entrant_ids) eid, mm.winner_entrant_id w
              FROM public.tournament_matches mm
             WHERE mm.tournament_id = _tid AND mm.round = t.current_round AND mm.phase = 'final') x
           WHERE x.eid <> x.w;
          IF array_length(v_losers,1) = 2 THEN
            INSERT INTO public.tournament_matches(tournament_id, phase, round, match_no, entrant_ids)
              VALUES (_tid, 'third_place', t.current_round + 1, 1, v_losers);
          END IF;
        END IF;

        SELECT array_agg(winner_entrant_id ORDER BY match_no) INTO v_next
          FROM public.tournament_matches
         WHERE tournament_id = _tid AND round = t.current_round AND phase = 'final'
           AND winner_entrant_id IS NOT NULL;
        IF COALESCE(array_length(v_next,1),0) <= 1 AND NOT EXISTS (
             SELECT 1 FROM public.tournament_matches
              WHERE tournament_id = _tid AND status IN ('scheduled','running')) THEN
          UPDATE public.tournaments SET champion_entrant_id = v_next[1] WHERE id = _tid;
          PERFORM public._t_finish(_tid);
          RETURN;
        ELSIF COALESCE(array_length(v_next,1),0) > 1 THEN
          PERFORM public._t_build_round(_tid, t.current_round + 1, v_next);
        END IF;
      END IF;
      SELECT * INTO t FROM public.tournaments WHERE id = _tid;
    END IF;
  END IF;

  -- 4) lancement des matchs (limite de simultanéité + anti-chevauchement joueur)
  -- Re-compter v_live et v_busy APRÈS les étapes précédentes
  SELECT count(*) INTO v_live FROM public.tournament_matches
   WHERE tournament_id = _tid AND status = 'running';
  SELECT COALESCE(array_agg(x), ARRAY[]::uuid[]) INTO v_busy FROM (
    SELECT unnest(entrant_ids) x FROM public.tournament_matches
     WHERE tournament_id = _tid AND status = 'running') s;

  FOR m IN SELECT * FROM public.tournament_matches
            WHERE tournament_id = _tid AND status = 'scheduled'
            ORDER BY round, match_no LOOP
    EXIT WHEN v_live >= t.max_concurrent_matches;
    CONTINUE WHEN m.entrant_ids && v_busy;
    PERFORM public._t_launch_match(m.id);
    v_busy := v_busy || m.entrant_ids;
    v_live := v_live + 1;
  END LOOP;
END $$;

-- ═══════════════════════════════════════════════════════════
-- BUG 2: Rang 3 dupliqué (deux joueurs avec final_rank = 3)
-- Le problème: _t_finish assigne rang 3 via la formule générale,
-- PUIS écrase avec le gagnant de la petite finale.
-- Solution: assigner rangs généraux SANS inclure rang 3,
-- puis fixer explicitement le gagnant de la petite finale à rang 3.
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._t_finish(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  t public.tournaments%ROWTYPE;
  v_net numeric;
  v_pcts numeric[];
  r record;
  i int := 0;
  v_amt numeric;
  v_third_place_winner uuid;
  v_third_place_loser uuid;
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF t.id IS NULL OR t.status IN ('finished','cancelled') THEN RETURN; END IF;

  -- Champion = rang 1
  UPDATE public.tournament_entrants SET final_rank = 1
   WHERE id = t.champion_entrant_id AND tournament_id = _tid;

  -- Gagnant de la petite finale = rang 3
  SELECT winner_entrant_id INTO v_third_place_winner
    FROM public.tournament_matches
   WHERE tournament_id = _tid AND phase = 'third_place' AND status = 'finished'
   LIMIT 1;

  IF v_third_place_winner IS NOT NULL THEN
    UPDATE public.tournament_entrants SET final_rank = 3
     WHERE id = v_third_place_winner AND tournament_id = _tid;

    -- Perdant de la petite finale = rang 4
    SELECT entrant_ids[array_position(entrant_ids, v_third_place_winner) - 1]
      INTO v_third_place_loser
      FROM public.tournament_matches
     WHERE tournament_id = _tid AND phase = 'third_place' AND status = 'finished'
     LIMIT 1;

    -- Si le perdant n'est pas trouvé via position, chercher l'autre entrant
    IF v_third_place_loser IS NULL AND v_third_place_winner IS NOT NULL THEN
      SELECT entrant_ids[1] INTO v_third_place_loser
        FROM public.tournament_matches
       WHERE tournament_id = _tid AND phase = 'third_place' AND status = 'finished'
         AND v_third_place_winner = ANY(entrant_ids)
       LIMIT 1;
      IF v_third_place_loser = v_third_place_winner THEN
        SELECT entrant_ids[2] INTO v_third_place_loser
          FROM public.tournament_matches
         WHERE tournament_id = _tid AND phase = 'third_place' AND status = 'finished'
           AND v_third_place_winner = ANY(entrant_ids)
         LIMIT 1;
      END IF;
    END IF;

    IF v_third_place_loser IS NOT NULL AND v_third_place_loser <> v_third_place_winner THEN
      UPDATE public.tournament_entrants SET final_rank = 4
       WHERE id = v_third_place_loser AND tournament_id = _tid;
    END IF;
  END IF;

  -- Rangs généraux pour les autres (rang 2, puis 5, 6, 7...)
  -- On saute le rang 3 et 4 qui sont déjà assignés par la petite finale
  WITH ranked AS (
    SELECT id,
           CASE
             -- Champion = rang 1 (déjà assigné)
             WHEN id = t.champion_entrant_id THEN 1
             -- Petite finale participants = déjà assignés (3 et 4)
             WHEN id = v_third_place_winner THEN 3
             WHEN id = v_third_place_loser THEN 4
             -- Le finaliste perdant = rang 2
             WHEN id IN (
               SELECT entrant_ids[array_position(entrant_ids, winner_entrant_id) - 1]
                 FROM public.tournament_matches
                WHERE tournament_id = _tid AND phase = 'final' AND round = t.current_round
                  AND status = 'finished' AND winner_entrant_id IS NOT NULL
             ) THEN 2
             -- Les autres: rang 5+
             ELSE row_number() OVER (
               ORDER BY COALESCE(eliminated_round, 0) DESC NULLS LAST, created_at
             ) + 4
           END AS rk
    FROM public.tournament_entrants
    WHERE tournament_id = _tid
  )
  UPDATE public.tournament_entrants e
    SET final_rank = ranked.rk
   FROM ranked
  WHERE e.id = ranked.id AND e.tournament_id = _tid;

  -- Distribution des gains
  v_net := round(t.prize_pool_ar * (100 - t.platform_pct) / 100) + t.admin_prize_pool_ar;
  v_pcts := ARRAY[t.prize_1_pct, t.prize_2_pct, t.prize_3_pct];

  FOR r IN SELECT * FROM public.tournament_entrants
            WHERE tournament_id = _tid AND final_rank IS NOT NULL
              AND final_rank <= t.winners_count
            ORDER BY final_rank LOOP
    i := r.final_rank;
    v_amt := round(v_net * COALESCE(v_pcts[i], 0) / 100);
    IF v_amt > 0 AND r.user_id IS NOT NULL AND NOT r.is_bot THEN
      PERFORM public.credit_user_balance(r.user_id, v_amt, 'tournament_prize', _tid,
        'Récompense tournoi: ' || t.name, jsonb_build_object('rank', i));
    END IF;
    PERFORM public._t_notify(r.id, '🏆 Tournoi terminé',
      'Vous terminez ' || i || 'e. Gain : ' || v_amt || ' Ar',
      '/tournaments/' || _tid);
  END LOOP;

  UPDATE public.tournaments
    SET status = 'finished', stage = 'done', finished_at = now()
   WHERE id = _tid;
END $$;
