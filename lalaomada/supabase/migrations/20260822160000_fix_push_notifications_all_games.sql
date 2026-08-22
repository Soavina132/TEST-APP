-- ═════════════════════════════════════════════════════════════════════════════
-- Migration: Fix push notifications for ALL events
--
-- 3 problèmes corrigés :
--   1. _send_push_for_notification() n'existait pas en DB → le trigger
--      sur la table notifications n'a jamais été créé → AUCUNE notif push
--      n'était jamais envoyée. Maintenant chaque INSERT dans notifications
--      déclenche l'edge function send-push via pg_net.
--
--   2. Triggers "partie créée" pour TOUS les jeux (domino, poker, chess,
--      fanorona, ludo, rami, billiard, penalty, petanque). Avant, seul domino
--      en avait, et ils avaient été supprimés.
--
--   3. Triggers "partie gagnée" pour TOUS les jeux. Notifie les participants
--      et le gagnant quand le statut passe à 'finished'.
-- ═════════════════════════════════════════════════════════════════════════════

-- ═════════════════════════════════════════════════════════════════════════════
-- PART 1: Trigger sur notifications → appelle send-push edge function
-- ═════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._send_push_for_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_edge_url text;
  v_payload jsonb;
BEGIN
  IF TG_OP <> 'INSERT' THEN RETURN NEW; END IF;

  v_edge_url := 'https://gifwfjgciwbsottztzoc.supabase.co/functions/v1/send-push';

  v_payload := jsonb_build_object(
    'user_id', NEW.user_id,
    'title', NEW.title,
    'body', COALESCE(NEW.body, ''),
    'link', COALESCE(NEW.link, '/'),
    'notification_id', NEW.id
  );

  PERFORM net.http_post(
    url := v_edge_url,
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body := v_payload
  );

  RETURN NEW;
END $function$;

DROP TRIGGER IF EXISTS trg_send_push_for_notification ON public.notifications;
CREATE TRIGGER trg_send_push_for_notification
  AFTER INSERT ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public._send_push_for_notification();

-- ═════════════════════════════════════════════════════════════════════════════
-- PART 2: "Partie créée" — notifie tous les utilisateurs avec push subs
-- ═════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._notify_game_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_host_id uuid;
  v_stake numeric;
  v_game_id uuid;
  v_game_type text;
  v_host_name text;
  v_table_name text := TG_TABLE_NAME;
  v_link text;
BEGIN
  IF TG_OP <> 'INSERT' THEN RETURN NEW; END IF;
  IF NEW.is_private THEN RETURN NEW; END IF;

  v_game_type := replace(v_table_name, '_games', '');
  v_game_id := NEW.id;
  v_stake := NEW.stake;

  -- petanque_games utilise creator_id au lieu de host_id
  IF v_table_name = 'petanque_games' THEN
    v_host_id := NEW.creator_id;
  ELSE
    v_host_id := NEW.host_id;
  END IF;

  IF v_host_id IS NULL THEN RETURN NEW; END IF;

  SELECT COALESCE(pseudo, 'Un joueur') INTO v_host_name
    FROM public.profiles WHERE id = v_host_id;

  v_link := '/' || v_game_type || '/' || v_game_id::text;

  -- Notifier les joueurs avec push subs (max 100), excluant l'hôte et les bannis
  INSERT INTO public.notifications (user_id, kind, title, body, link, ref_id)
  SELECT DISTINCT ps.user_id, 'game_created',
    '🎮 Nouvelle partie ' || initcap(v_game_type) || ' !',
    v_host_name || ' a créé une partie — Mise: ' || v_stake || ' Ar',
    v_link,
    v_game_id
  FROM public.push_subscriptions ps
  WHERE ps.user_id <> v_host_id
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = ps.user_id AND COALESCE(p.banned, false) = false
    )
  LIMIT 100;

  RETURN NEW;
END $$;

-- Attacher le trigger à toutes les tables de jeux
DROP TRIGGER IF EXISTS trg_notify_game_created ON public.domino_games;
CREATE TRIGGER trg_notify_game_created
  AFTER INSERT ON public.domino_games
  FOR EACH ROW EXECUTE FUNCTION public._notify_game_created();

DROP TRIGGER IF EXISTS trg_notify_game_created ON public.poker_games;
CREATE TRIGGER trg_notify_game_created
  AFTER INSERT ON public.poker_games
  FOR EACH ROW EXECUTE FUNCTION public._notify_game_created();

DROP TRIGGER IF EXISTS trg_notify_game_created ON public.chess_games;
CREATE TRIGGER trg_notify_game_created
  AFTER INSERT ON public.chess_games
  FOR EACH ROW EXECUTE FUNCTION public._notify_game_created();

