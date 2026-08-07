-- ============================================================================
-- Tournament rules: 10% commission, 60/20/10 splits, domino points mode,
-- Ludo max concurrent cap, lobby max 10 min
-- =============================================================================

-- 1. Relax winners_count CHECK (allow up to 4)
ALTER TABLE public.tournaments DROP CONSTRAINT IF EXISTS tournaments_winners_count_check;
ALTER TABLE public.tournaments ADD CONSTRAINT tournaments_winners_count_check
  CHECK (winners_count BETWEEN 1 AND 4);

-- 2. Add domino_scoring column (elimination vs points)
ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS domino_scoring text NOT NULL DEFAULT 'elimination'
  CHECK (domino_scoring IN ('elimination', 'points'));

-- 3. Add target_score for domino points mode (points needed to win a match)
ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS target_score integer NOT NULL DEFAULT 100;

-- 4. Enable realtime on tournament_waitlist
ALTER TABLE public.tournament_waitlist REPLICA IDENTITY FULL;

-- 5. Update admin_tournament_create to accept domino_scoring & target_score
DROP FUNCTION IF EXISTS public.admin_tournament_create(
  text, text, text, integer, integer, numeric, numeric, integer,
  numeric, numeric, numeric, integer, integer, integer, integer,
  text, timestamp with time zone, timestamp with time zone,
  integer, integer, integer, integer, numeric
) CASCADE;

CREATE OR REPLACE FUNCTION public.admin_tournament_create(
  _name text, _game_slug text, _format text, _players_per_match integer, _max_players integer,
  _entry_fee_ar numeric, _admin_prize_pool_ar numeric, _winners_count integer,
  _p1 numeric, _p2 numeric, _p3 numeric,
  _pool_size integer DEFAULT 4, _qualifiers_per_pool integer DEFAULT 2,
  _max_concurrent integer DEFAULT 8, _lobby_minutes integer DEFAULT 5,
  _description text DEFAULT NULL::text,
  _registration_closes_at timestamptz DEFAULT NULL::timestamptz,
  _starts_at timestamptz DEFAULT NULL::timestamptz,
  _break_seconds integer DEFAULT 180,
  _batch_gap_seconds integer DEFAULT 0,
  _max_match_duration_secs integer DEFAULT 600,
  _check_in_minutes integer DEFAULT 15,
  _prize_4_pct numeric DEFAULT 0,
  _domino_scoring text DEFAULT 'elimination',
  _target_score integer DEFAULT 100
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin uniquement';
  END IF;

  IF _game_slug = 'domino' AND _players_per_match <> 2 THEN
    _players_per_match := 2;
  END IF;

  -- Cap max_concurrent at 8 for Ludo
  IF _game_slug = 'ludo' AND _max_concurrent > 8 THEN
    _max_concurrent := 8;
  END IF;

  -- Cap lobby_minutes at 10
  IF _lobby_minutes > 10 THEN
    _lobby_minutes := 10;
  END IF;

  -- Default domino_scoring
  IF _domino_scoring IS NULL OR (_domino_scoring NOT IN ('elimination', 'points')) THEN
    _domino_scoring := 'elimination';
  END IF;

  INSERT INTO public.tournaments(
    name, description, game_slug, format, players_per_match, max_players,
    entry_fee_ar, admin_prize_pool_ar, winners_count, prize_1_pct, prize_2_pct, prize_3_pct, prize_4_pct,
    pool_size, qualifiers_per_pool, max_concurrent_matches, lobby_minutes,
    registration_closes_at, starts_at, status, created_by, break_seconds, batch_gap_seconds,
    max_match_duration_secs, check_in_minutes, domino_scoring, target_score
  )
  VALUES (
    _name, _description, _game_slug, _format, _players_per_match, _max_players,
    _entry_fee_ar, _admin_prize_pool_ar, _winners_count, _p1, _p2, _p3, COALESCE(_prize_4_pct, 0),
    _pool_size, _qualifiers_per_pool, _max_concurrent, _lobby_minutes,
    _registration_closes_at, _starts_at, 'open', auth.uid(), _break_seconds, _batch_gap_seconds,
    _max_match_duration_secs, _check_in_minutes, _domino_scoring, _target_score
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_tournament_create(text,text,text,integer,integer,numeric,numeric,integer,numeric,numeric,numeric,integer,integer,integer,integer,text,timestamp with time zone,timestamp with time zone,integer,integer,integer,integer,numeric,text,integer) TO authenticated;

-- 6. tournament_state: include domino_scoring & target_score
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
      'check_in_at', e.check_in_at
    ) ORDER BY e.seed
  ), '[]'::jsonb)
  INTO ents
  FROM public.tournament_entrants e
  WHERE e.tournament_id = _tid;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', w.id, 'user_id', w.user_id, 'display_name', w.display_name,
      'position', w.position, 'is_bot', w.is_bot
    ) ORDER BY w.position
  ), '[]'::jsonb)
  INTO wl
  FROM public.tournament_waitlist w
  WHERE w.tournament_id = _tid;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'pool', pe.pool_id, 'entrant_id', pe.entrant_id,
      'wins', pe.wins, 'losses', pe.losses, 'draws', pe.draws,
      'points_for', pe.points_for, 'points_against', pe.points_against,
      'pts', pe.pts
    )
  ), '[]'::jsonb)
  INTO pls
  FROM public.tournament_pool_entrants pe
  WHERE pe.tournament_id = _tid;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', m.id, 'round', m.round, 'phase', m.phase,
      'entrant_ids', m.entrant_ids, 'status', m.status,
      'winner_id', m.winner_id, 'loser_id', m.loser_id,
      'game_id', m.game_id, 'pool_id', m.pool_id,
      'created_at', m.created_at, 'started_at', m.started_at,
      'finished_at', m.finished_at, 'is_draw', COALESCE(m.is_draw, false),
      'scheduled_at', m.scheduled_at
    )
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
      'auto_advance', t.auto_advance, 'is_simulation', t.is_simulation,
      'break_seconds', t.break_seconds, 'batch_gap_seconds', t.batch_gap_seconds,
      'max_match_duration_secs', t.max_match_duration_secs,
      'check_in_minutes', t.check_in_minutes,
      'check_in_opened_at', t.check_in_opened_at,
      'check_in_closed_at', t.check_in_closed_at,
      'started_at', t.started_at, 'finished_at', t.finished_at,
      'registration_closes_at', t.registration_closes_at, 'starts_at', t.starts_at,
      'domino_scoring', t.domino_scoring, 'target_score', t.target_score
    ),
    'entrants', ents,
    'waitlist', wl,
    'pools', pls,
    'matches', mts
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_state(uuid) TO authenticated;
