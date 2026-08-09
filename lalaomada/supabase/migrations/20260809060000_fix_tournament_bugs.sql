-- ═══════════════════════════════════════════════════════════════════════
-- FIX: 4 bugs trouvés par simulation complète
--
-- 1. total_rounds ne compte pas correctement (pools + knockout)
-- 2. Ludo poules: pas de tiebreaker pour les perdants (qualifié aléatoire)
-- 3. 3e place et finale dans des rounds séparés (cosmétique mais confus)
-- 4. _t_match_finish ne stockait pas le classement dans le match
-- ═══════════════════════════════════════════════════════════════════════

-- ── Add placements column to tournament_matches ──
ALTER TABLE public.tournament_matches
  ADD COLUMN IF NOT EXISTS placements jsonb DEFAULT NULL;

-- ═══════════════════════════════════════════════════════════════════════
-- FIX 1: admin_tournament_start — compute total_rounds correctly
--   - For pools: 1 (pool round) + knockout rounds for qualifiers
--   - For knockout: knockout rounds from all players
--   - 3rd place and final share the same round, so no +1 needed
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.admin_tournament_start(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  t public.tournaments%ROWTYPE;
  ids uuid[];
  n int;
  r int := 0;
  v_ko_players int;
  v_pool_rounds int;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin uniquement'; END IF;
  SELECT * INTO t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF t.status <> 'open' THEN RAISE EXCEPTION 'Tournoi deja lance'; END IF;
  SELECT count(*) INTO n FROM public.tournament_entrants WHERE tournament_id = _tid;
  IF n < 2 THEN RAISE EXCEPTION 'Pas assez de joueurs'; END IF;

  -- Compute total_rounds
  IF t.format = 'pools' THEN
    v_ko_players := CEIL(n::numeric / t.pool_size) * t.qualifiers_per_pool;
    v_pool_rounds := 1;
  ELSE
    v_ko_players := n;
    v_pool_rounds := 0;
  END IF;

  r := v_pool_rounds;
  WHILE v_ko_players > 1 LOOP
    v_ko_players := CEIL(v_ko_players::numeric / GREATEST(COALESCE(t.players_per_match, 2), 2));
    r := r + 1;
  END LOOP;

  UPDATE public.tournaments
     SET status = 'running', started_at = now(), break_until = NULL,
         total_rounds = r, current_round_started_at = now()
   WHERE id = _tid;

  IF t.format = 'pools' THEN
    PERFORM public._t_draw_pools(_tid);
  ELSE
    SELECT array_agg(id ORDER BY random()) INTO ids
      FROM public.tournament_entrants
     WHERE tournament_id = _tid AND status = 'active';
    PERFORM public._t_build_round(_tid, 1, ids);
  END IF;
  PERFORM public.tournament_engine(_tid);
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- FIX 2 & 4: _t_match_finish — store placements for pool matches
--   For Ludo: use finish_rank from ludo_participants
--   For Domino: winner=1, loser=99
--   For simulation: winner=1, others=99 (no game data)
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._t_match_finish(_match_id uuid, _winner uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  m public.tournament_matches%ROWTYPE;
  e uuid;
  v_placements jsonb := '{}'::jsonb;
  v_game_slug text;
  v_slot int;
  v_rank int;
BEGIN
  SELECT * INTO m FROM public.tournament_matches WHERE id = _match_id FOR UPDATE;
  IF m.id IS NULL OR m.status = 'finished' THEN RETURN; END IF;

  IF _winner IS NULL AND m.phase = 'pool' THEN
    UPDATE public.tournament_matches
       SET status = 'finished', winner_entrant_id = NULL, is_draw = true, finished_at = now()
     WHERE id = _match_id;
  ELSE
    UPDATE public.tournament_matches
       SET status = 'finished', winner_entrant_id = _winner, is_draw = false, finished_at = now()
     WHERE id = _match_id;
  END IF;

  -- Compute placements for pool matches (used as tiebreaker in _t_pool_rank)
  IF m.phase = 'pool' AND m.pool_id IS NOT NULL THEN
    SELECT game_slug INTO v_game_slug FROM public.tournaments WHERE id = m.tournament_id;

    IF m.game_id IS NOT NULL AND v_game_slug = 'ludo' THEN
      -- Ludo: use finish_rank from ludo_participants
      FOR v_slot IN 0..array_length(m.entrant_ids, 1) - 1 LOOP
        SELECT COALESCE(finish_rank, 99) INTO v_rank
          FROM public.ludo_participants
         WHERE game_id = m.game_id AND slot = v_slot;
        v_placements := v_placements || jsonb_build_object(m.entrant_ids[v_slot + 1]::text, v_rank);
      END LOOP;
    ELSE
      -- Domino or simulation: winner=1, others=99
      FOREACH e IN ARRAY m.entrant_ids LOOP
        IF e = _winner THEN
          v_placements := v_placements || jsonb_build_object(e::text, 1);
        ELSE
          v_placements := v_placements || jsonb_build_object(e::text, 99);
        END IF;
      END LOOP;
    END IF;

    UPDATE public.tournament_matches SET placements = v_placements WHERE id = _match_id;
  END IF;

  -- Update entrant statuses
  IF m.phase = 'pool' AND m.pool_id IS NOT NULL THEN
    PERFORM public._t_pool_recompute(m.pool_id);
  ELSE
    FOREACH e IN ARRAY m.entrant_ids LOOP
      IF m.phase = 'third_place' OR _winner IS NULL OR e <> _winner THEN
        UPDATE public.tournament_entrants
           SET status = 'eliminated', eliminated_round = m.round
         WHERE id = e AND status = 'active';
      END IF;
    END LOOP;
  END IF;

  -- Notifications
  FOREACH e IN ARRAY m.entrant_ids LOOP
    IF _winner IS NOT NULL AND e = _winner THEN
      PERFORM public._t_notify(e, '✅ Match gagné', 'Vous passez à la suite du tournoi.', '/tournaments/' || m.tournament_id);
    ELSIF _winner IS NULL THEN
      PERFORM public._t_notify(e, '🤝 Match nul', 'Le match se termine sans vainqueur.', '/tournaments/' || m.tournament_id);
    ELSE
      PERFORM public._t_notify(e, '❌ Match perdu', 'Merci d''avoir participé.', '/tournaments/' || m.tournament_id);
    END IF;
  END LOOP;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- FIX 2 (cont): _t_pool_rank — use placements as tiebreaker
--   Order: points DESC → wins DESC → h2h_wins DESC → best_placement ASC → tiebreak
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._t_pool_rank(_pool_id uuid)
RETURNS TABLE(entrant_id uuid, pos integer)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH base AS (
    SELECT pe.entrant_id, pe.points, pe.wins, pe.id AS tiebreak,
           COALESCE(MIN(
             COALESCE(
               (m.placements ->> pe.entrant_id::text)::int,
               CASE WHEN m.winner_entrant_id = pe.entrant_id THEN 1 ELSE 99 END
             )
           ), 99) AS best_placement
      FROM public.tournament_pool_entrants pe
      LEFT JOIN public.tournament_matches m
        ON m.pool_id = _pool_id AND m.status = 'finished'
       AND pe.entrant_id = ANY(m.entrant_ids)
     WHERE pe.pool_id = _pool_id
     GROUP BY pe.entrant_id, pe.points, pe.wins, pe.id
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
         row_number() OVER (
           ORDER BY b.points DESC, b.wins DESC, h.h2h_wins DESC,
                    b.best_placement ASC, b.tiebreak
         )::int
    FROM base b JOIN h2h h ON h.entrant_id = b.entrant_id;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- FIX 3: _t_next_round — create 3rd place AND final in the same round
--   Before: 3rd place at R(n+1), then final at R(n+2) — separate rounds
--   After:  both 3rd place AND final at R(n+1) — same round, run in parallel
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._t_next_round(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  t public.tournaments%ROWTYPE;
  ids uuid[];
  losers uuid[];
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF t.id IS NULL OR t.status <> 'running' THEN RETURN; END IF;

  SELECT array_agg(e.id ORDER BY random()) INTO ids
    FROM public.tournament_entrants e
   WHERE e.tournament_id = _tid AND e.status = 'active';

  IF COALESCE(array_length(ids,1),0) <= 1 THEN
    UPDATE public.tournaments
       SET champion_entrant_id = COALESCE(champion_entrant_id, ids[1])
     WHERE id = _tid;
    PERFORM public._t_finish(_tid);
    RETURN;
  END IF;

  -- 3rd place + Final: create both in the SAME round
  IF array_length(ids,1) = 2 AND t.winners_count >= 3
     AND NOT EXISTS (SELECT 1 FROM public.tournament_matches
                      WHERE tournament_id = _tid AND phase = 'third_place') THEN

    -- Get the semifinal losers (from the previous round)
    SELECT array_agg(x.eid) INTO losers FROM (
      SELECT unnest(m.entrant_ids) eid, m.winner_entrant_id w
        FROM public.tournament_matches m
       WHERE m.tournament_id = _tid AND m.phase = 'final'
         AND m.status = 'finished' AND m.round = t.current_round) x
     WHERE x.eid IS DISTINCT FROM x.w;

    IF COALESCE(array_length(losers,1),0) = 2 THEN
      -- Reactivate the losers so they can play the 3rd place match
      UPDATE public.tournament_entrants
         SET status = 'active'
       WHERE id = ANY(losers) AND status = 'eliminated';

      -- Create BOTH 3rd place AND final in the same round
      INSERT INTO public.tournament_matches(tournament_id, phase, round, match_no, entrant_ids)
        VALUES (_tid, 'third_place', t.current_round + 1, 1, losers);
      INSERT INTO public.tournament_matches(tournament_id, phase, round, match_no, entrant_ids)
        VALUES (_tid, 'final', t.current_round + 1, 1, ids);

      UPDATE public.tournaments
         SET stage = 'finals', current_round = t.current_round + 1,
             current_round_started_at = now()
       WHERE id = _tid;
      RETURN;
    END IF;
  END IF;

  -- Normal next round
  PERFORM public._t_build_round(_tid, t.current_round + 1, ids);
END;
$$;