DROP TRIGGER IF EXISTS trg_notify_game_created ON public.fanorona_games;
CREATE TRIGGER trg_notify_game_created
  AFTER INSERT ON public.fanorona_games
  FOR EACH ROW EXECUTE FUNCTION public._notify_game_created();

DROP TRIGGER IF EXISTS trg_notify_game_created ON public.ludo_games;
CREATE TRIGGER trg_notify_game_created
  AFTER INSERT ON public.ludo_games
  FOR EACH ROW EXECUTE FUNCTION public._notify_game_created();

DROP TRIGGER IF EXISTS trg_notify_game_created ON public.rami_games;
CREATE TRIGGER trg_notify_game_created
  AFTER INSERT ON public.rami_games
  FOR EACH ROW EXECUTE FUNCTION public._notify_game_created();

DROP TRIGGER IF EXISTS trg_notify_game_created ON public.billiard_games;
CREATE TRIGGER trg_notify_game_created
  AFTER INSERT ON public.billiard_games
  FOR EACH ROW EXECUTE FUNCTION public._notify_game_created();

DROP TRIGGER IF EXISTS trg_notify_game_created ON public.penalty_games;
CREATE TRIGGER trg_notify_game_created
  AFTER INSERT ON public.penalty_games
  FOR EACH ROW EXECUTE FUNCTION public._notify_game_created();

DROP TRIGGER IF EXISTS trg_notify_game_created ON public.petanque_games;
CREATE TRIGGER trg_notify_game_created
  AFTER INSERT ON public.petanque_games
  FOR EACH ROW EXECUTE FUNCTION public._notify_game_created();

-- ═════════════════════════════════════════════════════════════════════════════
-- PART 3: "Partie gagnée" — notifie les participants et le gagnant
-- ═════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._notify_game_won()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_winner_id uuid;
  v_pot numeric;
  v_commission numeric;
  v_payout numeric;
  v_game_id uuid;
  v_game_type text;
  v_table_name text := TG_TABLE_NAME;
  v_winner_name text;
  v_link text;
  v_part_table text;
  v_loser_title text;
  v_loser_body text;
  v_win_title text;
  v_win_body text;
BEGIN
  IF TG_OP <> 'UPDATE' THEN RETURN NEW; END IF;
  -- Se déclenche uniquement au passage à 'finished'
  IF OLD.status::text = 'finished' OR NEW.status::text <> 'finished' THEN RETURN NEW; END IF;

  v_game_type := replace(v_table_name, '_games', '');
  v_game_id := NEW.id;
  v_link := '/' || v_game_type || '/' || v_game_id::text;

  -- Petanque n'a pas winner_id (utilise winner_team) → skip pour cette table
  IF v_table_name = 'petanque_games' THEN
    RETURN NEW;
  END IF;

  v_winner_id := NEW.winner_id;
  IF v_winner_id IS NULL THEN RETURN NEW; END IF;

  v_pot := COALESCE(NEW.pot, 0);
  v_commission := COALESCE(NEW.commission_pct, 10);
  v_payout := v_pot * (100 - v_commission) / 100;

  SELECT COALESCE(pseudo, 'Un joueur') INTO v_winner_name
    FROM public.profiles WHERE id = v_winner_id;

  v_loser_title := '🏆 ' || v_winner_name || ' a gagné !';
  v_loser_body  := v_winner_name || ' gagne ' || v_payout || ' Ar à la partie de ' || initcap(v_game_type);
  v_win_title   := '🎉 Vous avez gagné ' || v_payout || ' Ar !';
  v_win_body    := 'Vous gagnez la partie de ' || initcap(v_game_type) || ' — ' || v_payout || ' Ar';

  -- ── Notifier les PERDANTS (participants sauf le gagnant) ────────────────────

  IF v_table_name IN ('domino_games', 'fanorona_games', 'ludo_games', 'rami_games') THEN
    -- Ces tables ont une table _participants avec colonne is_bot
    v_part_table := replace(v_table_name, '_games', '_participants');
    EXECUTE format(
      'INSERT INTO public.notifications (user_id, kind, title, body, link, ref_id)
       SELECT p.user_id, $1, $2, $3, $4, $5
       FROM %I p
       WHERE p.game_id = $5
         AND p.user_id IS NOT NULL
         AND COALESCE(p.is_bot, false) = false
         AND p.user_id <> $6',
      v_part_table
    ) USING 'game_won', v_loser_title, v_loser_body, v_link, v_game_id, v_winner_id;

  ELSIF v_table_name = 'billiard_games' THEN
    -- billiard_participants n'a pas de colonne is_bot
    INSERT INTO public.notifications (user_id, kind, title, body, link, ref_id)
    SELECT p.user_id, 'game_won', v_loser_title, v_loser_body, v_link, v_game_id
    FROM public.billiard_participants p
    WHERE p.game_id = v_game_id
      AND p.user_id IS NOT NULL
      AND p.user_id <> v_winner_id;

  ELSIF v_table_name = 'poker_games' THEN
    -- poker utilise poker_players table avec is_bot
    INSERT INTO public.notifications (user_id, kind, title, body, link, ref_id)
    SELECT p.user_id, 'game_won', v_loser_title, v_loser_body, v_link, v_game_id
    FROM public.poker_players p
    WHERE p.game_id = v_game_id
      AND p.user_id IS NOT NULL
      AND COALESCE(p.is_bot, false) = false
      AND p.user_id <> v_winner_id;

  ELSIF v_table_name = 'chess_games' THEN
    -- chess utilise white_id et black_id
    INSERT INTO public.notifications (user_id, kind, title, body, link, ref_id)
    SELECT u, 'game_won', v_loser_title, v_loser_body, v_link, v_game_id
    FROM (VALUES (NEW.white_id), (NEW.black_id)) AS t(u)
    WHERE u IS NOT NULL AND u <> v_winner_id;

  ELSIF v_table_name = 'penalty_games' THEN
    -- penalty utilise player1_id et player2_id
    INSERT INTO public.notifications (user_id, kind, title, body, link, ref_id)
    SELECT u, 'game_won', v_loser_title, v_loser_body, v_link, v_game_id
    FROM (VALUES (NEW.player1_id), (NEW.player2_id)) AS t(u)
    WHERE u IS NOT NULL AND u <> v_winner_id;

  END IF;

  -- ── Notifier le GAGNANT ────────────────────────────────────────────────────
  INSERT INTO public.notifications (user_id, kind, title, body, link, ref_id)
  VALUES (v_winner_id, 'game_won', v_win_title, v_win_body, v_link, v_game_id);

  RETURN NEW;
