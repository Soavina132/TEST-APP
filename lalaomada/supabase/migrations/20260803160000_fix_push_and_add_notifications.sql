-- ═════════════════════════════════════════════════════════════════════════════
-- Migration : Fix "column value does not exist" + Add push notifications
--
-- Bug corrigé :
--   La fonction _send_push_for_notification() faisait :
--     SELECT value FROM app_settings WHERE key = 'edge_function_url'
--   Mais app_settings n'a pas de colonnes key/value → erreur à chaque notification.
--
-- Notifications ajoutées (push pour joueurs hors-ligne) :
--   1. "X joueur est en ligne"     — quand un joueur se connecte
--   2. "Partie (jeu) créée"        — quand une partie domino est créée
--   3. "X gagne (montant)"         — quand un joueur gagne une partie
--   4. "Message dans le groupe"    — quand un message est envoyé dans un salon
-- ═════════════════════════════════════════════════════════════════════════════

-- ═════════════════════════════════════════════════════════════════════════════
-- FIX 1 : Corriger le trigger _send_push_for_notification()
-- Remplace le SELECT sur colonnes inexistantes par l'URL codée en dur.
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

  -- URL codée en dur (évite le SELECT sur colonnes inexistantes)
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

-- ═════════════════════════════════════════════════════════════════════════════
-- FIX 2 : Notification "Partie créée"
-- Trigger sur domino_games INSERT → notifie les joueurs avec push subs
-- ═════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._notify_domino_game_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_host_name text;
BEGIN
  IF TG_OP <> 'INSERT' THEN RETURN NEW; END IF;
  IF NEW.is_private THEN RETURN NEW; END IF;

  SELECT COALESCE(pseudo, 'Un joueur') INTO v_host_name
    FROM public.profiles WHERE id = NEW.host_id;

  -- Notifier les joueurs avec push subs (max 100), excluant l'hôte
  -- et les joueurs bannis
  INSERT INTO public.notifications (user_id, kind, title, body, link, ref_id)
  SELECT DISTINCT ps.user_id, 'game_created',
    '🎮 Nouvelle partie Domino !',
    v_host_name || ' a créé une partie — Mise: ' || NEW.stake || ' Ar',
    '/domino/' || NEW.id::text,
    NEW.id
  FROM public.push_subscriptions ps
  WHERE ps.user_id <> NEW.host_id
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = ps.user_id AND COALESCE(p.banned, false) = false
    )
  LIMIT 100;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_notify_domino_created ON public.domino_games;
CREATE TRIGGER trg_notify_domino_created
  AFTER INSERT ON public.domino_games
  FOR EACH ROW EXECUTE FUNCTION public._notify_domino_game_created();

-- ═════════════════════════════════════════════════════════════════════════════
-- FIX 3 : Notification "X gagne (montant)"
-- Trigger sur domino_games UPDATE (status → finished) → notifie les participants
-- ═════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._notify_domino_game_finished()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_winner_name text;
  v_payout numeric;
BEGIN
  IF TG_OP <> 'UPDATE' THEN RETURN NEW; END IF;
  -- Ne se déclenche qu'au passage à 'finished'
  IF OLD.status = 'finished' OR NEW.status <> 'finished' THEN RETURN NEW; END IF;
  IF NEW.winner_id IS NULL THEN RETURN NEW; END IF;

  SELECT COALESCE(pseudo, 'Un joueur') INTO v_winner_name
    FROM public.profiles WHERE id = NEW.winner_id;

  v_payout := NEW.pot * (100 - NEW.commission_pct) / 100;

  -- Notifier tous les participants (sauf le gagnant)
  INSERT INTO public.notifications (user_id, kind, title, body, link, ref_id)
  SELECT p.user_id, 'game_won',
    '🏆 ' || v_winner_name || ' a gagné !',
    v_winner_name || ' gagne ' || v_payout || ' Ar à la partie de Domino',
    '/domino/' || NEW.id::text,
    NEW.id
  FROM public.domino_participants p
  WHERE p.game_id = NEW.id
    AND p.user_id IS NOT NULL
    AND COALESCE(p.is_bot, false) = false
    AND p.user_id <> NEW.winner_id;

  -- Notifier le gagnant
  INSERT INTO public.notifications (user_id, kind, title, body, link, ref_id)
  VALUES (NEW.winner_id, 'game_won',
    '🎉 Vous avez gagné ' || v_payout || ' Ar !',
    'Vous gagnez la partie de Domino — ' || v_payout || ' Ar',
    '/domino/' || NEW.id::text,
    NEW.id);

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_notify_domino_finished ON public.domino_games;
CREATE TRIGGER trg_notify_domino_finished
  AFTER UPDATE ON public.domino_games
  FOR EACH ROW EXECUTE FUNCTION public._notify_domino_game_finished();

