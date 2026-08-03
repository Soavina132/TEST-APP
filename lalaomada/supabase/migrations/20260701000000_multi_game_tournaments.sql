-- =====================================================================
-- Migration : Support multi-jeux pour les tournois
-- Crée admin_start_tournament et admin_advance_tournament_round (génériques)
-- Compatible avec chess, fanorona, ludo, poker, rami, domino
-- =====================================================================

-- ─────────────────────────────────────────────
-- 1. admin_start_tournament (générique, non-domino)
--    Utilise la logique de tournament_start existante
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_start_tournament(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_is_admin boolean;
  trn        record;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO trn FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF trn IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;
  IF trn.status <> 'open' THEN RAISE EXCEPTION 'Tournoi non en phase d''inscription'; END IF;

  -- Déléguer à la fonction générique tournament_start
  PERFORM public.tournament_start(_tid);
END;
$$;

-- ─────────────────────────────────────────────
-- 2. admin_advance_tournament_round (générique)
--    Pour tous les jeux sauf Domino qui a admin_advance_domino_round
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_advance_tournament_round(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_is_admin   boolean;
  trn          record;
  v_winners    uuid[];
  v_count      int;
  v_next_round int;
  i            int;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO trn FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF trn IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;
  IF trn.status <> 'running' THEN RAISE EXCEPTION 'Tournoi non en cours'; END IF;

  -- Vérifier que tous les matchs du round courant sont terminés
  IF EXISTS (
    SELECT 1 FROM public.tournament_matches
    WHERE tournament_id = _tid
      AND round = trn.current_round
      AND status NOT IN ('finished','forfeit','cancelled')
      AND is_bye = false
  ) THEN
    RAISE EXCEPTION 'Des matchs du round actuel ne sont pas encore terminés';
  END IF;

  -- Récupérer les gagnants du round courant
  SELECT ARRAY_AGG(winner_id ORDER BY random())
    INTO v_winners
    FROM public.tournament_matches
    WHERE tournament_id = _tid
      AND round = trn.current_round
      AND winner_id IS NOT NULL;

  v_count := COALESCE(array_length(v_winners, 1), 0);

  IF v_count <= 1 THEN
    -- Finale terminée → distribuer les gains
    UPDATE public.tournaments
      SET status = 'finished',
          winner_id = v_winners[1],
          finished_at = now()
      WHERE id = _tid;

    IF v_winners[1] IS NOT NULL THEN
      UPDATE public.profiles
        SET balance_ar = balance_ar + COALESCE(trn.prize_pool, 0)
        WHERE id = v_winners[1];

      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (
          v_winners[1], 'tournament_win',
          COALESCE(trn.prize_pool, 0), _tid,
          'Gains tournoi ' || COALESCE(trn.game_slug, 'multi')
        );
    END IF;
    RETURN;
  END IF;

  v_next_round := trn.current_round + 1;
  UPDATE public.tournaments SET current_round = v_next_round WHERE id = _tid;

  -- Créer les matchs du prochain round (bracket élimination directe)
  i := 1;
  WHILE i + 1 <= v_count LOOP
    INSERT INTO public.tournament_matches(
      tournament_id, round, player_ids, status, is_bye
    ) VALUES (
      _tid, v_next_round, ARRAY[v_winners[i], v_winners[i+1]], 'pending', false
    );
    i := i + 2;
  END LOOP;

  -- Bye si nombre impair
  IF v_count % 2 = 1 THEN
    INSERT INTO public.tournament_matches(
      tournament_id, round, player_ids, status, is_bye, winner_id
    ) VALUES (
      _tid, v_next_round, ARRAY[v_winners[v_count]], 'finished', true, v_winners[v_count]
    );
  END IF;
END;
$$;

-- ─────────────────────────────────────────────
-- 3. admin_create_game_tournament
--    Création unifiée pour tous les jeux avec game_slug obligatoire
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_create_game_tournament(
  _name                    text,
  _game_slug               text,          -- chess | fanorona | ludo | poker | rami | domino | all
  _max_players             int     DEFAULT 8,
  _stake                   numeric DEFAULT 0,
  _is_free                 boolean DEFAULT true,
  _total_rounds            int     DEFAULT 3,
  _description             text    DEFAULT NULL,
  _rewards_text            text    DEFAULT NULL,
  _registration_opens_at   timestamptz DEFAULT NULL,
  _registration_closes_at  timestamptz DEFAULT NULL,
  -- Domino-specific (ignoré pour les autres jeux)
  _bye_strategy            text    DEFAULT 'random',
  _move_timer_secs         int     DEFAULT 25,
  _join_timeout_secs       int     DEFAULT 240,
  _disconnect_grace_secs   int     DEFAULT 120
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_is_admin   boolean;
  v_season     int;
  v_tid        uuid;
  v_stake      numeric;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  IF _name IS NULL OR trim(_name) = '' THEN RAISE EXCEPTION 'Nom requis'; END IF;
  IF _max_players < 2 THEN RAISE EXCEPTION 'Minimum 2 joueurs'; END IF;
  IF _game_slug IS NULL OR _game_slug NOT IN ('chess','fanorona','ludo','poker','rami','domino','all')
    THEN RAISE EXCEPTION 'Jeu invalide'; END IF;

  SELECT COALESCE(MAX(season), 0) + 1 INTO v_season FROM public.tournaments;
  v_stake := CASE WHEN _is_free THEN 0 ELSE _stake END;

  IF _game_slug = 'domino' THEN
    -- Pour Domino, déléguer à la fonction spécialisée
    PERFORM public.admin_create_domino_tournament(
      _name                   := _name,
      _max_players            := _max_players,
      _stake                  := v_stake,
      _is_free                := _is_free,
      _description            := _description,
      _rewards_text           := _rewards_text,
      _registration_opens_at  := _registration_opens_at,
      _registration_closes_at := _registration_closes_at,
      _bye_strategy           := _bye_strategy,
      _move_timer_secs        := _move_timer_secs,
      _join_timeout_secs      := _join_timeout_secs,
      _disconnect_grace_secs  := _disconnect_grace_secs
    );

    -- Récupérer l'UUID du tournoi créé
    SELECT id INTO v_tid FROM public.tournaments
      WHERE name = _name ORDER BY created_at DESC LIMIT 1;
    RETURN v_tid;
  END IF;

  -- Pour tous les autres jeux (chess, fanorona, ludo, poker, rami, all)
  INSERT INTO public.tournaments(
    name, game_slug, mode, max_players, stake, prize_pool, is_free,
    total_rounds, current_round, status, season,
    description, rewards_text,
    registration_opens_at, registration_closes_at
  ) VALUES (
    trim(_name),
    _game_slug,
    CASE WHEN _max_players <= 2 THEN '1v1' ELSE '1v1' END,
    _max_players,
    v_stake,
    CASE WHEN _is_free THEN 0 ELSE v_stake * _max_players * 0.9 END,
    _is_free,
    _total_rounds,
    0,
    'open',
    v_season,
    _description,
    _rewards_text,
    _registration_opens_at,
    _registration_closes_at
  )
  RETURNING id INTO v_tid;

  -- Log admin action
  INSERT INTO public.admin_action_logs(admin_id, action, target_id, note)
    VALUES (v_uid, 'create_tournament', v_tid, 'Jeu: ' || _game_slug || ' · ' || _name)
  ON CONFLICT DO NOTHING;

  RETURN v_tid;
END;
$$;

-- ─────────────────────────────────────────────
-- 4. admin_force_start_tournament
--    Démarre un tournoi même avec peu d'inscrits (pour tests / urgences)
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_force_start_tournament(_tid uuid, _reason text DEFAULT 'Démarrage forcé par admin')
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_is_admin boolean;
  trn        record;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO trn FROM public.tournaments WHERE id = _tid;
  IF trn IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;
  IF trn.status NOT IN ('open','paused') THEN RAISE EXCEPTION 'Le tournoi ne peut pas être démarré'; END IF;

  IF trn.game_slug = 'domino' THEN
    PERFORM public.admin_start_domino_tournament(_tid);
  ELSE
    PERFORM public.tournament_start(_tid);
  END IF;

  INSERT INTO public.admin_action_logs(admin_id, action, target_id, note)
    VALUES (v_uid, 'force_start_tournament', _tid, _reason)
  ON CONFLICT DO NOTHING;
END;
$$;

-- ─────────────────────────────────────────────
-- 5. admin_get_tournament_overview
--    Vue d'ensemble d'un tournoi pour l'admin : matchs, claims en cours, joueurs
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_get_tournament_overview(_tid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_is_admin boolean;
  v_result   jsonb;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT jsonb_build_object(
    'tournament', row_to_json(t.*),
    'matches', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', m.id, 'round', m.round, 'status', m.status,
        'player_ids', m.player_ids, 'winner_id', m.winner_id,
        'is_bye', m.is_bye, 'game_id', m.game_id,
        'join_deadline', m.join_deadline
      ) ORDER BY m.round, m.created_at)
      FROM public.tournament_matches m WHERE m.tournament_id = _tid
    ), '[]'),
    'claims', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', c.id, 'status', c.status, 'category', c.category,
        'description', c.description, 'claimant_id', c.claimant_id,
        'match_id', c.match_id, 'created_at', c.created_at,
        'admin_comment', c.admin_comment
      ) ORDER BY c.created_at DESC)
      FROM public.tournament_claims c WHERE c.tournament_id = _tid
        AND c.status IN ('pending','reviewing')
    ), '[]'),
    'registered_count', (
      SELECT COUNT(*) FROM public.tournament_registrations WHERE tournament_id = _tid
    )
  )
  INTO v_result
  FROM public.tournaments t WHERE t.id = _tid;

  RETURN v_result;
END;
$$;

-- Index utiles
CREATE INDEX IF NOT EXISTS idx_tournaments_game_slug_status
  ON public.tournaments(game_slug, status);
