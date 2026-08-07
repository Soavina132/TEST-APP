-- ============================================================================
-- Migration: Tournament World Cup System Improvements
-- File: /app/conversations/6a756c3011d2460647247682/TEST-APP/supabase/migrations/20260807100000_tournament_world_cup.sql
-- Description:
--   1. New columns (max_match_duration_secs, check_in_minutes, prize_4_pct, check_in_opened_at, checked_in, check_in_at, waitlist_position, is_draw, tournament_wins, tournament_played, elo_rating)
--   2. New table: tournament_waitlist with RLS policies & realtime publication
--   3. Updated tournament_register with waitlist support
--   4. Updated tournament_unregister with waitlist removal & auto-promotion
--   5. Check-in system (admin_tournament_open_check_in, tournament_check_in, admin_tournament_close_check_in)
--   6. Draw support for Domino & updated _t_pool_recompute
--   7. Updated _t_finish for 4 places (prize_4_pct)
--   8. Pre-tournament notifications (admin_tournament_notify_upcoming)
--   9. ELO update function (tournament_update_elo)
--  10. Champion badge handling in _t_finish & ELO update
--  11. Playoff match creation (admin_tournament_playoff)
--  12. Match duration timer check in tournament_engine
--  13. Statistics view (tournament_player_stats)
--  14. Updated admin_tournament_create with new parameters
--  15. Updated tournament_state with waitlist array
--  16. Updated tournament_engine_all cron function
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. NEW COLUMNS
-- ----------------------------------------------------------------------------
ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS max_match_duration_secs int DEFAULT 600,
  ADD COLUMN IF NOT EXISTS check_in_minutes int DEFAULT 15,
  ADD COLUMN IF NOT EXISTS prize_4_pct numeric DEFAULT 0,
  ADD COLUMN IF NOT EXISTS check_in_opened_at timestamptz;

ALTER TABLE public.tournament_entrants
  ADD COLUMN IF NOT EXISTS checked_in boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS check_in_at timestamptz,
  ADD COLUMN IF NOT EXISTS waitlist_position int;

ALTER TABLE public.tournament_matches
  ADD COLUMN IF NOT EXISTS is_draw boolean DEFAULT false;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS tournament_wins int DEFAULT 0,
  ADD COLUMN IF NOT EXISTS tournament_played int DEFAULT 0,
  ADD COLUMN IF NOT EXISTS elo_rating int DEFAULT 1000;