-- ═════════════════════════════════════════════════════════════════════════════
-- FIX 4 : Notification "Message dans le groupe"
-- Trigger sur chat_messages INSERT → notifie les membres du salon
-- ═════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._notify_chat_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_sender_name text;
  v_room_type text;
  v_room_game_id uuid;
  v_link text;
  v_body text;
BEGIN
  IF TG_OP <> 'INSERT' THEN RETURN NEW; END IF;
  IF NEW.user_id IS NULL THEN RETURN NEW; END IF;

  -- Récupérer le pseudo de l'expéditeur
  SELECT COALESCE(pseudo, 'Un joueur') INTO v_sender_name
    FROM public.profiles WHERE id = NEW.user_id;

  -- Récupérer le type de salon
  SELECT type, game_id INTO v_room_type, v_room_game_id
    FROM public.chat_rooms WHERE id = NEW.room_id;

  v_body := COALESCE(NULLIF(NEW.body, ''), '[Image]');
  v_link := '/';

  -- Pour les salons de jeu : lier vers la partie
  IF v_room_type = 'game' AND v_room_game_id IS NOT NULL THEN
    v_link := '/jeux';
    -- Notifier les membres du salon (sauf l'expéditeur)
    INSERT INTO public.notifications (user_id, kind, title, body, link, ref_id)
    SELECT m.user_id, 'chat_message',
      '💬 ' || v_sender_name,
      v_body,
      v_link,
      NEW.room_id
    FROM public.chat_members m
    WHERE m.room_id = NEW.room_id AND m.user_id <> NEW.user_id;

  -- Pour les DM : notifier l'autre personne
  ELSIF v_room_type = 'dm' THEN
    INSERT INTO public.notifications (user_id, kind, title, body, link, ref_id)
    SELECT CASE WHEN dm_user_a = NEW.user_id THEN dm_user_b ELSE dm_user_a END,
      'chat_message',
      '💬 ' || v_sender_name,
      v_body,
      v_link,
      NEW.room_id
    FROM public.chat_rooms
    WHERE id = NEW.room_id AND (dm_user_a = NEW.user_id OR dm_user_b = NEW.user_id);

  -- Pour le salon global : ne pas notifier (trop d'utilisateurs)
  -- Les joueurs en ligne voient déjà en temps réel
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_notify_chat_message ON public.chat_messages;
CREATE TRIGGER trg_notify_chat_message
  AFTER INSERT ON public.chat_messages
  FOR EACH ROW EXECUTE FUNCTION public._notify_chat_message();

-- ═════════════════════════════════════════════════════════════════════════════
-- FIX 5 : Notification "X joueur est en ligne"
-- Trigger sur chat_presence INSERT (première connexion) → notifie les DM
-- ═════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._notify_player_online()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_player_name text;
BEGIN
  IF TG_OP <> 'INSERT' THEN RETURN NEW; END IF;

  SELECT COALESCE(pseudo, 'Un joueur') INTO v_player_name
    FROM public.profiles WHERE id = NEW.user_id;

  -- Notifier les utilisateurs qui ont un DM avec ce joueur
  INSERT INTO public.notifications (user_id, kind, title, body, link, ref_id)
  SELECT CASE WHEN dm_user_a = NEW.user_id THEN dm_user_b ELSE dm_user_a END,
    'player_online',
    '🟢 ' || v_player_name || ' est en ligne',
    v_player_name || ' vient de se connecter',
    '/',
    NEW.user_id
  FROM public.chat_rooms
  WHERE type = 'dm' AND (dm_user_a = NEW.user_id OR dm_user_b = NEW.user_id);

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_notify_player_online ON public.chat_presence;
CREATE TRIGGER trg_notify_player_online
  AFTER INSERT ON public.chat_presence
  FOR EACH ROW EXECUTE FUNCTION public._notify_player_online();