END $$;

-- Attacher le trigger à toutes les tables de jeux (sauf petanque — géré différemment)
DROP TRIGGER IF EXISTS trg_notify_game_won ON public.domino_games;
CREATE TRIGGER trg_notify_game_won
  AFTER UPDATE ON public.domino_games
  FOR EACH ROW EXECUTE FUNCTION public._notify_game_won();

DROP TRIGGER IF EXISTS trg_notify_game_won ON public.poker_games;
CREATE TRIGGER trg_notify_game_won
  AFTER UPDATE ON public.poker_games
  FOR EACH ROW EXECUTE FUNCTION public._notify_game_won();

DROP TRIGGER IF EXISTS trg_notify_game_won ON public.chess_games;
CREATE TRIGGER trg_notify_game_won
  AFTER UPDATE ON public.chess_games
  FOR EACH ROW EXECUTE FUNCTION public._notify_game_won();

DROP TRIGGER IF EXISTS trg_notify_game_won ON public.fanorona_games;
CREATE TRIGGER trg_notify_game_won
  AFTER UPDATE ON public.fanorona_games
  FOR EACH ROW EXECUTE FUNCTION public._notify_game_won();

DROP TRIGGER IF EXISTS trg_notify_game_won ON public.ludo_games;
CREATE TRIGGER trg_notify_game_won
  AFTER UPDATE ON public.ludo_games
  FOR EACH ROW EXECUTE FUNCTION public._notify_game_won();

DROP TRIGGER IF EXISTS trg_notify_game_won ON public.rami_games;
CREATE TRIGGER trg_notify_game_won
  AFTER UPDATE ON public.rami_games
  FOR EACH ROW EXECUTE FUNCTION public._notify_game_won();

DROP TRIGGER IF EXISTS trg_notify_game_won ON public.billiard_games;
CREATE TRIGGER trg_notify_game_won
  AFTER UPDATE ON public.billiard_games
  FOR EACH ROW EXECUTE FUNCTION public._notify_game_won();

DROP TRIGGER IF EXISTS trg_notify_game_won ON public.penalty_games;
CREATE TRIGGER trg_notify_game_won
  AFTER UPDATE ON public.penalty_games
  FOR EACH ROW EXECUTE FUNCTION public._notify_game_won();

-- ═════════════════════════════════════════════════════════════════════════════
-- PART 4: Sécurité — revoke access aux fonctions internes
-- ═════════════════════════════════════════════════════════════════════════════

REVOKE EXECUTE ON FUNCTION public._send_push_for_notification() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._notify_game_created() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._notify_game_won() FROM anon, authenticated;
