-- ============================================================
-- FIX: Ludo 4-player turn order + color consistency
--
-- Problem: player_add_bot and ludo_start_solo_bot used
--   4p colors = ['red','blue','green','yellow']
-- while join_game, ludo_quick_start used
--   4p colors = ['red','green','yellow','blue']
--
-- The frontend board layout is:
--   red=TL(0), green=TR(13), yellow=BR(26), blue=BL(39)
-- so the correct clockwise turn order is:
--   slot 0(red) -> slot 1(green) -> slot 2(yellow) -> slot 3(blue)
--
-- Also standardizing 3p colors to ['red','green','yellow']
-- so backend _ludo_start_idx(slot) matches frontend START_IDX[color].
-- ============================================================

-- 1. _ludo_next_slot: simple slot-based ordering
CREATE OR REPLACE FUNCTION public._ludo_next_slot(_game_id uuid, _from integer, _max integer)
RETURNS integer
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $function$
DECLARE
  i INT;
  s INT;
  v_forfeited BOOLEAN;
  v_finish_rank INT;
BEGIN
  FOR i IN 1.._max LOOP
    s := (_from + i) % _max;
    SELECT forfeited, finish_rank INTO v_forfeited, v_finish_rank
      FROM public.ludo_participants
      WHERE game_id = _game_id AND slot = s;
    IF COALESCE(v_forfeited, FALSE) THEN CONTINUE; END IF;
    IF v_finish_rank IS NOT NULL THEN CONTINUE; END IF;
    RETURN s;
  END LOOP;
  RETURN _from;
END $function$;

-- 2. player_add_bot: fix 4p colors
CREATE OR REPLACE FUNCTION public.player_add_bot(_game_id uuid, _bot_name text DEFAULT 'Bot'::text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  g public.ludo_games%ROWTYPE;
  v_slot int;
  v_colors4 text[] := ARRAY['red','green','yellow','blue'];
  v_colors2 text[] := ARRAY['red','yellow'];
  v_colors3 text[] := ARRAY['red','green','yellow'];
  v_color text;
  v_count int;
  v_uid uuid := auth.uid();
  v_is_admin boolean := public.is_admin();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status <> 'open' THEN RAISE EXCEPTION 'La partie a deja commence'; END IF;
  IF NOT v_is_admin THEN
    IF COALESCE(g.stake,0) > 0 THEN RAISE EXCEPTION 'Bots reserves aux parties gratuites'; END IF;
    IF g.host_id <> v_uid AND NOT EXISTS (SELECT 1 FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid) THEN
      RAISE EXCEPTION 'Vous devez rejoindre la partie pour ajouter un bot';
    END IF;
  END IF;
  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_count >= g.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;
  SELECT s INTO v_slot FROM generate_series(0, g.max_players-1) AS s
   WHERE s NOT IN (SELECT slot FROM public.ludo_participants WHERE game_id=_game_id) ORDER BY s LIMIT 1;
  IF g.max_players = 2 THEN v_color := v_colors2[v_slot+1];
  ELSIF g.max_players = 3 THEN v_color := v_colors3[v_slot+1];
  ELSE v_color := v_colors4[v_slot+1]; END IF;
  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, is_bot, bot_name, display_name, bot_intelligence, ready)
  VALUES (_game_id, NULL, v_slot, v_color, TRUE, COALESCE(NULLIF(trim(_bot_name),''),'Bot'), COALESCE(NULLIF(trim(_bot_name),''),'Bot'), 70, TRUE);
