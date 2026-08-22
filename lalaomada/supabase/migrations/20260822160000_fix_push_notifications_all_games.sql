-- ═════════════════════════════════════════════════════════════════════════════
-- Migration: Fix push notifications for remaining games + fix domino_forfeit
--
-- Corrections :
--   1. _send_push_for_notification() — trigger sur notifications pour appeler
--      l'edge function send-push via pg_net (manquait en DB)
--   2. Triggers "partie créée" pour les jeux ACTIFS :
--      domino, chess, fanorona, ludo, rami, billiard
--      (penalty, petanque, poker = jeux supprimés — PAS de triggers)
--   3. Triggers "partie gagnée" pour les mêmes jeux actifs
--   4. Fix domino_forfeit : utilise 'note' au lieu de 'description' (la colonne
--      n'existe pas dans transactions)
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
-- Jeux actifs uniquement : domino, chess, fanorona, ludo, rami, billiard
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

  -- Toutes les tables actives utilisent host_id
  v_host_id := NEW.host_id;

  IF v_host_id IS NULL THEN RETURN NEW; END IF;

  SELECT COALESCE(pseudo, 'Un joueur') INTO v_host_name
    FROM public.profiles WHERE id = v_host_id;

  v_link := '/' || v_game_type || '/' || v_game_id::text;

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

-- Triggers "partie créée" pour les jeux ACTIFS uniquement
DROP TRIGGER IF EXISTS trg_notify_game_created ON public.domino_games;
CREATE TRIGGER trg_notify_game_created
  AFTER INSERT ON public.domino_games
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

-- Supprimer les triggers pour les jeux SUPPRIMÉS
DROP TRIGGER IF EXISTS trg_notify_game_created ON public.penalty_games;
DROP TRIGGER IF EXISTS trg_notify_game_created ON public.petanque_games;
DROP TRIGGER IF EXISTS trg_notify_game_created ON public.poker_games;

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
  IF OLD.status::text = 'finished' OR NEW.status::text <> 'finished' THEN RETURN NEW; END IF;

  v_game_type := replace(v_table_name, '_games', '');
  v_game_id := NEW.id;
  v_link := '/' || v_game_type || '/' || v_game_id::text;

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

  IF v_table_name IN ('domino_games', 'fanorona_games', 'ludo_games', 'rami_games') THEN
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
    INSERT INTO public.notifications (user_id, kind, title, body, link, ref_id)
    SELECT p.user_id, 'game_won', v_loser_title, v_loser_body, v_link, v_game_id
    FROM public.billiard_participants p
    WHERE p.game_id = v_game_id
      AND p.user_id IS NOT NULL
      AND p.user_id <> v_winner_id;

  ELSIF v_table_name = 'chess_games' THEN
    INSERT INTO public.notifications (user_id, kind, title, body, link, ref_id)
    SELECT u, 'game_won', v_loser_title, v_loser_body, v_link, v_game_id
    FROM (VALUES (NEW.white_id), (NEW.black_id)) AS t(u)
    WHERE u IS NOT NULL AND u <> v_winner_id;

  END IF;

  -- Notifier le GAGNANT
  INSERT INTO public.notifications (user_id, kind, title, body, link, ref_id)
  VALUES (v_winner_id, 'game_won', v_win_title, v_win_body, v_link, v_game_id);

  RETURN NEW;
END $$;

-- Triggers "partie gagnée" pour les jeux ACTIFS uniquement
DROP TRIGGER IF EXISTS trg_notify_game_won ON public.domino_games;
CREATE TRIGGER trg_notify_game_won
  AFTER UPDATE ON public.domino_games
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

-- Supprimer les triggers pour les jeux SUPPRIMÉS
DROP TRIGGER IF EXISTS trg_notify_game_won ON public.penalty_games;
DROP TRIGGER IF EXISTS trg_notify_game_won ON public.petanque_games;
DROP TRIGGER IF EXISTS trg_notify_game_won ON public.poker_games;

-- ═════════════════════════════════════════════════════════════════════════════
-- PART 4: Fix domino_forfeit — 'description' n'existe pas, c'est 'note'
-- ═════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.domino_forfeit(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  _uid uuid := auth.uid();
  _game record;
  _part public.domino_participants;
  _is_host boolean;
  _remaining int;
  _p record;
BEGIN
  SELECT * INTO _game FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF _game.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;

  SELECT * INTO _part FROM public.domino_participants
    WHERE game_id = _game_id AND user_id = _uid AND forfeited = false;
  IF NOT FOUND THEN RAISE EXCEPTION 'Non participant'; END IF;

  IF _game.status = 'open' THEN
    _is_host := (_game.host_id = _uid);
    IF _is_host THEN
      FOR _p IN SELECT user_id FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false LOOP
        UPDATE public.profiles SET balance_ar = balance_ar + _game.stake WHERE id = _p.user_id;
        INSERT INTO public.transactions(user_id, type, amount, note)
          VALUES (_p.user_id, 'domino_refund', _game.stake, 'Annulation salle d''attente (hote)');
      END LOOP;
      UPDATE public.domino_games SET status = 'cancelled', finished_at = now(), updated_at = now() WHERE id = _game_id;
    ELSE
      UPDATE public.profiles SET balance_ar = balance_ar + _game.stake WHERE id = _uid;
      INSERT INTO public.transactions(user_id, type, amount, note)
        VALUES (_uid, 'domino_refund', _game.stake, 'Quitter salle d''attente');
      DELETE FROM public.domino_participants WHERE id = _part.id;
      UPDATE public.domino_games SET pot = pot - _game.stake, updated_at = now() WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;

  PERFORM public.domino_forfeit_internal(_game_id, _part);
END;
$function$;

-- ═════════════════════════════════════════════════════════════════════════════
-- PART 5: Sécurité
-- ═════════════════════════════════════════════════════════════════════════════

REVOKE EXECUTE ON FUNCTION public._send_push_for_notification() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._notify_game_created() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._notify_game_won() FROM anon, authenticated;
