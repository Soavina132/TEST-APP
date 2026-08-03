
-- ============================================================
-- TOURNOIS : mode POULES (round-robin) + phase finale
-- ============================================================

ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS bracket_mode text NOT NULL DEFAULT 'elimination',
  ADD COLUMN IF NOT EXISTS pool_size int NOT NULL DEFAULT 4,
  ADD COLUMN IF NOT EXISTS qualifiers_per_pool int NOT NULL DEFAULT 2,
  ADD COLUMN IF NOT EXISTS pools_per_batch int NOT NULL DEFAULT 4,
  ADD COLUMN IF NOT EXISTS max_live_matches int NOT NULL DEFAULT 8,
  ADD COLUMN IF NOT EXISTS match_gap_secs int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS batch_gap_mins int NOT NULL DEFAULT 5;

ALTER TABLE public.tournament_matches
  ADD COLUMN IF NOT EXISTS pool_id uuid,
  ADD COLUMN IF NOT EXISTS pool_match_no int,
  ADD COLUMN IF NOT EXISTS phase text NOT NULL DEFAULT 'final';

-- ---------- Tables ----------
CREATE TABLE IF NOT EXISTS public.tournament_pools (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid NOT NULL REFERENCES public.tournaments(id) ON DELETE CASCADE,
  label text NOT NULL,
  batch_no int NOT NULL DEFAULT 1,
  status text NOT NULL DEFAULT 'pending',
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tournament_id, label)
);
GRANT SELECT ON public.tournament_pools TO authenticated, anon;
GRANT ALL ON public.tournament_pools TO service_role;
ALTER TABLE public.tournament_pools ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "pools_read" ON public.tournament_pools;
CREATE POLICY "pools_read" ON public.tournament_pools FOR SELECT USING (true);
DROP POLICY IF EXISTS "pools_admin_write" ON public.tournament_pools;
CREATE POLICY "pools_admin_write" ON public.tournament_pools FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE TABLE IF NOT EXISTS public.tournament_pool_players (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pool_id uuid NOT NULL REFERENCES public.tournament_pools(id) ON DELETE CASCADE,
  tournament_id uuid NOT NULL REFERENCES public.tournaments(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  seat int NOT NULL,
  played int NOT NULL DEFAULT 0,
  wins int NOT NULL DEFAULT 0,
  losses int NOT NULL DEFAULT 0,
  points int NOT NULL DEFAULT 0,
  qualified boolean,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (pool_id, user_id),
  UNIQUE (tournament_id, user_id)
);
GRANT SELECT ON public.tournament_pool_players TO authenticated, anon;
GRANT ALL ON public.tournament_pool_players TO service_role;
ALTER TABLE public.tournament_pool_players ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "pool_players_read" ON public.tournament_pool_players;
CREATE POLICY "pool_players_read" ON public.tournament_pool_players FOR SELECT USING (true);
DROP POLICY IF EXISTS "pool_players_admin_write" ON public.tournament_pool_players;
CREATE POLICY "pool_players_admin_write" ON public.tournament_pool_players FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE TABLE IF NOT EXISTS public.tournament_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid NOT NULL REFERENCES public.tournaments(id) ON DELETE CASCADE,
  batch_no int NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  starts_at timestamptz,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tournament_id, batch_no)
);
GRANT SELECT ON public.tournament_batches TO authenticated, anon;
GRANT ALL ON public.tournament_batches TO service_role;
ALTER TABLE public.tournament_batches ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "batches_read" ON public.tournament_batches;
CREATE POLICY "batches_read" ON public.tournament_batches FOR SELECT USING (true);
DROP POLICY IF EXISTS "batches_admin_write" ON public.tournament_batches;
CREATE POLICY "batches_admin_write" ON public.tournament_batches FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE INDEX IF NOT EXISTS tm_pool_idx ON public.tournament_matches(pool_id);
CREATE INDEX IF NOT EXISTS tpp_pool_idx ON public.tournament_pool_players(pool_id);

