-- ============================================
-- Fix 1: Timer d'expiration des salles d'attente
-- Fix 2: Placement symétrique 1v1 Ludo
-- ============================================

-- ============================================
-- Fix 1: cleanup_stale_open_games était un faux (SELECT 0)
-- Maintenant il appelle _auto_cancel_open_games() qui annule+rembourse
-- ============================================
CREATE OR REPLACE FUNCTION public.cleanup_stale_open_games()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
BEGIN
  PERFORM public._auto_cancel_open_games();
  RETURN 0;
END;
$function$;

-- Ajout du support Poker dans _auto_cancel_open_games
CREATE OR REPLACE FUNCTION public._auto_cancel_open_games()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  r record;
  v_min int;
  v_iv interval;
BEGIN
  SELECT COALESCE(game_invite_timeout_minutes, 6) INTO v_min FROM public.app_settings WHERE id = 1;
  IF v_min IS NULL OR v_min <= 0 THEN v_min := 6; END IF;
  v_iv := (v_min || ' minutes')::interval;

  -- Fanorona
  FOR r IN SELECT id, stake FROM public.fanorona_games WHERE status='open' AND created_at < now() - v_iv
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      FROM public.fanorona_participants pp
      WHERE pp.game_id = r.id AND pp.user_id = p.id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT user_id, 'fanorona_refund', r.stake, r.id, 'Auto-cancelled'
      FROM public.fanorona_participants WHERE game_id = r.id;
    UPDATE public.fanorona_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;

  -- Chess
  FOR r IN SELECT id, stake FROM public.chess_games WHERE status='open' AND created_at < now() - v_iv
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      WHERE p.id IN (SELECT host_id FROM public.chess_games WHERE id=r.id);
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT host_id, 'chess_refund', r.stake, r.id, 'Auto-cancelled'
      FROM public.chess_games WHERE id=r.id;
    UPDATE public.chess_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;

  -- Domino
  FOR r IN SELECT id, stake FROM public.domino_games WHERE status='open' AND created_at < now() - v_iv
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      FROM public.domino_participants pp
      WHERE pp.game_id = r.id AND pp.user_id = p.id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT user_id, 'domino_refund', r.stake, r.id, 'Auto-cancelled'
      FROM public.domino_participants WHERE game_id = r.id;
    UPDATE public.domino_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;

  -- Rami (status='waiting')
  FOR r IN SELECT id, stake FROM public.rami_games WHERE status='waiting' AND created_at < now() - v_iv
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      FROM public.rami_participants pp
      WHERE pp.game_id = r.id AND pp.user_id = p.id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT user_id, 'rami_refund', r.stake, r.id, 'Auto-cancelled'
      FROM public.rami_participants WHERE game_id = r.id;
    UPDATE public.rami_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;

  -- Ludo
  FOR r IN SELECT id, stake FROM public.ludo_games WHERE status='open' AND created_at < now() - v_iv
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      FROM public.ludo_participants pp
      WHERE pp.game_id = r.id AND pp.user_id = p.id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT user_id, 'ludo_refund', r.stake, r.id, 'Auto-cancelled'
      FROM public.ludo_participants WHERE game_id = r.id;
    UPDATE public.ludo_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;

  -- Poker (nouveau)
  FOR r IN SELECT id, stake FROM public.poker_games WHERE status='open' AND created_at < now() - v_iv
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      FROM public.poker_players pp
      WHERE pp.game_id = r.id AND pp.user_id = p.id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT user_id, 'poker_refund', r.stake, r.id, 'Auto-cancelled'
      FROM public.poker_players WHERE game_id = r.id;
    UPDATE public.poker_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;
END;
$function$;

-- ============================================
-- Fix 2: Placement symétrique 1v1 (diagonal) Ludo
-- 2 joueurs: red (TL) + yellow (BR) = diagonal
-- 3 joueurs: red (TL) + yellow (BR) + blue (BL)
-- 4 joueurs: red + green + yellow + blue (complet)
-- ============================================

