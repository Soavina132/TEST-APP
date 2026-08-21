-- ════════════════════════════════════════════════════════════════════
-- Waiting Room Improvements
-- 1. start_with_current_players: démarrer avec moins de joueurs que max
-- 2. *_quit: l'hôte qui quitte n'annule plus la partie
-- 3. (auto-unready géré côté frontend)
-- ════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════════
-- 1. FONCTION start_with_current_players
-- ════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.start_with_current_players(_game_type text, _game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_count int;
  v_stake numeric;
  v_max int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;

  -- ── LUDO ──
  IF _game_type = 'ludo' THEN
    SELECT count(*), stake, max_players INTO v_count, v_stake, v_max
    FROM public.ludo_participants p
    JOIN public.ludo_games g ON g.id = p.game_id
    WHERE p.game_id = _game_id AND p.is_bot = false
    GROUP BY g.stake, g.max_players;
    IF v_count < 2 THEN RAISE EXCEPTION 'Au moins 2 joueurs requis'; END IF;
    -- Vérifier que le jeu est open
    PERFORM 1 FROM public.ludo_games WHERE id = _game_id AND status = 'open' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Partie non ouverte'; END IF;
    -- Marquer les bots inutilisés comme forfeited, recalculer max
    DELETE FROM public.ludo_participants WHERE game_id = _game_id AND is_bot = true;
    -- Recalculer le pot
    UPDATE public.ludo_games SET pot = v_stake * v_count, max_players = v_count WHERE id = _game_id;
    -- Tous prêts puis démarrer
    UPDATE public.ludo_participants SET ready = true WHERE game_id = _game_id AND is_bot = false;
    PERFORM public.ludo_set_ready(_game_id, true);

  -- ── DOMINO ──
  ELSIF _game_type = 'domino' THEN
    SELECT count(*), stake INTO v_count, v_stake
    FROM public.domino_participants p
    JOIN public.domino_games g ON g.id = p.game_id
    WHERE p.game_id = _game_id AND p.forfeited = false
    GROUP BY g.stake;
    IF v_count < 2 THEN RAISE EXCEPTION 'Au moins 2 joueurs requis'; END IF;
    PERFORM 1 FROM public.domino_games WHERE id = _game_id AND status = 'open' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Partie non ouverte'; END IF;
    -- Supprimer les bots excédentaires
    DELETE FROM public.domino_participants WHERE game_id = _game_id AND user_id IS NULL;
    -- Recalculer le pot et max_players
    UPDATE public.domino_games SET pot = v_stake * v_count, max_players = v_count WHERE id = _game_id;
    -- Marquer tous prêts et démarrer
    UPDATE public.domino_participants SET ready = true WHERE game_id = _game_id AND forfeited = false;
    PERFORM public.domino_set_ready(_game_id, true);

  -- ── FANORONA ──
  ELSIF _game_type = 'fanorona' THEN
    SELECT count(*), stake INTO v_count, v_stake
    FROM public.fanorona_participants p
    JOIN public.fanorona_games g ON g.id = p.game_id
    WHERE p.game_id = _game_id
    GROUP BY g.stake;
    IF v_count < 2 THEN RAISE EXCEPTION 'Au moins 2 joueurs requis'; END IF;
    PERFORM 1 FROM public.fanorona_games WHERE id = _game_id AND status = 'open' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Partie non ouverte'; END IF;
    UPDATE public.fanorona_games SET pot = v_stake * v_count, max_players = v_count WHERE id = _game_id;
    UPDATE public.fanorona_participants SET ready = true WHERE game_id = _game_id;
    PERFORM public.fanorona_set_ready(_game_id, true);

  -- ── CHESS ──
  ELSIF _game_type = 'chess' THEN
    -- Chess est 1v1, donc "commencer à moins" n'a pas de sens ici
    RAISE EXCEPTION 'Les échecs sont 1v1';

  -- ── RAMI ──
  ELSIF _game_type = 'rami' THEN
    SELECT count(*), stake INTO v_count, v_stake
    FROM public.rami_participants p
    JOIN public.rami_games g ON g.id = p.game_id
    WHERE p.game_id = _game_id
    GROUP BY g.stake;
    IF v_count < 2 THEN RAISE EXCEPTION 'Au moins 2 joueurs requis'; END IF;
    PERFORM 1 FROM public.rami_games WHERE id = _game_id AND status = 'open' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Partie non ouverte'; END IF;
    UPDATE public.rami_games SET pot = v_stake * v_count, max_players = v_count WHERE id = _game_id;
    UPDATE public.rami_participants SET ready = true WHERE game_id = _game_id;
    PERFORM public.rami_set_ready(_game_id, true);

  ELSE
    RAISE EXCEPTION 'Type de jeu non supporté: %', _game_type;
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.start_with_current_players(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_with_current_players(text, uuid) TO authenticated;

-- ════════════════════════════════════════════════════════════════════
-- 2. *_quit: l'hôte qui quitte n'annule plus la partie
-- Tous les joueurs sont traités de la même manière en salle d'attente
-- ════════════════════════════════════════════════════════════════════

-- ── LUDO ──
CREATE OR REPLACE FUNCTION public.ludo_quit(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); g public.ludo_games%ROWTYPE; st jsonb;
  v_slot INT; v_winner UUID; v_remaining INT;
  v_pawns jsonb; i INT; v_part record;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status NOT IN ('playing','open') THEN RAISE EXCEPTION 'Partie terminée'; END IF;
  SELECT slot INTO v_slot FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid AND is_bot=false;
  IF v_slot IS NULL THEN RAISE EXCEPTION 'Non participant'; END IF;

  IF g.status = 'open' THEN
    -- Tous les joueurs (hôte ou non) sont traités de la même manière
    UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id = v_uid;
    UPDATE public.ludo_games SET pot = pot - g.stake WHERE id = _game_id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'refund', g.stake, _game_id, 'Quitter salle d''attente');
    DELETE FROM public.ludo_participants WHERE game_id = _game_id AND user_id = v_uid AND is_bot = false;
    -- Si plus personne, annuler
    PERFORM public._ludo_purge(_game_id);
    RETURN;
  END IF;

  -- Partie en cours : forfait
  v_pawns := g.state->'pawns';
  FOR i IN 0..jsonb_array_length(v_pawns)-1 LOOP
    IF (v_pawns->i->>'player')::int = v_slot THEN
      v_pawns := jsonb_set(v_pawns, ARRAY[i::text, 'finished'], 'true'::jsonb);
    END IF;
  END LOOP;
  UPDATE public.ludo_games SET state = jsonb_set(g.state, ARRAY['pawns'], v_pawns) WHERE id = _game_id;
  UPDATE public.ludo_participants SET finished = true WHERE game_id = _game_id AND user_id = v_uid AND is_bot = false;

  SELECT count(*) INTO v_remaining FROM public.ludo_participants
    WHERE game_id = _game_id AND is_bot = false AND finished = false;
  IF v_remaining <= 1 THEN
    SELECT user_id INTO v_winner FROM public.ludo_participants
      WHERE game_id = _game_id AND is_bot = false AND finished = false LIMIT 1;
    PERFORM public._ludo_finalize(_game_id, v_winner, 'quit');
  END IF;
END;
$function$;

-- ── DOMINO ──
CREATE OR REPLACE FUNCTION public.domino_quit(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_game record;
  v_count int;
BEGIN
  SELECT * INTO v_game FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF v_game.status NOT IN ('playing', 'open') THEN RAISE EXCEPTION 'Partie terminée'; END IF;
  PERFORM 1 FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid AND forfeited = false;
  IF NOT FOUND THEN RAISE EXCEPTION 'Non participant'; END IF;

  IF v_game.status = 'open' THEN
    -- Tous les joueurs traités de la même manière
    UPDATE public.profiles SET balance_ar = balance_ar + v_game.stake WHERE id = v_uid;
    UPDATE public.domino_games SET pot = pot - v_game.stake WHERE id = _game_id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'domino_refund', v_game.stake, _game_id, 'Quitter salle d''attente');
    DELETE FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid;
    -- Si plus personne, annuler
    IF NOT EXISTS (SELECT 1 FROM public.domino_participants WHERE game_id = _game_id) THEN
      UPDATE public.domino_games SET status = 'cancelled', finished_at = now() WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;

  -- Partie en cours : forfait
  PERFORM public.domino_forfeit(_game_id, v_uid);
END;
$function$;

-- ── CHESS ──
CREATE OR REPLACE FUNCTION public.chess_quit(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_game record;
BEGIN
  SELECT * INTO v_game FROM public.chess_games WHERE id = _game_id FOR UPDATE;
  IF v_game.status NOT IN ('playing', 'open') THEN RAISE EXCEPTION 'Partie terminée'; END IF;

  IF v_game.status = 'open' THEN
    -- Tous les joueurs traités de la même manière
    IF v_game.stake > 0 AND (v_game.white_id = v_uid OR v_game.black_id = v_uid) THEN
      UPDATE public.profiles SET balance_ar = balance_ar + v_game.stake WHERE id = v_uid;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (v_uid, 'chess_refund', v_game.stake, _game_id, 'Quitter salle d''attente');
    END IF;
    UPDATE public.chess_games SET
      white_id = CASE WHEN white_id = v_uid THEN NULL ELSE white_id END,
      black_id = CASE WHEN black_id = v_uid THEN NULL ELSE black_id END
    WHERE id = _game_id;
    -- Si plus personne, annuler
    IF NOT EXISTS (SELECT 1 FROM public.chess_games WHERE id = _game_id AND (white_id IS NOT NULL OR black_id IS NOT NULL)) THEN
      UPDATE public.chess_games SET status = 'cancelled', finished_at = now() WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;

  -- Partie en cours : forfait
  PERFORM public.chess_forfeit(_game_id);
END;
$function$;

-- ── FANORONA ──
CREATE OR REPLACE FUNCTION public.fanorona_quit(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_game record;
BEGIN
  SELECT * INTO v_game FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF v_game.status NOT IN ('playing', 'open') THEN RAISE EXCEPTION 'Partie terminée'; END IF;
  PERFORM 1 FROM public.fanorona_participants WHERE game_id = _game_id AND user_id = v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Non participant'; END IF;

  IF v_game.status = 'open' THEN
    -- Tous les joueurs traités de la même manière
    UPDATE public.profiles SET balance_ar = balance_ar + v_game.stake WHERE id = v_uid;
    UPDATE public.fanorona_games SET pot = pot - v_game.stake WHERE id = _game_id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'fanorona_refund', v_game.stake, _game_id, 'Quitter salle d''attente');
    DELETE FROM public.fanorona_participants WHERE game_id = _game_id AND user_id = v_uid;
    -- Si plus personne, annuler
    IF NOT EXISTS (SELECT 1 FROM public.fanorona_participants WHERE game_id = _game_id) THEN
      UPDATE public.fanorona_games SET status = 'cancelled', finished_at = now() WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;

  -- Partie en cours : forfait
  PERFORM public.fanorona_forfeit(_game_id);
END;
$function$;

-- ── RAMI ──
CREATE OR REPLACE FUNCTION public.rami_quit(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_game record;
BEGIN
  SELECT * INTO v_game FROM public.rami_games WHERE id = _game_id FOR UPDATE;
  IF v_game.status NOT IN ('playing', 'open', 'waiting') THEN RAISE EXCEPTION 'Partie terminée'; END IF;
  PERFORM 1 FROM public.rami_participants WHERE game_id = _game_id AND user_id = v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Non participant'; END IF;

  IF v_game.status IN ('open', 'waiting') THEN
    -- Tous les joueurs traités de la même manière
    UPDATE public.profiles SET balance_ar = balance_ar + v_game.stake WHERE id = v_uid;
    UPDATE public.rami_games SET pot = pot - v_game.stake WHERE id = _game_id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'rami_refund', v_game.stake, _game_id, 'Quitter salle d''attente');
    DELETE FROM public.rami_participants WHERE game_id = _game_id AND user_id = v_uid;
    -- Si plus personne, annuler
    IF NOT EXISTS (SELECT 1 FROM public.rami_participants WHERE game_id = _game_id) THEN
      UPDATE public.rami_games SET status = 'cancelled', finished_at = now() WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;

  -- Partie en cours : forfait
  PERFORM public.rami_forfeit(_game_id);
END;
$function$;

-- Mettre à jour safe_leave_waiting_room pour qu'elle appelle *_quit au lieu de sa propre logique
-- (elle reste utilisée pour le timeout auto)
-- Pas besoin de la modifier car elle ne distingue pas hôte/non-hôte

