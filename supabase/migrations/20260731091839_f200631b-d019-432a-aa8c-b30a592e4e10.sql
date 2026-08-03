-- ============================================================
-- TOURNOIS V2 — remise à zéro complète
-- ============================================================
DROP TRIGGER IF EXISTS trg_tournament_on_game_finished ON public.ludo_games;

DROP TABLE IF EXISTS public.tournament_shuffle_drafts CASCADE;
DROP TABLE IF EXISTS public.tournament_audit_logs CASCADE;
DROP TABLE IF EXISTS public.tournament_payouts CASCADE;
DROP TABLE IF EXISTS public.tournament_claims CASCADE;
DROP TABLE IF EXISTS public.tournament_bots CASCADE;
DROP TABLE IF EXISTS public.tournament_pool_players CASCADE;
DROP TABLE IF EXISTS public.tournament_pools CASCADE;
DROP TABLE IF EXISTS public.tournament_batches CASCADE;
DROP TABLE IF EXISTS public.tournament_matches CASCADE;
DROP TABLE IF EXISTS public.tournament_registrations CASCADE;
DROP TABLE IF EXISTS public.tournament_tables CASCADE;
DROP TABLE IF EXISTS public.tournaments CASCADE;

DO $$ DECLARE r record; BEGIN
  FOR r IN SELECT p.oid::regprocedure AS sig
           FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public' AND p.proname ILIKE '%tournament%'
  LOOP EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE'; END LOOP;
END $$;

-- ============================================================
-- TABLES
-- ============================================================
CREATE TABLE public.tournaments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  game_slug text NOT NULL DEFAULT 'ludo' CHECK (game_slug IN ('ludo','domino')),
  format text NOT NULL DEFAULT 'knockout' CHECK (format IN ('pools','knockout')),
  players_per_match int NOT NULL DEFAULT 2 CHECK (players_per_match BETWEEN 2 AND 4),
  pool_size int NOT NULL DEFAULT 4 CHECK (pool_size BETWEEN 2 AND 6),
  qualifiers_per_pool int NOT NULL DEFAULT 2 CHECK (qualifiers_per_pool BETWEEN 1 AND 3),
  max_players int NOT NULL DEFAULT 32 CHECK (max_players BETWEEN 2 AND 256),
  entry_fee_ar numeric NOT NULL DEFAULT 0 CHECK (entry_fee_ar >= 0),
  prize_pool_ar numeric NOT NULL DEFAULT 0 CHECK (prize_pool_ar >= 0),
  admin_prize_pool_ar numeric NOT NULL DEFAULT 0 CHECK (admin_prize_pool_ar >= 0),
  platform_pct numeric NOT NULL DEFAULT 10 CHECK (platform_pct >= 0 AND platform_pct <= 50),
  winners_count int NOT NULL DEFAULT 1 CHECK (winners_count BETWEEN 1 AND 3),
  prize_1_pct numeric NOT NULL DEFAULT 100,
  prize_2_pct numeric NOT NULL DEFAULT 0,
  prize_3_pct numeric NOT NULL DEFAULT 0,
  max_concurrent_matches int NOT NULL DEFAULT 8 CHECK (max_concurrent_matches BETWEEN 1 AND 64),
  lobby_minutes int NOT NULL DEFAULT 5 CHECK (lobby_minutes BETWEEN 1 AND 60),
  auto_advance boolean NOT NULL DEFAULT true,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','open','running','paused','finished','cancelled')),
  stage text NOT NULL DEFAULT 'registration' CHECK (stage IN ('registration','pools','finals','done')),
  current_round int NOT NULL DEFAULT 0,
  registration_closes_at timestamptz,
  starts_at timestamptz,
  started_at timestamptz,
  finished_at timestamptz,
  champion_entrant_id uuid,
  created_by uuid DEFAULT auth.uid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.tournaments TO authenticated, anon;
GRANT ALL ON public.tournaments TO service_role;
ALTER TABLE public.tournaments ENABLE ROW LEVEL SECURITY;
CREATE POLICY t_read ON public.tournaments FOR SELECT USING (true);
CREATE POLICY t_admin ON public.tournaments FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE TABLE public.tournament_entrants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid NOT NULL REFERENCES public.tournaments(id) ON DELETE CASCADE,
  user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  display_name text NOT NULL,
  is_bot boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','eliminated','withdrawn')),
  eliminated_round int,
  final_rank int,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX tournament_entrants_uniq ON public.tournament_entrants(tournament_id, user_id) WHERE user_id IS NOT NULL;
