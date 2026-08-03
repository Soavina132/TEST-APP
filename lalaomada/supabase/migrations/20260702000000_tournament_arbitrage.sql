-- =====================================================================
-- Migration : Arbitrage admin avancé pour les tournois
-- Nouvelles actions : disqualifier, corriger résultat, relancer match
-- =====================================================================

-- ─────────────────────────────────────────────
-- 1. Étendre tournament_matches pour l'arbitrage
-- ─────────────────────────────────────────────

-- Statuts supplémentaires (forfeit, cancelled) + colonne is_bye + admin_notes
ALTER TABLE public.tournament_matches
  DROP CONSTRAINT IF EXISTS tournament_matches_status_check;

ALTER TABLE public.tournament_matches
  ADD CONSTRAINT tournament_matches_status_check
  CHECK (status IN ('pending','running','finished','bye','forfeit','cancelled','rematch'));

ALTER TABLE public.tournament_matches
  ADD COLUMN IF NOT EXISTS is_bye boolean NOT NULL DEFAULT false;

ALTER TABLE public.tournament_matches
  ADD COLUMN IF NOT EXISTS admin_notes text;

-- ─────────────────────────────────────────────
-- 2. admin_list_tournament_matches — liste les matchs d'un tournoi
--    avec les noms des joueurs (pour l'UI arbitrage)
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_list_tournament_matches(_tid uuid)
RETURNS TABLE(
  id            uuid,
  round         integer,
  match_index   integer,
  status        text,
  is_bye        boolean,
  player_ids    uuid[],
  player_names  text[],
  winner_id     uuid,
  winner_name   text,
  game_id       uuid,
  admin_notes   text,
  created_at    timestamptz,
  finished_at   timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_is_admin boolean;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  RETURN QUERY
    SELECT
      m.id,
      m.round,
      m.match_index,
      m.status,
      m.is_bye,
      m.player_ids,
      -- Tableau des pseudos dans le même ordre que player_ids
      ARRAY(
        SELECT COALESCE(p.pseudo, '?')
        FROM unnest(m.player_ids) WITH ORDINALITY AS pid(uid, ord)
        LEFT JOIN public.profiles p ON p.id = pid.uid
        ORDER BY pid.ord
      ) AS player_names,
      m.winner_id,
      (SELECT pseudo FROM public.profiles WHERE id = m.winner_id) AS winner_name,
      m.game_id,
      m.admin_notes,
      m.created_at,
      m.finished_at
    FROM public.tournament_matches m
    WHERE m.tournament_id = _tid
    ORDER BY m.round, m.match_index;
END;
$$;

-- ─────────────────────────────────────────────
-- 3. admin_tournament_disqualify — disqualifie un joueur
--    Le joueur perd son match en cours (forfait), son adversaire avance.
--    Si le joueur n'a pas encore de match en cours, il est juste exclu des inscrits.
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_tournament_disqualify(
  _tid     uuid,
  _user_id uuid,
  _reason  text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_is_admin   boolean;
  v_match      record;
  v_opponent   uuid;
  v_pseudo     text;
  v_trn        record;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO v_trn FROM public.tournaments WHERE id = _tid;
  IF v_trn IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;

  SELECT pseudo INTO v_pseudo FROM public.profiles WHERE id = _user_id;

  -- Chercher un match actif (pending ou running) de ce joueur dans ce tournoi
  SELECT * INTO v_match
    FROM public.tournament_matches
    WHERE tournament_id = _tid
      AND _user_id = ANY(player_ids)
      AND status IN ('pending','running')
      AND is_bye = false
    ORDER BY round DESC
    LIMIT 1;

  IF FOUND THEN
    -- Trouver l'adversaire
    SELECT p INTO v_opponent
      FROM unnest(v_match.player_ids) p
      WHERE p <> _user_id
      LIMIT 1;

    -- Marquer le match en forfait : le joueur disqualifié perd
    UPDATE public.tournament_matches
      SET status       = 'forfeit',
          winner_id    = v_opponent,
          finished_at  = now(),
          admin_notes  = COALESCE(_reason, 'Disqualifié par admin')
      WHERE id = v_match.id;

    -- Annuler la partie liée si elle existe
    IF v_match.game_id IS NOT NULL THEN
      PERFORM public.admin_force_finish_game(v_match.game_id, v_opponent)
      WHERE EXISTS (SELECT 1 FROM public.ludo_games WHERE id = v_match.game_id AND status IN ('open','playing'));
    END IF;
  END IF;

  -- Supprimer des inscrits si le tournoi est encore ouvert
  IF v_trn.status = 'open' THEN
    DELETE FROM public.tournament_participants
      WHERE tournament_id = _tid AND user_id = _user_id;

    -- Rembourser la mise si payant
    IF NOT v_trn.is_free AND v_trn.stake > 0 THEN
      UPDATE public.profiles
        SET balance_ar = balance_ar + v_trn.stake
        WHERE id = _user_id;

      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (_user_id, 'tournament_refund', v_trn.stake, _tid,
                'Remboursement disqualification tournoi');
    END IF;
  END IF;

  -- Log admin
  INSERT INTO public.admin_logs(admin_id, action, target_id, new_value)
    VALUES (v_uid, 'tournament_disqualify', _tid,
            jsonb_build_object(
              'player_id', _user_id,
              'pseudo', v_pseudo,
              'reason', _reason,
              'match_id', v_match.id
            ));

  RETURN jsonb_build_object(
    'ok', true,
    'pseudo', v_pseudo,
    'match_forfeited', v_match.id IS NOT NULL,
    'opponent_advances', v_opponent
  );
END;
$$;

-- ─────────────────────────────────────────────
-- 4. admin_tournament_override_match — corrige un résultat
--    Modifie le gagnant d'un match terminé (bug, erreur système)
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_tournament_override_match(
  _match_id uuid,
  _winner_id uuid,
  _reason   text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_is_admin   boolean;
  v_match      record;
  v_old_winner uuid;
  v_winner_pseudo text;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO v_match
    FROM public.tournament_matches WHERE id = _match_id;
  IF v_match IS NULL THEN RAISE EXCEPTION 'Match introuvable'; END IF;

  -- Vérifier que le gagnant désigné est bien un joueur du match
  IF _winner_id <> ALL(v_match.player_ids) THEN
    RAISE EXCEPTION 'Le joueur désigné ne fait pas partie de ce match';
  END IF;

  v_old_winner := v_match.winner_id;
  SELECT pseudo INTO v_winner_pseudo FROM public.profiles WHERE id = _winner_id;

  -- Corriger le résultat
  UPDATE public.tournament_matches
    SET winner_id   = _winner_id,
        status      = 'finished',
        finished_at = COALESCE(finished_at, now()),
        admin_notes = COALESCE(_reason, 'Résultat corrigé par admin')
    WHERE id = _match_id;

  -- Log
  INSERT INTO public.admin_logs(admin_id, action, target_id, new_value)
    VALUES (v_uid, 'tournament_override_match', _match_id,
            jsonb_build_object(
              'old_winner', v_old_winner,
              'new_winner', _winner_id,
              'new_winner_pseudo', v_winner_pseudo,
              'reason', _reason
            ));

  RETURN jsonb_build_object(
    'ok', true,
    'old_winner_id', v_old_winner,
    'new_winner_id', _winner_id,
    'new_winner_pseudo', v_winner_pseudo
  );
END;
$$;

-- ─────────────────────────────────────────────
-- 5. admin_tournament_rematch — relance un match (reset à pending)
--    Utilisé quand un match est bloqué par un bug serveur
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_tournament_rematch(_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_is_admin boolean;
  v_match    record;
  v_old_game uuid;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO v_match
    FROM public.tournament_matches WHERE id = _match_id;
  IF v_match IS NULL THEN RAISE EXCEPTION 'Match introuvable'; END IF;

  IF v_match.is_bye THEN
    RAISE EXCEPTION 'Impossible de relancer un bye';
  END IF;

  v_old_game := v_match.game_id;

  -- Remettre le match à zéro
  UPDATE public.tournament_matches
    SET status      = 'pending',
        winner_id   = NULL,
        finished_at = NULL,
        game_id     = NULL,
        admin_notes = 'Match relancé par admin (rematch)'
    WHERE id = _match_id;

  -- Annuler/rembourser l'ancienne partie si elle existe encore
  IF v_old_game IS NOT NULL THEN
    UPDATE public.ludo_games
      SET status = 'cancelled'
      WHERE id = v_old_game AND status IN ('open','playing');
  END IF;

  -- Log
  INSERT INTO public.admin_logs(admin_id, action, target_id, new_value)
    VALUES (v_uid, 'tournament_rematch', _match_id,
            jsonb_build_object(
              'tournament_id', v_match.tournament_id,
              'round', v_match.round,
              'old_game_id', v_old_game
            ));

  RETURN jsonb_build_object(
    'ok', true,
    'match_id', _match_id,
    'old_game_id', v_old_game,
    'new_status', 'pending'
  );
END;
$$;

-- Permissions
GRANT EXECUTE ON FUNCTION public.admin_list_tournament_matches(uuid)        TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_tournament_disqualify(uuid,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_tournament_override_match(uuid,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_tournament_rematch(uuid)              TO authenticated;