-- ----------------------------------------------------------------------------
-- 2. NEW TABLE: TOURNAMENT_WAITLIST
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.tournament_waitlist (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid NOT NULL REFERENCES public.tournaments(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  position int NOT NULL,
  display_name text,
  created_at timestamptz DEFAULT now(),
  CONSTRAINT tournament_waitlist_unique_user UNIQUE (tournament_id, user_id)
);

ALTER TABLE public.tournament_waitlist ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tw_read ON public.tournament_waitlist;
CREATE POLICY tw_read ON public.tournament_waitlist FOR SELECT USING (true);

DROP POLICY IF EXISTS tw_insert ON public.tournament_waitlist;
CREATE POLICY tw_insert ON public.tournament_waitlist FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS tw_delete ON public.tournament_waitlist;
CREATE POLICY tw_delete ON public.tournament_waitlist FOR DELETE TO authenticated
  USING (auth.uid() = user_id OR public.is_admin());

GRANT SELECT ON public.tournament_waitlist TO authenticated, anon;
GRANT INSERT, DELETE ON public.tournament_waitlist TO authenticated;
GRANT ALL ON public.tournament_waitlist TO service_role;

ALTER TABLE public.tournament_waitlist REPLICA IDENTITY FULL;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.tournament_waitlist;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;


-- ----------------------------------------------------------------------------
-- 3. UPDATED tournament_register (WAITLIST SUPPORT)
-- ----------------------------------------------------------------------------
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


-- ----------------------------------------------------------------------------
-- 4. UPDATED tournament_unregister
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tournament_unregister(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  t public.tournaments%ROWTYPE;
  v_uid uuid := auth.uid();
  v_was_entrant boolean := false;
  v_was_waitlisted boolean := false;
  v_pos int;
  v_waiter record;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  SELECT * INTO t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF t.status <> 'open' THEN
    RAISE EXCEPTION 'Tournoi déjà lancé';
  END IF;

  -- Retrait de la liste d'attente
  SELECT position INTO v_pos FROM public.tournament_waitlist WHERE tournament_id = _tid AND user_id = v_uid;
  IF FOUND THEN
    DELETE FROM public.tournament_waitlist WHERE tournament_id = _tid AND user_id = v_uid;
    UPDATE public.tournament_waitlist
       SET position = position - 1
     WHERE tournament_id = _tid AND position > v_pos;
    v_was_waitlisted := true;
  END IF;

  -- Retrait des entrants
  IF EXISTS (SELECT 1 FROM public.tournament_entrants WHERE tournament_id = _tid AND user_id = v_uid) THEN
    DELETE FROM public.tournament_entrants WHERE tournament_id = _tid AND user_id = v_uid;
    v_was_entrant := true;

    IF t.entry_fee_ar > 0 THEN
      PERFORM public.credit_user_balance(
        v_uid, t.entry_fee_ar, 'tournament_refund', _tid,
        'Désinscription tournoi: ' || t.name, '{}'::jsonb
      );
      UPDATE public.tournaments SET prize_pool_ar = GREATEST(0, prize_pool_ar - t.entry_fee_ar) WHERE id = _tid;
    END IF;
  END IF;

  -- Promotion de la liste d'attente si un entrant s'est désinscrit
  IF v_was_entrant AND t.status = 'open' THEN
    SELECT * INTO v_waiter
      FROM public.tournament_waitlist
     WHERE tournament_id = _tid
     ORDER BY position ASC
     LIMIT 1
     FOR UPDATE;

    IF v_waiter.id IS NOT NULL THEN
      IF t.entry_fee_ar > 0 THEN
        BEGIN
          PERFORM public.debit_user_balance(
            v_waiter.user_id, t.entry_fee_ar, 'tournament_entry', _tid,
            'Inscription tournoi: ' || t.name, '{}'::jsonb
          );
          UPDATE public.tournaments SET prize_pool_ar = prize_pool_ar + t.entry_fee_ar WHERE id = _tid;
        EXCEPTION WHEN OTHERS THEN
          v_waiter := NULL;
        END;
      END IF;

      IF v_waiter.id IS NOT NULL THEN
        INSERT INTO public.tournament_entrants (tournament_id, user_id, display_name)
        VALUES (_tid, v_waiter.user_id, v_waiter.display_name);

        DELETE FROM public.tournament_waitlist WHERE id = v_waiter.id;

        UPDATE public.tournament_waitlist
           SET position = position - 1
         WHERE tournament_id = _tid AND position > v_waiter.position;

        INSERT INTO public.notifications (user_id, title, body, link)
        VALUES (v_waiter.user_id, '🎉 Promotion en entrant !',
          'Vous avez été promu au tournoi ' || t.name, '/tournaments/' || _tid);
      END IF;
    END IF;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_unregister(uuid) TO authenticated;


-- ----------------------------------------------------------------------------
-- 5. CHECK-IN SYSTEM
-- ----------------------------------------------------------------------------

-- 5.1 admin_tournament_open_check_in
CREATE OR REPLACE FUNCTION public.admin_tournament_open_check_in(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  t public.tournaments%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin uniquement';
  END IF;

  SELECT * INTO t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF t.id IS NULL THEN
    RAISE EXCEPTION 'Tournoi introuvable';
  END IF;

  UPDATE public.tournaments
     SET check_in_opened_at = now()
   WHERE id = _tid;

  INSERT INTO public.notifications (user_id, title, body, link)
  SELECT user_id, '⏰ Check-in ouvert !', 'Confirmez votre présence pour le tournoi ' || t.name, '/tournaments/' || _tid
    FROM public.tournament_entrants
   WHERE tournament_id = _tid AND user_id IS NOT NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_tournament_open_check_in(uuid) TO authenticated;


-- 5.2 tournament_check_in
CREATE OR REPLACE FUNCTION public.tournament_check_in(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  t public.tournaments%ROWTYPE;
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  SELECT * INTO t FROM public.tournaments WHERE id = _tid;
  IF t.id IS NULL THEN
    RAISE EXCEPTION 'Tournoi introuvable';
  END IF;

  IF t.check_in_opened_at IS NULL THEN
    RAISE EXCEPTION 'Le check-in n''est pas ouvert';
  END IF;

  UPDATE public.tournament_entrants
     SET checked_in = true,
         check_in_at = now()
   WHERE tournament_id = _tid AND user_id = v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Vous n''êtes pas inscrit à ce tournoi';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_check_in(uuid) TO authenticated;


-- 5.3 admin_tournament_close_check_in
CREATE OR REPLACE FUNCTION public.admin_tournament_close_check_in(_tid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  t public.tournaments%ROWTYPE;
  v_withdrawn_count int := 0;
  v_promoted_count int := 0;
  v_current_active int := 0;
  v_needed int := 0;
  w record;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin uniquement';
  END IF;

  SELECT * INTO t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF t.id IS NULL THEN
    RAISE EXCEPTION 'Tournoi introuvable';
  END IF;

  WITH updated AS (
    UPDATE public.tournament_entrants
       SET status = 'withdrawn'
     WHERE tournament_id = _tid
       AND (checked_in IS FALSE OR checked_in IS NULL)
       AND status <> 'withdrawn'
    RETURNING id
  )
  SELECT count(*) INTO v_withdrawn_count FROM updated;

  SELECT count(*) INTO v_current_active
    FROM public.tournament_entrants
   WHERE tournament_id = _tid AND status <> 'withdrawn';

  v_needed := t.max_players - v_current_active;

  IF v_needed > 0 THEN
    FOR w IN SELECT * FROM public.tournament_waitlist
              WHERE tournament_id = _tid
              ORDER BY position ASC
              LIMIT v_needed LOOP
      BEGIN
        IF t.entry_fee_ar > 0 THEN
          PERFORM public.debit_user_balance(
            w.user_id, t.entry_fee_ar, 'tournament_entry', _tid,
            'Inscription tournoi: ' || t.name, '{}'::jsonb
          );
          UPDATE public.tournaments SET prize_pool_ar = prize_pool_ar + t.entry_fee_ar WHERE id = _tid;
        END IF;

        INSERT INTO public.tournament_entrants (tournament_id, user_id, display_name, checked_in, check_in_at)
        VALUES (_tid, w.user_id, w.display_name, true, now());

        DELETE FROM public.tournament_waitlist WHERE id = w.id;

        v_promoted_count := v_promoted_count + 1;

        INSERT INTO public.notifications (user_id, title, body, link)
        VALUES (w.user_id, '🎉 Promotion en entrant !',
          'Vous avez été promu au tournoi ' || t.name, '/tournaments/' || _tid);
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;
    END LOOP;

    WITH reordered AS (
      SELECT id, row_number() OVER (ORDER BY position) AS new_pos
        FROM public.tournament_waitlist
       WHERE tournament_id = _tid
    )
    UPDATE public.tournament_waitlist w
       SET position = reordered.new_pos
      FROM reordered WHERE w.id = reordered.id;
  END IF;

  RETURN jsonb_build_object(
    'withdrawn', v_withdrawn_count,
    'promoted', v_promoted_count
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_tournament_close_check_in(uuid) TO authenticated;


-- ----------------------------------------------------------------------------
-- 6. DRAW SUPPORT FOR DOMINO & POOL RECOMPUTE
-- ----------------------------------------------------------------------------

-- 6.1 _t_match_finish
CREATE OR REPLACE FUNCTION public._t_match_finish(_match_id uuid, _winner uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  m public.tournament_matches%ROWTYPE;
  e uuid;
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

GRANT EXECUTE ON FUNCTION public._t_match_finish(uuid, uuid) TO authenticated, service_role;


-- 6.2 _t_pool_recompute
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
             count(*) AS played,
             count(*) FILTER (WHERE x.won) AS wins,
             SUM(CASE WHEN x.won THEN 3 WHEN x.drew THEN 1 ELSE 0 END) AS points
        FROM (
          SELECT e_id AS entrant_id,
                 (m.winner_entrant_id IS NOT NULL AND e_id = m.winner_entrant_id) AS won,
                 (m.winner_entrant_id IS NULL OR m.is_draw IS TRUE) AS drew
            FROM public.tournament_matches m,
                 LATERAL unnest(m.entrant_ids) AS e_id
           WHERE m.pool_id = _pool_id AND m.status = 'finished'
        ) x
       GROUP BY x.entrant_id
    ) s
   WHERE pe.pool_id = _pool_id AND pe.entrant_id = s.entrant_id;

  UPDATE public.tournament_pool_entrants pe
     SET played = 0, wins = 0, points = 0
   WHERE pe.pool_id = _pool_id
     AND NOT EXISTS (
       SELECT 1 FROM public.tournament_matches m
        WHERE m.pool_id = _pool_id AND m.status = 'finished'
          AND pe.entrant_id = ANY(m.entrant_ids));
END;
$$;

GRANT EXECUTE ON FUNCTION public._t_pool_recompute(uuid) TO authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 9. ELO UPDATE FUNCTION
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tournament_update_elo(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  t public.tournaments%ROWTYPE;
  r record;
  v_delta int;
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid;
  IF t.id IS NULL THEN RETURN; END IF;

  FOR r IN SELECT e.*, p.is_bot
            FROM public.tournament_entrants e
            JOIN public.profiles p ON p.id = e.user_id
           WHERE e.tournament_id = _tid AND e.user_id IS NOT NULL AND p.is_bot IS NOT TRUE LOOP

    v_delta := 0;

    IF r.final_rank = 1 THEN
      v_delta := 25;
      UPDATE public.profiles SET tournament_wins = tournament_wins + 1 WHERE id = r.user_id;
    ELSIF r.final_rank = 2 THEN
      v_delta := 15;
    ELSIF r.final_rank = 3 THEN
      v_delta := 10;
    ELSIF r.final_rank = 4 THEN
      v_delta := 5;
    ELSIF EXISTS (
      SELECT 1 FROM public.tournament_pool_entrants pe
       WHERE pe.entrant_id = r.id AND pe.qualified IS FALSE
    ) THEN
      v_delta := -5;
    ELSIF r.eliminated_round = 1 THEN
      v_delta := 5;
    ELSE
      v_delta := 0;
    END IF;

    UPDATE public.profiles
       SET tournament_played = tournament_played + 1,
           elo_rating = LEAST(3000, GREATEST(500, COALESCE(elo_rating, 1000) + v_delta))
     WHERE id = r.user_id;
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_update_elo(uuid) TO authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 7 & 10. UPDATED _t_finish FOR 4 PLACES & CHAMPION BADGE
-- ----------------------------------------------------------------------------
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

  v_net := round(t.prize_pool_ar * (100 - t.platform_pct) / 100) + t.admin_prize_pool_ar;
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

  PERFORM public.tournament_update_elo(_tid);

  UPDATE public.tournaments SET status = 'finished', stage = 'done', finished_at = now() WHERE id = _tid;
END;
$$;

GRANT EXECUTE ON FUNCTION public._t_finish(uuid) TO authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 8. PRE-TOURNAMENT NOTIFICATIONS
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_tournament_notify_upcoming(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  t public.tournaments%ROWTYPE;
  v_diff interval;
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid;
  IF t.id IS NULL OR t.status <> 'open' OR t.starts_at IS NULL THEN RETURN; END IF;

  v_diff := t.starts_at - now();

  IF v_diff > interval '0 seconds' AND v_diff <= interval '15 minutes' THEN
    IF v_diff <= interval '5 minutes' THEN
      INSERT INTO public.notifications (user_id, title, body, link)
      SELECT user_id, '🚨 URGENT : Tournoi imminent !',
             'Le tournoi ' || t.name || ' commence dans moins de 5 minutes !', '/tournaments/' || _tid
        FROM public.tournament_entrants
       WHERE tournament_id = _tid AND user_id IS NOT NULL;
    ELSE
      INSERT INTO public.notifications (user_id, title, body, link)
      SELECT user_id, '🔔 Tournoi bientôt',
             'Le tournoi ' || t.name || ' commence dans moins de 15 minutes.', '/tournaments/' || _tid
        FROM public.tournament_entrants
       WHERE tournament_id = _tid AND user_id IS NOT NULL;
    END IF;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_tournament_notify_upcoming(uuid) TO authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 11. PLAYOFF MATCH
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_tournament_playoff(_pool_id uuid, _entrant_a uuid, _entrant_b uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_tid uuid;
  v_match_no int;
  v_match_id uuid;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin uniquement';
  END IF;

  SELECT tournament_id INTO v_tid FROM public.tournament_pools WHERE id = _pool_id;
  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'Poule introuvable';
  END IF;

  SELECT COALESCE(MAX(match_no), 0) + 1 INTO v_match_no
    FROM public.tournament_matches
   WHERE pool_id = _pool_id;

  INSERT INTO public.tournament_matches (
    tournament_id, pool_id, phase, round, match_no, entrant_ids, status
  ) VALUES (
    v_tid, _pool_id, 'pool', 99, v_match_no, ARRAY[_entrant_a, _entrant_b], 'scheduled'
  ) RETURNING id INTO v_match_id;

  RETURN v_match_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_tournament_playoff(uuid, uuid, uuid) TO authenticated;


-- ----------------------------------------------------------------------------
-- 12. UPDATED TOURNAMENT ENGINE
-- ----------------------------------------------------------------------------
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

    -- Dépassement durée maximale de match
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

GRANT EXECUTE ON FUNCTION public.tournament_engine(uuid) TO authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 13. STATISTICS VIEW
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.tournament_player_stats AS
SELECT
  p.id AS user_id,
  p.pseudo,
  COALESCE(p.tournament_played, 0) AS tournaments_played,
  COALESCE(p.tournament_wins, 0) AS wins,
  GREATEST(0, COALESCE(p.tournament_played, 0) - COALESCE(p.tournament_wins, 0)) AS losses,
  CASE
    WHEN COALESCE(p.tournament_played, 0) > 0
    THEN ROUND((COALESCE(p.tournament_wins, 0)::numeric / p.tournament_played::numeric) * 100, 2)
    ELSE 0
  END AS win_rate,
  (
    SELECT MIN(e.final_rank)
      FROM public.tournament_entrants e
      JOIN public.tournaments t ON t.id = e.tournament_id
     WHERE e.user_id = p.id AND e.final_rank IS NOT NULL AND t.status = 'finished'
  ) AS best_rank,
  COALESCE(
    (
      SELECT SUM(tx.amount)
        FROM public.transactions tx
       WHERE tx.user_id = p.id AND tx.type = 'tournament_prize'
    ), 0
  ) AS total_earnings,
  COALESCE(p.elo_rating, 1000) AS elo_rating
FROM public.profiles p
WHERE p.is_bot IS NOT TRUE;

GRANT SELECT ON public.tournament_player_stats TO authenticated, anon, service_role;


-- ----------------------------------------------------------------------------
-- 14. UPDATED admin_tournament_create
-- ----------------------------------------------------------------------------
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
  _prize_4_pct numeric DEFAULT 0
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

  INSERT INTO public.tournaments(
    name, description, game_slug, format, players_per_match, max_players,
    entry_fee_ar, admin_prize_pool_ar, winners_count, prize_1_pct, prize_2_pct, prize_3_pct, prize_4_pct,
    pool_size, qualifiers_per_pool, max_concurrent_matches, lobby_minutes,
    registration_closes_at, starts_at, status, created_by, break_seconds, batch_gap_seconds,
    max_match_duration_secs, check_in_minutes
  )
  VALUES (
    _name, _description, _game_slug, _format, _players_per_match, _max_players,
    _entry_fee_ar, _admin_prize_pool_ar, _winners_count, _p1, _p2, _p3, COALESCE(_prize_4_pct, 0),
    _pool_size, _qualifiers_per_pool, _max_concurrent, _lobby_minutes,
    _registration_closes_at, _starts_at, 'open', auth.uid(), _break_seconds, _batch_gap_seconds,
    _max_match_duration_secs, _check_in_minutes
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_tournament_create TO authenticated;


-- ----------------------------------------------------------------------------
-- 15. UPDATED tournament_state
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tournament_state(_tid uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT jsonb_build_object(
    'tournament', to_jsonb(t),
    'entrants', COALESCE((SELECT jsonb_agg(to_jsonb(e) ORDER BY e.created_at)
                          FROM public.tournament_entrants e WHERE e.tournament_id = t.id), '[]'::jsonb),
    'pools', COALESCE((SELECT jsonb_agg(to_jsonb(p))
                       FROM public.tournament_pools p WHERE p.tournament_id = t.id), '[]'::jsonb),
    'pool_entrants', COALESCE((SELECT jsonb_agg(to_jsonb(pe))
                               FROM public.tournament_pool_entrants pe
                               JOIN public.tournament_pools p ON p.id = pe.pool_id
                               WHERE p.tournament_id = t.id), '[]'::jsonb),
    'matches', COALESCE((SELECT jsonb_agg(to_jsonb(m) ORDER BY m.round, m.match_no)
                         FROM public.tournament_matches m WHERE m.tournament_id = t.id), '[]'::jsonb),
    'waitlist', COALESCE((SELECT jsonb_agg(to_jsonb(w) ORDER BY w.position)
                          FROM public.tournament_waitlist w WHERE w.tournament_id = t.id), '[]'::jsonb)
  )
  FROM public.tournaments t WHERE t.id = _tid;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_state(uuid) TO authenticated, anon;


-- ----------------------------------------------------------------------------
-- 16. UPDATED CRON / TOURNAMENT_ENGINE_ALL
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tournament_engine_all()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT id FROM public.tournaments WHERE status = 'running' LOOP
    BEGIN
      PERFORM public.tournament_engine(r.id);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;

  FOR r IN SELECT id FROM public.tournaments WHERE status = 'open' AND starts_at IS NOT NULL LOOP
    BEGIN
      PERFORM public.admin_tournament_notify_upcoming(r.id);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_engine_all() TO authenticated, service_role;
