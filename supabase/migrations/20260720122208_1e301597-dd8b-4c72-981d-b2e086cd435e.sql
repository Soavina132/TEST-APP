
-- Add "add bot" RPCs for chess, poker, rami, fanorona.
-- Admin can add bots at any stake; non-admins can only add bots on free games where they're a participant.

CREATE OR REPLACE FUNCTION public.rami_add_bot(_game_id uuid, _bot_name text DEFAULT 'Bot')
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_is_admin boolean := public.is_admin();
  g public.rami_games%ROWTYPE;
  v_count int; v_slot int; v_name text;
  v_bot_names text[] := ARRAY['Bot Rija','Bot Naina','Bot Hery','Bot Voara'];
  v_total int; v_ready int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  SELECT * INTO g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status NOT IN ('open','waiting') THEN RAISE EXCEPTION 'La partie a déjà commencé'; END IF;

  IF NOT v_is_admin THEN
    IF COALESCE(g.stake,0) > 0 THEN RAISE EXCEPTION 'Bots réservés aux parties gratuites'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.rami_participants WHERE game_id=_game_id AND user_id=v_uid) THEN
      RAISE EXCEPTION 'Rejoignez la partie pour ajouter un bot';
    END IF;
  END IF;

  SELECT count(*) INTO v_count FROM public.rami_participants WHERE game_id=_game_id;
  IF v_count >= g.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;

  SELECT s INTO v_slot FROM generate_series(0, g.max_players-1) s
    WHERE s NOT IN (SELECT slot FROM public.rami_participants WHERE game_id=_game_id)
    ORDER BY s LIMIT 1;

  v_name := COALESCE(NULLIF(trim(_bot_name),''), v_bot_names[LEAST(v_slot+1, array_length(v_bot_names,1))]);

  INSERT INTO public.rami_participants(game_id, user_id, slot, display_name, hand_count, ready, is_bot, bot_name, bot_intelligence)
    VALUES (_game_id, NULL, v_slot, v_name, 0, TRUE, TRUE, v_name, 70);

  SELECT count(*), count(*) FILTER (WHERE ready) INTO v_total, v_ready
    FROM public.rami_participants WHERE game_id=_game_id;
  IF v_total = g.max_players AND v_ready = v_total THEN
    PERFORM public.rami_start(_game_id);
  END IF;
END $fn$;

CREATE OR REPLACE FUNCTION public.fanorona_add_bot(_game_id uuid, _bot_name text DEFAULT 'Bot')
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_is_admin boolean := public.is_admin();
  g public.fanorona_games%ROWTYPE;
  v_count int; v_slot int; v_color text; v_name text;
  v_total int; v_ready int; v_starter uuid; v_p1 uuid; v_p2 uuid; v_swap boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  SELECT * INTO g FROM public.fanorona_games WHERE id=_game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status <> 'open' THEN RAISE EXCEPTION 'La partie a déjà commencé'; END IF;

  IF NOT v_is_admin THEN
    IF COALESCE(g.stake,0) > 0 THEN RAISE EXCEPTION 'Bots réservés aux parties gratuites'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.fanorona_participants WHERE game_id=_game_id AND user_id=v_uid) THEN
      RAISE EXCEPTION 'Rejoignez la partie pour ajouter un bot';
    END IF;
  END IF;

  SELECT count(*) INTO v_count FROM public.fanorona_participants WHERE game_id=_game_id;
  IF v_count >= 2 THEN RAISE EXCEPTION 'Partie pleine'; END IF;

  v_slot := v_count;
  v_color := CASE WHEN v_slot = 0 THEN 'white' ELSE 'black' END;
  v_name := COALESCE(NULLIF(trim(_bot_name),''),'Bot Moyen');

  INSERT INTO public.fanorona_participants(game_id, user_id, slot, color, display_name, ready, is_bot, bot_intelligence, bot_name)
    VALUES (_game_id, NULL, v_slot, v_color, v_name, TRUE, TRUE, 2, v_name);

  SELECT count(*), count(*) FILTER (WHERE ready) INTO v_total, v_ready
    FROM public.fanorona_participants WHERE game_id=_game_id;
  IF v_total = 2 AND v_ready = 2 THEN
    SELECT user_id INTO v_p1 FROM public.fanorona_participants WHERE game_id=_game_id ORDER BY joined_at LIMIT 1;
    SELECT user_id INTO v_p2 FROM public.fanorona_participants WHERE game_id=_game_id AND (user_id IS NULL OR user_id <> COALESCE(v_p1, '00000000-0000-0000-0000-000000000000')) LIMIT 1;
    v_swap := (get_byte(extensions.gen_random_bytes(1),0) % 2) = 1;
    v_starter := CASE WHEN v_swap THEN v_p2 ELSE v_p1 END;
    UPDATE public.fanorona_participants
       SET slot  = CASE WHEN user_id IS NOT DISTINCT FROM v_starter THEN 0 ELSE 1 END,
           color = CASE WHEN user_id IS NOT DISTINCT FROM v_starter THEN 'white' ELSE 'black' END
     WHERE game_id = _game_id;
    UPDATE public.fanorona_games
       SET status='playing', started_at=now(), current_turn=0,
           state = jsonb_set(state, '{phase}', '"playing"'::jsonb),
           turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')),60) || ' seconds')::interval
     WHERE id=_game_id AND status='open';
  END IF;
