-- 1) Recalcul complet et déterministe du classement d'une poule
CREATE OR REPLACE FUNCTION public._t_pool_recompute(_pool_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  UPDATE public.tournament_pool_entrants pe
     SET played = COALESCE(s.played, 0),
         wins   = COALESCE(s.wins, 0),
         points = COALESCE(s.points, 0)
    FROM (
      SELECT x.entrant_id,
             count(*)                                        AS played,
             count(*) FILTER (WHERE x.won)                   AS wins,
             SUM(CASE WHEN x.won THEN 3 WHEN x.drew THEN 1 ELSE 0 END) AS points
        FROM (
          SELECT unnest(m.entrant_ids) AS entrant_id,
                 m.winner_entrant_id IS NOT NULL
                   AND unnest(m.entrant_ids) = m.winner_entrant_id AS won,
                 m.winner_entrant_id IS NULL AS drew
            FROM public.tournament_matches m
           WHERE m.pool_id = _pool_id AND m.status = 'finished'
        ) x
       GROUP BY x.entrant_id
    ) s
   WHERE pe.pool_id = _pool_id AND pe.entrant_id = s.entrant_id;

  -- remise à zéro des joueurs sans match joué
  UPDATE public.tournament_pool_entrants pe
     SET played = 0, wins = 0, points = 0
   WHERE pe.pool_id = _pool_id
     AND NOT EXISTS (
       SELECT 1 FROM public.tournament_matches m
        WHERE m.pool_id = _pool_id AND m.status = 'finished'
          AND pe.entrant_id = ANY(m.entrant_ids));
END $$;

-- 2) Classement ordonné : points, victoires, confrontation directe, ordre stable
CREATE OR REPLACE FUNCTION public._t_pool_rank(_pool_id uuid)
RETURNS TABLE(entrant_id uuid, pos int)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH base AS (
    SELECT pe.entrant_id, pe.points, pe.wins, pe.id AS tiebreak
      FROM public.tournament_pool_entrants pe
     WHERE pe.pool_id = _pool_id
  ),
  h2h AS (
    SELECT b.entrant_id,
           COALESCE((
             SELECT count(*) FROM public.tournament_matches m
              WHERE m.pool_id = _pool_id AND m.status = 'finished'
                AND m.winner_entrant_id = b.entrant_id
                AND EXISTS (
                  SELECT 1 FROM base b2
                   WHERE b2.entrant_id <> b.entrant_id
                     AND b2.points = b.points
                     AND b2.entrant_id = ANY(m.entrant_ids))
           ), 0) AS h2h_wins
      FROM base b
  )
  SELECT b.entrant_id,
         row_number() OVER (ORDER BY b.points DESC, b.wins DESC, h.h2h_wins DESC, b.tiebreak)::int
    FROM base b JOIN h2h h ON h.entrant_id = b.entrant_id;
$$;

