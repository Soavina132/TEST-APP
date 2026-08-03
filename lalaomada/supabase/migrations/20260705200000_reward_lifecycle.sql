-- ═══════════════════════════════════════════════════════════════════════════
-- Migration : Système de récompenses, tables multi-joueurs, cycle de vie complet
-- Couvre :
--   • Distribution configurable (60/20/10/10 admin-modifiable en cours de tournoi)
--   • Format tables de 4 joueurs (2 qualifiés par table)
--   • Système "Prêt" + démarrage auto après 10 min si 2+ prêts
--   • Gestion 3 joueurs dans une table (2 qualifiés)
--   • Égalité → relance automatique
--   • Podium (1er/2e/3e) + archivage complet
--   • Admin peut modifier les récompenses même pendant le tournoi
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- 1. Colonnes supplémentaires sur tournaments
-- ─────────────────────────────────────────────────────────────────────────
ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS reward_distribution  jsonb NOT NULL DEFAULT '{"first":60,"second":20,"third":10,"platform":10}',
  ADD COLUMN IF NOT EXISTS players_per_table    int   NOT NULL DEFAULT 2,
  ADD COLUMN IF NOT EXISTS qualifiers_per_table int   NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS grace_period_secs    int   NOT NULL DEFAULT 300,
  ADD COLUMN IF NOT EXISTS auto_start_mins      int   NOT NULL DEFAULT 10,
  ADD COLUMN IF NOT EXISTS podium               jsonb          DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS archived_at          timestamptz,
  ADD COLUMN IF NOT EXISTS rewards_paid_at      timestamptz,
  ADD COLUMN IF NOT EXISTS platform_cut_ar      numeric        DEFAULT 0,
  ADD COLUMN IF NOT EXISTS format               text  NOT NULL DEFAULT 'elimination';
  -- format: 'elimination' (1v1 bracket) | 'tables' (4-player tables) | 'groups'

-- ─────────────────────────────────────────────────────────────────────────
-- 2. Colonnes supplémentaires sur tournament_matches
-- ─────────────────────────────────────────────────────────────────────────
ALTER TABLE public.tournament_matches
  ADD COLUMN IF NOT EXISTS auto_start_at   timestamptz,
  ADD COLUMN IF NOT EXISTS match_rankings  jsonb NOT NULL DEFAULT '{}',
  -- match_rankings: {"1": uuid_1er, "2": uuid_2e, "3": uuid_3e, "4": uuid_4e}
  ADD COLUMN IF NOT EXISTS rematch_count   int   NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS table_index     int   NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS forfeit_ids     uuid[]         DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS ready_deadline  timestamptz;