CREATE OR REPLACE FUNCTION public._tpool_touch() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END $$;
DROP TRIGGER IF EXISTS trg_pools_touch ON public.tournament_pools;
CREATE TRIGGER trg_pools_touch BEFORE UPDATE ON public.tournament_pools
  FOR EACH ROW EXECUTE FUNCTION public._tpool_touch();
DROP TRIGGER IF EXISTS trg_pool_players_touch ON public.tournament_pool_players;
CREATE TRIGGER trg_pool_players_touch BEFORE UPDATE ON public.tournament_pool_players
  FOR EACH ROW EXECUTE FUNCTION public._tpool_touch();
DROP TRIGGER IF EXISTS trg_batches_touch ON public.tournament_batches;
CREATE TRIGGER trg_batches_touch BEFORE UPDATE ON public.tournament_batches
  FOR EACH ROW EXECUTE FUNCTION public._tpool_touch();

-- ---------- Notification helper ----------
CREATE OR REPLACE FUNCTION public._tpool_notify(_uids uuid[], _title text, _body text, _tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid;
BEGIN
  IF _uids IS NULL THEN RETURN; END IF;
  FOREACH u IN ARRAY _uids LOOP
    IF u IS NOT NULL THEN
      INSERT INTO public.notifications(user_id, kind, title, body, link)
        VALUES (u, 'tournament', _title, _body, '/tournaments/' || _tid::text);
    END IF;
  END LOOP;
END $$;

-- ---------- Planification des 6 matchs d'une poule ----------
CREATE OR REPLACE FUNCTION public._tournament_pool_schedule(_pool_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  p public.tournament_pools%ROWTYPE;
  ids uuid[];
  pairs int[][] := ARRAY[[1,2],[3,4],[1,3],[2,4],[1,4],[2,3]];
  i int;
BEGIN
  SELECT * INTO p FROM public.tournament_pools WHERE id = _pool_id;
  IF p.id IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM public.tournament_matches WHERE pool_id = _pool_id) THEN RETURN; END IF;

  SELECT array_agg(user_id ORDER BY seat) INTO ids
    FROM public.tournament_pool_players WHERE pool_id = _pool_id;
  IF COALESCE(array_length(ids,1),0) < 2 THEN RETURN; END IF;

  FOR i IN 1..6 LOOP
    IF pairs[i][1] <= array_length(ids,1) AND pairs[i][2] <= array_length(ids,1) THEN
      INSERT INTO public.tournament_matches(
        tournament_id, round, match_index, player_ids, status, is_bye,
        qualifiers_count, pool_id, pool_match_no, phase)
      VALUES (p.tournament_id, 0, i - 1,
        ARRAY[ids[pairs[i][1]], ids[pairs[i][2]]], 'pending', false,
        1, _pool_id, i, 'pool');
    END IF;
  END LOOP;
END $$;

-- ---------- Tirage au sort ----------
CREATE OR REPLACE FUNCTION public.tournament_pools_draw(_tid uuid)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_t public.tournaments%ROWTYPE;
  v_players uuid[]; v_n int; v_size int; v_npools int;
  v_per_batch int; i int; j int; v_pool_id uuid; v_label text; v_batch int;
  v_total_batches int;
BEGIN
  SELECT * INTO v_t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF v_t.id IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;
  IF EXISTS (SELECT 1 FROM public.tournament_pools WHERE tournament_id = _tid) THEN
    RETURN 0;
  END IF;

  v_size := GREATEST(COALESCE(v_t.pool_size,4), 2);
  v_per_batch := GREATEST(COALESCE(v_t.pools_per_batch,4), 1);

  SELECT array_agg(user_id ORDER BY random()) INTO v_players
    FROM public.tournament_registrations WHERE tournament_id = _tid;
  v_n := COALESCE(array_length(v_players,1),0);
  IF v_n < v_size THEN RAISE EXCEPTION 'Pas assez de joueurs inscrits'; END IF;

  v_npools := CEIL(v_n::numeric / v_size);
  v_total_batches := CEIL(v_npools::numeric / v_per_batch);

  FOR b IN 1..v_total_batches LOOP
    INSERT INTO public.tournament_batches(tournament_id, batch_no, status)
      VALUES (_tid, b, 'pending')
      ON CONFLICT (tournament_id, batch_no) DO NOTHING;
  END LOOP;

  FOR i IN 1..v_npools LOOP
    v_label := chr(64 + i);
    v_batch := CEIL(i::numeric / v_per_batch);
    INSERT INTO public.tournament_pools(tournament_id, label, batch_no, status)
      VALUES (_tid, v_label, v_batch, 'pending') RETURNING id INTO v_pool_id;

    FOR j IN 1..v_size LOOP
      IF ((i - 1) * v_size + j) <= v_n THEN
        INSERT INTO public.tournament_pool_players(pool_id, tournament_id, user_id, seat)
          VALUES (v_pool_id, _tid, v_players[(i - 1) * v_size + j], j)
          ON CONFLICT DO NOTHING;
      END IF;
    END LOOP;

    PERFORM public._tournament_pool_schedule(v_pool_id);
  END LOOP;

  PERFORM public._tpool_notify(v_players, '🎲 Tirage au sort effectué',
    'Les poules du tournoi ' || COALESCE(v_t.name,'') || ' sont formées. Consulte ta poule !', _tid);

  RETURN v_npools;
END $$;

-- ---------- Classement d'une poule ----------
CREATE OR REPLACE FUNCTION public._tournament_pool_recount(_pool_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.tournament_pool_players pp
     SET played = s.played, wins = s.wins, losses = s.losses, points = s.wins * 3
    FROM (
      SELECT pl.user_id,
        count(*) FILTER (WHERE m.status IN ('finished','forfeit')) AS played,
        count(*) FILTER (WHERE m.status IN ('finished','forfeit') AND m.winner_id = pl.user_id) AS wins,
        count(*) FILTER (WHERE m.status IN ('finished','forfeit') AND m.winner_id IS NOT NULL AND m.winner_id <> pl.user_id) AS losses
      FROM public.tournament_pool_players pl
      LEFT JOIN public.tournament_matches m
        ON m.pool_id = pl.pool_id AND pl.user_id = ANY(m.player_ids)
      WHERE pl.pool_id = _pool_id
      GROUP BY pl.user_id
    ) s
   WHERE pp.pool_id = _pool_id AND pp.user_id = s.user_id;
END $$;

-- ---------- Fin d'une poule ----------
CREATE OR REPLACE FUNCTION public._tournament_pool_finish(_pool_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  p public.tournament_pools%ROWTYPE;
  v_qpp int; r record; v_rank int := 0;
  v_q uuid[] := ARRAY[]::uuid[]; v_out uuid[] := ARRAY[]::uuid[];
BEGIN
  SELECT * INTO p FROM public.tournament_pools WHERE id = _pool_id FOR UPDATE;
  IF p.id IS NULL OR p.status = 'finished' THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM public.tournament_matches
              WHERE pool_id = _pool_id AND status NOT IN ('finished','forfeit','cancelled')) THEN
    RETURN;
  END IF;

  PERFORM public._tournament_pool_recount(_pool_id);
  SELECT COALESCE(qualifiers_per_pool,2) INTO v_qpp FROM public.tournaments WHERE id = p.tournament_id;

  FOR r IN
    SELECT pl.user_id,
      (SELECT count(*) FROM public.tournament_matches m
        WHERE m.pool_id = _pool_id AND m.winner_id = pl.user_id) AS h2h
    FROM public.tournament_pool_players pl
    WHERE pl.pool_id = _pool_id
    ORDER BY pl.points DESC, pl.wins DESC, 2 DESC, random()
  LOOP
    v_rank := v_rank + 1;
    IF v_rank <= v_qpp THEN
      v_q := v_q || r.user_id;
      UPDATE public.tournament_pool_players SET qualified = true
        WHERE pool_id = _pool_id AND user_id = r.user_id;
    ELSE
      v_out := v_out || r.user_id;
      UPDATE public.tournament_pool_players SET qualified = false
        WHERE pool_id = _pool_id AND user_id = r.user_id;
      UPDATE public.tournament_registrations SET eliminated_round = 0
        WHERE tournament_id = p.tournament_id AND user_id = r.user_id AND eliminated_round IS NULL;
    END IF;
  END LOOP;

  UPDATE public.tournament_pools SET status = 'finished', finished_at = now() WHERE id = _pool_id;

  PERFORM public._tpool_notify(v_q, '✅ Tu es qualifié !',
    'Poule ' || p.label || ' terminée — tu passes en phase finale.', p.tournament_id);
  PERFORM public._tpool_notify(v_out, '❌ Éliminé',
    'Poule ' || p.label || ' terminée. Merci d''avoir participé !', p.tournament_id);
END $$;

-- ---------- Construction de la phase finale ----------
CREATE OR REPLACE FUNCTION public.tournament_build_finals(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_players uuid[];
BEGIN
  IF EXISTS (SELECT 1 FROM public.tournament_matches WHERE tournament_id=_tid AND phase='final') THEN RETURN; END IF;

  SELECT array_agg(user_id ORDER BY random()) INTO v_players
    FROM public.tournament_pool_players
   WHERE tournament_id = _tid AND qualified = true;

  IF COALESCE(array_length(v_players,1),0) < 2 THEN RETURN; END IF;

  UPDATE public.tournaments
     SET current_round = 1, players_per_match = 2, auto_advance_rounds = true
   WHERE id = _tid;

  PERFORM public._tournament_build_round(_tid, 1, v_players);
  UPDATE public.tournament_matches SET phase = 'final'
   WHERE tournament_id = _tid AND round = 1 AND phase <> 'pool';

  PERFORM public._tpool_notify(v_players, '🚀 La phase finale commence',
    'Les poules sont terminées, place à l''élimination directe !', _tid);
END $$;

-- ---------- LA POMPE ----------
CREATE OR REPLACE FUNCTION public.tournament_pump(_tid uuid)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_t public.tournaments%ROWTYPE;
  v_live int; v_max int; v_launched int := 0;
  v_batch int; b public.tournament_batches%ROWTYPE;
  m record; v_busy uuid[]; ok boolean;
BEGIN
  SELECT * INTO v_t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF v_t.id IS NULL OR v_t.status <> 'running' THEN RETURN 0; END IF;
  IF COALESCE(v_t.bracket_mode,'elimination') <> 'pools' THEN RETURN 0; END IF;

  v_max := GREATEST(COALESCE(v_t.max_live_matches,8), 1);

  -- 1. clôturer les poules complètes
  PERFORM public._tournament_pool_finish(id)
    FROM public.tournament_pools
   WHERE tournament_id = _tid AND status <> 'finished'
     AND NOT EXISTS (SELECT 1 FROM public.tournament_matches m
                      WHERE m.pool_id = tournament_pools.id
                        AND m.status NOT IN ('finished','forfeit','cancelled'));

  -- 2. clôturer les lots complets et programmer le suivant
  FOR b IN SELECT * FROM public.tournament_batches
            WHERE tournament_id = _tid AND status = 'running' LOOP
    IF NOT EXISTS (SELECT 1 FROM public.tournament_pools
                    WHERE tournament_id = _tid AND batch_no = b.batch_no AND status <> 'finished') THEN
      UPDATE public.tournament_batches SET status='finished', finished_at=now() WHERE id = b.id;
      UPDATE public.tournament_batches
         SET starts_at = now() + (COALESCE(v_t.batch_gap_mins,5) || ' minutes')::interval
       WHERE tournament_id = _tid AND batch_no = b.batch_no + 1 AND status = 'pending' AND starts_at IS NULL;
    END IF;
  END LOOP;

  -- 3. démarrer le lot actif
  SELECT * INTO b FROM public.tournament_batches
    WHERE tournament_id = _tid AND status IN ('pending','running')
    ORDER BY batch_no LIMIT 1;

  IF b.id IS NOT NULL AND b.status = 'pending' THEN
    IF b.starts_at IS NULL OR b.starts_at <= now() THEN
      UPDATE public.tournament_batches SET status='running', started_at=now() WHERE id = b.id;
      UPDATE public.tournament_pools SET status='running', started_at=now()
        WHERE tournament_id = _tid AND batch_no = b.batch_no AND status='pending';
      b.status := 'running';
      PERFORM public._tpool_notify(
        (SELECT array_agg(pp.user_id) FROM public.tournament_pool_players pp
          JOIN public.tournament_pools p ON p.id = pp.pool_id
         WHERE p.tournament_id = _tid AND p.batch_no = b.batch_no),
        '🔔 Ta poule commence',
        'Prépare-toi, tes matchs de poule vont être lancés.', _tid);
    END IF;
  END IF;

  -- 4. toutes les poules terminées → phase finale
  IF NOT EXISTS (SELECT 1 FROM public.tournament_pools WHERE tournament_id=_tid AND status <> 'finished')
     AND EXISTS (SELECT 1 FROM public.tournament_pools WHERE tournament_id=_tid) THEN
    PERFORM public.tournament_build_finals(_tid);
  END IF;

  -- 5. lancer les matchs
  SELECT count(*) INTO v_live FROM public.tournament_matches
   WHERE tournament_id = _tid AND status = 'running';

  SELECT COALESCE(array_agg(u), ARRAY[]::uuid[]) INTO v_busy
    FROM (SELECT DISTINCT unnest(player_ids) AS u FROM public.tournament_matches
           WHERE tournament_id = _tid AND status = 'running') s;

  v_batch := COALESCE(b.batch_no, 0);

  FOR m IN
    SELECT tm.id, tm.player_ids
      FROM public.tournament_matches tm
      LEFT JOIN public.tournament_pools p ON p.id = tm.pool_id
     WHERE tm.tournament_id = _tid
       AND tm.status = 'pending' AND tm.game_id IS NULL AND tm.is_bye = false
       AND (
         (tm.phase = 'pool' AND p.batch_no = v_batch AND p.status = 'running')
         OR (tm.phase = 'final' AND tm.round = v_t.current_round)
       )
     ORDER BY tm.phase DESC, COALESCE(p.label,''), COALESCE(tm.pool_match_no, 0), tm.match_index
  LOOP
    EXIT WHEN v_live >= v_max;
    ok := true;
    IF v_busy && m.player_ids THEN ok := false; END IF;
    IF ok THEN
      BEGIN
        PERFORM public._tourn_launch_ludo_match(m.id);
        v_live := v_live + 1;
        v_launched := v_launched + 1;
        v_busy := v_busy || m.player_ids;
        PERFORM public._tpool_notify(m.player_ids, '🎮 Ton match est prêt !',
          'Rejoins ta partie maintenant.', _tid);
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;
  END LOOP;

  RETURN v_launched;
END $$;

CREATE OR REPLACE FUNCTION public.tournament_pump_all()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE t record;
BEGIN
  FOR t IN SELECT id FROM public.tournaments
            WHERE status='running' AND COALESCE(bracket_mode,'elimination')='pools' LOOP
    BEGIN PERFORM public.tournament_pump(t.id); EXCEPTION WHEN OTHERS THEN NULL; END;
  END LOOP;
END $$;

-- ---------- Scoring automatique sur fin de match de poule ----------
CREATE OR REPLACE FUNCTION public._trg_pool_match_finished()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_loser uuid;
BEGIN
  IF COALESCE(NEW.phase,'final') <> 'pool' THEN RETURN NEW; END IF;
  IF NEW.status NOT IN ('finished','forfeit') OR OLD.status = NEW.status THEN RETURN NEW; END IF;

  PERFORM public._tournament_pool_recount(NEW.pool_id);

  IF NEW.winner_id IS NOT NULL THEN
    SELECT p INTO v_loser FROM unnest(NEW.player_ids) p WHERE p <> NEW.winner_id LIMIT 1;
    PERFORM public._tpool_notify(ARRAY[NEW.winner_id], '🏆 Match gagné (+3 pts)',
      'Bravo ! Ton classement de poule est mis à jour.', NEW.tournament_id);
    IF v_loser IS NOT NULL THEN
      PERFORM public._tpool_notify(ARRAY[v_loser], '❌ Match perdu',
        'Pas de points cette fois. Prochain match bientôt.', NEW.tournament_id);
    END IF;
  END IF;

  PERFORM public.tournament_pump(NEW.tournament_id);
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_pool_match_finished ON public.tournament_matches;
CREATE TRIGGER trg_pool_match_finished
  AFTER UPDATE OF status ON public.tournament_matches
  FOR EACH ROW EXECUTE FUNCTION public._trg_pool_match_finished();

-- ---------- Ne pas laisser l'ancien automate toucher aux poules ----------
CREATE OR REPLACE FUNCTION public._trg_tournament_match_auto_advance()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','extensions' AS $$
DECLARE trn record; v_remaining int;
BEGIN
  IF COALESCE(NEW.phase,'final') = 'pool' THEN RETURN NEW; END IF;
  IF NEW.status NOT IN ('finished','forfeit','cancelled') THEN RETURN NEW; END IF;
  IF OLD.status = NEW.status THEN RETURN NEW; END IF;
  IF NEW.is_bye THEN RETURN NEW; END IF;
  SELECT * INTO trn FROM public.tournaments WHERE id = NEW.tournament_id;
  IF trn IS NULL OR trn.status <> 'running' OR NOT COALESCE(trn.auto_advance_rounds,false) THEN RETURN NEW; END IF;
  IF NEW.round <> trn.current_round THEN RETURN NEW; END IF;
  SELECT count(*) INTO v_remaining FROM public.tournament_matches
    WHERE tournament_id=NEW.tournament_id AND round=trn.current_round AND COALESCE(phase,'final')<>'pool'
      AND status NOT IN ('finished','forfeit','cancelled') AND is_bye=false;
  IF v_remaining = 0 THEN PERFORM public._tournament_advance_round_core(NEW.tournament_id); END IF;
  RETURN NEW;
END; $$;

-- ---------- Admin ----------
CREATE OR REPLACE FUNCTION public.admin_tournament_set_pool_config(
  _tid uuid, _pool_size int, _qualifiers_per_pool int, _pools_per_batch int,
  _max_live_matches int, _batch_gap_mins int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Accès refusé'; END IF;
  UPDATE public.tournaments
     SET bracket_mode = 'pools',
         pool_size = GREATEST(COALESCE(_pool_size,4),2),
         qualifiers_per_pool = GREATEST(COALESCE(_qualifiers_per_pool,2),1),
         pools_per_batch = GREATEST(COALESCE(_pools_per_batch,4),1),
         max_live_matches = GREATEST(COALESCE(_max_live_matches,8),1),
         batch_gap_mins = GREATEST(COALESCE(_batch_gap_mins,5),0)
   WHERE id = _tid;
END $$;

CREATE OR REPLACE FUNCTION public.admin_tournament_start_pools(_tid uuid)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_pools int;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Accès refusé'; END IF;
  UPDATE public.tournaments
     SET bracket_mode='pools', status='running', started_at=COALESCE(started_at, now()),
         current_round = 0, players_per_match = 2
   WHERE id = _tid;
  v_pools := public.tournament_pools_draw(_tid);
  PERFORM public.tournament_pump(_tid);
  RETURN v_pools;
END $$;

CREATE OR REPLACE FUNCTION public.admin_tournament_start_next_batch(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Accès refusé'; END IF;
  UPDATE public.tournament_batches SET starts_at = now()
   WHERE tournament_id = _tid AND status = 'pending';
  PERFORM public.tournament_pump(_tid);
END $$;

-- ---------- Lecture (UI) ----------
CREATE OR REPLACE FUNCTION public.tournament_pools_state(_tid uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'tournament', (SELECT to_jsonb(t) FROM public.tournaments t WHERE t.id = _tid),
    'batches', COALESCE((SELECT jsonb_agg(to_jsonb(b) ORDER BY b.batch_no)
                          FROM public.tournament_batches b WHERE b.tournament_id=_tid), '[]'::jsonb),
    'pools', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', p.id, 'label', p.label, 'batch_no', p.batch_no, 'status', p.status,
        'players', COALESCE((SELECT jsonb_agg(jsonb_build_object(
              'user_id', pp.user_id, 'seat', pp.seat, 'played', pp.played,
              'wins', pp.wins, 'losses', pp.losses, 'points', pp.points,
              'qualified', pp.qualified,
              'pseudo', pr.pseudo, 'avatar_url', pr.avatar_url)
            ORDER BY pp.points DESC, pp.wins DESC, pp.seat)
          FROM public.tournament_pool_players pp
          LEFT JOIN public.profiles pr ON pr.id = pp.user_id
          WHERE pp.pool_id = p.id), '[]'::jsonb),
        'matches', COALESCE((SELECT jsonb_agg(jsonb_build_object(
              'id', m.id, 'no', m.pool_match_no, 'player_ids', m.player_ids,
              'status', m.status, 'winner_id', m.winner_id, 'game_id', m.game_id,
              'scheduled_at', m.scheduled_at, 'finished_at', m.finished_at)
            ORDER BY m.pool_match_no)
          FROM public.tournament_matches m WHERE m.pool_id = p.id), '[]'::jsonb)
      ) ORDER BY p.label)
      FROM public.tournament_pools p WHERE p.tournament_id = _tid), '[]'::jsonb),
    'finals', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', m.id, 'round', m.round, 'match_index', m.match_index,
        'player_ids', m.player_ids, 'status', m.status, 'winner_id', m.winner_id,
        'game_id', m.game_id, 'is_third_place', m.is_third_place)
      ORDER BY m.round, m.match_index)
      FROM public.tournament_matches m
      WHERE m.tournament_id=_tid AND COALESCE(m.phase,'final')='final'), '[]'::jsonb)
  );
