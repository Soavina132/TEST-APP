-- ═══════════════════════════════════════════════════════════════════════
-- TIMER FIXES: precise deadline_at for every match phase
-- + tournament_state includes deadline_at
-- ═══════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════
-- FIX: tournament_engine — update deadline_at when game transitions
--   from 'open' (lobby) to 'playing'. Previously deadline_at stayed at
--   the lobby deadline even after the game started, so the frontend
--   couldn't show a match countdown.
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

  v_dur_limit := COALESCE(t.max_match_duration_secs, 600);

  FOR m IN SELECT * FROM public.tournament_matches
            WHERE tournament_id = _tid AND status = 'running' AND game_id IS NOT NULL LOOP
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
          -- ═══ UPDATE deadline_at to match duration limit ═══
          UPDATE public.tournament_matches SET deadline_at = now() + make_interval(secs => v_dur_limit)
           WHERE id = m.id;
        END IF;
      ELSE
        SELECT count(*), count(*) FILTER (WHERE ready OR is_bot) INTO v_total, v_ready
          FROM public.domino_participants WHERE game_id = m.game_id;
        IF v_total > 1 AND v_ready = v_total THEN
          PERFORM public._domino_start(m.game_id);
          -- ═══ UPDATE deadline_at to match duration limit ═══
          UPDATE public.tournament_matches SET deadline_at = now() + make_interval(secs => v_dur_limit)
           WHERE id = m.id;
        END IF;
      END IF;

      -- Lobby deadline expired → forfeit
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

  -- Clôture des poules terminées
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

  -- Phase terminée : pause puis phase suivante
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

  -- Lancement des matchs simultanés
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
-- FIX: tournament_state — include deadline_at in match data
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.tournament_state(_tid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  t     record;
  ents  jsonb;
  wl    jsonb;
  pls   jsonb;
  mts   jsonb;
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid;
  IF NOT FOUND THEN RETURN NULL; END IF;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', e.id, 'user_id', e.user_id, 'display_name', e.display_name,
      'status', e.status, 'seed', e.seed, 'final_rank', e.final_rank,
      'is_bot', e.is_bot, 'checked_in', COALESCE(e.checked_in, false),
      'check_in_at', e.check_in_at,
      'eliminated_round', e.eliminated_round
    ) ORDER BY e.seed
  ), '[]'::jsonb)
  INTO ents
  FROM public.tournament_entrants e
  WHERE e.tournament_id = _tid;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', w.id, 'user_id', w.user_id, 'display_name', w.display_name,
      'position', w.position
    ) ORDER BY w.position
  ), '[]'::jsonb)
  INTO wl
  FROM public.tournament_waitlist w
  WHERE w.tournament_id = _tid;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'pool', jsonb_build_object('id', p.id, 'label', p.label, 'status', p.status),
      'players', COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', pe.id, 'entrant_id', pe.entrant_id, 'played', pe.played,
            'wins', pe.wins, 'points', pe.points, 'qualified', COALESCE(pe.qualified, false)
          ) ORDER BY pe.points DESC, pe.wins DESC
        )
        FROM public.tournament_pool_entrants pe WHERE pe.pool_id = p.id
      ), '[]'::jsonb)
    ) ORDER BY p.label
  ), '[]'::jsonb)
  INTO pls
  FROM public.tournament_pools p
  WHERE p.tournament_id = _tid;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', m.id, 'round', m.round, 'phase', m.phase, 'match_no', m.match_no,
      'entrant_ids', m.entrant_ids, 'status', m.status,
      'winner_entrant_id', m.winner_entrant_id,
      'winner_id', m.winner_entrant_id,
      'loser_id', CASE
        WHEN array_length(m.entrant_ids, 1) = 2 AND m.winner_entrant_id IS NOT NULL AND NOT COALESCE(m.is_draw, false)
        THEN (SELECT x FROM unnest(m.entrant_ids) x WHERE x <> m.winner_entrant_id LIMIT 1)
        ELSE NULL
      END,
      'game_id', m.game_id, 'pool_id', m.pool_id,
      'created_at', m.created_at, 'started_at', m.started_at,
      'finished_at', m.finished_at,
      'deadline_at', m.deadline_at,
      'is_draw', COALESCE(m.is_draw, false),
      'scheduled_at', m.created_at,
      'is_third_place', COALESCE(m.is_third_place, false)
    ) ORDER BY m.round, m.match_no
  ), '[]'::jsonb)
  INTO mts
  FROM public.tournament_matches m
  WHERE m.tournament_id = _tid;

  RETURN jsonb_build_object(
    'tournament', jsonb_build_object(
      'id', t.id, 'name', t.name, 'description', t.description,
      'game_slug', t.game_slug, 'format', t.format,
      'players_per_match', t.players_per_match, 'max_players', t.max_players,
      'entry_fee_ar', t.entry_fee_ar, 'admin_prize_pool_ar', t.admin_prize_pool_ar,
      'prize_pool_ar', t.prize_pool_ar, 'platform_pct', t.platform_pct,
      'winners_count', t.winners_count,
      'prize_1_pct', t.prize_1_pct, 'prize_2_pct', t.prize_2_pct,
      'prize_3_pct', t.prize_3_pct, 'prize_4_pct', t.prize_4_pct,
      'pool_size', t.pool_size, 'qualifiers_per_pool', t.qualifiers_per_pool,
      'max_concurrent_matches', t.max_concurrent_matches, 'lobby_minutes', t.lobby_minutes,
      'status', t.status, 'stage', t.stage, 'current_round', t.current_round,
      'total_rounds', t.total_rounds,
      'auto_advance', t.auto_advance, 'is_simulation', t.is_simulation,
      'break_seconds', t.break_seconds, 'batch_gap_seconds', t.batch_gap_seconds,
      'max_match_duration_secs', t.max_match_duration_secs,
      'check_in_minutes', t.check_in_minutes,
      'check_in_opened_at', t.check_in_opened_at,
      'started_at', t.started_at, 'finished_at', t.finished_at,
      'break_until', t.break_until,
      'registration_closes_at', t.registration_closes_at, 'starts_at', t.starts_at,
      'domino_scoring', t.domino_scoring, 'target_score', t.target_score,
      'rewards_paid_at', t.rewards_paid_at
    ),
    'entrants', ents,
    'waitlist', wl,
    'pools', pls,
    'matches', mts
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_state(uuid) TO authenticated;
