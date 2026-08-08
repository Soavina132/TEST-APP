-- ═══════════════════════════════════════════════════════════════════════
-- FIX: tournament_state now includes eliminated_round and total_rounds
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

  -- Entrants (with eliminated_round)
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

  -- Waitlist
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', w.id, 'user_id', w.user_id, 'display_name', w.display_name,
      'position', w.position
    ) ORDER BY w.position
  ), '[]'::jsonb)
  INTO wl
  FROM public.tournament_waitlist w
  WHERE w.tournament_id = _tid;

  -- Pools grouped as { pool, players }
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

  -- Matches (with computed winner_id/loser_id aliases for frontend compat)
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
      'finished_at', m.finished_at, 'is_draw', COALESCE(m.is_draw, false),
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