END $fn$;

CREATE OR REPLACE FUNCTION public.poker_add_bot(_game_id uuid, _bot_name text DEFAULT 'Bot')
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_is_admin boolean := public.is_admin();
  g public.poker_games%ROWTYPE;
  v_count int; v_seat int; v_name text;
  v_bot_names text[] := ARRAY['Bot Rija','Bot Naina','Bot Hery','Bot Voara','Bot Tojo','Bot Fara'];
  v_bot_uid uuid := gen_random_uuid();
  v_start_chips numeric := 10000;
  v_all_ready boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  SELECT * INTO g FROM public.poker_games WHERE id=_game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status <> 'waiting' THEN RAISE EXCEPTION 'La partie a déjà commencé'; END IF;

  IF NOT v_is_admin THEN
    IF COALESCE(g.stake,0) > 0 THEN RAISE EXCEPTION 'Bots réservés aux parties gratuites'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.poker_players WHERE game_id=_game_id AND user_id=v_uid) THEN
      RAISE EXCEPTION 'Rejoignez la partie pour ajouter un bot';
    END IF;
  END IF;

  SELECT count(*) INTO v_count FROM public.poker_players WHERE game_id=_game_id;
  IF v_count >= g.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;

  SELECT s INTO v_seat FROM generate_series(0, g.max_players-1) s
    WHERE s NOT IN (SELECT seat FROM public.poker_players WHERE game_id=_game_id)
    ORDER BY s LIMIT 1;

  v_name := COALESCE(NULLIF(trim(_bot_name),''), v_bot_names[LEAST(v_seat+1, array_length(v_bot_names,1))]);

  INSERT INTO public.poker_players(game_id, user_id, seat, chips, status, is_ready, is_bot, bot_name, bot_intelligence)
    VALUES (_game_id, v_bot_uid, v_seat, v_start_chips, 'waiting', TRUE, TRUE, v_name, 70);

  SELECT bool_and(is_ready) INTO v_all_ready FROM public.poker_players WHERE game_id=_game_id;
  IF COALESCE(v_all_ready,false) AND (v_count+1) >= 2 THEN
    UPDATE public.poker_games SET status='playing', started_at=now(), updated_at=now() WHERE id=_game_id;
    UPDATE public.poker_players SET status='playing' WHERE game_id=_game_id;
    PERFORM public._poker_deal_hand(_game_id);
    PERFORM public.poker_autoplay_bots(_game_id);
  END IF;
END $fn$;

CREATE OR REPLACE FUNCTION public.chess_add_bot(_game_id uuid, _difficulty text DEFAULT 'medium')
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_is_admin boolean := public.is_admin();
  g public.chess_games%ROWTYPE;
  v_bot_id uuid := gen_random_uuid();
  v_bot_mail text;
  v_intel int;
  v_bot_name text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  SELECT * INTO g FROM public.chess_games WHERE id=_game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status <> 'open' THEN RAISE EXCEPTION 'La partie a déjà commencé'; END IF;
  IF g.white_id IS NOT NULL AND g.black_id IS NOT NULL THEN RAISE EXCEPTION 'Partie pleine'; END IF;

  IF NOT v_is_admin THEN
    IF COALESCE(g.stake,0) > 0 THEN RAISE EXCEPTION 'Bots réservés aux parties gratuites'; END IF;
    IF g.host_id <> v_uid AND g.white_id <> v_uid AND g.black_id <> v_uid THEN
      RAISE EXCEPTION 'Rejoignez la partie pour ajouter un bot';
    END IF;
  END IF;

  v_intel := CASE lower(COALESCE(_difficulty,'medium'))
    WHEN 'easy' THEN 30 WHEN 'hard' THEN 95 WHEN 'expert' THEN 100 ELSE 70 END;
  v_bot_name := CASE v_intel WHEN 30 THEN 'Bot Facile'
                             WHEN 95 THEN 'Bot Fort'
                             WHEN 100 THEN 'Bot Expert'
                             ELSE 'Bot Moyen' END;

  v_bot_mail := 'chessbot_' || v_bot_id::text || '@bot.lalaomada.internal';
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change, email_change_token_new
  ) VALUES (
    v_bot_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    v_bot_mail, crypt(gen_random_uuid()::text, gen_salt('bf')), now(),
    jsonb_build_object('pseudo', v_bot_name, 'is_bot', true),
    now(), now(), '', '', '', ''
  );
  UPDATE public.profiles SET balance_ar=0, pseudo=v_bot_name, avatar_url=NULL, is_bot=true WHERE id=v_bot_id;
  DELETE FROM public.transactions WHERE user_id=v_bot_id;

  IF g.white_id IS NULL THEN
    UPDATE public.chess_games
       SET white_id=v_bot_id, white_is_bot=true, bot_intelligence=v_intel, bot_name=v_bot_name,
           status='playing', started_at=now(), last_move_at=now()
     WHERE id=_game_id;
  ELSE
    UPDATE public.chess_games
       SET black_id=v_bot_id, black_is_bot=true, bot_intelligence=v_intel, bot_name=v_bot_name,
           status='playing', started_at=now(), last_move_at=now()
     WHERE id=_game_id;
  END IF;
END $fn$;

GRANT EXECUTE ON FUNCTION public.rami_add_bot(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fanorona_add_bot(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.poker_add_bot(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chess_add_bot(uuid, text) TO authenticated;