-- player_add_bot
CREATE OR REPLACE FUNCTION public.player_add_bot(_game_id uuid, _bot_name text DEFAULT 'Bot'::text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_game public.ludo_games%ROWTYPE;
  v_count INT;
  v_slot INT;
  v_color TEXT;
  v_colors TEXT[];
  v_uid UUID := auth.uid();
  v_is_participant BOOLEAN;
  v_team INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF v_game.id IS NULL OR v_game.status <> 'open' THEN
    RAISE EXCEPTION 'Partie non ouverte';
  END IF;
  SELECT EXISTS(
    SELECT 1 FROM public.ludo_participants
    WHERE game_id = _game_id AND user_id = v_uid
  ) INTO v_is_participant;
  IF NOT v_is_participant THEN
    RAISE EXCEPTION 'Seuls les participants peuvent ajouter un bot';
  END IF;
  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = _game_id;
  IF v_count >= v_game.max_players THEN
    RAISE EXCEPTION 'Partie pleine';
  END IF;
  IF v_game.stake > 0 AND NOT v_game.is_private THEN
    RAISE EXCEPTION 'Bots réservés aux parties amicales (mise 0) ou privées';
  END IF;
  v_slot := v_count;
  v_colors := CASE v_game.max_players
    WHEN 2 THEN ARRAY['red', 'yellow']
    WHEN 3 THEN ARRAY['red', 'yellow', 'blue']
    ELSE ARRAY['red', 'green', 'yellow', 'blue']
  END;
  v_color := v_colors[v_slot + 1];
  IF v_game.match_type = 'groupe' THEN
    v_team := CASE WHEN v_slot % 2 = 0 THEN 1 ELSE 2 END;
  ELSE
    v_team := NULL;
  END IF;
  INSERT INTO public.ludo_participants(
    game_id, user_id, slot, color, is_bot, bot_name, display_name,
    bot_intelligence, bot_win_bias, ready, team
  ) VALUES (
    _game_id, NULL, v_slot, v_color, TRUE, _bot_name, _bot_name,
    70, 0, TRUE, v_team
  );
  IF v_count + 1 = v_game.max_players THEN
    UPDATE public.ludo_games
      SET status = 'playing',
          started_at = now(),
          state = public._ludo_init_state(v_game.max_players),
          current_turn = 0
      WHERE id = _game_id;
  END IF;
END;
$function$;

-- join_game
CREATE OR REPLACE FUNCTION public.join_game(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_balance NUMERIC; v_game public.ludo_games%ROWTYPE;
  v_count INT; v_slot INT; v_color TEXT; v_paused BOOLEAN; v_banned BOOLEAN;
  v_colors TEXT[];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT paused INTO v_paused FROM public.app_settings WHERE id=1;
  IF COALESCE(v_paused,FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned INTO v_banned FROM public.profiles WHERE id=v_uid;
  IF COALESCE(v_banned,FALSE) THEN RAISE EXCEPTION 'Compte banni'; END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_game.status <> 'open' THEN RAISE EXCEPTION 'Partie déjà commencée'; END IF;
  IF EXISTS (SELECT 1 FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid) THEN
    RAISE EXCEPTION 'Déjà inscrit'; END IF;
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id=v_uid FOR UPDATE;
  IF v_balance < v_game.stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_count >= v_game.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;
  v_slot := v_count;
  v_colors := CASE v_game.max_players
    WHEN 2 THEN ARRAY['red', 'yellow']
    WHEN 3 THEN ARRAY['red', 'yellow', 'blue']
    ELSE ARRAY['red', 'green', 'yellow', 'blue']
  END;
  v_color := v_colors[v_slot+1];
  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name)
    SELECT _game_id, v_uid, v_slot, v_color, pseudo FROM public.profiles WHERE id=v_uid;
  UPDATE public.profiles SET balance_ar = balance_ar - v_game.stake WHERE id=v_uid;
  UPDATE public.ludo_games SET pot = pot + v_game.stake WHERE id=_game_id;
  INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
    VALUES (v_uid,'stake',-v_game.stake,_game_id,'Mise join partie');
  PERFORM public._ludo_maybe_auto_start(_game_id);
END;
$function$;

-- admin_add_bot
CREATE OR REPLACE FUNCTION public.admin_add_bot(_game_id uuid, _bot_name text, _intelligence integer DEFAULT 70, _win_bias integer DEFAULT 0)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_game public.ludo_games%ROWTYPE;
  v_count INT;
  v_slot INT;
  v_color TEXT;
  v_colors TEXT[];
  v_team INT;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF v_game.id IS NULL OR v_game.status NOT IN ('open','waiting') THEN
    RAISE EXCEPTION 'Partie non ouverte';
  END IF;
  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = _game_id;
  IF v_count >= v_game.max_players THEN
    RAISE EXCEPTION 'Partie pleine';
  END IF;
  v_slot := v_count;
  v_colors := CASE v_game.max_players
    WHEN 2 THEN ARRAY['red', 'yellow']
    WHEN 3 THEN ARRAY['red', 'yellow', 'blue']
    ELSE ARRAY['red', 'green', 'yellow', 'blue']
  END;
  v_color := v_colors[(v_slot % array_length(v_colors,1)) + 1];
  v_team := v_slot;
  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, team, is_bot, bot_name, bot_intelligence, bot_win_bias)
  VALUES (_game_id, gen_random_uuid(), v_slot, v_color, v_team, true, _bot_name, _intelligence, _win_bias);
END;
$function$;

-- admin_join_game
CREATE OR REPLACE FUNCTION public.admin_join_game(_game_id uuid, _display_name text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE v_uid uuid:=auth.uid(); v_game public.ludo_games%ROWTYPE; v_count int; v_slot int; v_color text;
  v_colors text[]; v_name text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL OR v_game.status <> 'open' THEN RAISE EXCEPTION 'Partie non ouverte'; END IF;
  IF EXISTS(SELECT 1 FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid) THEN
    RAISE EXCEPTION 'Déjà inscrit'; END IF;
  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_count >= v_game.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;
  v_slot:=v_count;
  v_colors := CASE v_game.max_players
    WHEN 2 THEN ARRAY['red', 'yellow']
    WHEN 3 THEN ARRAY['red', 'yellow', 'blue']
    ELSE ARRAY['red', 'green', 'yellow', 'blue']
  END;
  v_color:=v_colors[v_slot+1];
  SELECT COALESCE(NULLIF(_display_name,''), pseudo) INTO v_name FROM public.profiles WHERE id=v_uid;
  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name,ready)
    VALUES (_game_id, v_uid, v_slot, v_color, v_name, true);
END;
$function$;
