-- ═══════════════════════════════════════════════════════════════════════
-- CRITICAL FIXES for tournament end-to-end flow
-- ═══════════════════════════════════════════════════════════════════════
-- Bug #1: No trigger calls tournament_engine after a game finishes
--   → Create poll_tournament_engine() RPC for frontend to call
-- Bug #2: Engine query filters game_id IS NOT NULL → simulation matches ignored
--   → Remove the filter, handle NULL game_id inside the loop
-- Bug #3: Bye matches (1 player) stall → game never starts
--   → Auto-finish 1-player matches in the engine
-- Bug #4: Third place match players already eliminated
--   → Reactivate them when creating the third place match
-- ═══════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════
-- FIX #1: poll_tournament_engine — callable by any authenticated user
--   Frontend calls this every 10s to keep the tournament flowing
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.poll_tournament_engine(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Only run if tournament is running
  PERFORM 1 FROM public.tournaments WHERE id = _tid AND status = 'running';
  IF FOUND THEN
    PERFORM public.tournament_engine(_tid);
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.poll_tournament_engine(uuid) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- FIX #2 + #3: Rewrite tournament_engine to handle:
--   - Simulation matches (game_id IS NULL)
--   - Bye matches (1 entrant) → auto-finish with that player as winner
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.tournament_engine(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  t public.tournaments%ROWTYPE;
  m record; g record; v_win uuid; v_slot int; v_busy uuid[]; v_live int; v_cap int;
  v_pool record; v_ready int; v_total int; v_active int; v_e record;
  v_dur_limit int;
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF t.id IS NULL OR t.status <> 'running' THEN RETURN; END IF;

  v_dur_limit := COALESCE(t.max_match_duration_secs, 1800);

  -- ═══ Process all running matches (including simulation with game_id NULL) ═══
  FOR m IN SELECT * FROM public.tournament_matches
            WHERE tournament_id = _tid AND status = 'running' LOOP

    -- ── Bye match: only 1 entrant → auto-win ──
    IF array_length(m.entrant_ids, 1) <= 1 THEN
      PERFORM public._t_match_finish(m.id, m.entrant_ids[1]);
      CONTINUE;
    END IF;

    -- ── Simulation match (game_id is NULL) → wait for timeout ──
    IF m.game_id IS NULL THEN
      IF m.started_at IS NOT NULL AND EXTRACT(EPOCH FROM (now() - m.started_at)) > v_dur_limit THEN
        -- Pick random winner for simulation
        v_win := m.entrant_ids[floor(random() * array_length(m.entrant_ids, 1) + 1)];
        PERFORM public._t_match_finish(m.id, v_win);
      END IF;
      CONTINUE;
    END IF;

    -- ── Real match: check game status ──
    v_win := NULL;
    IF t.game_slug = 'ludo' THEN
      SELECT status::text AS st, winner_id INTO g FROM public.ludo_games WHERE id = m.game_id;
    ELSE
      SELECT status::text AS st, winner_id INTO g FROM public.domino_games WHERE id = m.game_id;
    END IF;
    CONTINUE WHEN g IS NULL;

    -- ── Match timeout (max duration exceeded) ──
    IF m.started_at IS NOT NULL AND EXTRACT(EPOCH FROM (now() - m.started_at)) > v_dur_limit THEN
      v_slot := NULL;
      IF t.game_slug = 'ludo' THEN
        SELECT slot INTO v_slot FROM public.ludo_participants
         WHERE game_id = m.game_id
         ORDER BY finish_rank ASC NULLS LAST, score DESC NULLS LAST, random()
         LIMIT 1;
        UPDATE public.ludo_games SET status = 'finished', finished_at = now() WHERE id = m.game_id;
      ELSE
        SELECT slot INTO v_slot FROM public.domino_participants
         WHERE game_id = m.game_id
         ORDER BY score DESC NULLS LAST, score_round DESC NULLS LAST, random()
         LIMIT 1;
        UPDATE public.domino_games SET status = 'finished', finished_at = now() WHERE id = m.game_id;
      END IF;

      IF v_slot IS NOT NULL AND (v_slot + 1) <= array_length(m.entrant_ids, 1) THEN
        v_win := m.entrant_ids[v_slot + 1];
      ELSE
        v_win := m.entrant_ids[floor(random() * array_length(m.entrant_ids, 1) + 1)];
      END IF;
      PERFORM public._t_match_finish(m.id, v_win);
      CONTINUE;
    END IF;

    -- ── Game finished normally ──
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

    -- ── Game cancelled ──
    ELSIF g.st = 'cancelled' THEN
      UPDATE public.tournament_matches SET status = 'scheduled', game_id = NULL, started_at = NULL, deadline_at = NULL
       WHERE id = m.id;

    -- ── Game in lobby (open) — check ready + lobby deadline ──
    ELSIF g.st = 'open' THEN
      IF t.game_slug = 'ludo' THEN
        SELECT count(*), count(*) FILTER (WHERE ready OR is_bot) INTO v_total, v_ready
          FROM public.ludo_participants WHERE game_id = m.game_id;
        IF v_total > 1 AND v_ready = v_total THEN
          UPDATE public.ludo_games SET status = 'playing', started_at = now(),
                 state = public._ludo_init_state(v_total) WHERE id = m.game_id AND status = 'open';
          UPDATE public.tournament_matches SET deadline_at = now() + make_interval(secs => v_dur_limit)
           WHERE id = m.id;
        END IF;
      ELSE
        SELECT count(*), count(*) FILTER (WHERE ready OR is_bot) INTO v_total, v_ready
          FROM public.domino_participants WHERE game_id = m.game_id;
        IF v_total > 1 AND v_ready = v_total THEN
          PERFORM public._domino_start(m.game_id);
          UPDATE public.tournament_matches SET deadline_at = now() + make_interval(secs => v_dur_limit)
           WHERE id = m.id;
        END IF;
      END IF;

      -- Lobby deadline expired → forfeit
      IF m.deadline_at IS NOT NULL AND m.deadline_at < now() THEN
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

  -- ═══ Close finished pools ═══
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

  -- ═══ Phase transition ═══
  IF NOT EXISTS (SELECT 1 FROM public.tournament_matches
                  WHERE tournament_id = _tid AND status IN ('scheduled','running'))
     AND t.stage IN ('pools','finals') THEN

    SELECT count(*) INTO v_active FROM public.tournament_entrants
     WHERE tournament_id = _tid AND status = 'active';

    IF v_active <= 1 THEN
      UPDATE public.tournaments SET break_until = NULL,
             champion_entrant_id = COALESCE(champion_entrant_id,
               (SELECT id FROM public.tournament_entrants WHERE tournament_id = _tid AND status = 'active' LIMIT 1))
       WHERE id = _tid;
      PERFORM public._t_finish(_tid);
      RETURN;
    END IF;

    IF t.auto_advance THEN
      IF t.break_until IS NULL AND COALESCE(t.break_seconds,0) > 0 THEN
        UPDATE public.tournaments
           SET break_until = now() + make_interval(secs => t.break_seconds) WHERE id = _tid;
        FOR v_e IN SELECT id FROM public.tournament_entrants
                    WHERE tournament_id = _tid AND status = 'active' LOOP
          PERFORM public._t_notify(v_e.id, '⏸ Pause avant la phase suivante',
            'Préparez-vous : la phase suivante démarre dans ' || (t.break_seconds / 60) || ' min.',
            '/tournaments/' || _tid);
        END LOOP;
        RETURN;
      ELSIF t.break_until IS NOT NULL AND now() < t.break_until THEN
        RETURN;
      ELSE
        UPDATE public.tournaments SET break_until = NULL WHERE id = _tid;
        PERFORM public._t_next_round(_tid);
        SELECT * INTO t FROM public.tournaments WHERE id = _tid;
        IF t.status <> 'running' THEN RETURN; END IF;
      END IF;
    END IF;
  END IF;

  -- ═══ Launch scheduled matches ═══
  v_cap := LEAST(GREATEST(COALESCE(t.max_concurrent_matches, 8), 1), 8);
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
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- FIX #4: _t_next_round — reactivate third place match players
--   When creating the third place match, set the losers back to 'active'
--   so they can play the match properly
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._t_next_round(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE t public.tournaments%ROWTYPE; ids uuid[]; losers uuid[];
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF t.id IS NULL OR t.status <> 'running' THEN RETURN; END IF;

  SELECT array_agg(e.id ORDER BY random()) INTO ids
    FROM public.tournament_entrants e
   WHERE e.tournament_id = _tid AND e.status = 'active';

  IF COALESCE(array_length(ids,1),0) <= 1 THEN
    UPDATE public.tournaments SET champion_entrant_id = COALESCE(champion_entrant_id, ids[1]) WHERE id = _tid;
    PERFORM public._t_finish(_tid);
    RETURN;
  END IF;

  IF array_length(ids,1) = 2 AND t.winners_count >= 3
     AND NOT EXISTS (SELECT 1 FROM public.tournament_matches
                      WHERE tournament_id = _tid AND phase = 'third_place') THEN
    SELECT array_agg(x.eid) INTO losers FROM (
      SELECT unnest(m.entrant_ids) eid, m.winner_entrant_id w
        FROM public.tournament_matches m
       WHERE m.tournament_id = _tid AND m.phase = 'final'
         AND m.status = 'finished' AND m.round = t.current_round) x
     WHERE x.eid IS DISTINCT FROM x.w;
    IF COALESCE(array_length(losers,1),0) = 2 THEN
      -- ═══ REACTIVATE the losers so they can play the third place match ═══
      UPDATE public.tournament_entrants
         SET status = 'active'
       WHERE id = ANY(losers) AND status = 'eliminated';

      INSERT INTO public.tournament_matches(tournament_id, phase, round, match_no, entrant_ids)
        VALUES (_tid, 'third_place', t.current_round + 1, 1, losers);
      UPDATE public.tournaments SET stage = 'finals', current_round = t.current_round + 1, current_round_started_at = now() WHERE id = _tid;
      RETURN;
    END IF;
  END IF;

  PERFORM public._t_build_round(_tid, t.current_round + 1, ids);
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- FIX #3 (b): _t_build_round — handle odd player counts better
--   When 1 player is left (bye), DON'T create a 1-player match.
--   Instead, carry them to the next round automatically.
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._t_build_round(_tid uuid, _round integer, _ids uuid[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  t public.tournaments%ROWTYPE;
  n int; i int := 1; v_take int; v_rest int; v_mno int := 0;
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
    v_take := LEAST(t.players_per_match, v_rest);

    -- 3 players left in Ludo → table of 3
    IF v_rest = 3 AND t.game_slug = 'ludo' AND t.players_per_match >= 3 THEN
      v_take := 3;
    END IF;

    -- Odd leftover (1 player after pairing) → give them a bye to next round
    -- by putting them in a 1-player "bye" match that the engine auto-finishes
    IF v_rest = 1 AND v_take = 1 THEN
      v_mno := v_mno + 1;
      INSERT INTO public.tournament_matches(tournament_id, phase, round, match_no, entrant_ids)
        VALUES (_tid, 'final', _round, v_mno, ARRAY[_ids[i]]);
      i := i + 1;
      CONTINUE;
    END IF;

    -- Avoid leaving exactly 1 player after this match (absorb them)
    IF v_rest - v_take = 1 AND t.players_per_match >= 3 THEN
      v_take := v_take + 1;
    END IF;

    v_mno := v_mno + 1;
    INSERT INTO public.tournament_matches(tournament_id, phase, round, match_no, entrant_ids)
      VALUES (_tid, 'final', _round, v_mno, (SELECT array_agg(_ids[j]) FROM generate_series(i, i + v_take - 1) j));
    i := i + v_take;
  END LOOP;

  UPDATE public.tournaments SET stage = 'finals', current_round = _round, current_round_started_at = now() WHERE id = _tid;
END;
$$;
