ALTER TABLE public.tournaments ADD COLUMN IF NOT EXISTS is_simulation boolean NOT NULL DEFAULT false;

-- _t_launch_match : en simulation, on ne crée aucune vraie partie
CREATE OR REPLACE FUNCTION public._t_launch_match(_match_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  m public.tournament_matches%ROWTYPE;
  t public.tournaments%ROWTYPE;
  v_host uuid; v_gid uuid; v_slot int := 0; e record; v_n int;
  v_colors text[] := ARRAY['red','blue','green','yellow'];
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
  END IF;

  UPDATE public.tournament_matches
     SET status = 'running', game_id = v_gid, started_at = now(),
         deadline_at = now() + make_interval(mins => t.lobby_minutes)
   WHERE id = _match_id;

  FOR e IN SELECT id FROM public.tournament_entrants WHERE id = ANY(m.entrant_ids) LOOP
    PERFORM public._t_notify(e.id, '🎮 Votre match est prêt',
      'Rejoignez la table maintenant, vous avez ' || t.lobby_minutes || ' minutes.',
      '/' || t.game_slug || '/' || v_gid);
  END LOOP;
END $function$;

-- Résout tous les matchs virtuels en cours avec un vainqueur aléatoire
CREATE OR REPLACE FUNCTION public._t_sim_resolve(_tid uuid)
 RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE m record; v_win uuid; v_n int := 0;
BEGIN
  FOR m IN SELECT * FROM public.tournament_matches
            WHERE tournament_id = _tid AND status = 'running' AND game_id IS NULL LOOP
    v_win := m.entrant_ids[1 + floor(random() * COALESCE(array_length(m.entrant_ids,1),1))::int];
    -- 12% de matchs nuls en phase de poule (test du départage)
    IF m.phase = 'pool' AND random() < 0.12 THEN v_win := NULL; END IF;
    PERFORM public._t_match_finish(m.id, v_win);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $function$;

-- Rapport de vérification de cohérence
CREATE OR REPLACE FUNCTION public.tournament_sim_report(_tid uuid)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE t public.tournaments%ROWTYPE; v_issues text[] := ARRAY[]::text[]; r record; v int;
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid;
  IF t.id IS NULL THEN RETURN jsonb_build_object('error','tournoi introuvable'); END IF;

  -- 1. points de poule = 3*victoires + nuls, played cohérent
  FOR r IN
    SELECT pe.pool_id, pe.entrant_id, pe.points, pe.wins, pe.played,
           (SELECT count(*) FROM public.tournament_matches mm
             WHERE mm.pool_id = pe.pool_id AND mm.status='finished' AND pe.entrant_id = ANY(mm.entrant_ids)) AS real_played,
           (SELECT count(*) FROM public.tournament_matches mm
             WHERE mm.pool_id = pe.pool_id AND mm.status='finished' AND mm.winner_entrant_id = pe.entrant_id) AS real_wins,
           (SELECT count(*) FROM public.tournament_matches mm
             WHERE mm.pool_id = pe.pool_id AND mm.status='finished' AND mm.winner_entrant_id IS NULL
               AND pe.entrant_id = ANY(mm.entrant_ids)) AS real_draws
      FROM public.tournament_pool_entrants pe
      JOIN public.tournament_pools p ON p.id = pe.pool_id
     WHERE p.tournament_id = _tid
  LOOP
    IF r.played <> r.real_played THEN
      v_issues := v_issues || format('poule: matchs joués incohérents (%s)', r.entrant_id);
    END IF;
    IF r.wins <> r.real_wins THEN
      v_issues := v_issues || format('poule: victoires incohérentes (%s)', r.entrant_id);
    END IF;
    IF r.points <> (3 * r.real_wins + r.real_draws) THEN
      v_issues := v_issues || format('poule: points incohérents (%s)', r.entrant_id);
    END IF;
  END LOOP;

  -- 2. qualifiés par poule = qualifiers_per_pool
  FOR r IN SELECT p.id, p.label, p.status,
                  (SELECT count(*) FROM public.tournament_pool_entrants pe WHERE pe.pool_id = p.id AND pe.qualified) q
             FROM public.tournament_pools p WHERE p.tournament_id = _tid AND p.status = 'finished' LOOP
    IF r.q <> t.qualifiers_per_pool THEN
      v_issues := v_issues || format('%s: %s qualifiés au lieu de %s', r.label, r.q, t.qualifiers_per_pool);
    END IF;
  END LOOP;

  -- 3. bracket : aucun match sans vainqueur ni en attente une fois terminé
  IF t.status = 'finished' THEN
    SELECT count(*) INTO v FROM public.tournament_matches
     WHERE tournament_id = _tid AND status IN ('scheduled','running');
    IF v > 0 THEN v_issues := v_issues || format('%s match(s) non terminés', v); END IF;

    SELECT count(*) INTO v FROM public.tournament_matches
     WHERE tournament_id = _tid AND phase <> 'pool' AND status = 'finished' AND winner_entrant_id IS NULL;
    IF v > 0 THEN v_issues := v_issues || format('%s match(s) éliminatoires sans vainqueur', v); END IF;

    IF t.champion_entrant_id IS NULL THEN v_issues := v_issues || 'aucun champion désigné'; END IF;

    SELECT count(*) INTO v FROM public.tournament_entrants
     WHERE tournament_id = _tid AND final_rank IS NULL;
    IF v > 0 THEN v_issues := v_issues || format('%s joueur(s) sans classement final', v); END IF;

    SELECT count(*) INTO v FROM (
      SELECT final_rank FROM public.tournament_entrants
       WHERE tournament_id = _tid AND final_rank IS NOT NULL
       GROUP BY final_rank HAVING count(*) > 1) s;
    IF v > 0 THEN v_issues := v_issues || format('%s rang(s) final(aux) en doublon', v); END IF;

    SELECT count(*) INTO v FROM public.tournament_entrants
     WHERE tournament_id = _tid AND status = 'active' AND id IS DISTINCT FROM t.champion_entrant_id;
    IF v > 0 THEN v_issues := v_issues || format('%s joueur(s) encore actifs', v); END IF;
  END IF;

  -- 4. un joueur ne doit jamais être dans 2 matchs simultanés
  SELECT count(*) INTO v FROM (
    SELECT unnest(entrant_ids) eid FROM public.tournament_matches
     WHERE tournament_id = _tid AND status = 'running'
     GROUP BY 1 HAVING count(*) > 1) s;
  IF v > 0 THEN v_issues := v_issues || format('%s joueur(s) dans plusieurs matchs à la fois', v); END IF;

  RETURN jsonb_build_object(
    'tournament_id', _tid,
    'name', t.name,
    'game', t.game_slug,
    'format', t.format,
    'status', t.status,
    'stage', t.stage,
    'rounds', t.current_round,
    'entrants', (SELECT count(*) FROM public.tournament_entrants WHERE tournament_id = _tid),
    'matches', (SELECT count(*) FROM public.tournament_matches WHERE tournament_id = _tid),
    'pools', (SELECT count(*) FROM public.tournament_pools WHERE tournament_id = _tid),
    'champion', (SELECT display_name FROM public.tournament_entrants WHERE id = t.champion_entrant_id),
    'podium', COALESCE((SELECT jsonb_agg(jsonb_build_object('rank', final_rank, 'name', display_name) ORDER BY final_rank)
                          FROM public.tournament_entrants
                         WHERE tournament_id = _tid AND final_rank IS NOT NULL AND final_rank <= 3), '[]'::jsonb),
    'standings', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                              'pool', p.label,
                              'rows', (SELECT jsonb_agg(jsonb_build_object(
                                          'name', e.display_name, 'pts', pe.points, 'v', pe.wins,
                                          'j', pe.played, 'qualifie', pe.qualified) ORDER BY pe.points DESC, pe.wins DESC)
                                         FROM public.tournament_pool_entrants pe
                                         JOIN public.tournament_entrants e ON e.id = pe.entrant_id
                                        WHERE pe.pool_id = p.id)) ORDER BY p.label)
                            FROM public.tournament_pools p WHERE p.tournament_id = _tid), '[]'::jsonb),
    'ok', array_length(v_issues,1) IS NULL,
    'issues', to_jsonb(v_issues)
  );