-- ─────────────────────────────────────────────────────────────────────────
-- 3. admin_set_reward_distribution — modifiable à tout moment (même pendant)
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_set_reward_distribution(
  _tid         uuid,
  _first_pct   numeric,   -- ex: 60
  _second_pct  numeric,   -- ex: 20
  _third_pct   numeric,   -- ex: 10
  _platform_pct numeric   -- ex: 10
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_is_admin boolean;
  trn        record;
  total      numeric;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  total := COALESCE(_first_pct,0) + COALESCE(_second_pct,0) + COALESCE(_third_pct,0) + COALESCE(_platform_pct,0);
  IF ABS(total - 100) > 0.01 THEN
    RAISE EXCEPTION 'Les pourcentages doivent totaliser 100%% (actuellement: %%)', total;
  END IF;

  SELECT * INTO trn FROM public.tournaments WHERE id = _tid;
  IF trn IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;
  IF trn.status = 'cancelled' THEN RAISE EXCEPTION 'Tournoi annulé'; END IF;

  UPDATE public.tournaments
    SET reward_distribution = jsonb_build_object(
      'first',    _first_pct,
      'second',   _second_pct,
      'third',    _third_pct,
      'platform', _platform_pct
    )
    WHERE id = _tid;

  -- Notifier tous les participants de la modification
  INSERT INTO public.notifications(user_id, type, title, body, ref_id)
    SELECT r.user_id,
           'tournament_rewards_updated',
           'Répartition des gains modifiée',
           'Tournoi ' || trn.name || ' : 1er=' || _first_pct || '% · 2e=' || _second_pct || '% · 3e=' || _third_pct || '%',
           _tid
    FROM public.tournament_registrations r WHERE r.tournament_id = _tid
    ON CONFLICT DO NOTHING;

  -- Log
  BEGIN
    INSERT INTO public.admin_action_logs(admin_id, action, target_id, note)
      VALUES (v_uid, 'set_reward_distribution', _tid,
              _first_pct||'/'||_second_pct||'/'||_third_pct||'/'||_platform_pct)
    ON CONFLICT DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object(
    'ok', true,
    'distribution', jsonb_build_object(
      'first', _first_pct, 'second', _second_pct,
      'third', _third_pct, 'platform', _platform_pct
    ),
    'prize_pool', trn.prize_pool
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_set_reward_distribution(uuid,numeric,numeric,numeric,numeric) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 4. admin_distribute_tournament_rewards — distribue les gains au podium
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_distribute_tournament_rewards(
  _tid         uuid,
  _first_id    uuid,
  _second_id   uuid,
  _third_id    uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_is_admin   boolean;
  trn          record;
  dist         jsonb;
  v_prize      numeric;
  v_first_amt  numeric;
  v_second_amt numeric;
  v_third_amt  numeric;
  v_plat_amt   numeric;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO trn FROM public.tournaments WHERE id = _tid;
  IF trn IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;
  IF trn.status NOT IN ('finished','running') THEN
    RAISE EXCEPTION 'Le tournoi doit être en cours ou terminé';
  END IF;
  IF trn.rewards_paid_at IS NOT NULL THEN
    RAISE EXCEPTION 'Les récompenses ont déjà été distribuées';
  END IF;

  v_prize := COALESCE(trn.prize_pool, 0);
  dist    := COALESCE(trn.reward_distribution, '{"first":60,"second":20,"third":10,"platform":10}');

  v_first_amt  := ROUND(v_prize * (dist->>'first')::numeric  / 100, 0);
  v_second_amt := ROUND(v_prize * (dist->>'second')::numeric / 100, 0);
  v_third_amt  := ROUND(v_prize * (dist->>'third')::numeric  / 100, 0);
  v_plat_amt   := v_prize - v_first_amt - v_second_amt - v_third_amt;
  -- La part plateforme reste dans la caisse (pas créditée à un joueur)

  -- Créditer le 1er
  IF _first_id IS NOT NULL THEN
    UPDATE public.profiles SET balance_ar = balance_ar + v_first_amt WHERE id = _first_id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (_first_id, 'tournament_win', v_first_amt, _tid,
              '🥇 1er — Tournoi ' || trn.name || ' (' || dist->>'first' || '%)');
    INSERT INTO public.notifications(user_id, type, title, body, ref_id)
      VALUES (_first_id, 'tournament_reward',
              '🥇 Félicitations — Vous avez gagné !',
              'Gain de ' || v_first_amt || ' Ar crédité sur votre compte.',
              _tid) ON CONFLICT DO NOTHING;
  END IF;

  -- Créditer le 2e
  IF _second_id IS NOT NULL THEN
    UPDATE public.profiles SET balance_ar = balance_ar + v_second_amt WHERE id = _second_id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (_second_id, 'tournament_win', v_second_amt, _tid,
              '🥈 2e — Tournoi ' || trn.name || ' (' || dist->>'second' || '%)');
    INSERT INTO public.notifications(user_id, type, title, body, ref_id)
      VALUES (_second_id, 'tournament_reward',
              '🥈 2e place — Bravo !',
              'Gain de ' || v_second_amt || ' Ar crédité sur votre compte.',
              _tid) ON CONFLICT DO NOTHING;
  END IF;

  -- Créditer le 3e (si existe)
  IF _third_id IS NOT NULL AND v_third_amt > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar + v_third_amt WHERE id = _third_id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (_third_id, 'tournament_win', v_third_amt, _tid,
              '🥉 3e — Tournoi ' || trn.name || ' (' || dist->>'third' || '%)');
    INSERT INTO public.notifications(user_id, type, title, body, ref_id)
      VALUES (_third_id, 'tournament_reward',
              '🥉 3e place — Félicitations !',
              'Gain de ' || v_third_amt || ' Ar crédité sur votre compte.',
              _tid) ON CONFLICT DO NOTHING;
  END IF;

  -- Enregistrer le podium et les métadonnées
  UPDATE public.tournaments
    SET podium = jsonb_build_object(
          'first',  _first_id,
          'second', _second_id,
          'third',  _third_id
        ),
        winner_id        = _first_id,
        status           = 'finished',
        finished_at      = COALESCE(finished_at, now()),
        rewards_paid_at  = now(),
        platform_cut_ar  = v_plat_amt
    WHERE id = _tid;

  -- Log admin
  BEGIN
    INSERT INTO public.admin_action_logs(admin_id, action, target_id, note)
      VALUES (v_uid, 'distribute_rewards', _tid,
              '1er:'||v_first_amt||' 2e:'||v_second_amt||' 3e:'||v_third_amt||' Plateforme:'||v_plat_amt)
    ON CONFLICT DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object(
    'ok', true,
    'first_amount',    v_first_amt,
    'second_amount',   v_second_amt,
    'third_amount',    v_third_amt,
    'platform_amount', v_plat_amt,
    'prize_pool',      v_prize
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_distribute_tournament_rewards(uuid,uuid,uuid,uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 5. player_mark_ready — joueur clique "Prêt"
--    Logique : si tous prêts → lancer immédiatement
--              si déjà auto_start_at défini → rien
--              si premier ready → fixer auto_start_at = now + 10 min
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.player_mark_ready(_mid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_match     record;
  trn         record;
  v_ready_cnt int;
  v_total_cnt int;
  v_new_ready jsonb;
  v_all_ready boolean;
BEGIN
  SELECT * INTO v_match FROM public.tournament_matches WHERE id = _mid FOR UPDATE;
  IF v_match IS NULL THEN RAISE EXCEPTION 'Match introuvable'; END IF;
  IF v_match.status NOT IN ('pending','waiting') THEN
    RAISE EXCEPTION 'Ce match ne permet pas de se marquer prêt';
  END IF;
  IF v_uid <> ALL(v_match.player_ids) THEN
    RAISE EXCEPTION 'Vous ne faites pas partie de ce match';
  END IF;

  SELECT * INTO trn FROM public.tournaments WHERE id = v_match.tournament_id;

  -- Mettre à jour player_ready
  v_new_ready := COALESCE(v_match.player_ready, '{}') || jsonb_build_object(v_uid::text, true);
  v_total_cnt := array_length(v_match.player_ids, 1);
  v_ready_cnt := (SELECT COUNT(*) FROM jsonb_object_keys(v_new_ready) WHERE v_new_ready->jsonb_object_keys = 'true');

  -- Fallback count : compter les clés avec valeur true
  SELECT COUNT(*) INTO v_ready_cnt
    FROM jsonb_each_text(v_new_ready)
    WHERE value = 'true';

  v_all_ready := v_ready_cnt >= v_total_cnt;

  UPDATE public.tournament_matches
    SET player_ready = v_new_ready,
        -- Si premier joueur ready → fixer auto_start_at si pas encore fait
        auto_start_at = CASE
          WHEN auto_start_at IS NULL AND v_ready_cnt >= 1
          THEN now() + (COALESCE(trn.auto_start_mins, 10) || ' minutes')::interval
          ELSE auto_start_at
        END,
        -- Si tous prêts → passer en running et fixer join_deadline maintenant
        status = CASE WHEN v_all_ready THEN 'running' ELSE status END,
        join_deadline = CASE WHEN v_all_ready THEN now() ELSE join_deadline END
    WHERE id = _mid;

  -- Si tous prêts et c'est Ludo → lancer la partie automatiquement
  IF v_all_ready AND trn.game_slug = 'ludo' THEN
    PERFORM public.ludo_tournament_launch_game(_mid);
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'ready_count', v_ready_cnt,
    'total_count', v_total_cnt,
    'all_ready',   v_all_ready,
    'auto_start_at', CASE
      WHEN v_all_ready THEN NULL
      ELSE (now() + (COALESCE(trn.auto_start_mins, 10) || ' minutes')::interval)
    END
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.player_mark_ready(uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 6. admin_auto_start_ready_matches — déclenche les matchs dont auto_start_at est passé
--    Appelé par admin ou via cron (edge function)
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_auto_start_ready_matches(_tid uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_is_admin boolean;
  v_match    record;
  v_ready_cnt int;
  v_started  int := 0;
  v_forfeited int := 0;
  v_player   uuid;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  FOR v_match IN
    SELECT tm.*, t.game_slug, t.qualifiers_per_table
    FROM public.tournament_matches tm
    JOIN public.tournaments t ON t.id = tm.tournament_id
    WHERE tm.status IN ('pending','waiting')
      AND tm.is_bye = false
      AND tm.auto_start_at IS NOT NULL
      AND tm.auto_start_at <= now()
      AND (_tid IS NULL OR tm.tournament_id = _tid)
  LOOP
    -- Compter les joueurs prêts
    SELECT COUNT(*) INTO v_ready_cnt
      FROM jsonb_each_text(COALESCE(v_match.player_ready, '{}'))
      WHERE value = 'true';

    IF v_ready_cnt = 0 THEN
      -- Personne de prêt → forfait général, le match est annulé
      UPDATE public.tournament_matches
        SET status = 'forfeit', admin_notes = 'Aucun joueur prêt — forfait général',
            finished_at = now()
        WHERE id = v_match.id;
      v_forfeited := v_forfeited + 1;

    ELSIF v_ready_cnt = 1 THEN
      -- Un seul joueur prêt → qualification automatique sans jouer
      SELECT (key::uuid) INTO v_player
        FROM jsonb_each_text(COALESCE(v_match.player_ready, '{}'))
        WHERE value = 'true' LIMIT 1;
      UPDATE public.tournament_matches
        SET status = 'finished', winner_id = v_player, finished_at = now(),
            match_rankings = jsonb_build_object('1', v_player::text),
            admin_notes = 'Qualification auto — seul joueur présent'
        WHERE id = v_match.id;
      v_started := v_started + 1;

    ELSE
      -- 2+ joueurs prêts → démarrer même si tous ne sont pas là
      -- Les absents sont enregistrés comme forfait
      UPDATE public.tournament_matches
        SET status = 'running',
            join_deadline = now(),
            admin_notes = 'Démarré auto (' || v_ready_cnt || '/' ||
                          array_length(v_match.player_ids, 1) || ' prêts)',
            -- Marquer les absents comme forfait
            forfeit_ids = ARRAY(
              SELECT unnest(v_match.player_ids) AS uid
              EXCEPT
              SELECT (key::uuid)
              FROM jsonb_each_text(COALESCE(v_match.player_ready, '{}'))
              WHERE value = 'true'
            )
        WHERE id = v_match.id;

      -- Si Ludo → lancer la partie avec les joueurs prêts seulement
      IF v_match.game_slug = 'ludo' THEN
        BEGIN
          PERFORM public.ludo_tournament_launch_game(v_match.id);
        EXCEPTION WHEN OTHERS THEN
          -- Ignorer les erreurs de lancement (partie déjà lancée etc.)
          NULL;
        END;
      END IF;
      v_started := v_started + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'started', v_started,
    'forfeited', v_forfeited
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_auto_start_ready_matches(uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 7. admin_start_multi_table_tournament — créer des tables de 4 joueurs
--    Format : players_per_table joueurs par table, qualifiers_per_table avancent
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_start_multi_table_tournament(_tid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid          uuid := auth.uid();
  v_is_admin     boolean;
  trn            record;
  v_players      uuid[];
  v_count        int;
  v_ppt          int;  -- players per table
  v_tables       int;  -- nombre de tables
  v_remainder    int;  -- joueurs restants (table incomplète)
  i              int;
  j              int;
  v_table_players uuid[];
  v_dl           timestamptz;
  v_auto_at      timestamptz;
  v_match_id     uuid;
  v_tables_created int := 0;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO trn FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF trn IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;
  IF trn.status <> 'open' THEN RAISE EXCEPTION 'Le tournoi n''est pas ouvert'; END IF;

  v_ppt := COALESCE(trn.players_per_table, 4);
  IF v_ppt < 2 THEN v_ppt := 4; END IF;

  -- Récupérer les joueurs inscrits (mélangés aléatoirement)
  SELECT ARRAY_AGG(r.user_id ORDER BY random())
    INTO v_players
    FROM public.tournament_registrations r
    WHERE r.tournament_id = _tid;

  v_count := COALESCE(array_length(v_players, 1), 0);
  IF v_count < 2 THEN RAISE EXCEPTION 'Pas assez de joueurs (minimum 2)'; END IF;

  -- Calculer nombre de tables
  v_tables    := v_count / v_ppt;
  v_remainder := v_count % v_ppt;

  -- Si reste < 2 joueurs → les fusionner dans la dernière table
  -- Si reste >= 2 → créer une table incomplète (valide)
  IF v_remainder = 1 AND v_tables > 0 THEN
    -- 1 joueur seul → le mettre avec la table précédente
    v_tables    := v_tables - 1;
    v_remainder := v_remainder + v_ppt; -- cette dernière table a ppt+1 joueurs
  END IF;
  IF v_tables = 0 THEN
    -- Tous dans une seule table
    v_tables    := 1;
    v_remainder := 0;
  END IF;

  -- Calculer total_rounds approximatif
  -- Exemple: 16 joueurs, 4/table, 2 qualifs → 4 tables → 2 rounds avant finale
  DECLARE
    v_qualifiers_r1 int := (v_tables * COALESCE(trn.qualifiers_per_table, 2));
    v_total_rounds  int;
  BEGIN
    v_total_rounds := 1 + CEIL(LOG(2, GREATEST(v_qualifiers_r1, 2)::float))::int;
    IF v_total_rounds < 1 THEN v_total_rounds := 1; END IF;

    UPDATE public.tournaments
      SET status = 'running',
          current_round = 1,
          total_rounds = v_total_rounds
      WHERE id = _tid;
  END;

  v_dl      := now() + (COALESCE(trn.join_timeout_secs, 240) || ' seconds')::interval;
  v_auto_at := now() + (COALESCE(trn.auto_start_mins, 10) || ' minutes')::interval;

  -- Créer les tables complètes
  i := 1;
  FOR j IN 1..v_tables LOOP
    v_table_players := v_players[i : i + v_ppt - 1];
    i := i + v_ppt;

    INSERT INTO public.tournament_matches(
      tournament_id, round, player_ids, status, is_bye,
      join_deadline, auto_start_at, table_index
    ) VALUES (
      _tid, 1, v_table_players, 'pending', false,
      v_dl, v_auto_at, j
    ) RETURNING id INTO v_match_id;

    -- Notifier les joueurs de cette table
    FOR v_idx IN 1..array_length(v_table_players, 1) LOOP
      INSERT INTO public.notifications(user_id, type, title, body, ref_id)
        VALUES (v_table_players[v_idx], 'match_ready',
                'Votre table est prête !',
                'Tournoi ' || trn.name || ' — Table ' || j ||
                ' · ' || array_length(v_table_players, 1) || ' joueurs · Cliquez "Prêt" maintenant !',
                v_match_id)
        ON CONFLICT DO NOTHING;
    END LOOP;

    v_tables_created := v_tables_created + 1;
  END LOOP;

  -- Table incomplète (reste de joueurs)
  IF v_remainder >= 2 THEN
    v_table_players := v_players[i : i + v_remainder - 1];
    INSERT INTO public.tournament_matches(
      tournament_id, round, player_ids, status, is_bye,
      join_deadline, auto_start_at, table_index
    ) VALUES (
      _tid, 1, v_table_players, 'pending', false,
      v_dl, v_auto_at, v_tables + 1
    ) RETURNING id INTO v_match_id;

    FOR v_idx IN 1..array_length(v_table_players, 1) LOOP
      INSERT INTO public.notifications(user_id, type, title, body, ref_id)
        VALUES (v_table_players[v_idx], 'match_ready',
                'Votre table est prête !',
                'Tournoi ' || trn.name || ' — Table ' || (v_tables+1) ||
                ' · ' || array_length(v_table_players, 1) || ' joueurs (table incomplète) · Cliquez "Prêt" maintenant !',
                v_match_id)
        ON CONFLICT DO NOTHING;
    END LOOP;

    v_tables_created := v_tables_created + 1;
  END IF;

  -- Log
  BEGIN
    INSERT INTO public.admin_action_logs(admin_id, action, target_id, note)
      VALUES (v_uid, 'start_multi_table_tournament', _tid,
              v_tables_created || ' tables créées, ' || v_count || ' joueurs')
    ON CONFLICT DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object(
    'ok', true,
    'tables_created', v_tables_created,
    'players_total', v_count,
    'players_per_table', v_ppt
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_start_multi_table_tournament(uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 8. tournament_set_multi_result — enregistrer le classement 1er/2e/3e/4e
--    Appelé automatiquement quand la partie Ludo envoie son résultat final
--    Gère : égalité → relance auto, avancement qualifiés
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.tournament_set_multi_result(
  _mid       uuid,
  _rankings  jsonb   -- {"1": "uuid1er", "2": "uuid2e", "3": "uuid3e", "4": "uuid4e"}
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid         uuid := auth.uid();
  v_match       record;
  trn           record;
  v_first       uuid;
  v_second      uuid;
  v_qualifiers  uuid[];
  v_q           int;
  v_tie         boolean := false;
  i             int;
BEGIN
  -- Autoriser authenticated (résultat envoyé par le système de jeu)
  SELECT * INTO v_match FROM public.tournament_matches WHERE id = _mid;
  IF v_match IS NULL THEN RAISE EXCEPTION 'Match introuvable'; END IF;
  IF v_match.status = 'finished' THEN RAISE EXCEPTION 'Match déjà terminé'; END IF;

  SELECT * INTO trn FROM public.tournaments WHERE id = v_match.tournament_id;
  v_q := COALESCE(trn.qualifiers_per_table, 2);

  v_first  := (_rankings->>'1')::uuid;
  v_second := (_rankings->>'2')::uuid;

  -- Détecter égalité : si 1er et 2e ont le même score (indiqué par null ou égaux)
  -- Convention: si _rankings contient {"tie": true} → relance
  IF (_rankings->>'tie')::boolean = true THEN
    v_tie := true;
  END IF;

  IF v_tie THEN
    -- Égalité → relancer le match automatiquement
    UPDATE public.tournament_matches
      SET status = 'pending',
          winner_id = NULL,
          finished_at = NULL,
          player_ready = '{}',
          auto_start_at = now() + interval '10 minutes',
          rematch_count = rematch_count + 1,
          admin_notes = COALESCE(admin_notes, '') || ' | Égalité → Rematch auto #' || (rematch_count + 1)
      WHERE id = _mid;

    -- Notifier les joueurs
    INSERT INTO public.notifications(user_id, type, title, body, ref_id)
      SELECT uid, 'match_rematch',
             '🔄 Égalité — Rematch !',
             'Le match s''est terminé en égalité. Un nouveau match commence dans 10 min.',
             _mid
      FROM unnest(v_match.player_ids) AS uid
      ON CONFLICT DO NOTHING;

    RETURN jsonb_build_object('ok', true, 'tie', true, 'rematch', true);
  END IF;

  -- Enregistrer le classement complet
  UPDATE public.tournament_matches
    SET status        = 'finished',
        winner_id     = v_first,
        finished_at   = now(),
        match_rankings = _rankings
    WHERE id = _mid;

  -- Déterminer les qualifiés (top qualifiers_per_table)
  v_qualifiers := ARRAY[]::uuid[];
  FOR i IN 1..LEAST(v_q, array_length(v_match.player_ids, 1)) LOOP
    v_qualifiers := array_append(v_qualifiers, (_rankings->>(i::text))::uuid);
  END LOOP;

  -- Notifier tous les joueurs
  INSERT INTO public.notifications(user_id, type, title, body, ref_id)
    SELECT uid, 'match_result',
           CASE
             WHEN uid = v_first THEN '🥇 Vous avez terminé 1er !'
             WHEN uid = v_second THEN '🥈 Vous avez terminé 2e !'
             ELSE '❌ Éliminé'
           END,
           CASE
             WHEN uid = ANY(v_qualifiers)
             THEN 'Vous êtes qualifié pour le tour suivant !'
             ELSE 'Vous avez été éliminé du tournoi. Merci d''avoir participé.'
           END,
           _mid
    FROM unnest(v_match.player_ids) AS uid
    ON CONFLICT DO NOTHING;

  RETURN jsonb_build_object(
    'ok', true,
    'winner_id', v_first,
    'qualifiers', v_qualifiers,
    'rankings', _rankings
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.tournament_set_multi_result(uuid, jsonb) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 9. admin_advance_multi_round — passer au tour suivant (tables multi-joueurs)
--    Récupère les qualifiés de toutes les tables, crée nouvelles tables
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_advance_multi_round(_tid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid          uuid := auth.uid();
  v_is_admin     boolean;
  trn            record;
  v_qualifiers   uuid[] := ARRAY[]::uuid[];
  v_match        record;
  v_q            int;
  i              int;
  v_next_round   int;
  v_tables       int;
  v_ppt          int;
  v_dl           timestamptz;
  v_auto_at      timestamptz;
  v_table_players uuid[];
  v_match_id     uuid;
  v_tables_created int := 0;
  v_winner_id    uuid;
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
    RAISE EXCEPTION 'Des matchs du round % ne sont pas encore terminés', trn.current_round;
  END IF;

  v_q   := COALESCE(trn.qualifiers_per_table, 2);
  v_ppt := COALESCE(trn.players_per_table, 4);

  -- Collecter les qualifiés depuis match_rankings
  FOR v_match IN
    SELECT * FROM public.tournament_matches
    WHERE tournament_id = _tid
      AND round = trn.current_round
      AND is_bye = false
    ORDER BY table_index
  LOOP
    -- Récupérer les top qualifiers_per_table du classement
    FOR i IN 1..LEAST(v_q, COALESCE(array_length(v_match.player_ids,1),0)) LOOP
      IF v_match.match_rankings->(i::text) IS NOT NULL THEN
        v_qualifiers := array_append(v_qualifiers,
          (v_match.match_rankings->>(i::text))::uuid);
      ELSIF i = 1 AND v_match.winner_id IS NOT NULL THEN
        v_qualifiers := array_append(v_qualifiers, v_match.winner_id);
      END IF;
    END LOOP;
    -- Également inclure les byes (qualifiés automatiques)
  END LOOP;

  -- Inclure les byes du round courant
  FOR v_match IN
    SELECT * FROM public.tournament_matches
    WHERE tournament_id = _tid AND round = trn.current_round AND is_bye = true
  LOOP
    IF v_match.winner_id IS NOT NULL THEN
      v_qualifiers := array_append(v_qualifiers, v_match.winner_id);
    END IF;
  END LOOP;

  -- Dédupliquer
  SELECT ARRAY_AGG(DISTINCT u ORDER BY random()) INTO v_qualifiers
    FROM unnest(v_qualifiers) u;

  IF COALESCE(array_length(v_qualifiers, 1), 0) = 0 THEN
    RAISE EXCEPTION 'Aucun qualifié trouvé pour le round suivant';
  END IF;

  -- Si 1 seul qualifié → c'est le champion !
  IF array_length(v_qualifiers, 1) = 1 THEN
    v_winner_id := v_qualifiers[1];

    UPDATE public.tournaments
      SET status = 'finished',
          winner_id = v_winner_id,
          finished_at = now()
      WHERE id = _tid;

    INSERT INTO public.notifications(user_id, type, title, body, ref_id)
      VALUES (v_winner_id, 'tournament_win',
              '🏆 Vous êtes Champion !',
              'Félicitations ! Vous avez remporté le tournoi ' || trn.name || ' !',
              _tid)
      ON CONFLICT DO NOTHING;

    RETURN jsonb_build_object('ok', true, 'champion', v_winner_id, 'tournament_finished', true);
  END IF;

  -- Si 2 qualifiés → finale 1v1 ou petite finale à organiser
  -- Si 3 qualifiés → table de 3 (les 2 premiers avancent)
  -- Si 4+ qualifiés → nouvelles tables de players_per_table

  v_next_round := trn.current_round + 1;
  UPDATE public.tournaments SET current_round = v_next_round WHERE id = _tid;

  v_dl      := now() + (COALESCE(trn.join_timeout_secs, 240) || ' seconds')::interval;
  v_auto_at := now() + (COALESCE(trn.auto_start_mins, 10) || ' minutes')::interval;

  -- Créer les tables du round suivant
  i := 1;
  v_tables := CEIL(array_length(v_qualifiers,1)::float / v_ppt);
  FOR j IN 1..v_tables LOOP
    v_table_players := v_qualifiers[i : LEAST(i + v_ppt - 1, array_length(v_qualifiers,1))];
    i := i + v_ppt;

    IF array_length(v_table_players, 1) < 2 THEN
      -- Un seul joueur : bye
      INSERT INTO public.tournament_matches(
        tournament_id, round, player_ids, status, is_bye, winner_id, table_index
      ) VALUES (_tid, v_next_round, v_table_players, 'finished', true, v_table_players[1], j);
    ELSE
      INSERT INTO public.tournament_matches(
        tournament_id, round, player_ids, status, is_bye,
        join_deadline, auto_start_at, table_index
      ) VALUES (
        _tid, v_next_round, v_table_players, 'pending', false,
        v_dl, v_auto_at, j
      ) RETURNING id INTO v_match_id;

      -- Notifier
      FOR v_idx IN 1..array_length(v_table_players,1) LOOP
        INSERT INTO public.notifications(user_id, type, title, body, ref_id)
          VALUES (v_table_players[v_idx], 'match_ready',
                  '⏭ Round ' || v_next_round || ' — Votre prochaine table !',
                  'Tournoi ' || trn.name || ' · Cliquez "Prêt" pour commencer.',
                  v_match_id)
          ON CONFLICT DO NOTHING;
      END LOOP;

      v_tables_created := v_tables_created + 1;
    END IF;
  END LOOP;

  -- Log
  BEGIN
    INSERT INTO public.admin_action_logs(admin_id, action, target_id, note)
      VALUES (v_uid, 'advance_round', _tid, 'Round '||v_next_round||' · '||array_length(v_qualifiers,1)||' qualifiés · '||v_tables_created||' tables')
    ON CONFLICT DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object(
    'ok', true,
    'next_round', v_next_round,
    'qualifiers', array_length(v_qualifiers, 1),
    'tables_created', v_tables_created
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_advance_multi_round(uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 10. admin_archive_tournament — archivage complet avec statistiques
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_archive_tournament(_tid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_is_admin boolean;
  trn        record;
  v_archive  jsonb;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO trn FROM public.tournaments WHERE id = _tid;
  IF trn IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;

  IF trn.archived_at IS NOT NULL THEN
    RAISE EXCEPTION 'Ce tournoi est déjà archivé';
  END IF;

  -- Construire le snapshot complet
  SELECT jsonb_build_object(
    'tournament', row_to_json(t.*),
    'podium', t.podium,
    'total_players', (SELECT COUNT(*) FROM public.tournament_registrations WHERE tournament_id = _tid),
    'total_matches', (SELECT COUNT(*) FROM public.tournament_matches WHERE tournament_id = _tid AND is_bye = false),
    'matches', (
      SELECT jsonb_agg(jsonb_build_object(
        'id', m.id, 'round', m.round, 'table_index', m.table_index,
        'player_ids', m.player_ids, 'winner_id', m.winner_id,
        'match_rankings', m.match_rankings,
        'status', m.status, 'is_bye', m.is_bye,
        'rematch_count', m.rematch_count,
        'admin_notes', m.admin_notes,
        'game_id', m.game_id, 'finished_at', m.finished_at
      ) ORDER BY m.round, m.table_index)
      FROM public.tournament_matches m WHERE m.tournament_id = _tid
    ),
    'claims', (
      SELECT jsonb_agg(row_to_json(c.*))
      FROM public.tournament_claims c WHERE c.tournament_id = _tid
    ),
    'prize_pool', t.prize_pool,
    'reward_distribution', t.reward_distribution,
    'platform_cut_ar', t.platform_cut_ar,
    'rewards_paid_at', t.rewards_paid_at,
    'archived_at', now()
  ) INTO v_archive
  FROM public.tournaments t WHERE t.id = _tid;

  -- Enregistrer l'archive dans extra_config (ou table dédiée si elle existe)
  UPDATE public.tournaments
    SET archived_at  = now(),
        extra_config = COALESCE(extra_config, '{}') || jsonb_build_object('archive_snapshot', v_archive)
    WHERE id = _tid;

  RETURN jsonb_build_object('ok', true, 'archive', v_archive);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_archive_tournament(uuid) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 11. admin_validate_tournament_end — valide la fin + distribue les gains
--     L'admin désigne le podium, le système crédite automatiquement
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_validate_tournament_end(
  _tid       uuid,
  _first_id  uuid,
  _second_id uuid,
  _third_id  uuid DEFAULT NULL,
  _auto_archive boolean DEFAULT false
)
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

  -- Distribuer les gains
  SELECT public.admin_distribute_tournament_rewards(_tid, _first_id, _second_id, _third_id)
    INTO v_result;

  -- Archiver si demandé
  IF _auto_archive THEN
    PERFORM public.admin_archive_tournament(_tid);
  END IF;

  RETURN v_result;
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_validate_tournament_end(uuid,uuid,uuid,uuid,boolean) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 12. Mettre à jour admin_create_game_tournament pour supporter les nouveaux paramètres
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_create_game_tournament(
  _name                    text,
  _game_slug               text,
  _max_players             int      DEFAULT 8,
  _stake                   numeric  DEFAULT 0,
  _is_free                 boolean  DEFAULT true,
  _total_rounds            int      DEFAULT 3,
  _description             text     DEFAULT NULL,
  _rewards_text            text     DEFAULT NULL,
  _registration_opens_at   timestamptz DEFAULT NULL,
  _registration_closes_at  timestamptz DEFAULT NULL,
  _bye_strategy            text     DEFAULT 'random',
  _move_timer_secs         int      DEFAULT 25,
  _join_timeout_secs       int      DEFAULT 240,
  _disconnect_grace_secs   int      DEFAULT 120,
  -- Nouveaux paramètres
  _format                  text     DEFAULT 'elimination',
  _players_per_table       int      DEFAULT 2,
  _qualifiers_per_table    int      DEFAULT 1,
  _grace_period_secs       int      DEFAULT 300,
  _auto_start_mins         int      DEFAULT 10,
  _reward_first_pct        numeric  DEFAULT 60,
  _reward_second_pct       numeric  DEFAULT 20,
  _reward_third_pct        numeric  DEFAULT 10,
  _reward_platform_pct     numeric  DEFAULT 10
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
  v_ppt        int;
  v_qpt        int;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  IF _name IS NULL OR trim(_name) = '' THEN RAISE EXCEPTION 'Nom requis'; END IF;
  IF _max_players < 2 THEN RAISE EXCEPTION 'Minimum 2 joueurs'; END IF;
  IF _game_slug IS NULL OR _game_slug NOT IN ('chess','fanorona','ludo','poker','rami','domino','all')
    THEN RAISE EXCEPTION 'Jeu invalide'; END IF;

  -- Valider répartition
  IF ABS((_reward_first_pct + _reward_second_pct + _reward_third_pct + _reward_platform_pct) - 100) > 0.01 THEN
    RAISE EXCEPTION 'La répartition doit totaliser 100%%';
  END IF;

  SELECT COALESCE(MAX(season), 0) + 1 INTO v_season FROM public.tournaments;
  v_stake := CASE WHEN _is_free THEN 0 ELSE _stake END;

  -- Ajuster players_per_table selon le format
  v_ppt := CASE
    WHEN _format = 'tables' THEN COALESCE(_players_per_table, 4)
    ELSE 2  -- élimination directe = 1v1
  END;
  v_qpt := CASE
    WHEN _format = 'tables' THEN COALESCE(_qualifiers_per_table, 2)
    ELSE 1
  END;

  IF _game_slug = 'domino' AND _format = 'elimination' THEN
    -- Déléguer au créateur Domino existant
    SELECT public.admin_create_domino_tournament(
      _name, _max_players, v_stake, _is_free, _description, _rewards_text,
      _registration_opens_at, _registration_closes_at,
      _bye_strategy, _move_timer_secs, _join_timeout_secs, _disconnect_grace_secs
    ) INTO v_tid;

    IF v_tid IS NULL THEN
      SELECT id INTO v_tid FROM public.tournaments WHERE name = _name ORDER BY created_at DESC LIMIT 1;
    END IF;

    -- Appliquer les nouveaux champs
    UPDATE public.tournaments
      SET reward_distribution = jsonb_build_object(
            'first', _reward_first_pct, 'second', _reward_second_pct,
            'third', _reward_third_pct, 'platform', _reward_platform_pct),
          format = _format,
          players_per_table = v_ppt,
          qualifiers_per_table = v_qpt,
          grace_period_secs = _grace_period_secs,
          auto_start_mins = _auto_start_mins
      WHERE id = v_tid;

    RETURN v_tid;
  END IF;

  INSERT INTO public.tournaments(
    name, game_slug, mode, max_players, stake, prize_pool, is_free,
    total_rounds, current_round, status, season,
    description, rewards_text,
    registration_opens_at, registration_closes_at,
    move_timer_secs, join_timeout_secs, disconnect_grace_secs,
    reward_distribution, format, players_per_table, qualifiers_per_table,
    grace_period_secs, auto_start_mins
  ) VALUES (
    trim(_name), _game_slug,
    CASE WHEN _format = 'tables' THEN 'tables' ELSE '1v1' END,
    _max_players, v_stake,
    CASE WHEN _is_free THEN 0 ELSE v_stake * _max_players * (1 - _reward_platform_pct/100.0) END,
    _is_free, _total_rounds, 0, 'open', v_season,
    _description, _rewards_text, _registration_opens_at, _registration_closes_at,
    _move_timer_secs, _join_timeout_secs, _disconnect_grace_secs,
    jsonb_build_object(
      'first', _reward_first_pct, 'second', _reward_second_pct,
      'third', _reward_third_pct, 'platform', _reward_platform_pct),
    _format, v_ppt, v_qpt, _grace_period_secs, _auto_start_mins
  ) RETURNING id INTO v_tid;

  BEGIN
    INSERT INTO public.admin_action_logs(admin_id, action, target_id, note)
      VALUES (v_uid, 'create_tournament', v_tid,
              _game_slug || ' · format=' || _format || ' · ' || _max_players || ' joueurs')
    ON CONFLICT DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN v_tid;
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_create_game_tournament(text,text,int,numeric,boolean,int,text,text,timestamptz,timestamptz,text,int,int,int,text,int,int,int,int,numeric,numeric,numeric,numeric) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 13. Vue admin enrichie pour le tableau de bord des tournois
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.admin_tournament_dashboard AS
SELECT
  t.id,
  t.name,
  t.game_slug,
  t.format,
  t.status,
  t.current_round,
  t.total_rounds,
  t.max_players,
  t.players_per_table,
  t.qualifiers_per_table,
  t.prize_pool,
  t.stake,
  t.reward_distribution,
  t.platform_cut_ar,
  t.rewards_paid_at,
  t.archived_at,
  t.podium,
  t.created_at,
  t.finished_at,
  (SELECT COUNT(*) FROM public.tournament_registrations r WHERE r.tournament_id = t.id)::int   AS registered_count,
  (SELECT COUNT(*) FROM public.tournament_matches m WHERE m.tournament_id = t.id AND m.status IN ('pending','running') AND NOT m.is_bye)::int AS active_matches,
  (SELECT COUNT(*) FROM public.tournament_claims c WHERE c.tournament_id = t.id AND c.status IN ('pending','reviewing'))::int AS open_claims
FROM public.tournaments t
ORDER BY t.created_at DESC;

-- ─────────────────────────────────────────────────────────────────────────
-- 14. Indexes de performance
-- ─────────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_tournament_matches_auto_start
  ON public.tournament_matches(auto_start_at)
  WHERE auto_start_at IS NOT NULL AND status IN ('pending','waiting');

CREATE INDEX IF NOT EXISTS idx_tournament_matches_table_index
  ON public.tournament_matches(tournament_id, round, table_index);

CREATE INDEX IF NOT EXISTS idx_tournaments_format_status
  ON public.tournaments(format, status);