-- 3) Fin de match : recalcul complet de la poule (idempotent)
CREATE OR REPLACE FUNCTION public._t_match_finish(_match_id uuid, _winner uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE m public.tournament_matches%ROWTYPE; e uuid;
BEGIN
  SELECT * INTO m FROM public.tournament_matches WHERE id = _match_id FOR UPDATE;
  IF m.id IS NULL OR m.status = 'finished' THEN RETURN; END IF;

  UPDATE public.tournament_matches
     SET status = 'finished', winner_entrant_id = _winner, finished_at = now()
   WHERE id = _match_id;

  IF m.phase = 'pool' AND m.pool_id IS NOT NULL THEN
    PERFORM public._t_pool_recompute(m.pool_id);
  ELSE
    FOREACH e IN ARRAY m.entrant_ids LOOP
      IF _winner IS NULL OR e <> _winner THEN
        UPDATE public.tournament_entrants
           SET status = 'eliminated', eliminated_round = m.round
         WHERE id = e AND status = 'active';
      END IF;
    END LOOP;
  END IF;

  FOREACH e IN ARRAY m.entrant_ids LOOP
    IF _winner IS NOT NULL AND e = _winner THEN
      PERFORM public._t_notify(e, '✅ Match gagné', 'Vous passez à la suite du tournoi.', '/tournaments/' || m.tournament_id);
    ELSIF _winner IS NULL THEN
      PERFORM public._t_notify(e, '🤝 Match nul', 'Le match se termine sans vainqueur.', '/tournaments/' || m.tournament_id);
    ELSE
      PERFORM public._t_notify(e, '❌ Match perdu', 'Merci d''avoir participé.', '/tournaments/' || m.tournament_id);
    END IF;
  END LOOP;
END $$;

-- 4) Phase d'élimination toujours en 1v1
CREATE OR REPLACE FUNCTION public._t_build_round(_tid uuid, _round integer, _ids uuid[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE t public.tournaments%ROWTYPE; n int; i int := 1; v_take int; v_rest int; v_mno int := 0;
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid;
  n := COALESCE(array_length(_ids,1),0);
  IF n = 0 THEN RETURN; END IF;

  IF n = 1 THEN
    UPDATE public.tournaments SET champion_entrant_id = _ids[1] WHERE id = _tid;
    PERFORM public._t_finish(_tid);
    RETURN;
  END IF;

  WHILE i <= n LOOP
    v_rest := n - i + 1;
    v_take := LEAST(2, v_rest);
    -- joueur seul restant : table de 3 en Ludo, sinon il est qualifié d'office
    IF v_rest = 3 THEN
      IF t.game_slug = 'ludo' THEN
        v_take := 3;
      ELSE
        v_take := 2;
      END IF;
    END IF;
    IF v_rest = 1 THEN
      -- impossible d'appairer : le joueur passe directement au tour suivant
      EXIT;
    END IF;
    v_mno := v_mno + 1;
    INSERT INTO public.tournament_matches(tournament_id, phase, round, match_no, entrant_ids)
      VALUES (_tid, 'final', _round, v_mno, (SELECT array_agg(_ids[j]) FROM generate_series(i, i + v_take - 1) j));
    i := i + v_take;
  END LOOP;

  UPDATE public.tournaments SET stage = 'finals', current_round = _round WHERE id = _tid;
END $$;

-- 5) Moteur : qualification déterministe + max 8 matchs simultanés + report des joueurs non appairés
CREATE OR REPLACE FUNCTION public.tournament_engine(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  t public.tournaments%ROWTYPE;
  m record; g record; v_win uuid; v_slot int; v_busy uuid[]; v_live int; v_cap int;
  v_pool record; v_next uuid[]; v_losers uuid[]; v_ready int; v_total int;
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF t.id IS NULL OR t.status <> 'running' THEN RETURN; END IF;

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

  -- clôture des poules terminées : classement recalculé puis départage déterministe
  FOR v_pool IN SELECT p.* FROM public.tournament_pools p
                 WHERE p.tournament_id = _tid AND p.status = 'running'
                   AND NOT EXISTS (SELECT 1 FROM public.tournament_matches mm
                                    WHERE mm.pool_id = p.id AND mm.status IN ('scheduled','running')) LOOP
    PERFORM public._t_pool_recompute(v_pool.id);
    UPDATE public.tournament_pool_entrants pe SET qualified = true
     WHERE pe.pool_id = v_pool.id
       AND pe.entrant_id IN (
         SELECT r.entrant_id FROM public._t_pool_rank(v_pool.id) r
          WHERE r.pos <= (SELECT qualifiers_per_pool FROM public.tournaments WHERE id = _tid));
    UPDATE public.tournament_entrants e SET status = 'eliminated', eliminated_round = 1
      FROM public.tournament_pool_entrants pe
     WHERE pe.pool_id = v_pool.id AND pe.entrant_id = e.id AND NOT pe.qualified AND e.status = 'active';
    UPDATE public.tournament_pools SET status = 'finished' WHERE id = v_pool.id;
  END LOOP;

  IF NOT EXISTS (SELECT 1 FROM public.tournament_matches
                  WHERE tournament_id = _tid AND status IN ('scheduled','running')) THEN
    IF t.auto_advance THEN
      IF t.stage = 'pools' THEN
        SELECT array_agg(e.id ORDER BY random()) INTO v_next
          FROM public.tournament_entrants e WHERE e.tournament_id = _tid AND e.status = 'active';
        PERFORM public._t_build_round(_tid, 2, v_next);
      ELSIF t.stage = 'finals' THEN
        IF (SELECT count(*) FROM public.tournament_matches
                 WHERE tournament_id = _tid AND round = t.current_round AND phase = 'final') = 2
           AND NOT EXISTS (SELECT 1 FROM public.tournament_matches
                            WHERE tournament_id = _tid AND phase = 'third_place') THEN
          SELECT array_agg(x.eid) INTO v_losers FROM (
            SELECT unnest(mm.entrant_ids) eid, mm.winner_entrant_id w
              FROM public.tournament_matches mm
             WHERE mm.tournament_id = _tid AND mm.round = t.current_round AND mm.phase = 'final') x
           WHERE x.eid IS DISTINCT FROM x.w;
          IF array_length(v_losers,1) = 2 THEN
            INSERT INTO public.tournament_matches(tournament_id, phase, round, match_no, entrant_ids)
              VALUES (_tid, 'third_place', t.current_round + 1, 1, v_losers);
          END IF;
        END IF;

        -- vainqueurs du tour + joueurs restés actifs sans match (non appairés)
        SELECT array_agg(id) INTO v_next FROM (
          SELECT e.id
            FROM public.tournament_entrants e
           WHERE e.tournament_id = _tid AND e.status = 'active'
           ORDER BY e.created_at) s;

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

  -- lancement des matchs : maximum 8 simultanés
  v_cap := LEAST(COALESCE(t.max_concurrent_matches, 8), 8);
  SELECT count(*) INTO v_live FROM public.tournament_matches
   WHERE tournament_id = _tid AND status = 'running';
  SELECT COALESCE(array_agg(x), ARRAY[]::uuid[]) INTO v_busy FROM (
    SELECT unnest(entrant_ids) x FROM public.tournament_matches
     WHERE tournament_id = _tid AND status = 'running') s;

  FOR m IN SELECT * FROM public.tournament_matches
            WHERE tournament_id = _tid AND status = 'scheduled'
            ORDER BY round, match_no LOOP
    EXIT WHEN v_live >= v_cap;
    CONTINUE WHEN m.entrant_ids && v_busy;
    PERFORM public._t_launch_match(m.id);
    v_busy := v_busy || m.entrant_ids;
    v_live := v_live + 1;
  END LOOP;
END $$;

REVOKE ALL ON FUNCTION public._t_pool_recompute(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._t_pool_recompute(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._t_pool_rank(uuid) TO authenticated, service_role;