END $function$;
REVOKE EXECUTE ON FUNCTION public.player_add_bot(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.player_add_bot(uuid, text) TO authenticated;

-- 3. ludo_start_solo_bot: fix 4p colors
DROP FUNCTION IF EXISTS public.ludo_start_solo_bot(integer, text);
DROP FUNCTION IF EXISTS public.ludo_start_solo_bot(integer, numeric, text, text);
DROP FUNCTION IF EXISTS public.ludo_start_solo_bot(integer, numeric, text, text, numeric);
DROP FUNCTION IF EXISTS public.ludo_start_solo_bot(integer, numeric, text, text, text);

CREATE OR REPLACE FUNCTION public.ludo_start_solo_bot(
  _max_players integer DEFAULT 2, _difficulty text DEFAULT 'medium',
  _stake numeric DEFAULT 0, _mode text DEFAULT 'classic', _match_type text DEFAULT 'solo'
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_uid uuid := auth.uid(); v_game_id uuid; v_name text; v_intel int;
  v_colors4 text[] := ARRAY['red','green','yellow','blue'];
  v_colors3 text[] := ARRAY['red','green','yellow'];
  v_colors2 text[] := ARRAY['red','yellow'];
  v_color text; i int;
  v_bot_names text[] := ARRAY['Bot Rina','Bot Naina','Bot Toky','Bot Sanda'];
  v_mode text; v_total int; v_ready int; v_team int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifie'; END IF;
  IF _max_players < 2 OR _max_players > 4 THEN RAISE EXCEPTION 'max_players doit etre entre 2 et 4'; END IF;
  v_intel := CASE _difficulty WHEN 'easy' THEN 40 WHEN 'hard' THEN 90 ELSE 70 END;
  v_mode := CASE WHEN _mode = 'fast' THEN 'fast' ELSE 'classic' END;
  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, is_private, mode, match_type, status, is_solo)
  VALUES (v_uid, _max_players, _stake, _stake, 0, TRUE, v_mode, COALESCE(_match_type, 'solo'), 'open', TRUE)
  RETURNING id INTO v_game_id;
  SELECT COALESCE(NULLIF(trim(pseudo), ''), 'Joueur') INTO v_name FROM public.profiles WHERE id = v_uid;
  IF _max_players = 2 THEN v_color := v_colors2[1];
  ELSIF _max_players = 3 THEN v_color := v_colors3[1];
  ELSE v_color := v_colors4[1]; END IF;
  IF _match_type = 'groupe' THEN v_team := 1; ELSE v_team := NULL; END IF;
  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name, ready, team)
  VALUES (v_game_id, v_uid, 0, v_color, COALESCE(v_name, 'Joueur'), TRUE, v_team);
  FOR i IN 1..(_max_players - 1) LOOP
    IF _max_players = 2 THEN v_color := v_colors2[i + 1];
    ELSIF _max_players = 3 THEN v_color := v_colors3[i + 1];
    ELSE v_color := v_colors4[i + 1]; END IF;
    IF _match_type = 'groupe' THEN v_team := CASE WHEN i % 2 = 0 THEN 1 ELSE 2 END; ELSE v_team := NULL; END IF;
    INSERT INTO public.ludo_participants(game_id, user_id, slot, color, is_bot, bot_name, display_name, bot_intelligence, bot_win_bias, ready, team)
    VALUES (v_game_id, NULL, i, v_color, TRUE, v_bot_names[i], v_bot_names[i], v_intel, 0, TRUE, v_team);
  END LOOP;
  SELECT count(*), count(*) FILTER (WHERE ready OR is_bot) INTO v_total, v_ready FROM public.ludo_participants WHERE game_id = v_game_id;
  IF v_total = _max_players AND v_ready = v_total THEN
    UPDATE public.ludo_games SET status = 'playing', started_at = now(), state = public._ludo_init_state(_max_players, COALESCE(_mode, 'classic')), current_turn = 0 WHERE id = v_game_id;
  END IF;
  RETURN v_game_id;
