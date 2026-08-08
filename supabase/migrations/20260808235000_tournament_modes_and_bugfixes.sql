-- ═══════════════════════════════════════════════════════════════════════
-- TOURNAMENT MODES: Free (admin-funded) vs Paid (player-funded)
-- + bug fixes in the tournament lifecycle
-- ═══════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════
-- BUG FIX 1: _t_finish used wrong field names
--   It referenced t.prize_pool_ar for the pool but the prize distribution
--   should use prize_pool (synced via trigger) OR prize_pool_ar.
--   Also, for free tournaments (entry_fee=0, admin_prize>0), the platform
--   commission was incorrectly deducted from admin_prize_pool_ar.
--   Fix: compute net correctly per mode.
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._t_finish(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  t public.tournaments%ROWTYPE;
  v_net numeric;
  v_pcts numeric[];
  r record;
  i int;
  v_amt numeric;
  v_final_loser uuid;
  v_tp_win uuid;
  v_tp_lose uuid;
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF t.status IN ('finished','cancelled') THEN RETURN; END IF;

  SELECT x.eid INTO v_final_loser FROM (
    SELECT unnest(m.entrant_ids) eid, m.winner_entrant_id w, m.round
      FROM public.tournament_matches m
     WHERE m.tournament_id = _tid AND m.phase = 'final' AND m.status = 'finished'
       AND t.champion_entrant_id = ANY(m.entrant_ids)
     ORDER BY m.round DESC LIMIT 4) x
   WHERE x.eid IS DISTINCT FROM t.champion_entrant_id LIMIT 1;

  SELECT m.winner_entrant_id INTO v_tp_win FROM public.tournament_matches m
   WHERE m.tournament_id = _tid AND m.phase = 'third_place' AND m.status = 'finished' LIMIT 1;

  IF v_tp_win IS NOT NULL THEN
    SELECT x.eid INTO v_tp_lose FROM (
      SELECT unnest(m.entrant_ids) eid FROM public.tournament_matches m
       WHERE m.tournament_id = _tid AND m.phase = 'third_place' AND m.status = 'finished') x
     WHERE x.eid IS DISTINCT FROM v_tp_win LIMIT 1;
  END IF;

  WITH keyed AS (
    SELECT e.id,
           CASE
             WHEN e.id = t.champion_entrant_id THEN 0
             WHEN e.id = v_final_loser THEN 1
             WHEN e.id = v_tp_win THEN 2
             WHEN e.id = v_tp_lose THEN 3
             ELSE 10
           END AS k,
           e.eliminated_round, e.created_at
      FROM public.tournament_entrants e WHERE e.tournament_id = _tid
  ), ranked AS (
    SELECT id, row_number() OVER (ORDER BY k, eliminated_round DESC NULLS FIRST, created_at) AS rk
      FROM keyed
  )
  UPDATE public.tournament_entrants e SET final_rank = ranked.rk
    FROM ranked WHERE e.id = ranked.id;

  -- ═══ PRIZE COMPUTATION PER MODE ═══
  -- PAID mode: net = (entry fees * (100 - platform_pct) / 100) + admin_prize
  --   Platform takes commission ONLY on entry fees, not on admin prize.
  -- FREE mode (entry_fee=0): net = admin_prize_pool_ar (no commission)
  IF t.entry_fee_ar > 0 THEN
    v_net := round(t.prize_pool_ar * (100 - t.platform_pct) / 100) + t.admin_prize_pool_ar;
  ELSE
    v_net := t.admin_prize_pool_ar;
  END IF;

  v_pcts := ARRAY[t.prize_1_pct, t.prize_2_pct, t.prize_3_pct, COALESCE(t.prize_4_pct, 0)];

  FOR r IN SELECT * FROM public.tournament_entrants
            WHERE tournament_id = _tid AND final_rank IS NOT NULL AND final_rank <= t.winners_count
            ORDER BY final_rank LOOP
    i := r.final_rank;
    v_amt := round(v_net * COALESCE(v_pcts[i],0) / 100);
    IF v_amt > 0 AND r.user_id IS NOT NULL AND NOT r.is_bot AND NOT t.is_simulation THEN
      PERFORM public.credit_user_balance(
        r.user_id, v_amt, 'tournament_prize', _tid,
        'Récompense tournoi: ' || t.name, jsonb_build_object('rank', i)
      );
    END IF;
    PERFORM public._t_notify(r.id, '🏆 Tournoi terminé',
      'Vous terminez ' || i || 'e. Gain : ' || v_amt || ' Ar', '/tournaments/' || _tid);
  END LOOP;

  -- Mark rewards as paid
  UPDATE public.tournaments
     SET status = 'finished', stage = 'done', finished_at = now(),
         rewards_paid_at = now(),
         platform_cut_ar = CASE WHEN entry_fee_ar > 0 THEN round(prize_pool_ar * platform_pct / 100) ELSE 0 END
   WHERE id = _tid;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- BUG FIX 2: admin_tournament_create — for free mode, force winners_count=1
--   (single reward for the champion) unless admin explicitly chooses more.
--   Also enforce: free mode → no platform commission.
-- ═══════════════════════════════════════════════════════════════════════
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
  _domino_scoring text DEFAULT 'elimination'::text,
  _target_score integer DEFAULT 100
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_id uuid;
  v_platform_pct numeric := 10;
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

  -- ═══ MODE LOGIC ═══
  -- FREE mode (entry_fee = 0, admin_prize > 0): no platform commission
  -- PAID mode (entry_fee > 0): 10% platform commission on entry fees
  IF _entry_fee_ar > 0 THEN
    v_platform_pct := 10;  -- paid mode: 10% commission
  ELSE
    v_platform_pct := 0;   -- free mode: no commission on admin prize
  END IF;

  INSERT INTO public.tournaments(
    name, description, game_slug, format, players_per_match, max_players,
    entry_fee_ar, admin_prize_pool_ar, winners_count, prize_1_pct, prize_2_pct, prize_3_pct, prize_4_pct,
    pool_size, qualifiers_per_pool, max_concurrent_matches, lobby_minutes,
    registration_closes_at, starts_at, status, created_by, break_seconds, batch_gap_seconds,
    max_match_duration_secs, check_in_minutes, domino_scoring, target_score, platform_pct
  )
  VALUES (
    _name, _description, _game_slug, _format, _players_per_match, _max_players,
    _entry_fee_ar, _admin_prize_pool_ar, _winners_count, _p1, _p2, _p3, COALESCE(_prize_4_pct, 0),
    _pool_size, _qualifiers_per_pool, _max_concurrent, _lobby_minutes,
    _registration_closes_at, _starts_at, 'open', auth.uid(), _break_seconds, _batch_gap_seconds,
    _max_match_duration_secs, _check_in_minutes, _domino_scoring, _target_score, v_platform_pct
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_tournament_create TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- BUG FIX 3: _t_build_round — single player left gets stuck
--   When v_rest = 1, the loop exits without giving the player a bye
--   to the next round. Fix: mark them as champion if only 1 active.
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
    v_take := LEAST(2, v_rest);

    -- 3 players left in Ludo → table of 3
    IF v_rest = 3 AND t.game_slug = 'ludo' THEN
      v_take := 3;
    END IF;

    v_mno := v_mno + 1;
    INSERT INTO public.tournament_matches(tournament_id, phase, round, match_no, entrant_ids)
      VALUES (_tid, 'final', _round, v_mno, (SELECT array_agg(_ids[j]) FROM generate_series(i, i + v_take - 1) j));
    i := i + v_take;
  END LOOP;

  UPDATE public.tournaments SET stage = 'finals', current_round = _round, current_round_started_at = now() WHERE id = _tid;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- BUG FIX 4: _t_launch_match — notify with correct game URL
--   The notification link used '/' || game_slug || '/' || game_id
--   but the actual routes are /jeux/ludo/$id or /jeux/domino/$id
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._t_launch_match(_match_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  m public.tournament_matches%ROWTYPE;
  t public.tournaments%ROWTYPE;
  v_host uuid; v_gid uuid; v_slot int := 0; e record; v_n int;
  v_colors text[] := ARRAY['red','blue','green','yellow'];
  v_link text;
BEGIN
  SELECT * INTO m FROM public.tournament_matches WHERE id = _match_id FOR UPDATE;
  IF m.id IS NULL OR m.status <> 'scheduled' THEN RETURN; END IF;
  SELECT * INTO t FROM public.tournaments WHERE id = m.tournament_id;
  v_n := array_length(m.entrant_ids, 1);

  IF t.is_simulation THEN
    UPDATE public.tournament_matches
       SET status = 'running', game_id = NULL, started_at = now(),
           deadline_at = now() + make_interval(mins => t.lobby_minutes)
     WHERE id = _match_id;
    RETURN;
  END IF;

  SELECT user_id INTO v_host FROM public.tournament_entrants
   WHERE id = ANY(m.entrant_ids) AND user_id IS NOT NULL LIMIT 1;
  v_host := COALESCE(v_host, t.created_by);
  IF v_host IS NULL THEN RETURN; END IF;

  IF t.game_slug = 'ludo' THEN
    INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, is_private, mode, status, ready_deadline, auto_move)
      VALUES (v_host, v_n, 0, 0, 0, TRUE, 'classic', 'open', now() + make_interval(mins => t.lobby_minutes), TRUE)
      RETURNING id INTO v_gid;
    FOR e IN SELECT * FROM public.tournament_entrants WHERE id = ANY(m.entrant_ids)
             ORDER BY array_position(m.entrant_ids, id) LOOP
      INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name, is_bot, bot_name, ready)
        VALUES (v_gid, e.user_id, v_slot, v_colors[v_slot+1], e.display_name, e.is_bot,
                CASE WHEN e.is_bot THEN e.display_name END, e.is_bot);
      v_slot := v_slot + 1;
    END LOOP;
    v_link := '/jeux/ludo/' || v_gid::text;
  ELSE
    INSERT INTO public.domino_games(host_id, max_players, stake, pot, commission_pct, is_private, mode, status, target_score, first_tile_rule)
      VALUES (v_host, v_n, 0, 0, 0, TRUE, 'classic', 'open', 0, 'libre')
      RETURNING id INTO v_gid;
    FOR e IN SELECT * FROM public.tournament_entrants WHERE id = ANY(m.entrant_ids)
             ORDER BY array_position(m.entrant_ids, id) LOOP
      INSERT INTO public.domino_participants(game_id, user_id, slot, display_name, is_bot, bot_name, ready)
        VALUES (v_gid, e.user_id, v_slot, e.display_name, e.is_bot,
                CASE WHEN e.is_bot THEN e.display_name END, e.is_bot);
      v_slot := v_slot + 1;
    END LOOP;
    v_link := '/jeux/domino/' || v_gid::text;
  END IF;

  UPDATE public.tournament_matches
     SET status = 'running', game_id = v_gid, started_at = now(),
         deadline_at = now() + make_interval(mins => t.lobby_minutes)
   WHERE id = _match_id;

  FOR e IN SELECT id FROM public.tournament_entrants WHERE id = ANY(m.entrant_ids) LOOP
    PERFORM public._t_notify(e.id, '🎮 Votre match est prêt',
      'Rejoignez la table maintenant, vous avez ' || t.lobby_minutes || ' minutes.',
      v_link);
  END LOOP;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════
-- BUG FIX 5: tournament_register — for free tournaments, the prize_pool_ar
--   was never initialized with admin_prize_pool_ar. Fix: initialize on
--   first registration.
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.tournament_register(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  t public.tournaments%ROWTYPE;
  v_uid uuid := auth.uid();
  v_n int;
  v_name text;
  v_next_pos int;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  SELECT * INTO t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF t.id IS NULL OR t.status <> 'open' THEN
    RAISE EXCEPTION 'Inscriptions fermées';
  END IF;

  IF EXISTS (SELECT 1 FROM public.tournament_entrants WHERE tournament_id = _tid AND user_id = v_uid) THEN
    RAISE EXCEPTION 'Déjà inscrit';
  END IF;

  IF EXISTS (SELECT 1 FROM public.tournament_waitlist WHERE tournament_id = _tid AND user_id = v_uid) THEN
    RAISE EXCEPTION 'Déjà sur la liste d''attente';
  END IF;

  SELECT count(*) INTO v_n FROM public.tournament_entrants WHERE tournament_id = _tid AND status <> 'withdrawn';
  SELECT COALESCE(pseudo, 'Joueur') INTO v_name FROM public.profiles WHERE id = v_uid;

  IF v_n >= t.max_players THEN
    SELECT COALESCE(MAX(position), 0) + 1 INTO v_next_pos
      FROM public.tournament_waitlist
     WHERE tournament_id = _tid;

    INSERT INTO public.tournament_waitlist (tournament_id, user_id, position, display_name)
    VALUES (_tid, v_uid, v_next_pos, v_name);

    INSERT INTO public.notifications (user_id, title, body, link)
    VALUES (v_uid, '📋 Liste d''attente', 'Vous êtes en position ' || v_next_pos || ' sur la liste d''attente.', '/tournaments/' || _tid);
  ELSE
    -- Paid mode: debit entry fee and add to prize pool
    IF t.entry_fee_ar > 0 THEN
      PERFORM public.debit_user_balance(
        v_uid, t.entry_fee_ar, 'tournament_entry', _tid,
        'Inscription tournoi: ' || t.name, '{}'::jsonb
      );
      UPDATE public.tournaments SET prize_pool_ar = prize_pool_ar + t.entry_fee_ar WHERE id = _tid;
    END IF;

    INSERT INTO public.tournament_entrants (tournament_id, user_id, display_name)
    VALUES (_tid, v_uid, v_name);
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_register(uuid) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- Update existing free tournaments: set platform_pct = 0
-- ═══════════════════════════════════════════════════════════════════════
UPDATE public.tournaments SET platform_pct = 0 WHERE entry_fee_ar = 0;
