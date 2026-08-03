-- ============================================================
-- FIX TOURNOI LUDO — 5 corrections
-- 1. Nettoyer les données orphelines
-- 2. Corriger _t_draw_pools (bug variable de boucle)
-- 3. Ajouter trigger ludo_games → tournament_matches
-- 4. Corriger le ranking (rangs uniques)
-- 5. Gérer les matches sans gagnant (timeout)
-- ============================================================

-- ═══════════════════════════════════════════════════════════
-- 1. NETTOYAGE des données orphelines
-- ═══════════════════════════════════════════════════════════
DELETE FROM public.tournament_matches
  WHERE tournament_id NOT IN (SELECT id FROM public.tournaments);

DELETE FROM public.tournament_pool_entrants
  WHERE pool_id NOT IN (SELECT id FROM public.tournament_pools);

DELETE FROM public.tournament_pool_entrants
  WHERE entrant_id NOT IN (SELECT id FROM public.tournament_entrants);

DELETE FROM public.tournament_entrants
  WHERE tournament_id NOT IN (SELECT id FROM public.tournaments);

-- ═══════════════════════════════════════════════════════════
-- 2. CORRECTION de _t_draw_pools (bug: variable i écrasée)
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._t_draw_pools(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  t public.tournaments%ROWTYPE;
  ids uuid[];
  n int;
  pos int := 1;
  k int := 0;
  v_pool uuid;
  v_size int;
  v_rest int;
  v_take int;
  v_mno int;
  a int;
  b int;
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid;
  SELECT array_agg(id ORDER BY random()) INTO ids
    FROM public.tournament_entrants WHERE tournament_id = _tid AND status = 'active';
  n := COALESCE(array_length(ids, 1), 0);
  IF n < 2 THEN RETURN; END IF;

  WHILE pos <= n LOOP
    v_rest := n - pos + 1;
    v_take := LEAST(t.pool_size, v_rest);
    IF v_rest - v_take = 1 THEN v_take := v_take - 1; END IF;
    IF v_take < 2 THEN v_take := v_rest; END IF;

    k := k + 1;
    INSERT INTO public.tournament_pools(tournament_id, label, status)
      VALUES (_tid, 'Poule ' || chr(64 + k), 'running')
      RETURNING id INTO v_pool;

    INSERT INTO public.tournament_pool_entrants(pool_id, entrant_id)
      SELECT v_pool, ids[pos + g - 1] FROM generate_series(1, v_take) g;

    v_mno := 0;
    IF t.players_per_match = 2 THEN
      -- Round-robin: chaque joueur joue contre tous les autres de sa poule
      FOR a IN 1..v_take-1 LOOP
        FOR b IN a+1..v_take LOOP
          v_mno := v_mno + 1;
          INSERT INTO public.tournament_matches(tournament_id, pool_id, phase, round, match_no, entrant_ids)
            VALUES (_tid, v_pool, 'pool', 1, v_mno, ARRAY[ids[pos + a - 1], ids[pos + b - 1]]);
        END LOOP;
      END LOOP;
    ELSE
      -- Match unique avec tous les joueurs de la poule
      INSERT INTO public.tournament_matches(tournament_id, pool_id, phase, round, match_no, entrant_ids)
        VALUES (_tid, v_pool, 'pool', 1, k,
          (SELECT array_agg(ids[pos + g - 1]) FROM generate_series(1, v_take) g));
    END IF;

    pos := pos + v_take;
  END LOOP;

  UPDATE public.tournaments SET stage = 'pools', current_round = 1 WHERE id = _tid;
END $$;

-- ═══════════════════════════════════════════════════════════
-- 3. TRIGGER ludo_games → tournament_matches
--    Quand une partie Ludo liée à un tournoi se termine,
--    mettre à jour automatiquement le match correspondant
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._t_ludo_on_finish()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  m public.tournament_matches%ROWTYPE;
  v_winner_entrant uuid;
  v_slot int;
  v_finish_ranks int[];
  v_entrant uuid;
  i int;
BEGIN
  IF NEW.status <> 'finished' OR OLD.status = 'finished' THEN RETURN NEW; END IF;
  IF NEW.tournament_match_id IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO m FROM public.tournament_matches
   WHERE id = NEW.tournament_match_id FOR UPDATE;
  IF m.id IS NULL OR m.status = 'finished' THEN RETURN NEW; END IF;

  -- Trouver le gagnant: slot du joueur gagnant → entrant correspondant
  IF NEW.winner_id IS NOT NULL THEN
    SELECT slot INTO v_slot FROM public.ludo_participants
     WHERE game_id = NEW.id AND user_id = NEW.winner_id LIMIT 1;
  ELSE
    -- Si pas de winner_id, prendre finish_rank = 1
    SELECT slot INTO v_slot FROM public.ludo_participants
     WHERE game_id = NEW.id AND finish_rank = 1 LIMIT 1;
  END IF;

  v_winner_entrant := m.entrant_ids[COALESCE(v_slot, 0) + 1];

  -- Mettre à jour le match
  UPDATE public.tournament_matches
    SET status = 'finished',
        winner_entrant_id = v_winner_entrant,
        game_id = NEW.id,
        finished_at = now()
   WHERE id = m.id;

  -- Mettre à jour les stats de poule si applicable
  IF m.phase = 'pool' AND m.pool_id IS NOT NULL THEN
    UPDATE public.tournament_pool_entrants SET played = played + 1
      WHERE pool_id = m.pool_id AND entrant_id = ANY(m.entrant_ids);
    IF v_winner_entrant IS NOT NULL THEN
      UPDATE public.tournament_pool_entrants
        SET wins = wins + 1, points = points + 3
       WHERE pool_id = m.pool_id AND entrant_id = v_winner_entrant;
    END IF;
  ELSE
    -- Éliminer les perdants en phase finale
    FOREACH v_entrant IN ARRAY m.entrant_ids LOOP
      IF v_entrant <> v_winner_entrant THEN
        UPDATE public.tournament_entrants
          SET status = 'eliminated', eliminated_round = m.round
         WHERE id = v_entrant AND status = 'active';
      END IF;
    END LOOP;
  END IF;

  -- Notifier les joueurs
  FOREACH v_entrant IN ARRAY m.entrant_ids LOOP
    IF v_entrant = v_winner_entrant THEN
      PERFORM public._t_notify(v_entrant, '✅ Match gagné',
        'Vous passez à la suite du tournoi.', '/tournaments/' || m.tournament_id);
    ELSE
      PERFORM public._t_notify(v_entrant, '❌ Match perdu',
        'Merci d''avoir participé.', '/tournaments/' || m.tournament_id);
    END IF;
  END LOOP;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_tournament_ludo_finish ON public.ludo_games;
CREATE TRIGGER trg_tournament_ludo_finish
  AFTER UPDATE ON public.ludo_games
  FOR EACH ROW EXECUTE FUNCTION public._t_ludo_on_finish();

-- ═══════════════════════════════════════════════════════════
-- 3b. Idem pour domino_games
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._t_domino_on_finish()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  m public.tournament_matches%ROWTYPE;
  v_winner_entrant uuid;
  v_slot int;
  v_entrant uuid;
BEGIN
  IF NEW.status <> 'finished' OR OLD.status = 'finished' THEN RETURN NEW; END IF;
  IF NEW.tournament_match_id IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO m FROM public.tournament_matches
   WHERE id = NEW.tournament_match_id FOR UPDATE;
  IF m.id IS NULL OR m.status = 'finished' THEN RETURN NEW; END IF;

  IF NEW.winner_id IS NOT NULL THEN
    SELECT slot INTO v_slot FROM public.domino_participants
     WHERE game_id = NEW.id AND user_id = NEW.winner_id LIMIT 1;
  ELSE
    SELECT slot INTO v_slot FROM public.domino_participants
     WHERE game_id = NEW.id AND is_bot = true LIMIT 1;
  END IF;

  v_winner_entrant := m.entrant_ids[COALESCE(v_slot, 0) + 1];

  UPDATE public.tournament_matches
    SET status = 'finished', winner_entrant_id = v_winner_entrant,
        game_id = NEW.id, finished_at = now()
   WHERE id = m.id;

  IF m.phase = 'pool' AND m.pool_id IS NOT NULL THEN
    UPDATE public.tournament_pool_entrants SET played = played + 1
      WHERE pool_id = m.pool_id AND entrant_id = ANY(m.entrant_ids);
    IF v_winner_entrant IS NOT NULL THEN
      UPDATE public.tournament_pool_entrants
        SET wins = wins + 1, points = points + 3
       WHERE pool_id = m.pool_id AND entrant_id = v_winner_entrant;
    END IF;
  ELSE
    FOREACH v_entrant IN ARRAY m.entrant_ids LOOP
      IF v_entrant <> v_winner_entrant THEN
        UPDATE public.tournament_entrants
          SET status = 'eliminated', eliminated_round = m.round
         WHERE id = v_entrant AND status = 'active';
      END IF;
    END LOOP;
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_tournament_domino_finish ON public.domino_games;
CREATE TRIGGER trg_tournament_domino_finish
  AFTER UPDATE ON public.domino_games
  FOR EACH ROW EXECUTE FUNCTION public._t_domino_on_finish();

-- ═══════════════════════════════════════════════════════════
-- 4. CORRECTION du ranking (rangs uniques par tournoi)
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._t_finish(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  t public.tournaments%ROWTYPE;
  v_net numeric;
  v_pcts numeric[];
  r record;
  i int := 0;
  v_amt numeric;
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF t.id IS NULL OR t.status IN ('finished','cancelled') THEN RETURN; END IF;

  -- Champion = rang 1
  UPDATE public.tournament_entrants SET final_rank = 1
   WHERE id = t.champion_entrant_id AND tournament_id = _tid;

  -- Rangs uniques pour les autres (2, 3, 4...) par tournoi
  WITH ranked AS (
    SELECT id,
           row_number() OVER (
             ORDER BY COALESCE(eliminated_round, 0) DESC NULLS LAST,
                      created_at
           ) + 1 AS rk
    FROM public.tournament_entrants
    WHERE tournament_id = _tid
      AND id IS DISTINCT FROM t.champion_entrant_id
  )
  UPDATE public.tournament_entrants e
    SET final_rank = ranked.rk
   FROM ranked
  WHERE e.id = ranked.id AND e.tournament_id = _tid;

  -- Petite finale → 3e place
  UPDATE public.tournament_entrants e SET final_rank = 3
   FROM public.tournament_matches m
  WHERE m.tournament_id = _tid AND m.phase = 'third_place'
    AND m.status = 'finished' AND e.id = m.winner_entrant_id
    AND e.tournament_id = _tid;

  -- Distribution des gains
  v_net := round(t.prize_pool_ar * (100 - t.platform_pct) / 100) + t.admin_prize_pool_ar;
  v_pcts := ARRAY[t.prize_1_pct, t.prize_2_pct, t.prize_3_pct];

  FOR r IN SELECT * FROM public.tournament_entrants
            WHERE tournament_id = _tid AND final_rank IS NOT NULL
              AND final_rank <= t.winners_count
            ORDER BY final_rank LOOP
    i := r.final_rank;
    v_amt := round(v_net * COALESCE(v_pcts[i], 0) / 100);
    IF v_amt > 0 AND r.user_id IS NOT NULL AND NOT r.is_bot THEN
      PERFORM public.credit_user_balance(r.user_id, v_amt, 'tournament_prize', _tid,
        'Récompense tournoi: ' || t.name, jsonb_build_object('rank', i));
    END IF;
    PERFORM public._t_notify(r.id, '🏆 Tournoi terminé',
      'Vous terminez ' || i || 'e. Gain : ' || v_amt || ' Ar',
      '/tournaments/' || _tid);
  END LOOP;

  UPDATE public.tournaments
    SET status = 'finished', stage = 'done', finished_at = now()
   WHERE id = _tid;
END $$;

-- ═══════════════════════════════════════════════════════════
-- 5. GESTION des matches sans gagnant (timeout + disqualification)
-- ═══════════════════════════════════════════════════════════

-- Fonction: forfait automatique si deadline dépassée
CREATE OR REPLACE FUNCTION public._t_handle_expired_matches(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  m record;
  v_ready_slot int;
  v_winner uuid;
  v_game text;
  v_table text;
BEGIN
  SELECT game_slug INTO v_game FROM public.tournaments WHERE id = _tid;
  v_table := CASE WHEN v_game = 'ludo' THEN 'ludo_games' ELSE 'domino_games' END;

  FOR m IN SELECT * FROM public.tournament_matches
            WHERE tournament_id = _tid
              AND status = 'running'
              AND deadline_at IS NOT NULL
              AND deadline_at < now()
              AND game_id IS NOT NULL LOOP
    BEGIN
      -- Vérifier si la partie est toujours en cours
      EXECUTE format('SELECT status FROM public.%I WHERE id = $1', v_table)
        INTO v_game USING m.game_id;

      IF v_game = 'open' THEN
        -- Salle d'attente expirée: le joueur prêt (ou bot) gagne
        IF m.tournament_id IN (SELECT id FROM public.tournaments WHERE game_slug = 'ludo') THEN
          SELECT slot INTO v_ready_slot FROM public.ludo_participants
           WHERE game_id = m.game_id AND (ready OR is_bot) ORDER BY slot LIMIT 1;
        ELSE
          SELECT slot INTO v_ready_slot FROM public.domino_participants
           WHERE game_id = m.game_id AND (ready OR is_bot) ORDER BY slot LIMIT 1;
        END IF;

        v_winner := m.entrant_ids[COALESCE(v_ready_slot, 0) + 1];

        -- Annuler la partie
        IF m.tournament_id IN (SELECT id FROM public.tournaments WHERE game_slug = 'ludo') THEN
          UPDATE public.ludo_games SET status = 'cancelled', finished_at = now()
           WHERE id = m.game_id;
        ELSE
          UPDATE public.domino_games SET status = 'cancelled', finished_at = now()
           WHERE id = m.game_id;
        END IF;

        -- Déclarer le gagnant
        PERFORM public._t_match_finish(m.id, v_winner);
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;

  -- Matches scheduled sans game_id depuis trop longtemps → relancer
  FOR m IN SELECT * FROM public.tournament_matches
            WHERE tournament_id = _tid
              AND status = 'scheduled'
              AND game_id IS NULL LOOP
    PERFORM public._t_launch_match(m.id);
  END LOOP;
END $$;

-- ═══════════════════════════════════════════════════════════
-- 5b. Intégrer le handler dans tournament_engine
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.tournament_engine(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  t public.tournaments%ROWTYPE;
  m record; g record; v_win uuid; v_slot int; v_busy uuid[]; v_live int;
  v_pool record; v_next uuid[]; v_losers uuid[]; v_ready int; v_total int;
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF t.id IS NULL OR t.status <> 'running' THEN RETURN; END IF;

  -- 0) Gérer les matches expirés
  PERFORM public._t_handle_expired_matches(_tid);

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

-- ═══════════════════════════════════════════════════════════
-- 6. FONCTION: créer un tournoi de test avec bots + humains
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.admin_tournament_create(
  _name text,
  _description text DEFAULT NULL,
  _game_slug text DEFAULT 'ludo',
  _format text DEFAULT 'pools',
  _players_per_match int DEFAULT 2,
  _pool_size int DEFAULT 4,
  _qualifiers_per_pool int DEFAULT 2,
  _max_players int DEFAULT 32,
  _entry_fee_ar numeric DEFAULT 0,
  _admin_prize_pool_ar numeric DEFAULT 0,
  _platform_pct numeric DEFAULT 10,
  _winners_count int DEFAULT 3,
  _prize_1_pct numeric DEFAULT 50,
  _prize_2_pct numeric DEFAULT 30,
  _prize_3_pct numeric DEFAULT 20,
  _lobby_minutes int DEFAULT 5,
  _max_concurrent_matches int DEFAULT 8,
  _fill_with_bots boolean DEFAULT true,
  _auto_advance boolean DEFAULT true
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_tid uuid;
  v_uid uuid := auth.uid();
  v_is_admin boolean;
  v_name text;
  i int;
  v_bots_needed int;
  v_human_count int;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  -- Créer le tournoi
  INSERT INTO public.tournaments(
    name, description, game_slug, format, players_per_match, pool_size,
    qualifiers_per_pool, max_players, entry_fee_ar, prize_pool_ar,
    admin_prize_pool_ar, platform_pct, winners_count,
    prize_1_pct, prize_2_pct, prize_3_pct,
    max_concurrent_matches, lobby_minutes, auto_advance,
    status, stage, created_by
  )
  VALUES(
    _name, _description, _game_slug, _format, _players_per_match, _pool_size,
    _qualifiers_per_pool, _max_players, _entry_fee_ar, 0,
    _admin_prize_pool_ar, _platform_pct, _winners_count,
    _prize_1_pct, _prize_2_pct, _prize_3_pct,
    _max_concurrent_matches, _lobby_minutes, _auto_advance,
    'open', 'registration', v_uid
  )
  RETURNING id INTO v_tid;

  -- Remplir avec des bots si demandé
  IF _fill_with_bots THEN
    SELECT count(*) INTO v_human_count FROM public.tournament_entrants WHERE tournament_id = v_tid;
    v_bots_needed := _max_players - v_human_count;
    FOR i IN 1..v_bots_needed LOOP
      INSERT INTO public.tournament_entrants(tournament_id, display_name, is_bot)
        VALUES (v_tid, 'Bot ' || i, true);
    END LOOP;
  END IF;

  -- Logger
  INSERT INTO public.admin_logs(admin_id, action, target_id, new_value)
    VALUES (v_uid, 'tournament_create', v_tid,
      jsonb_build_object('name', _name, 'game', _game_slug, 'format', _format,
        'max_players', _max_players, 'fill_bots', _fill_with_bots));

  RETURN v_tid;
END $$;
GRANT EXECUTE ON FUNCTION public.admin_tournament_create(text,text,text,text,int,int,int,int,numeric,numeric,numeric,int,numeric,numeric,numeric,int,int,boolean,boolean)
  TO authenticated;

-- ═══════════════════════════════════════════════════════════
-- 7. Ajouter tournament_match_id à ludo_games si manquant
-- ═══════════════════════════════════════════════════════════
ALTER TABLE public.ludo_games
  ADD COLUMN IF NOT EXISTS tournament_match_id uuid
    REFERENCES public.tournament_matches(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_ludo_games_tournament
  ON public.ludo_games(tournament_match_id)
  WHERE tournament_match_id IS NOT NULL;

-- ═══════════════════════════════════════════════════════════
-- 8. CRON: s'assurer que le moteur tourne toutes les 15s
-- ═══════════════════════════════════════════════════════════
DO $$
DECLARE j bigint;
BEGIN
  FOR j IN SELECT jobid FROM cron.job WHERE jobname IN ('tournament_engine_all','tournament_pump_all','tournament_tick') LOOP
    PERFORM cron.unschedule(j);
  END LOOP;
  PERFORM cron.schedule('tournament_engine_all', '15 seconds', $q$SELECT public.tournament_engine_all();$q$);
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
