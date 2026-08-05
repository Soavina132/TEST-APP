-- ============================================================================
-- Migration : Lots (batches) de matchs simultanés + horodatage de round
-- Complète le moteur de tournoi existant (tournament_engine / _t_build_round /
-- _t_next_round / _t_finish) sans rien casser :
--   - batch_gap_seconds = 0 (valeur par défaut) => comportement identique à
--     avant (lancement "au fil de l'eau" dès qu'une place se libère).
--   - batch_gap_seconds > 0 => les matchs d'un round sont lancés par lots de
--     `max_concurrent_matches` (8 par défaut), avec une attente fixe entre
--     chaque lot, comme demandé : ex. 16 matchs, 8 lancés, on attend N min,
--     puis les 8 suivants.
-- Le match pour la 3e place et la finale existaient déjà (_t_next_round),
-- ainsi que le classement final (1er/2e/3e) dans _t_finish. On ajoute juste
-- l'horodatage nécessaire au calcul des lots.
-- ============================================================================

ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS batch_gap_seconds     integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS current_round_started_at timestamptz;

COMMENT ON COLUMN public.tournaments.batch_gap_seconds IS
  'Délai (secondes) entre chaque lot de matchs simultanés au sein d''un même round. 0 = lancement au fil de l''eau (comportement historique).';
COMMENT ON COLUMN public.tournaments.current_round_started_at IS
  'Horodatage du début du round courant, utilisé pour calculer quel lot de matchs simultanés est autorisé à démarrer.';

-- ── _t_build_round : mémorise le début du round ────────────────────────────
CREATE OR REPLACE FUNCTION public._t_build_round(_tid uuid, _round integer, _ids uuid[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  UPDATE public.tournaments SET stage = 'finals', current_round = _round, current_round_started_at = now() WHERE id = _tid;
END $function$;

-- ── _t_next_round : mémorise aussi le début du round pour le match de 3e place ──
-- (inchangé par rapport à l'original SAUF : horodatage current_round_started_at)
CREATE OR REPLACE FUNCTION public._t_next_round(_tid uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      -- Crée UNIQUEMENT le match de 3e place dans ce round.
      -- La finale sera créée au tour suivant (quand la 3e place sera terminée
      -- et que seuls les 2 gagnants des demies restent actifs).
      INSERT INTO public.tournament_matches(tournament_id, phase, round, match_no, entrant_ids)
        VALUES (_tid, 'third_place', t.current_round + 1, 1, losers);
      UPDATE public.tournaments SET stage = 'finals', current_round = t.current_round + 1, current_round_started_at = now() WHERE id = _tid;
      RETURN;
    END IF;
  END IF;

  PERFORM public._t_build_round(_tid, t.current_round + 1, ids);
END $function$;

-- ── admin_tournament_start : horodate aussi le round 1 ─────────────────────
CREATE OR REPLACE FUNCTION public.admin_tournament_start(_tid uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE t public.tournaments%ROWTYPE; ids uuid[]; n int; r int := 0;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin uniquement'; END IF;
  SELECT * INTO t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF t.status <> 'open' THEN RAISE EXCEPTION 'Tournoi déjà lancé'; END IF;
  SELECT count(*) INTO n FROM public.tournament_entrants WHERE tournament_id = _tid;
  IF n < 2 THEN RAISE EXCEPTION 'Pas assez de joueurs'; END IF;

  WHILE n > 1 LOOP
    n := CEIL(n::numeric / GREATEST(COALESCE(t.players_per_match,2), 2));
    r := r + 1;
  END LOOP;

  UPDATE public.tournaments
     SET status = 'running', started_at = now(), break_until = NULL, total_rounds = r,
         current_round_started_at = now()
   WHERE id = _tid;

  IF t.format = 'pools' THEN
    PERFORM public._t_draw_pools(_tid);
  ELSE
    SELECT array_agg(id ORDER BY random()) INTO ids FROM public.tournament_entrants
     WHERE tournament_id = _tid AND status = 'active';
    PERFORM public._t_build_round(_tid, 1, ids);
  END IF;
  PERFORM public.tournament_engine(_tid);
END $function$;

-- ── tournament_engine : lancement par lots avec attente entre chaque lot ──
CREATE OR REPLACE FUNCTION public.tournament_engine(_tid uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  t public.tournaments%ROWTYPE;
  m record; g record; v_win uuid; v_slot int; v_busy uuid[]; v_live int; v_cap int;
  v_pool record; v_ready int; v_total int; v_active int; v_e record;
  v_round_started timestamptz; v_batches_elapsed int; v_allowed int; v_started_this_round int;
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

  -- clôture des poules terminées
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

  -- phase terminée : pause puis phase suivante
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

  -- lancement des matchs : maximum `max_concurrent_matches` (8 max) simultanés,
  -- par lots espacés de `batch_gap_seconds` si celui-ci est défini (> 0).
  v_cap := LEAST(GREATEST(COALESCE(t.max_concurrent_matches, 8), 1), 8);
  SELECT count(*) INTO v_live FROM public.tournament_matches
   WHERE tournament_id = _tid AND status = 'running';
  SELECT COALESCE(array_agg(x), ARRAY[]::uuid[]) INTO v_busy FROM (
    SELECT unnest(entrant_ids) x FROM public.tournament_matches
     WHERE tournament_id = _tid AND status = 'running') s;

  v_round_started := COALESCE(t.current_round_started_at, now());
  IF COALESCE(t.batch_gap_seconds, 0) > 0 THEN
    v_batches_elapsed := GREATEST(floor(extract(epoch FROM (now() - v_round_started)) / t.batch_gap_seconds)::int, 0);
    v_allowed := (v_batches_elapsed + 1) * v_cap;
  ELSE
    v_allowed := 1000000; -- pas de limite par lot : comportement historique (au fil de l'eau)
  END IF;
  SELECT count(*) INTO v_started_this_round FROM public.tournament_matches
   WHERE tournament_id = _tid AND round = t.current_round AND phase <> 'pool' AND status <> 'scheduled';

  FOR m IN SELECT * FROM public.tournament_matches
            WHERE tournament_id = _tid AND status = 'scheduled'
            ORDER BY round, match_no LOOP
    EXIT WHEN v_live >= v_cap;
    CONTINUE WHEN m.entrant_ids && v_busy;
    IF m.round = t.current_round AND m.phase <> 'pool' AND v_started_this_round >= v_allowed THEN
      CONTINUE; -- ce lot n'est pas encore autorisé à démarrer (attente batch_gap_seconds)
    END IF;
    PERFORM public._t_launch_match(m.id);
    v_busy := v_busy || m.entrant_ids;
    v_live := v_live + 1;
    IF m.round = t.current_round AND m.phase <> 'pool' THEN
      v_started_this_round := v_started_this_round + 1;
    END IF;
  END LOOP;
END $function$;

-- ── admin_tournament_create : ajoute break_seconds / batch_gap_seconds ────
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
  _batch_gap_seconds integer DEFAULT 0
)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_id uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin uniquement'; END IF;
  IF _game_slug = 'domino' AND _players_per_match <> 2 THEN _players_per_match := 2; END IF;
  INSERT INTO public.tournaments(name, description, game_slug, format, players_per_match, max_players,
    entry_fee_ar, admin_prize_pool_ar, winners_count, prize_1_pct, prize_2_pct, prize_3_pct,
    pool_size, qualifiers_per_pool, max_concurrent_matches, lobby_minutes,
    registration_closes_at, starts_at, status, created_by, break_seconds, batch_gap_seconds)
  VALUES (_name, _description, _game_slug, _format, _players_per_match, _max_players,
    _entry_fee_ar, _admin_prize_pool_ar, _winners_count, _p1, _p2, _p3,
    _pool_size, _qualifiers_per_pool, _max_concurrent, _lobby_minutes,
    _registration_closes_at, _starts_at, 'open', auth.uid(),
    GREATEST(COALESCE(_break_seconds, 180), 0), GREATEST(COALESCE(_batch_gap_seconds, 0), 0))
  RETURNING id INTO v_id;
  RETURN v_id;
END $function$;
