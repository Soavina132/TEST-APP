-- ============================================================
-- Migration : Tournois Domino avec gestion avancée
-- ============================================================

-- 1. Colonnes supplémentaires sur la table tournaments
ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS game_slug          text        NOT NULL DEFAULT 'all',
  ADD COLUMN IF NOT EXISTS registration_opens_at  timestamptz,
  ADD COLUMN IF NOT EXISTS registration_closes_at timestamptz,
  ADD COLUMN IF NOT EXISTS bye_strategy       text        NOT NULL DEFAULT 'random',
  ADD COLUMN IF NOT EXISTS move_timer_secs    int         NOT NULL DEFAULT 25,
  ADD COLUMN IF NOT EXISTS join_timeout_secs  int         NOT NULL DEFAULT 240,
  ADD COLUMN IF NOT EXISTS disconnect_grace_secs int      NOT NULL DEFAULT 120,
  ADD COLUMN IF NOT EXISTS extra_config       jsonb       NOT NULL DEFAULT '{}';

-- 2. Colonnes supplémentaires sur tournament_matches
ALTER TABLE public.tournament_matches
  ADD COLUMN IF NOT EXISTS is_bye             boolean     NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS game_id            uuid,
  ADD COLUMN IF NOT EXISTS join_deadline      timestamptz,
  ADD COLUMN IF NOT EXISTS player_ready       jsonb       NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS player_joined_at   jsonb       NOT NULL DEFAULT '{}';