CREATE INDEX tournament_entrants_tid ON public.tournament_entrants(tournament_id);
GRANT SELECT ON public.tournament_entrants TO authenticated, anon;
GRANT ALL ON public.tournament_entrants TO service_role;
ALTER TABLE public.tournament_entrants ENABLE ROW LEVEL SECURITY;
CREATE POLICY te_read ON public.tournament_entrants FOR SELECT USING (true);
CREATE POLICY te_admin ON public.tournament_entrants FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE TABLE public.tournament_pools (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid NOT NULL REFERENCES public.tournaments(id) ON DELETE CASCADE,
  label text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','running','finished')),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX tournament_pools_tid ON public.tournament_pools(tournament_id);
GRANT SELECT ON public.tournament_pools TO authenticated, anon;
GRANT ALL ON public.tournament_pools TO service_role;
ALTER TABLE public.tournament_pools ENABLE ROW LEVEL SECURITY;
CREATE POLICY tp_read ON public.tournament_pools FOR SELECT USING (true);
CREATE POLICY tp_admin ON public.tournament_pools FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE TABLE public.tournament_pool_entrants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pool_id uuid NOT NULL REFERENCES public.tournament_pools(id) ON DELETE CASCADE,
  entrant_id uuid NOT NULL REFERENCES public.tournament_entrants(id) ON DELETE CASCADE,
  played int NOT NULL DEFAULT 0,
  wins int NOT NULL DEFAULT 0,
  points int NOT NULL DEFAULT 0,
  qualified boolean NOT NULL DEFAULT false,
  UNIQUE (pool_id, entrant_id)
);
GRANT SELECT ON public.tournament_pool_entrants TO authenticated, anon;
GRANT ALL ON public.tournament_pool_entrants TO service_role;
ALTER TABLE public.tournament_pool_entrants ENABLE ROW LEVEL SECURITY;
CREATE POLICY tpe_read ON public.tournament_pool_entrants FOR SELECT USING (true);
CREATE POLICY tpe_admin ON public.tournament_pool_entrants FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE TABLE public.tournament_matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid NOT NULL REFERENCES public.tournaments(id) ON DELETE CASCADE,
  pool_id uuid REFERENCES public.tournament_pools(id) ON DELETE CASCADE,
  phase text NOT NULL DEFAULT 'final' CHECK (phase IN ('pool','final','third_place')),
  round int NOT NULL DEFAULT 1,
  match_no int NOT NULL DEFAULT 1,
  entrant_ids uuid[] NOT NULL,
  game_id uuid,
  status text NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled','running','finished','cancelled')),
  winner_entrant_id uuid REFERENCES public.tournament_entrants(id) ON DELETE SET NULL,
  started_at timestamptz,
  deadline_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX tournament_matches_tid ON public.tournament_matches(tournament_id, round);
CREATE INDEX tournament_matches_game ON public.tournament_matches(game_id);
GRANT SELECT ON public.tournament_matches TO authenticated, anon;
GRANT ALL ON public.tournament_matches TO service_role;
ALTER TABLE public.tournament_matches ENABLE ROW LEVEL SECURITY;
CREATE POLICY tm_read ON public.tournament_matches FOR SELECT USING (true);
CREATE POLICY tm_admin ON public.tournament_matches FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

ALTER TABLE public.tournaments REPLICA IDENTITY FULL;
ALTER TABLE public.tournament_entrants REPLICA IDENTITY FULL;
ALTER TABLE public.tournament_pools REPLICA IDENTITY FULL;
ALTER TABLE public.tournament_pool_entrants REPLICA IDENTITY FULL;
ALTER TABLE public.tournament_matches REPLICA IDENTITY FULL;
DO $$ BEGIN
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.tournaments; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.tournament_entrants; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.tournament_pools; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.tournament_pool_entrants; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.tournament_matches; EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;