END $function$;
REVOKE EXECUTE ON FUNCTION public.ludo_start_solo_bot(integer, text, numeric, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ludo_start_solo_bot(integer, text, numeric, text, text) TO authenticated;

-- 4. join_game: fix 3p + 4p colors
CREATE OR REPLACE FUNCTION public.join_game(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $function$
DECLARE
  v_uid UUID := auth.uid(); v_balance NUMERIC; v_game public.ludo_games%ROWTYPE;
  v_count INT; v_slot INT; v_color TEXT; v_paused BOOLEAN; v_banned BOOLEAN; v_colors TEXT[];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifie'; END IF;
  SELECT paused INTO v_paused FROM public.app_settings WHERE id=1;
  IF COALESCE(v_paused,FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned INTO v_banned FROM public.profiles WHERE id=v_uid;
  IF COALESCE(v_banned,FALSE) THEN RAISE EXCEPTION 'Compte banni'; END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_game.status <> 'open' THEN RAISE EXCEPTION 'Partie deja commencee'; END IF;
  IF EXISTS (SELECT 1 FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid) THEN RAISE EXCEPTION 'Deja inscrit'; END IF;
  PERFORM public._validate_stake(v_game.stake);
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id=v_uid FOR UPDATE;
  IF v_balance < v_game.stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_count >= v_game.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;
  v_slot := v_count;
  v_colors := CASE v_game.max_players WHEN 2 THEN ARRAY['red','yellow'] WHEN 3 THEN ARRAY['red','green','yellow'] ELSE ARRAY['red','green','yellow','blue'] END;
  v_color := v_colors[v_slot+1];
  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
    SELECT _game_id, v_uid, v_slot, v_color, pseudo FROM public.profiles WHERE id=v_uid;
  UPDATE public.profiles SET balance_ar = balance_ar - v_game.stake WHERE id=v_uid;
  UPDATE public.ludo_games SET pot = pot + v_game.stake WHERE id=_game_id;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note) VALUES (v_uid, 'ludo_stake', -v_game.stake, _game_id, 'Mise join partie Ludo');
  PERFORM public._ludo_maybe_auto_start(_game_id);
END; $function$;
REVOKE EXECUTE ON FUNCTION public.join_game(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.join_game(uuid) TO authenticated;

-- 5. ludo_quick_start: fix 3p colors
CREATE OR REPLACE FUNCTION public.ludo_quick_start(_max_players integer DEFAULT 2, _stake numeric DEFAULT 0, _mode text DEFAULT 'classic'::text, _match_type text DEFAULT 'solo'::text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_uid uuid; v_game_id uuid; v_code text; v_name text; v_balance numeric; v_paused boolean; v_banned boolean;
  v_commission numeric; v_slot int; v_colors text[]; v_color text; v_team int;
  v_bot_names text[] := ARRAY['Bot Rija','Bot Naina','Bot Hery','Bot Voara'];
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifie'; END IF;
  IF _max_players NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'Joueurs invalides (2-4)'; END IF;
  PERFORM public._validate_stake(_stake);
  SELECT paused INTO v_paused FROM public.app_settings WHERE id = 1;
  IF COALESCE(v_paused, false) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned, COALESCE(pseudo, 'Joueur'), balance_ar INTO v_banned, v_name, v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF COALESCE(v_banned, false) THEN RAISE EXCEPTION 'Compte banni'; END IF;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
  v_colors := CASE _max_players WHEN 2 THEN ARRAY['red','yellow'] WHEN 3 THEN ARRAY['red','green','yellow'] ELSE ARRAY['red','green','yellow','blue'] END;
  SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id = 1;
  v_code := public._gen_room_code();
  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, room_code, is_private, mode, match_type)
  VALUES (v_uid, _max_players, _stake, _stake, COALESCE(v_commission, 10), v_code, TRUE, COALESCE(_mode, 'classic'), COALESCE(_match_type, 'solo'))
  RETURNING id INTO v_game_id;
  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note) VALUES (v_uid, 'stake', -_stake, v_game_id, 'Mise creation partie solo bot');
  END IF;
  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name, ready, is_bot)
    VALUES (v_game_id, v_uid, 0, v_colors[1], v_name, TRUE, FALSE);
  FOR v_slot IN 1.._max_players - 1 LOOP
    v_color := v_colors[v_slot + 1];
    IF _match_type = 'groupe' THEN v_team := CASE WHEN v_slot % 2 = 0 THEN 1 ELSE 2 END; ELSE v_team := NULL; END IF;
    INSERT INTO public.ludo_participants(game_id, user_id, slot, color, is_bot, bot_name, display_name, bot_intelligence, bot_win_bias, ready, team)
    VALUES (v_game_id, NULL, v_slot, v_color, TRUE, v_bot_names[v_slot], v_bot_names[v_slot], 70, 0, TRUE, v_team);
  END LOOP;
  UPDATE public.ludo_games SET status = 'playing'::game_status, started_at = now(), state = public._ludo_init_state(_max_players), current_turn = 0 WHERE id = v_game_id;
  RETURN v_game_id;
END $function$;
REVOKE EXECUTE ON FUNCTION public.ludo_quick_start(integer, numeric, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ludo_quick_start(integer, numeric, text, text) TO authenticated;

-- 6. ludo_rematch: fix 3p colors
CREATE OR REPLACE FUNCTION public.ludo_rematch(_old_game_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_old public.ludo_games%ROWTYPE; v_new_id uuid; v_part public.ludo_participants%ROWTYPE;
  v_count INT; v_slot INT; v_colors TEXT[]; v_color TEXT; v_room_code TEXT; v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifie'; END IF;
  SELECT * INTO v_old FROM public.ludo_games WHERE id = _old_game_id;
  IF v_old.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_old.status <> 'finished' THEN RAISE EXCEPTION 'La partie doit etre terminee'; END IF;
  v_room_code := CASE WHEN v_old.is_private THEN substr(md5(random()::text), 1, 6) ELSE NULL END;
  INSERT INTO public.ludo_games(max_players, stake, mode, is_private, room_code, commission_pct, status, pot, created_by)
  VALUES (v_old.max_players, v_old.stake, v_old.mode, v_old.is_private, v_room_code, v_old.commission_pct, 'open', 0, v_uid)
  RETURNING id INTO v_new_id;
  FOR v_part IN SELECT * FROM public.ludo_participants WHERE game_id = _old_game_id AND NOT forfeited AND NOT is_bot ORDER BY slot LOOP
    IF v_old.stake > 0 AND NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_part.user_id AND balance_ar >= v_old.stake) THEN CONTINUE; END IF;
    SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = v_new_id;
    v_slot := v_count;
    v_colors := CASE v_old.max_players WHEN 2 THEN ARRAY['red','yellow'] WHEN 3 THEN ARRAY['red','green','yellow'] ELSE ARRAY['red','green','yellow','blue'] END;
    v_color := v_colors[v_slot + 1];
    INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name, ready)
    VALUES (v_new_id, v_part.user_id, v_slot, v_color, v_part.display_name, false);
    IF v_old.stake > 0 THEN
      UPDATE public.profiles SET balance_ar = balance_ar - v_old.stake WHERE id = v_part.user_id;
      UPDATE public.ludo_games SET pot = pot + v_old.stake WHERE id = v_new_id;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note) VALUES (v_part.user_id, 'stake', -v_old.stake, v_new_id, 'Mise revanche');
    END IF;
  END LOOP;
  FOR v_part IN SELECT * FROM public.ludo_participants WHERE game_id = _old_game_id AND NOT forfeited AND is_bot ORDER BY slot LOOP
    SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = v_new_id;
    IF v_count >= v_old.max_players THEN EXIT; END IF;
    v_slot := v_count;
    v_colors := CASE v_old.max_players WHEN 2 THEN ARRAY['red','yellow'] WHEN 3 THEN ARRAY['red','green','yellow'] ELSE ARRAY['red','green','yellow','blue'] END;
    v_color := v_colors[v_slot + 1];
    INSERT INTO public.ludo_participants(game_id, user_id, slot, color, is_bot, bot_name, display_name, bot_intelligence, bot_win_bias, ready)
    VALUES (v_new_id, NULL, v_slot, v_color, TRUE, v_part.bot_name, v_part.bot_name, v_part.bot_intelligence, 0, TRUE);
  END LOOP;
  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = v_new_id;
  IF v_count >= v_old.max_players THEN
    UPDATE public.ludo_games SET status = 'playing', started_at = now(), state = public._ludo_init_state(v_old.max_players) WHERE id = v_new_id;
  END IF;
  RETURN v_new_id;
