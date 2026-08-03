ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS break_seconds int NOT NULL DEFAULT 180,
  ADD COLUMN IF NOT EXISTS break_until timestamptz,
  ADD COLUMN IF NOT EXISTS total_rounds int NOT NULL DEFAULT 0;

-- La petite finale élimine aussi son vainqueur (le classement final est calculé dans _t_finish)
CREATE OR REPLACE FUNCTION public._t_match_finish(_match_id uuid, _winner uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
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
END $function$;

-- Construction de la phase suivante (petite finale avant la finale si 3 récompensés)
CREATE OR REPLACE FUNCTION public._t_next_round(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
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
      INSERT INTO public.tournament_matches(tournament_id, phase, round, match_no, entrant_ids)
        VALUES (_tid, 'third_place', t.current_round + 1, 1, losers);
      UPDATE public.tournaments SET stage = 'finals', current_round = t.current_round + 1 WHERE id = _tid;
      RETURN;
    END IF;
  END IF;

  PERFORM public._t_build_round(_tid, t.current_round + 1, ids);
END $function$;

-- Moteur : pause entre chaque phase, 8 matchs simultanés maximum
CREATE OR REPLACE FUNCTION public.tournament_engine(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  t public.tournaments%ROWTYPE;
  m record; g record; v_win uuid; v_slot int; v_busy uuid[]; v_live int; v_cap int;
  v_pool record; v_ready int; v_total int; v_active int; v_e record;
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

  -- lancement des matchs : maximum 8 simultanés
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
END $function$;

-- Démarrage : calcule le nombre total de phases
CREATE OR REPLACE FUNCTION public.admin_tournament_start(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
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
     SET status = 'running', started_at = now(), break_until = NULL, total_rounds = r
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

-- Admin : démarrer la phase suivante immédiatement
CREATE OR REPLACE FUNCTION public.admin_tournament_next_stage(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_auto boolean;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin uniquement'; END IF;
  SELECT auto_advance INTO v_auto FROM public.tournaments WHERE id = _tid;
  UPDATE public.tournaments SET auto_advance = true, break_until = NULL WHERE id = _tid;
  PERFORM public.tournament_engine(_tid);
  UPDATE public.tournaments SET auto_advance = v_auto WHERE id = _tid;
END $function$;

-- Admin : retarder la phase suivante
CREATE OR REPLACE FUNCTION public.admin_tournament_delay(_tid uuid, _minutes int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin uniquement'; END IF;
  UPDATE public.tournaments
     SET break_until = GREATEST(COALESCE(break_until, now()), now()) + make_interval(mins => GREATEST(_minutes,1))
   WHERE id = _tid;
END $function$;

-- Admin : durée des pauses entre phases
CREATE OR REPLACE FUNCTION public.admin_tournament_set_break(_tid uuid, _seconds int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin uniquement'; END IF;
  UPDATE public.tournaments SET break_seconds = GREATEST(LEAST(_seconds, 3600), 0) WHERE id = _tid;
END $function$;

GRANT EXECUTE ON FUNCTION public.admin_tournament_delay(uuid,int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_tournament_set_break(uuid,int) TO authenticated;