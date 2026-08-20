-- ═══════════════════════════════════════════════════════════════════════════
-- TOURNOI 1v1 — SUPPORT COMPLET: Ludo, Domino (direct + par point),
--                                 Fanorona, Échecs, Rami
--
-- Fix:
-- 1. tournament_register utilisait tournament_registrations (table inexistante)
-- 2. tournament_engine avait un TODO — ne créait aucune partie
-- 3. Fonctions manquantes: poll_tournament_engine, tournament_check_in, etc.
-- 4. admin_tournament_create n'acceptait pas les paramètres du frontend
-- 5. Pas de trigger pour détecter la fin d'une partie de tournoi (sauf Ludo cassé)
-- 6. tournament_mark_ready utilisait player_ids (colonne inexistante)
-- 7. _t_build_round ne gérait pas les byes
-- 8. _t_match_finish éliminait tout le monde en cas de draw
-- ═══════════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────────
-- 1. SCHÉMA: ajouter tournament_match_id aux tables de jeu qui n'en ont pas
-- ───────────────────────────────────────────────────────────────────────────
ALTER TABLE public.domino_games ADD COLUMN IF NOT EXISTS tournament_match_id uuid;
ALTER TABLE public.fanorona_games ADD COLUMN IF NOT EXISTS tournament_match_id uuid;
ALTER TABLE public.chess_games ADD COLUMN IF NOT EXISTS tournament_match_id uuid;