END $function$;
REVOKE EXECUTE ON FUNCTION public.ludo_rematch(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ludo_rematch(uuid) TO authenticated;

-- 7. admin_join_game: fix 3p colors
CREATE OR REPLACE FUNCTION public.admin_join_game(_game_id uuid, _display_name text DEFAULT NULL::text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_uid uuid := auth.uid(); v_game public.ludo_games%ROWTYPE; v_count int; v_slot int; v_color text; v_colors text[]; v_name text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL OR v_game.status <> 'open' THEN RAISE EXCEPTION 'Partie non ouverte'; END IF;
  IF EXISTS(SELECT 1 FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid) THEN RAISE EXCEPTION 'Deja inscrit'; END IF;
  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_count >= v_game.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;
  v_slot := v_count;
  v_colors := CASE v_game.max_players WHEN 2 THEN ARRAY['red','yellow'] WHEN 3 THEN ARRAY['red','green','yellow'] ELSE ARRAY['red','green','yellow','blue'] END;
  v_color := v_colors[v_slot+1];
  SELECT COALESCE(NULLIF(_display_name,''), pseudo) INTO v_name FROM public.profiles WHERE id=v_uid;
  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name,ready)
    VALUES (_game_id, v_uid, v_slot, v_color, v_name, true);
END; $function$;
REVOKE EXECUTE ON FUNCTION public.admin_join_game(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_join_game(uuid, text) TO authenticated;