$$;

REVOKE EXECUTE ON FUNCTION public.tournament_pump(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tournament_pump_all() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tournament_pools_draw(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tournament_build_finals(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._tournament_pool_schedule(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._tournament_pool_finish(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._tournament_pool_recount(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._tpool_notify(uuid[], text, text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.tournament_pump_all() TO service_role;
GRANT EXECUTE ON FUNCTION public.tournament_pools_state(uuid) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.admin_tournament_set_pool_config(uuid,int,int,int,int,int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_tournament_start_pools(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_tournament_start_next_batch(uuid) TO authenticated;

-- ---------- Cron ----------
DO $$
DECLARE j bigint;
BEGIN
  SELECT jobid INTO j FROM cron.job WHERE jobname = 'tournament_pump_all';
  IF j IS NOT NULL THEN PERFORM cron.unschedule(j); END IF;
END $$;
SELECT cron.schedule('tournament_pump_all', '10 seconds', $$SELECT public.tournament_pump_all();$$);

ALTER TABLE public.tournament_pools REPLICA IDENTITY FULL;
ALTER TABLE public.tournament_pool_players REPLICA IDENTITY FULL;
ALTER TABLE public.tournament_batches REPLICA IDENTITY FULL;
DO $$
BEGIN
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.tournament_pools; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.tournament_pool_players; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.tournament_batches; EXCEPTION WHEN OTHERS THEN NULL; END;
END $$;