CREATE OR REPLACE FUNCTION public._t_touch() RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;
CREATE TRIGGER trg_tournaments_touch BEFORE UPDATE ON public.tournaments
  FOR EACH ROW EXECUTE FUNCTION public._t_touch();

-- ============================================================
-- HELPERS
-- ============================================================
CREATE OR REPLACE FUNCTION public._t_notify(_entrant uuid, _title text, _body text, _link text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid;
BEGIN
  SELECT user_id INTO v_uid FROM public.tournament_entrants WHERE id = _entrant;
  IF v_uid IS NULL THEN RETURN; END IF;
  INSERT INTO public.notifications(user_id, kind, title, body, link, ref_id)
  VALUES (v_uid, 'tournoi', _title, _body, _link, _entrant);
END $$;

-- Crée la partie réelle et démarre le match
CREATE OR REPLACE FUNCTION public._t_launch_match(_match_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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
END $$;

-- Enregistre le résultat d'un match
CREATE OR REPLACE FUNCTION public._t_match_finish(_match_id uuid, _winner uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE m public.tournament_matches%ROWTYPE; e uuid;
BEGIN
  SELECT * INTO m FROM public.tournament_matches WHERE id = _match_id FOR UPDATE;
  IF m.id IS NULL OR m.status = 'finished' THEN RETURN; END IF;

  UPDATE public.tournament_matches
     SET status = 'finished', winner_entrant_id = _winner, finished_at = now()
   WHERE id = _match_id;

  IF m.phase = 'pool' AND m.pool_id IS NOT NULL THEN
    UPDATE public.tournament_pool_entrants SET played = played + 1
      WHERE pool_id = m.pool_id AND entrant_id = ANY(m.entrant_ids);
    UPDATE public.tournament_pool_entrants SET wins = wins + 1, points = points + 3
      WHERE pool_id = m.pool_id AND entrant_id = _winner;
  ELSE
    FOREACH e IN ARRAY m.entrant_ids LOOP
      IF e <> _winner THEN
        UPDATE public.tournament_entrants
           SET status = 'eliminated', eliminated_round = m.round
         WHERE id = e AND status = 'active';
      END IF;
    END LOOP;
  END IF;

  FOREACH e IN ARRAY m.entrant_ids LOOP
    IF e = _winner THEN
      PERFORM public._t_notify(e, '✅ Match gagné', 'Vous passez à la suite du tournoi.', '/tournaments/' || m.tournament_id);
    ELSE
      PERFORM public._t_notify(e, '❌ Match perdu', 'Merci d''avoir participé.', '/tournaments/' || m.tournament_id);
    END IF;
  END LOOP;
END $$;

-- Tirage des poules
CREATE OR REPLACE FUNCTION public._t_draw_pools(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  t public.tournaments%ROWTYPE; ids uuid[]; n int; i int := 1; k int := 0;
  v_pool uuid; v_size int; v_rest int; v_take int; v_mno int;
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid;
  SELECT array_agg(id ORDER BY random()) INTO ids FROM public.tournament_entrants
   WHERE tournament_id = _tid AND status = 'active';
  n := COALESCE(array_length(ids,1),0);
  IF n < 2 THEN RETURN; END IF;

  WHILE i <= n LOOP
    v_rest := n - i + 1;
    v_take := LEAST(t.pool_size, v_rest);
    IF v_rest - v_take = 1 THEN v_take := v_take - 1; END IF;  -- jamais de poule à 1 joueur
    IF v_take < 2 THEN v_take := v_rest; END IF;
    k := k + 1;
    INSERT INTO public.tournament_pools(tournament_id, label, status)
      VALUES (_tid, 'Poule ' || chr(64 + k), 'running') RETURNING id INTO v_pool;
    INSERT INTO public.tournament_pool_entrants(pool_id, entrant_id)
      SELECT v_pool, ids[j] FROM generate_series(i, i + v_take - 1) j;

    v_mno := 0;
    IF t.players_per_match = 2 THEN
      FOR i IN 0..0 LOOP END LOOP; -- no-op
      INSERT INTO public.tournament_matches(tournament_id, pool_id, phase, round, match_no, entrant_ids)
        SELECT _tid, v_pool, 'pool', 1, row_number() OVER (), ARRAY[a.e, b.e]
          FROM (SELECT ids[x] e, x FROM generate_series(i, i + v_take - 1) x) a
          JOIN (SELECT ids[y] e, y FROM generate_series(i, i + v_take - 1) y) b ON b.y > a.x;
    ELSE
      INSERT INTO public.tournament_matches(tournament_id, pool_id, phase, round, match_no, entrant_ids)
        VALUES (_tid, v_pool, 'pool', 1, k, (SELECT array_agg(ids[j]) FROM generate_series(i, i + v_take - 1) j));
    END IF;
    i := i + v_take;
  END LOOP;

  UPDATE public.tournaments SET stage = 'pools', current_round = 1 WHERE id = _tid;
END $$;

-- Construit un tour à élimination directe à partir d'une liste
CREATE OR REPLACE FUNCTION public._t_build_round(_tid uuid, _round int, _ids uuid[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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

  -- Petite finale : demi-finales (2 matchs) déjà jouées => finale + 3e place
  WHILE i <= n LOOP
    v_rest := n - i + 1;
    v_take := LEAST(t.players_per_match, v_rest);
    IF v_rest - v_take = 1 THEN v_take := v_take + 1; END IF; -- absorbe le joueur seul
    v_take := LEAST(v_take, v_rest);
    v_mno := v_mno + 1;
    INSERT INTO public.tournament_matches(tournament_id, phase, round, match_no, entrant_ids)
      VALUES (_tid, 'final', _round, v_mno, (SELECT array_agg(_ids[j]) FROM generate_series(i, i + v_take - 1) j));
    i := i + v_take;
  END LOOP;

  UPDATE public.tournaments SET stage = 'finals', current_round = _round WHERE id = _tid;
END $$;

-- Clôture du tournoi + récompenses
CREATE OR REPLACE FUNCTION public._t_finish(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  t public.tournaments%ROWTYPE; v_net numeric; v_pcts numeric[]; r record; i int := 0; v_amt numeric;
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF t.status IN ('finished','cancelled') THEN RETURN; END IF;

  -- classement final
  UPDATE public.tournament_entrants SET final_rank = 1 WHERE id = t.champion_entrant_id;
  WITH ranked AS (
    SELECT id, row_number() OVER (ORDER BY COALESCE(eliminated_round,0) DESC, created_at) + 1 AS rk
    FROM public.tournament_entrants
    WHERE tournament_id = _tid AND id IS DISTINCT FROM t.champion_entrant_id
  )
  UPDATE public.tournament_entrants e SET final_rank = ranked.rk FROM ranked WHERE e.id = ranked.id;

  -- petite finale prioritaire pour la 3e place
  UPDATE public.tournament_entrants e SET final_rank = 3
   FROM public.tournament_matches m
  WHERE m.tournament_id = _tid AND m.phase = 'third_place' AND m.status = 'finished'
    AND e.id = m.winner_entrant_id;

  v_net := round(t.prize_pool_ar * (100 - t.platform_pct) / 100) + t.admin_prize_pool_ar;
  v_pcts := ARRAY[t.prize_1_pct, t.prize_2_pct, t.prize_3_pct];

  FOR r IN SELECT * FROM public.tournament_entrants
            WHERE tournament_id = _tid AND final_rank IS NOT NULL AND final_rank <= t.winners_count
            ORDER BY final_rank LOOP
    i := r.final_rank;
    v_amt := round(v_net * COALESCE(v_pcts[i],0) / 100);
    IF v_amt > 0 AND r.user_id IS NOT NULL AND NOT r.is_bot THEN
      PERFORM public.credit_user_balance(r.user_id, v_amt, 'tournament_prize', _tid,
        'Récompense tournoi: ' || t.name, jsonb_build_object('rank', i));
    END IF;
    PERFORM public._t_notify(r.id, '🏆 Tournoi terminé',
      'Vous terminez ' || i || 'e. Gain : ' || v_amt || ' Ar', '/tournaments/' || _tid);
  END LOOP;

  UPDATE public.tournaments SET status = 'finished', stage = 'done', finished_at = now() WHERE id = _tid;
END $$;

-- ============================================================
-- MOTEUR
-- ============================================================
CREATE OR REPLACE FUNCTION public.tournament_engine(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  t public.tournaments%ROWTYPE;
  m record; g record; v_win uuid; v_slot int; v_busy uuid[]; v_live int;
  v_pool record; v_next uuid[]; v_losers uuid[]; v_ready int; v_total int;
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF t.id IS NULL OR t.status <> 'running' THEN RETURN; END IF;

  -- 1) synchronisation des matchs en cours
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
      -- démarrage dès que tout le monde est prêt
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

      -- forfait si la salle d'attente expire
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

  -- 2) clôture des poules terminées
  FOR v_pool IN SELECT p.* FROM public.tournament_pools p
                 WHERE p.tournament_id = _tid AND p.status = 'running'
                   AND NOT EXISTS (SELECT 1 FROM public.tournament_matches mm
                                    WHERE mm.pool_id = p.id AND mm.status IN ('scheduled','running')) LOOP
    UPDATE public.tournament_pool_entrants pe SET qualified = true
     WHERE pe.pool_id = v_pool.id
       AND pe.entrant_id IN (
         SELECT entrant_id FROM public.tournament_pool_entrants
          WHERE pool_id = v_pool.id ORDER BY points DESC, wins DESC, random()
          LIMIT (SELECT qualifiers_per_pool FROM public.tournaments WHERE id = _tid));
    UPDATE public.tournament_entrants e SET status = 'eliminated', eliminated_round = 1
      FROM public.tournament_pool_entrants pe
     WHERE pe.pool_id = v_pool.id AND pe.entrant_id = e.id AND NOT pe.qualified AND e.status = 'active';
    UPDATE public.tournament_pools SET status = 'finished' WHERE id = v_pool.id;
  END LOOP;

  -- 3) avancement d'étape
  IF NOT EXISTS (SELECT 1 FROM public.tournament_matches
                  WHERE tournament_id = _tid AND status IN ('scheduled','running')) THEN
    IF t.auto_advance THEN
      IF t.stage = 'pools' THEN
        SELECT array_agg(e.id ORDER BY random()) INTO v_next
          FROM public.tournament_entrants e WHERE e.tournament_id = _tid AND e.status = 'active';
        PERFORM public._t_build_round(_tid, 2, v_next);
      ELSIF t.stage = 'finals' THEN
        -- petite finale entre les 2 perdants des demi-finales
        IF t.players_per_match = 2
           AND (SELECT count(*) FROM public.tournament_matches
                 WHERE tournament_id = _tid AND round = t.current_round AND phase = 'final') = 2
           AND NOT EXISTS (SELECT 1 FROM public.tournament_matches
                            WHERE tournament_id = _tid AND phase = 'third_place') THEN
          SELECT array_agg(x.eid) INTO v_losers FROM (
            SELECT unnest(mm.entrant_ids) eid, mm.winner_entrant_id w
              FROM public.tournament_matches mm
             WHERE mm.tournament_id = _tid AND mm.round = t.current_round AND mm.phase = 'final') x
           WHERE x.eid <> x.w;
          IF array_length(v_losers,1) = 2 THEN
            INSERT INTO public.tournament_matches(tournament_id, phase, round, match_no, entrant_ids)
              VALUES (_tid, 'third_place', t.current_round + 1, 1, v_losers);
          END IF;
        END IF;

        SELECT array_agg(winner_entrant_id ORDER BY match_no) INTO v_next
          FROM public.tournament_matches
         WHERE tournament_id = _tid AND round = t.current_round AND phase = 'final'
           AND winner_entrant_id IS NOT NULL;
        IF COALESCE(array_length(v_next,1),0) <= 1 AND NOT EXISTS (
             SELECT 1 FROM public.tournament_matches
              WHERE tournament_id = _tid AND status IN ('scheduled','running')) THEN
          UPDATE public.tournaments SET champion_entrant_id = v_next[1] WHERE id = _tid;
          PERFORM public._t_finish(_tid);
          RETURN;
        ELSIF COALESCE(array_length(v_next,1),0) > 1 THEN
          PERFORM public._t_build_round(_tid, t.current_round + 1, v_next);
        END IF;
      END IF;
      SELECT * INTO t FROM public.tournaments WHERE id = _tid;
    END IF;
  END IF;

  -- 4) lancement des matchs (limite de simultanéité, pas 2 matchs pour un joueur)
  SELECT count(*) INTO v_live FROM public.tournament_matches
   WHERE tournament_id = _tid AND status = 'running';
  SELECT COALESCE(array_agg(x), ARRAY[]::uuid[]) INTO v_busy FROM (
    SELECT unnest(entrant_ids) x FROM public.tournament_matches
     WHERE tournament_id = _tid AND status = 'running') s;

  FOR m IN SELECT * FROM public.tournament_matches
            WHERE tournament_id = _tid AND status = 'scheduled'
            ORDER BY round, match_no LOOP
    EXIT WHEN v_live >= t.max_concurrent_matches;
    CONTINUE WHEN m.entrant_ids && v_busy;
    PERFORM public._t_launch_match(m.id);
    v_busy := v_busy || m.entrant_ids;
    v_live := v_live + 1;
  END LOOP;
END $$;
GRANT EXECUTE ON FUNCTION public.tournament_engine(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.tournament_engine_all()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record;
BEGIN
  FOR r IN SELECT id FROM public.tournaments WHERE status = 'running' LOOP
    BEGIN PERFORM public.tournament_engine(r.id); EXCEPTION WHEN OTHERS THEN NULL; END;
  END LOOP;
END $$;

-- ============================================================
-- API JOUEUR
-- ============================================================
CREATE OR REPLACE FUNCTION public.tournament_register(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE t public.tournaments%ROWTYPE; v_uid uuid := auth.uid(); v_n int; v_name text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT * INTO t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF t.id IS NULL OR t.status <> 'open' THEN RAISE EXCEPTION 'Inscriptions fermées'; END IF;
  IF EXISTS (SELECT 1 FROM public.tournament_entrants WHERE tournament_id = _tid AND user_id = v_uid) THEN
    RAISE EXCEPTION 'Déjà inscrit';
  END IF;
  SELECT count(*) INTO v_n FROM public.tournament_entrants WHERE tournament_id = _tid;
  IF v_n >= t.max_players THEN RAISE EXCEPTION 'Tournoi complet'; END IF;

  IF t.entry_fee_ar > 0 THEN
    PERFORM public.debit_user_balance(v_uid, t.entry_fee_ar, 'tournament_entry', _tid,
      'Inscription tournoi: ' || t.name, '{}'::jsonb);
    UPDATE public.tournaments SET prize_pool_ar = prize_pool_ar + t.entry_fee_ar WHERE id = _tid;
  END IF;

  SELECT COALESCE(pseudo, 'Joueur') INTO v_name FROM public.profiles WHERE id = v_uid;
  INSERT INTO public.tournament_entrants(tournament_id, user_id, display_name) VALUES (_tid, v_uid, v_name);
END $$;
GRANT EXECUTE ON FUNCTION public.tournament_register(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.tournament_unregister(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE t public.tournaments%ROWTYPE; v_uid uuid := auth.uid();
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF t.status <> 'open' THEN RAISE EXCEPTION 'Tournoi déjà lancé'; END IF;
  DELETE FROM public.tournament_entrants WHERE tournament_id = _tid AND user_id = v_uid;
  IF FOUND AND t.entry_fee_ar > 0 THEN
    PERFORM public.credit_user_balance(v_uid, t.entry_fee_ar, 'tournament_refund', _tid,
      'Désinscription tournoi: ' || t.name, '{}'::jsonb);
    UPDATE public.tournaments SET prize_pool_ar = GREATEST(0, prize_pool_ar - t.entry_fee_ar) WHERE id = _tid;
  END IF;
END $$;
GRANT EXECUTE ON FUNCTION public.tournament_unregister(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.tournament_state(_tid uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'tournament', to_jsonb(t),
    'entrants', COALESCE((SELECT jsonb_agg(to_jsonb(e) ORDER BY e.created_at)
                          FROM public.tournament_entrants e WHERE e.tournament_id = t.id), '[]'::jsonb),
    'pools', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                          'pool', to_jsonb(p),
                          'players', COALESCE((SELECT jsonb_agg(to_jsonb(pe) ORDER BY pe.points DESC, pe.wins DESC)
                                               FROM public.tournament_pool_entrants pe WHERE pe.pool_id = p.id), '[]'::jsonb))
                          ORDER BY p.label)
                       FROM public.tournament_pools p WHERE p.tournament_id = t.id), '[]'::jsonb),
    'matches', COALESCE((SELECT jsonb_agg(to_jsonb(m) ORDER BY m.round, m.match_no)
                         FROM public.tournament_matches m WHERE m.tournament_id = t.id), '[]'::jsonb)
  ) FROM public.tournaments t WHERE t.id = _tid;
$$;
GRANT EXECUTE ON FUNCTION public.tournament_state(uuid) TO authenticated, anon;

CREATE OR REPLACE FUNCTION public.list_tournaments(_status text DEFAULT NULL, _game_slug text DEFAULT NULL, _limit int DEFAULT 100)
RETURNS SETOF public.tournaments LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM public.tournaments
   WHERE (_status IS NULL OR status = _status)
     AND (_game_slug IS NULL OR game_slug = _game_slug)
     AND (status <> 'draft' OR public.is_admin())
   ORDER BY created_at DESC LIMIT _limit;
$$;
GRANT EXECUTE ON FUNCTION public.list_tournaments(text, text, int) TO authenticated, anon;

-- ============================================================
-- API ADMIN
-- ============================================================
CREATE OR REPLACE FUNCTION public.admin_tournament_create(
  _name text, _game_slug text, _format text, _players_per_match int, _max_players int,
  _entry_fee_ar numeric, _admin_prize_pool_ar numeric, _winners_count int,
  _p1 numeric, _p2 numeric, _p3 numeric, _pool_size int DEFAULT 4, _qualifiers_per_pool int DEFAULT 2,
  _max_concurrent int DEFAULT 8, _lobby_minutes int DEFAULT 5, _description text DEFAULT NULL,
  _registration_closes_at timestamptz DEFAULT NULL, _starts_at timestamptz DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin uniquement'; END IF;
  IF _game_slug = 'domino' AND _players_per_match <> 2 THEN _players_per_match := 2; END IF;
  INSERT INTO public.tournaments(name, description, game_slug, format, players_per_match, max_players,
    entry_fee_ar, admin_prize_pool_ar, winners_count, prize_1_pct, prize_2_pct, prize_3_pct,
    pool_size, qualifiers_per_pool, max_concurrent_matches, lobby_minutes,
    registration_closes_at, starts_at, status, created_by)
  VALUES (_name, _description, _game_slug, _format, _players_per_match, _max_players,
    _entry_fee_ar, _admin_prize_pool_ar, _winners_count, _p1, _p2, _p3,
    _pool_size, _qualifiers_per_pool, _max_concurrent, _lobby_minutes,
    _registration_closes_at, _starts_at, 'open', auth.uid())
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;
GRANT EXECUTE ON FUNCTION public.admin_tournament_create(text,text,text,int,int,numeric,numeric,int,numeric,numeric,numeric,int,int,int,int,text,timestamptz,timestamptz) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_tournament_add_bots(_tid uuid, _count int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE i int; v_n int;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin uniquement'; END IF;
  SELECT count(*) INTO v_n FROM public.tournament_entrants WHERE tournament_id = _tid;
  FOR i IN 1.._count LOOP
    INSERT INTO public.tournament_entrants(tournament_id, display_name, is_bot)
      VALUES (_tid, 'Bot ' || (v_n + i), true);
  END LOOP;
END $$;
GRANT EXECUTE ON FUNCTION public.admin_tournament_add_bots(uuid,int) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_tournament_start(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE t public.tournaments%ROWTYPE; ids uuid[];
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin uniquement'; END IF;
  SELECT * INTO t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF t.status <> 'open' THEN RAISE EXCEPTION 'Tournoi déjà lancé'; END IF;
  IF (SELECT count(*) FROM public.tournament_entrants WHERE tournament_id = _tid) < 2 THEN
    RAISE EXCEPTION 'Pas assez de joueurs';
  END IF;
  UPDATE public.tournaments SET status = 'running', started_at = now() WHERE id = _tid;
  IF t.format = 'pools' THEN
    PERFORM public._t_draw_pools(_tid);
  ELSE
    SELECT array_agg(id ORDER BY random()) INTO ids FROM public.tournament_entrants
     WHERE tournament_id = _tid AND status = 'active';
    PERFORM public._t_build_round(_tid, 1, ids);
  END IF;
  PERFORM public.tournament_engine(_tid);
END $$;
GRANT EXECUTE ON FUNCTION public.admin_tournament_start(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_tournament_set_status(_tid uuid, _status text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin uniquement'; END IF;
  IF _status NOT IN ('open','running','paused') THEN RAISE EXCEPTION 'statut invalide'; END IF;
  UPDATE public.tournaments SET status = _status WHERE id = _tid;
  IF _status = 'running' THEN PERFORM public.tournament_engine(_tid); END IF;
END $$;
GRANT EXECUTE ON FUNCTION public.admin_tournament_set_status(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_tournament_cancel(_tid uuid, _reason text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE t public.tournaments%ROWTYPE; r record;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin uniquement'; END IF;
  SELECT * INTO t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF t.status IN ('finished','cancelled') THEN RETURN; END IF;
  IF t.entry_fee_ar > 0 THEN
    FOR r IN SELECT * FROM public.tournament_entrants
              WHERE tournament_id = _tid AND user_id IS NOT NULL AND NOT is_bot LOOP
      PERFORM public.credit_user_balance(r.user_id, t.entry_fee_ar, 'tournament_refund', _tid,
        'Tournoi annulé: ' || t.name, '{}'::jsonb);
      PERFORM public._t_notify(r.id, '⚠️ Tournoi annulé',
        COALESCE(_reason, 'Votre inscription a été remboursée.'), '/tournaments');
    END LOOP;
  END IF;
  UPDATE public.tournament_matches SET status = 'cancelled'
   WHERE tournament_id = _tid AND status IN ('scheduled','running');
  UPDATE public.tournaments SET status = 'cancelled', finished_at = now() WHERE id = _tid;
END $$;
GRANT EXECUTE ON FUNCTION public.admin_tournament_cancel(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_tournament_delete(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin uniquement'; END IF;
  PERFORM public.admin_tournament_cancel(_tid, 'Tournoi supprimé');
  DELETE FROM public.tournaments WHERE id = _tid;
END $$;
GRANT EXECUTE ON FUNCTION public.admin_tournament_delete(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_tournament_force_winner(_match_id uuid, _entrant_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE m public.tournament_matches%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin uniquement'; END IF;
  SELECT * INTO m FROM public.tournament_matches WHERE id = _match_id;
  IF m.game_id IS NOT NULL THEN
    UPDATE public.ludo_games SET status = 'cancelled', finished_at = now() WHERE id = m.game_id AND status <> 'finished';
    UPDATE public.domino_games SET status = 'cancelled', finished_at = now() WHERE id = m.game_id AND status <> 'finished';
  END IF;
  PERFORM public._t_match_finish(_match_id, _entrant_id);
  PERFORM public.tournament_engine(m.tournament_id);
END $$;
GRANT EXECUTE ON FUNCTION public.admin_tournament_force_winner(uuid,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_tournament_next_stage(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_auto boolean;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin uniquement'; END IF;
  SELECT auto_advance INTO v_auto FROM public.tournaments WHERE id = _tid;
  UPDATE public.tournaments SET auto_advance = true WHERE id = _tid;
  PERFORM public.tournament_engine(_tid);
  UPDATE public.tournaments SET auto_advance = v_auto WHERE id = _tid;
END $$;
GRANT EXECUTE ON FUNCTION public.admin_tournament_next_stage(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_tournament_set_auto(_tid uuid, _auto boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin uniquement'; END IF;
  UPDATE public.tournaments SET auto_advance = _auto WHERE id = _tid;
END $$;
GRANT EXECUTE ON FUNCTION public.admin_tournament_set_auto(uuid,boolean) TO authenticated;

-- ============================================================
-- CRON
-- ============================================================
DO $$
DECLARE j bigint;
BEGIN
  FOR j IN SELECT jobid FROM cron.job WHERE jobname IN ('tournament_pump_all','tournament_tick','tournament_engine_all') LOOP
    PERFORM cron.unschedule(j);
  END LOOP;
  PERFORM cron.schedule('tournament_engine_all', '15 seconds', $q$SELECT public.tournament_engine_all();$q$);
EXCEPTION WHEN OTHERS THEN NULL;
END $$;