END $function$;

-- Fait tourner un tournoi en mode simulation jusqu'à son terme
CREATE OR REPLACE FUNCTION public.admin_tournament_simulate(_tid uuid, _max_steps integer DEFAULT 200)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE t public.tournaments%ROWTYPE; i int := 0; v_done int;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin uniquement'; END IF;
  SELECT * INTO t FROM public.tournaments WHERE id = _tid;
  IF t.id IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;
  IF NOT t.is_simulation THEN RAISE EXCEPTION 'Ce tournoi n''est pas en mode simulation'; END IF;

  WHILE i < _max_steps LOOP
    i := i + 1;
    PERFORM public.tournament_engine(_tid);
    v_done := public._t_sim_resolve(_tid);
    SELECT status INTO t.status FROM public.tournaments WHERE id = _tid;
    EXIT WHEN t.status <> 'running';
    EXIT WHEN v_done = 0 AND NOT EXISTS (
      SELECT 1 FROM public.tournament_matches
       WHERE tournament_id = _tid AND status IN ('scheduled','running'));
  END LOOP;
  PERFORM public.tournament_engine(_tid);

  RETURN public.tournament_sim_report(_tid) || jsonb_build_object('steps', i);
END $function$;

-- Crée un tournoi de test rempli de bots et le simule de bout en bout
CREATE OR REPLACE FUNCTION public.admin_tournament_simulate_new(
  _game_slug text DEFAULT 'domino',
  _format text DEFAULT 'pools',
  _players integer DEFAULT 16,
  _players_per_match integer DEFAULT 2,
  _pool_size integer DEFAULT 4,
  _qualifiers_per_pool integer DEFAULT 2
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_id uuid; i int;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin uniquement'; END IF;
  IF _players < 2 OR _players > 128 THEN RAISE EXCEPTION 'Nombre de joueurs invalide'; END IF;

  INSERT INTO public.tournaments(
      name, description, game_slug, format, players_per_match, pool_size, qualifiers_per_pool,
      max_players, entry_fee_ar, prize_pool_ar, winners_count, prize_1_pct, prize_2_pct, prize_3_pct,
      lobby_minutes, auto_advance, status, stage, is_simulation, created_by)
  VALUES (
      '🧪 Simulation ' || upper(_game_slug) || ' ' || to_char(now(), 'DD/MM HH24:MI'),
      'Tournoi de test automatique (résultats aléatoires, aucun gain réel)',
      _game_slug, _format, _players_per_match, _pool_size, _qualifiers_per_pool,
      GREATEST(_players, 2), 0, 0, 3, 50, 30, 20,
      1, true, 'open', 'registration', true, auth.uid())
  RETURNING id INTO v_id;

  FOR i IN 1.._players LOOP
    INSERT INTO public.tournament_entrants(tournament_id, display_name, is_bot)
      VALUES (v_id, 'Bot ' || lpad(i::text, 2, '0'), true);
  END LOOP;

  PERFORM public.admin_tournament_start(v_id);
  RETURN public.admin_tournament_simulate(v_id);
END $function$;

REVOKE ALL ON FUNCTION public.admin_tournament_simulate(uuid, integer) FROM anon;
REVOKE ALL ON FUNCTION public.admin_tournament_simulate_new(text, text, integer, integer, integer, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_tournament_simulate(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_tournament_simulate_new(text, text, integer, integer, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tournament_sim_report(uuid) TO authenticated;