-- ───────────────────────────────────────────────────────────────────────────
-- 2. admin_tournament_create — accepter tous les paramètres du frontend
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_tournament_create(
  _name text, _game_slug text, _format text, _players_per_match integer,
  _max_players integer, _entry_fee_ar numeric, _admin_prize_pool_ar numeric,
  _winners_count integer, _p1 numeric, _p2 numeric, _p3 numeric,
  _pool_size integer DEFAULT 4, _qualifiers_per_pool integer DEFAULT 2,
  _max_concurrent integer DEFAULT 8, _lobby_minutes integer DEFAULT 5,
  _description text DEFAULT NULL,
  _registration_closes_at timestamptz DEFAULT NULL,
  _starts_at timestamptz DEFAULT NULL,
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
AS $function$
DECLARE v_id uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin uniquement'; END IF;
  IF _game_slug = 'domino' AND _players_per_match <> 2 THEN _players_per_match := 2; END IF;
  INSERT INTO public.tournaments(name, description, game_slug, format, players_per_match, max_players,
    entry_fee_ar, admin_prize_pool_ar, winners_count, prize_1_pct, prize_2_pct, prize_3_pct, prize_4_pct,
    pool_size, qualifiers_per_pool, max_concurrent_matches, lobby_minutes,
    registration_closes_at, starts_at, status, created_by,
    break_seconds, batch_gap_seconds, max_match_duration_secs, check_in_minutes,
    domino_scoring, target_score)
  VALUES (_name, _description, _game_slug, _format, _players_per_match, _max_players,
    _entry_fee_ar, _admin_prize_pool_ar, _winners_count, _p1, _p2, _p3, _prize_4_pct,
    _pool_size, _qualifiers_per_pool, _max_concurrent, _lobby_minutes,
    _registration_closes_at, _starts_at, 'open', auth.uid(),
    _break_seconds, _batch_gap_seconds, _max_match_duration_secs, _check_in_minutes,
    _domino_scoring, _target_score)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_tournament_create(text,text,text,integer,integer,numeric,numeric,integer,numeric,numeric,numeric,integer,integer,integer,integer,text,timestamptz,timestamptz,integer,integer,integer,integer,numeric,text,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_tournament_create(text,text,text,integer,integer,numeric,numeric,integer,numeric,numeric,numeric,integer,integer,integer,integer,text,timestamptz,timestamptz,integer,integer,integer,integer,numeric,text,integer) TO authenticated;

-- ───────────────────────────────────────────────────────────────────────────
-- 3. tournament_register — utiliser tournament_entrants (pas tournament_registrations)
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.tournament_register(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid  uuid := auth.uid();
  trn    record;
  v_bal  numeric;
  v_name text;
  v_cnt  int;
BEGIN
  SELECT * INTO trn FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;
  IF trn.status <> 'open' THEN RAISE EXCEPTION 'Les inscriptions sont closes'; END IF;

  IF trn.registration_opens_at IS NOT NULL AND now() < trn.registration_opens_at THEN
    RAISE EXCEPTION 'Les inscriptions ne sont pas encore ouvertes';
  END IF;
  IF trn.registration_closes_at IS NOT NULL AND now() > trn.registration_closes_at THEN
    RAISE EXCEPTION 'Les inscriptions sont fermées';
  END IF;

  SELECT count(*) INTO v_cnt FROM public.tournament_entrants WHERE tournament_id = _tid;
  IF v_cnt >= trn.max_players THEN RAISE EXCEPTION 'Le tournoi est complet'; END IF;

  IF EXISTS (SELECT 1 FROM public.tournament_entrants WHERE tournament_id = _tid AND user_id = v_uid) THEN
    RAISE EXCEPTION 'Déjà inscrit';
  END IF;

  -- Prélever les frais si tournoi payant
  IF NOT COALESCE(trn.is_free, false) AND trn.entry_fee_ar > 0 THEN
    SELECT balance_ar INTO v_bal FROM public.profiles WHERE id = v_uid FOR UPDATE;
    IF v_bal < trn.entry_fee_ar THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
    UPDATE public.profiles SET balance_ar = balance_ar - trn.entry_fee_ar WHERE id = v_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'tournament_entry', -trn.entry_fee_ar, _tid, 'Inscription tournoi: ' || trn.name);
    UPDATE public.tournaments SET prize_pool_ar = COALESCE(prize_pool_ar, 0) + trn.entry_fee_ar WHERE id = _tid;
  END IF;

  SELECT pseudo INTO v_name FROM public.profiles WHERE id = v_uid;
  INSERT INTO public.tournament_entrants(tournament_id, user_id, display_name, is_bot, status, checked_in)
    VALUES (_tid, v_uid, COALESCE(v_name, 'Joueur'), false, 'active', false);
END;
$function$;

REVOKE ALL ON FUNCTION public.tournament_register(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.tournament_register(uuid) TO authenticated;

-- ───────────────────────────────────────────────────────────────────────────
-- 4. _t_build_round — gérer les byes correctement
-- ───────────────────────────────────────────────────────────────────────────
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
    UPDATE public.tournaments SET champion_entrant_id = _ids[1], status = 'finished', finished_at = now() WHERE id = _tid;
    PERFORM public._t_finish(_tid);
    RETURN;
  END IF;

  WHILE i <= n LOOP
    v_rest := n - i + 1;
    v_take := LEAST(2, v_rest);

    IF v_rest = 3 THEN
      IF t.game_slug = 'ludo' THEN v_take := 3;
      ELSE v_take := 2; END IF;
    END IF;

    IF v_rest = 1 THEN
      -- Bye: le joueur passe automatiquement
      v_mno := v_mno + 1;
      INSERT INTO public.tournament_matches(tournament_id, phase, round, match_no, entrant_ids, status, is_bye, winner_entrant_id, finished_at)
        VALUES (_tid, 'final', _round, v_mno, ARRAY[_ids[i]], 'finished', true, _ids[i], now());
      i := i + 1;
      CONTINUE;
    END IF;

    v_mno := v_mno + 1;
    INSERT INTO public.tournament_matches(tournament_id, phase, round, match_no, entrant_ids)
      VALUES (_tid, 'final', _round, v_mno, (SELECT array_agg(_ids[j]) FROM generate_series(i, i + v_take - 1) j));
    i := i + v_take;
  END LOOP;

  UPDATE public.tournaments SET stage = 'finals', current_round = _round WHERE id = _tid;
END $function$;

-- ───────────────────────────────────────────────────────────────────────────
-- 5. _t_match_finish — ne pas éliminer tout le monde en cas de draw
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._t_match_finish(_match_id uuid, _winner uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE m public.tournament_matches%ROWTYPE; e uuid;
BEGIN
  SELECT * INTO m FROM public.tournament_matches WHERE id = _match_id FOR UPDATE;
  IF m.id IS NULL OR m.status = 'finished' THEN RETURN; END IF;

  UPDATE public.tournament_matches
     SET status = 'finished', winner_entrant_id = _winner, finished_at = now()
   WHERE id = _match_id;

  IF m.phase = 'pool' AND m.pool_id IS NOT NULL THEN
    PERFORM public._t_pool_recompute(m.pool_id);
  ELSIF _winner IS NOT NULL THEN
    -- Éliminer les perdants seulement si on a un gagnant
    FOREACH e IN ARRAY m.entrant_ids LOOP
      IF e <> _winner THEN
        UPDATE public.tournament_entrants
           SET status = 'eliminated', eliminated_round = m.round
         WHERE id = e AND status = 'active';
      END IF;
    END LOOP;
  END IF;
  -- Si _winner est NULL (draw en knockout): personne n'est éliminé,
  -- l'admin peut utiliser admin_tournament_force_winner pour résoudre

  FOREACH e IN ARRAY m.entrant_ids LOOP
    IF _winner IS NOT NULL AND e = _winner THEN
      PERFORM public._t_notify(e, '✅ Match gagné', 'Vous passez à la suite du tournoi.', '/tournaments/' || m.tournament_id);
    ELSIF _winner IS NULL THEN
      PERFORM public._t_notify(e, '🤝 Match nul', 'Le match se termine sans vainqueur — en attente de résolution.', '/tournaments/' || m.tournament_id);
    ELSE
      PERFORM public._t_notify(e, '❌ Match perdu', 'Merci d''avoir participé.', '/tournaments/' || m.tournament_id);
    END IF;
  END LOOP;
END $function$;

-- ───────────────────────────────────────────────────────────────────────────
-- 6. _t_create_game — créer la partie selon le game_slug
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._t_create_game(_match_id uuid, _game_slug text, _tid uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  m record;
  t record;
  v_game_id uuid;
  v_p1_uid uuid; v_p2_uid uuid;
  v_p1_name text; v_p2_name text;
  v_p1_bot boolean; v_p2_bot boolean;
  v_mode text;
  v_target int;
  v_join_deadline timestamptz;
BEGIN
  SELECT * INTO m FROM public.tournament_matches WHERE id = _match_id FOR UPDATE;
  SELECT * INTO t FROM public.tournaments WHERE id = _tid;

  -- Récupérer les infos des entrants (arrays PostgreSQL sont 1-indexed)
  SELECT user_id, display_name, is_bot INTO v_p1_uid, v_p1_name, v_p1_bot
    FROM public.tournament_entrants WHERE id = m.entrant_ids[1];
  SELECT user_id, display_name, is_bot INTO v_p2_uid, v_p2_name, v_p2_bot
    FROM public.tournament_entrants WHERE id = m.entrant_ids[2];

  v_mode := CASE WHEN t.domino_scoring = 'points' THEN 'par_point' ELSE 'classic' END;
  v_target := t.target_score;
  v_join_deadline := now() + COALESCE(t.join_timeout_secs, 240) * interval '1 second';

  IF _game_slug = 'domino' THEN
    INSERT INTO public.domino_games (host_id, max_players, stake, pot, commission_pct,
      is_private, mode, status, target_score, tournament_match_id, first_tile_rule)
    VALUES (v_p1_uid, 2, 0, 0, 0, true, v_mode, 'open'::game_status,
      CASE WHEN v_mode = 'par_point' THEN v_target ELSE 0 END, _match_id, 'libre')
    RETURNING id INTO v_game_id;

    INSERT INTO public.domino_participants (game_id, user_id, slot, display_name, is_bot, ready)
    VALUES (v_game_id, v_p1_uid, 0, v_p1_name, v_p1_bot, true),
           (v_game_id, v_p2_uid, 1, v_p2_name, v_p2_bot, true);

  ELSIF _game_slug = 'ludo' THEN
    INSERT INTO public.ludo_games (host_id, max_players, stake, pot, commission_pct,
      is_private, mode, status, tournament_match_id)
    VALUES (v_p1_uid, 2, 0, 0, 0, true, 'classic', 'open'::game_status, _match_id)
    RETURNING id INTO v_game_id;

    INSERT INTO public.ludo_participants (game_id, user_id, slot, color, display_name, is_bot, ready)
    VALUES (v_game_id, v_p1_uid, 0, 'red', v_p1_name, v_p1_bot, true),
           (v_game_id, v_p2_uid, 1, 'blue', v_p2_name, v_p2_bot, true);

  ELSIF _game_slug = 'fanorona' THEN
    INSERT INTO public.fanorona_games (host_id, max_players, stake, pot, commission_pct,
      is_private, status, tournament_match_id, variant, mandatory_capture, time_control_min)
    VALUES (v_p1_uid, 2, 0, 0, 0, true, 'open'::game_status, _match_id, 'tsivy', true, 10)
    RETURNING id INTO v_game_id;

    INSERT INTO public.fanorona_participants (game_id, user_id, slot, display_name, is_bot, color, ready)
    VALUES (v_game_id, v_p1_uid, 0, v_p1_name, v_p1_bot, 'white', true),
           (v_game_id, v_p2_uid, 1, v_p2_name, v_p2_bot, 'black', true);

  ELSIF _game_slug = 'chess' THEN
    INSERT INTO public.chess_games (host_id, white_id, black_id, status, stake, pot,
      commission_pct, is_private, turn, tournament_match_id, time_control_min,
      white_is_bot, black_is_bot, ready_white, ready_black)
    VALUES (v_p1_uid, v_p1_uid, v_p2_uid, 'open'::game_status, 0, 0, 0, true, 'white',
      _match_id, 10, v_p1_bot, v_p2_bot, true, true)
    RETURNING id INTO v_game_id;

  ELSIF _game_slug = 'rami' THEN
    INSERT INTO public.rami_games (created_by, max_players, stake, pot, commission_pct,
      is_private, status, tournament_match_id, game_mode, joker_mode, seven_cards)
    VALUES (v_p1_uid, 2, 0, 0, 0, true, 'open', _match_id, 'bordel', 'classique', true)
    RETURNING id INTO v_game_id;

    INSERT INTO public.rami_participants (game_id, user_id, slot, display_name, is_bot, ready)
    VALUES (v_game_id, v_p1_uid, 0, v_p1_name, v_p1_bot, true),
           (v_game_id, v_p2_uid, 1, v_p2_name, v_p2_bot, true);
  ELSE
    RAISE EXCEPTION 'Jeu non supporté: %', _game_slug;
  END IF;

  RETURN v_game_id;
END;
$function$;

-- ───────────────────────────────────────────────────────────────────────────
-- 7. _t_advance_from_pools — calculer les qualifiés et créer le knockout
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._t_advance_from_pools(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  t public.tournaments%ROWTYPE;
  v_qualified uuid[];
  v_pool_id uuid;
  v_q int;
  rec record;
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid FOR UPDATE;

  -- Pour chaque poule, prendre les top N par points
  FOR v_pool_id IN SELECT id FROM public.tournament_pools WHERE tournament_id = _tid ORDER BY label LOOP
    v_q := t.qualifiers_per_pool;
    FOR rec IN
      SELECT pe.entrant_id
        FROM public.tournament_pool_entrants pe
        WHERE pe.pool_id = v_pool_id
        ORDER BY pe.points DESC, pe.wins DESC, pe.played ASC
        LIMIT v_q
    LOOP
      v_qualified := array_append(v_qualified, rec.entrant_id);
    END LOOP;
    UPDATE public.tournament_pools SET status = 'finished' WHERE id = v_pool_id;
  END LOOP;

  -- Mélanger les qualifiés et créer le bracket knockout
  SELECT array_agg(e ORDER BY random()) INTO v_qualified
    FROM unnest(v_qualified) AS e;

  IF array_length(v_qualified, 1) >= 2 THEN
    PERFORM public._t_build_round(_tid, 1, v_qualified);
  END IF;
END $function$;

-- ───────────────────────────────────────────────────────────────────────────
-- 8. tournament_engine — créer les parties et avancer les rounds
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.tournament_engine(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  t public.tournaments%ROWTYPE;
  m record;
  v_game_id uuid;
  v_pending int;
  v_winners uuid[];
  v_all_bots boolean;
  v_rand_win uuid;
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF t.id IS NULL OR t.status <> 'running' THEN RETURN; END IF;

  -- 1. Créer les parties pour les matchs en attente
  FOR m IN SELECT * FROM public.tournament_matches
            WHERE tournament_id = _tid AND status = 'scheduled'
            ORDER BY round ASC, match_no ASC LOOP

    -- Vérifier si tous les entrants sont des bots
    SELECT bool_and(is_bot) INTO v_all_bots
      FROM public.tournament_entrants WHERE id = ANY(m.entrant_ids);

    IF v_all_bots THEN
      -- Match bots uniquement: simuler le résultat
      v_rand_win := m.entrant_ids[1 + floor(random() * array_length(m.entrant_ids, 1))::int];
      PERFORM public._t_match_finish(m.id, v_rand_win);
    ELSE
      -- Créer la partie réelle
      v_game_id := public._t_create_game(m.id, t.game_slug, _tid);
      UPDATE public.tournament_matches
        SET status = 'running', game_id = v_game_id, started_at = now(),
            join_deadline = now() + COALESCE(t.join_timeout_secs, 240) * interval '1 second'
        WHERE id = m.id;
    END IF;
  END LOOP;

  -- 2. Vérifier si tous les matchs du tour actuel sont terminés
  SELECT count(*) INTO v_pending
    FROM public.tournament_matches
    WHERE tournament_id = _tid AND status IN ('scheduled', 'running');

  IF v_pending = 0 THEN
    -- Tous les matchs sont terminés, avancer
    IF t.format = 'pools' AND t.stage = 'pools' THEN
      -- Phase de poules terminée → créer le bracket knockout
      PERFORM public._t_advance_from_pools(_tid);
    ELSIF t.stage = 'finals' THEN
      -- Knockout: collecter les gagnants du tour actuel
      SELECT array_agg(winner_entrant_id ORDER BY match_no) INTO v_winners
        FROM public.tournament_matches
        WHERE tournament_id = _tid AND phase = 'final' AND round = t.current_round
          AND winner_entrant_id IS NOT NULL;

      IF v_winners IS NOT NULL AND array_length(v_winners, 1) >= 2 THEN
        PERFORM public._t_build_round(_tid, t.current_round + 1, v_winners);
        -- Créer les parties du nouveau tour
        PERFORM public.tournament_engine(_tid);
      ELSIF v_winners IS NOT NULL AND array_length(v_winners, 1) = 1 THEN
        -- Un seul gagnant: champion
        UPDATE public.tournaments
          SET champion_entrant_id = v_winners[1], status = 'finished', finished_at = now()
          WHERE id = _tid;
        PERFORM public._t_finish(_tid);
      END IF;
    END IF;
  END IF;
END $function$;

-- ───────────────────────────────────────────────────────────────────────────
-- 9. _t_on_game_finished — trigger appelé quand une partie de tournoi finit
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._t_on_game_finished()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_match_id uuid;
  v_winner_uid uuid;
  v_winner_entrant uuid;
  v_tid uuid;
  v_match_count int;
BEGIN
  IF NEW.status <> 'finished' THEN RETURN NEW; END IF;
  IF OLD.status = 'finished' THEN RETURN NEW; END IF;

  v_match_id := NEW.tournament_match_id;
  IF v_match_id IS NULL THEN RETURN NEW; END IF;

  -- Vérifier que le match existe et n'est pas déjà fini
  SELECT count(*) INTO v_match_count FROM public.tournament_matches
    WHERE id = v_match_id AND status NOT IN ('finished', 'cancelled');
  IF v_match_count = 0 THEN RETURN NEW; END IF;

  v_winner_uid := NEW.winner_id;

  IF v_winner_uid IS NOT NULL THEN
    -- Trouver l'entrant par user_id
    SELECT e.id INTO v_winner_entrant
      FROM public.tournament_entrants e
      WHERE e.tournament_id = (SELECT tournament_id FROM public.tournament_matches WHERE id = v_match_id)
        AND e.user_id = v_winner_uid
      LIMIT 1;
  ELSE
    -- Bot a gagné (winner_id NULL): trouver l'entrant bot dans le match
    SELECT e.id INTO v_winner_entrant
      FROM public.tournament_entrants e
      JOIN public.tournament_matches m ON m.tournament_id = e.tournament_id
      WHERE m.id = v_match_id AND e.is_bot = true AND e.id = ANY(m.entrant_ids)
      LIMIT 1;
  END IF;

  -- Terminer le match
  PERFORM public._t_match_finish(v_match_id, v_winner_entrant);

  -- Faire avancer le tournoi
  SELECT tournament_id INTO v_tid FROM public.tournament_matches WHERE id = v_match_id;
  IF v_tid IS NOT NULL THEN
    PERFORM public.tournament_engine(v_tid);
  END IF;

  RETURN NEW;
END $function$;

-- ───────────────────────────────────────────────────────────────────────────
-- 10. Créer les triggers pour chaque table de jeu
-- ───────────────────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_tournament_domino_finished ON public.domino_games;
CREATE TRIGGER trg_tournament_domino_finished
  AFTER UPDATE ON public.domino_games
  FOR EACH ROW EXECUTE FUNCTION public._t_on_game_finished();

DROP TRIGGER IF EXISTS trg_tournament_fanorona_finished ON public.fanorona_games;
CREATE TRIGGER trg_tournament_fanorona_finished
  AFTER UPDATE ON public.fanorona_games
  FOR EACH ROW EXECUTE FUNCTION public._t_on_game_finished();

DROP TRIGGER IF EXISTS trg_tournament_chess_finished ON public.chess_games;
CREATE TRIGGER trg_tournament_chess_finished
  AFTER UPDATE ON public.chess_games
  FOR EACH ROW EXECUTE FUNCTION public._t_on_game_finished();

DROP TRIGGER IF EXISTS trg_tournament_rami_finished ON public.rami_games;
CREATE TRIGGER trg_tournament_rami_finished
  AFTER UPDATE ON public.rami_games
  FOR EACH ROW EXECUTE FUNCTION public._t_on_game_finished();

-- Ludo: remplacer les anciens triggers cassés
DROP TRIGGER IF EXISTS trg_tournament_ludo_finished ON public.ludo_games;
CREATE TRIGGER trg_tournament_ludo_finished
  AFTER UPDATE ON public.ludo_games
  FOR EACH ROW EXECUTE FUNCTION public._t_on_game_finished();

-- ───────────────────────────────────────────────────────────────────────────
-- 11. Fonctions manquantes appelées par le frontend
-- ───────────────────────────────────────────────────────────────────────────

-- poll_tournament_engine: exécuter le moteur et retourner l'état
CREATE OR REPLACE FUNCTION public.poll_tournament_engine(_tid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.tournament_engine(_tid);
  RETURN public.tournament_state(_tid);
END;
$function$;
REVOKE ALL ON FUNCTION public.poll_tournament_engine(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.poll_tournament_engine(uuid) TO authenticated;

-- tournament_check_in: joueur fait son check-in
CREATE OR REPLACE FUNCTION public.tournament_check_in(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.tournaments WHERE id = _tid AND check_in_opened_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Le check-in n''est pas ouvert';
  END IF;
  UPDATE public.tournament_entrants
    SET checked_in = true, check_in_at = now()
    WHERE tournament_id = _tid AND user_id = v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Non inscrit'; END IF;
END;
$function$;
REVOKE ALL ON FUNCTION public.tournament_check_in(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.tournament_check_in(uuid) TO authenticated;

-- admin_tournament_open_check_in: admin ouvre le check-in
CREATE OR REPLACE FUNCTION public.admin_tournament_open_check_in(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin uniquement'; END IF;
  UPDATE public.tournaments SET check_in_opened_at = now() WHERE id = _tid;
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_tournament_open_check_in(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_tournament_open_check_in(uuid) TO authenticated;

-- admin_tournament_set_timers: admin configure les minuteries
CREATE OR REPLACE FUNCTION public.admin_tournament_set_timers(
  _tid uuid,
  _match_duration_secs integer DEFAULT NULL,
  _break_secs integer DEFAULT NULL,
  _lobby_mins integer DEFAULT NULL,
  _check_in_mins integer DEFAULT NULL,
  _max_concurrent integer DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin uniquement'; END IF;
  UPDATE public.tournaments SET
    max_match_duration_secs = COALESCE(_match_duration_secs, max_match_duration_secs),
    break_seconds = COALESCE(_break_secs, break_seconds),
    lobby_minutes = COALESCE(_lobby_mins, lobby_minutes),
    check_in_minutes = COALESCE(_check_in_mins, check_in_minutes),
    max_concurrent_matches = COALESCE(_max_concurrent, max_concurrent_matches)
  WHERE id = _tid;
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_tournament_set_timers(uuid,integer,integer,integer,integer,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_tournament_set_timers(uuid,integer,integer,integer,integer,integer) TO authenticated;

-- ───────────────────────────────────────────────────────────────────────────
-- 12. tournament_mark_ready — utiliser entrant_ids au lieu de player_ids
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.tournament_mark_ready(_mid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  m record;
  v_entrant uuid;
  v_ready jsonb;
BEGIN
  SELECT * INTO m FROM public.tournament_matches WHERE id = _mid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Match introuvable'; END IF;

  -- Trouver l'entrant_id correspondant à l'utilisateur
  SELECT e.id INTO v_entrant
    FROM public.tournament_entrants e
    WHERE e.tournament_id = m.tournament_id AND e.user_id = v_uid
      AND e.id = ANY(m.entrant_ids);
  IF v_entrant IS NULL THEN RAISE EXCEPTION 'Vous n''êtes pas dans ce match'; END IF;

  v_ready := COALESCE(m.player_ready, '{}') || jsonb_build_object(v_entrant::text, true);

  UPDATE public.tournament_matches SET player_ready = v_ready WHERE id = _mid;

  RETURN jsonb_build_object('ok', true, 'ready', v_ready);
END;
$function$;
REVOKE ALL ON FUNCTION public.tournament_mark_ready(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.tournament_mark_ready(uuid) TO authenticated;

-- ───────────────────────────────────────────────────────────────────────────
-- 13. Nettoyer les anciennes fonctions cassées
-- ───────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.tournament_start(uuid);
DROP FUNCTION IF EXISTS public.admin_start_domino_tournament(uuid);
DROP FUNCTION IF EXISTS public.admin_create_domino_tournament(text,integer,numeric,boolean,text,text,timestamptz,timestamptz,text,integer,integer,integer);
DROP FUNCTION IF EXISTS public.on_ludo_tournament_game_finished();
DROP FUNCTION IF EXISTS public._trg_ludo_tournament_finished();

-- ───────────────────────────────────────────────────────────────────────────
-- 14. admin_tournament_start — fixer le stage pour le format pools
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_tournament_start(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
    UPDATE public.tournaments SET stage = 'pools' WHERE id = _tid;
    PERFORM public._t_draw_pools(_tid);
  ELSE
    SELECT array_agg(id ORDER BY random()) INTO ids FROM public.tournament_entrants
     WHERE tournament_id = _tid AND status = 'active';
    PERFORM public._t_build_round(_tid, 1, ids);
  END IF;
  PERFORM public.tournament_engine(_tid);
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_tournament_start(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_tournament_start(uuid) TO authenticated;