-- 3. RPC : admin_create_domino_tournament
CREATE OR REPLACE FUNCTION public.admin_create_domino_tournament(
  _name                    text,
  _max_players             int,
  _stake                   numeric,
  _is_free                 boolean,
  _description             text,
  _rewards_text            text,
  _registration_opens_at   timestamptz,
  _registration_closes_at  timestamptz,
  _bye_strategy            text,       -- 'random' | 'ranked'
  _move_timer_secs         int,        -- 20-30
  _join_timeout_secs       int,        -- 180-300
  _disconnect_grace_secs   int         -- 60-180
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid   uuid := auth.uid();
  v_is_admin boolean;
  v_tid   uuid;
  v_rounds int;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN
    RAISE EXCEPTION 'Accès refusé';
  END IF;

  -- Valider max_players >= 2
  IF _max_players < 2 THEN RAISE EXCEPTION 'max_players doit être >= 2'; END IF;

  -- Calculer total_rounds = ceil(log2(next power of 2 >= max_players))
  v_rounds := CEIL(LOG(2, _max_players::float));
  IF v_rounds < 1 THEN v_rounds := 1; END IF;

  INSERT INTO public.tournaments (
    name, mode, max_players, stake, is_free, total_rounds, description, rewards_text,
    status, current_round, season,
    game_slug, registration_opens_at, registration_closes_at,
    bye_strategy, move_timer_secs, join_timeout_secs, disconnect_grace_secs
  )
  VALUES (
    _name, '1v1', _max_players,
    CASE WHEN _is_free THEN 0 ELSE _stake END,
    _is_free, v_rounds, _description, _rewards_text,
    'open', 0,
    EXTRACT(YEAR FROM now()),
    'domino',
    _registration_opens_at, _registration_closes_at,
    _bye_strategy, _move_timer_secs, _join_timeout_secs, _disconnect_grace_secs
  )
  RETURNING id INTO v_tid;

  RETURN v_tid;
END;
$$;

-- 4. Mise à jour de tournament_register pour vérifier la fenêtre d'inscription
CREATE OR REPLACE FUNCTION public.tournament_register(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  trn    record;
  v_bal  numeric;
BEGIN
  SELECT * INTO trn FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;
  IF trn.status <> 'open' THEN RAISE EXCEPTION 'Les inscriptions sont closes'; END IF;

  -- Vérifier la fenêtre d'inscription si définie
  IF trn.registration_opens_at IS NOT NULL AND now() < trn.registration_opens_at THEN
    RAISE EXCEPTION 'Les inscriptions ne sont pas encore ouvertes';
  END IF;
  IF trn.registration_closes_at IS NOT NULL AND now() > trn.registration_closes_at THEN
    RAISE EXCEPTION 'Les inscriptions sont fermées';
  END IF;

  -- Vérifier nombre max
  IF (SELECT COUNT(*) FROM public.tournament_registrations WHERE tournament_id = _tid) >= trn.max_players THEN
    RAISE EXCEPTION 'Le tournoi est complet';
  END IF;

  -- Vérifier si déjà inscrit
  IF EXISTS (SELECT 1 FROM public.tournament_registrations WHERE tournament_id = _tid AND user_id = v_uid) THEN
    RAISE EXCEPTION 'Déjà inscrit';
  END IF;

  -- Prélever les frais d'inscription si tournoi payant
  IF NOT trn.is_free AND trn.stake > 0 THEN
    SELECT balance_ar INTO v_bal FROM public.profiles WHERE id = v_uid FOR UPDATE;
    IF v_bal < trn.stake THEN RAISE EXCEPTION 'Solde insuffisant pour les frais d''inscription'; END IF;
    UPDATE public.profiles SET balance_ar = balance_ar - trn.stake WHERE id = v_uid;
    UPDATE public.tournaments SET prize_pool = COALESCE(prize_pool, 0) + trn.stake WHERE id = _tid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'tournament_entry', -trn.stake, _tid, 'Frais inscription tournoi');
  END IF;

  INSERT INTO public.tournament_registrations(tournament_id, user_id)
    VALUES (_tid, v_uid)
    ON CONFLICT DO NOTHING;
END;
$$;

-- 5. RPC : admin_start_domino_tournament (avec gestion des byes)
CREATE OR REPLACE FUNCTION public.admin_start_domino_tournament(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_is_admin boolean;
  trn        record;
  v_players  uuid[];
  v_count    int;
  v_bracket  int;   -- prochaine puissance de 2
  v_byes     int;   -- nombre de byes à attribuer
  v_bye_ids  uuid[];
  v_play_ids uuid[];
  i          int;
  v_dl       timestamptz;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO trn FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF trn.status <> 'open' THEN RAISE EXCEPTION 'Tournoi non ouvert'; END IF;

  -- Récupérer les joueurs inscrits
  IF trn.bye_strategy = 'ranked' THEN
    SELECT ARRAY_AGG(r.user_id ORDER BY COALESCE(p.ranking_points, 0) DESC)
      INTO v_players
      FROM public.tournament_registrations r
      JOIN public.profiles p ON p.id = r.user_id
      WHERE r.tournament_id = _tid;
  ELSE
    SELECT ARRAY_AGG(r.user_id ORDER BY random())
      INTO v_players
      FROM public.tournament_registrations r
      WHERE r.tournament_id = _tid;
  END IF;

  v_count := COALESCE(array_length(v_players, 1), 0);
  IF v_count < 2 THEN RAISE EXCEPTION 'Pas assez de joueurs (minimum 2)'; END IF;

  -- Calculer la prochaine puissance de 2
  v_bracket := 1;
  WHILE v_bracket < v_count LOOP
    v_bracket := v_bracket * 2;
  END LOOP;

  v_byes := v_bracket - v_count;

  -- Mettre le tournoi en cours
  UPDATE public.tournaments
    SET status = 'running', current_round = 1,
        total_rounds = CEIL(LOG(2, v_bracket::float))::int
    WHERE id = _tid;

  v_dl := now() + (trn.join_timeout_secs || ' seconds')::interval;

  -- Créer les matchs BYE (les premiers joueurs du classement passent automatiquement)
  v_bye_ids  := v_players[1:v_byes];
  v_play_ids := v_players[v_byes+1:v_count];

  FOR i IN 1..v_byes LOOP
    INSERT INTO public.tournament_matches(tournament_id, round, player_ids, status, is_bye, winner_id)
      VALUES (_tid, 1, ARRAY[v_bye_ids[i]], 'finished', true, v_bye_ids[i]);
  END LOOP;

  -- Créer les vrais matchs du round 1
  i := 1;
  WHILE i + 1 <= array_length(v_play_ids, 1) LOOP
    INSERT INTO public.tournament_matches(
      tournament_id, round, player_ids, status, join_deadline, is_bye
    ) VALUES (
      _tid, 1, ARRAY[v_play_ids[i], v_play_ids[i+1]], 'pending', v_dl, false
    );
    i := i + 2;
  END LOOP;
END;
$$;

-- 6. RPC : tournament_mark_ready (joueur marque qu'il est prêt pour son match)
CREATE OR REPLACE FUNCTION public.tournament_mark_ready(_mid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid   uuid := auth.uid();
  m       record;
  v_ready jsonb;
  v_all_ready boolean;
BEGIN
  SELECT * INTO m FROM public.tournament_matches WHERE id = _mid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Match introuvable'; END IF;
  IF NOT (v_uid = ANY(m.player_ids)) THEN RAISE EXCEPTION 'Vous n''êtes pas dans ce match'; END IF;
  IF m.status NOT IN ('pending','waiting') THEN RAISE EXCEPTION 'Match déjà commencé ou terminé'; END IF;

  -- Vérifier timeout
  IF m.join_deadline IS NOT NULL AND now() > m.join_deadline THEN
    PERFORM public.tournament_check_forfeit(_mid);
    RAISE EXCEPTION 'Délai de connexion dépassé';
  END IF;

  v_ready := COALESCE(m.player_ready, '{}') || jsonb_build_object(v_uid::text, true);

  -- Vérifier si tous les joueurs sont prêts
  v_all_ready := true;
  DECLARE uid_t uuid;
  BEGIN
    FOREACH uid_t IN ARRAY m.player_ids LOOP
      IF NOT COALESCE((v_ready ->> uid_t::text)::boolean, false) THEN
        v_all_ready := false;
      END IF;
    END LOOP;
  END;

  UPDATE public.tournament_matches
    SET player_ready = v_ready,
        status = CASE WHEN v_all_ready THEN 'running' ELSE status END
    WHERE id = _mid;

  RETURN jsonb_build_object('all_ready', v_all_ready, 'ready', v_ready);
END;
$$;

-- 7. RPC : tournament_check_forfeit (vérifie le timeout de connexion)
CREATE OR REPLACE FUNCTION public.tournament_check_forfeit(_mid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  m           record;
  v_joined    jsonb;
  v_present   uuid[] := '{}';
  v_absent    uuid[] := '{}';
  uid_t       uuid;
  v_winner    uuid;
BEGIN
  SELECT * INTO m FROM public.tournament_matches WHERE id = _mid FOR UPDATE;
  IF NOT FOUND OR m.status IN ('finished','forfeit','cancelled') THEN
    RETURN jsonb_build_object('status', m.status);
  END IF;
  IF m.join_deadline IS NULL OR now() <= m.join_deadline THEN
    RETURN jsonb_build_object('status', m.status, 'time_remaining', EXTRACT(EPOCH FROM (m.join_deadline - now()))::int);
  END IF;

  v_joined := COALESCE(m.player_ready, '{}');
  FOREACH uid_t IN ARRAY m.player_ids LOOP
    IF COALESCE((v_joined ->> uid_t::text)::boolean, false) THEN
      v_present := v_present || uid_t;
    ELSE
      v_absent := v_absent || uid_t;
    END IF;
  END LOOP;

  -- Si un seul présent → gagne par forfait
  IF array_length(v_present, 1) = 1 THEN
    v_winner := v_present[1];
    UPDATE public.tournament_matches
      SET status = 'forfeit', winner_id = v_winner
      WHERE id = _mid;
    RETURN jsonb_build_object('status', 'forfeit', 'winner_id', v_winner, 'absent', v_absent);
  END IF;

  -- Aucun présent → les deux éliminés, match annulé
  IF array_length(v_present, 1) IS NULL OR array_length(v_present, 1) = 0 THEN
    UPDATE public.tournament_matches SET status = 'cancelled' WHERE id = _mid;
    RETURN jsonb_build_object('status', 'cancelled');
  END IF;

  RETURN jsonb_build_object('status', m.status);
END;
$$;

-- 8. RPC : admin_advance_domino_round (génère le round suivant avec byes si impair)
CREATE OR REPLACE FUNCTION public.admin_advance_domino_round(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_is_admin  boolean;
  trn         record;
  v_winners   uuid[];
  v_count     int;
  i           int;
  v_dl        timestamptz;
  v_next_round int;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO trn FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF trn.status <> 'running' THEN RAISE EXCEPTION 'Tournoi non en cours'; END IF;

  -- Vérifier que tous les matchs du round courant sont terminés
  IF EXISTS (
    SELECT 1 FROM public.tournament_matches
    WHERE tournament_id = _tid AND round = trn.current_round
      AND status NOT IN ('finished','forfeit','cancelled')
      AND is_bye = false
  ) THEN
    RAISE EXCEPTION 'Des matchs du round actuel ne sont pas encore terminés';
  END IF;

  -- Récupérer les gagnants du round courant
  SELECT ARRAY_AGG(winner_id ORDER BY random())
    INTO v_winners
    FROM public.tournament_matches
    WHERE tournament_id = _tid AND round = trn.current_round
      AND winner_id IS NOT NULL;

  v_count := COALESCE(array_length(v_winners, 1), 0);

  IF v_count <= 1 THEN
    -- Finale terminée
    UPDATE public.tournaments
      SET status = 'finished',
          winner_id = v_winners[1],
          finished_at = now()
      WHERE id = _tid;

    -- Distribuer les gains au gagnant
    IF v_winners[1] IS NOT NULL THEN
      UPDATE public.profiles
        SET balance_ar = balance_ar + COALESCE(trn.prize_pool, 0)
        WHERE id = v_winners[1];
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (v_winners[1], 'tournament_win', COALESCE(trn.prize_pool, 0), _tid, 'Gains tournoi Domino');
    END IF;
    RETURN;
  END IF;

  v_next_round := trn.current_round + 1;
  v_dl := now() + (trn.join_timeout_secs || ' seconds')::interval;

  UPDATE public.tournaments SET current_round = v_next_round WHERE id = _tid;

  -- Créer les matchs du prochain round
  i := 1;
  WHILE i + 1 <= v_count LOOP
    INSERT INTO public.tournament_matches(
      tournament_id, round, player_ids, status, join_deadline, is_bye
    ) VALUES (
      _tid, v_next_round, ARRAY[v_winners[i], v_winners[i+1]], 'pending', v_dl, false
    );
    i := i + 2;
  END LOOP;

  -- Si nombre impair, le dernier reçoit un bye
  IF v_count % 2 = 1 THEN
    INSERT INTO public.tournament_matches(tournament_id, round, player_ids, status, is_bye, winner_id)
      VALUES (_tid, v_next_round, ARRAY[v_winners[v_count]], 'finished', true, v_winners[v_count]);
  END IF;
END;
$$;

-- 9. Politique RLS pour les nouvelles colonnes (héritage des politiques existantes)
-- (pas besoin de nouvelles politiques si les politiques sur tournaments/tournament_matches sont déjà correctes)

-- 10. Index utiles
CREATE INDEX IF NOT EXISTS idx_tournaments_game_slug ON public.tournaments(game_slug);
CREATE INDEX IF NOT EXISTS idx_tournament_matches_status ON public.tournament_matches(status);
CREATE INDEX IF NOT EXISTS idx_tournament_matches_join_deadline ON public.tournament_matches(join_deadline)
  WHERE status = 'pending';
