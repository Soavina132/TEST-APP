-- Migration: Fix ludo_start_solo_bot — auto-start the game after creation
-- Date: 2026-08-13
-- Problem: ludo_start_solo_bot creates a game with all participants ready=TRUE
--          but never starts the game (status stays 'open', state stays '{}').
--          The game page shows nothing useful and the game gets cancelled by cleanup.
-- Fix: Auto-start the game immediately after inserting all participants.

-- 1. Drop the old 2-param version to avoid PostgREST overload confusion
DROP FUNCTION IF EXISTS public.ludo_start_solo_bot(integer, text);

-- 2. Recreate the 5-param version with auto-start
CREATE OR REPLACE FUNCTION public.ludo_start_solo_bot(
  _max_players integer DEFAULT 2,
  _difficulty text DEFAULT 'medium',
  _stake numeric DEFAULT 0,
  _mode text DEFAULT 'classic',
  _match_type text DEFAULT 'solo'
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_game_id uuid;
  v_name text;
  v_intel int;
  v_colors4 text[] := ARRAY['red','blue','green','yellow'];
  v_colors3 text[] := ARRAY['red','green','yellow'];
  v_colors2 text[] := ARRAY['red','yellow'];
  v_color text;
  i int;
  v_bot_names text[] := ARRAY['Bot Rina','Bot Naina','Bot Toky','Bot Sanda'];
  v_mode text;
  v_total int;
  v_ready int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _max_players < 2 OR _max_players > 4 THEN
    RAISE EXCEPTION 'max_players doit être entre 2 et 4';
  END IF;

  v_intel := CASE _difficulty WHEN 'easy' THEN 40 WHEN 'hard' THEN 90 ELSE 70 END;
  v_mode := CASE WHEN _mode = 'fast' THEN 'fast' ELSE 'classic' END;

  -- Créer la partie
  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct,
                                is_private, mode, match_type, status, is_solo)
  VALUES (v_uid, _max_players, _stake, _stake, 0, TRUE, v_mode,
          COALESCE(_match_type, 'solo'), 'open', TRUE)
  RETURNING id INTO v_game_id;

  -- Récupérer le pseudo (avec fallback)
  SELECT COALESCE(NULLIF(trim(pseudo), ''), 'Joueur') INTO v_name
    FROM public.profiles WHERE id = v_uid;

  -- Ajouter le joueur humain (slot 0, prêt)
  IF _max_players = 2 THEN v_color := v_colors2[1];
  ELSIF _max_players = 3 THEN v_color := v_colors3[1];
  ELSE v_color := v_colors4[1];
  END IF;

  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name, ready)
  VALUES (v_game_id, v_uid, 0, v_color, COALESCE(v_name, 'Joueur'), TRUE);

  -- Ajouter les bots (slots 1..N-1, prêts)
  FOR i IN 1..(_max_players - 1) LOOP
    IF _max_players = 2 THEN v_color := v_colors2[i + 1];
    ELSIF _max_players = 3 THEN v_color := v_colors3[i + 1];
    ELSE v_color := v_colors4[i + 1];
    END IF;
    INSERT INTO public.ludo_participants(
      game_id, user_id, slot, color, is_bot, bot_name, display_name,
      bot_intelligence, bot_win_bias, ready
    ) VALUES (
      v_game_id, NULL, i, v_color, TRUE,
      v_bot_names[i], v_bot_names[i], v_intel, 0, TRUE
    );
  END LOOP;

  -- ── DÉMARRER LA PARTIE IMMÉDIATEMENT ──
  -- Tous les participants sont prêts (humain + bots), on lance la partie
  SELECT count(*), count(*) FILTER (WHERE ready OR is_bot)
    INTO v_total, v_ready
    FROM public.ludo_participants WHERE game_id = v_game_id;

  IF v_total = _max_players AND v_ready = v_total THEN
    UPDATE public.ludo_games
    SET status = 'playing',
        started_at = now(),
        state = public._ludo_init_state(_max_players),
        current_turn = 0
    WHERE id = v_game_id;
  END IF;

  RETURN v_game_id;
END $function$;

-- 3. Fix create_private_game: safe pseudo handling (COALESCE)
CREATE OR REPLACE FUNCTION public.create_private_game(
  _max_players integer, _stake numeric,
  _mode text DEFAULT 'classic', _match_type text DEFAULT 'solo'
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_balance NUMERIC;
  v_game_id UUID;
  v_commission NUMERIC;
  v_paused BOOLEAN;
  v_banned BOOLEAN;
  v_code TEXT;
  v_name text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  PERFORM public.cleanup_stale_open_games();
  SELECT paused INTO v_paused FROM public.app_settings WHERE id = 1;
  IF COALESCE(v_paused, FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned, COALESCE(NULLIF(trim(pseudo), ''), 'Joueur') INTO v_banned, v_name
    FROM public.profiles WHERE id = v_uid;
  IF COALESCE(v_banned, FALSE) THEN RAISE EXCEPTION 'Compte banni'; END IF;
  IF _max_players NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'Joueurs invalides'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'Mise invalide'; END IF;
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
  SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id = 1;
  v_code := public._gen_room_code();
  INSERT INTO public.ludo_games(
    host_id, max_players, stake, pot, commission_pct,
    room_code, is_private, mode, match_type
  ) VALUES (
    v_uid, _max_players, _stake, _stake, COALESCE(v_commission, 10),
    v_code, TRUE, COALESCE(_mode, 'classic'), COALESCE(_match_type, 'solo')
  ) RETURNING id INTO v_game_id;
  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
    VALUES (v_uid, 'stake', -_stake, v_game_id, 'Mise création partie privée');
  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
    VALUES (v_game_id, v_uid, 0, 'red', v_name);
  RETURN v_game_id;
END $function$;

-- 4. Fix create_game: same safe pseudo handling
CREATE OR REPLACE FUNCTION public.create_game(
  _max_players integer, _stake numeric,
  _mode text DEFAULT 'classic', _match_type text DEFAULT 'solo'
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_balance NUMERIC;
  v_game_id UUID;
  v_commission NUMERIC;
  v_paused BOOLEAN;
  v_banned BOOLEAN;
  v_code TEXT;
  v_name text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  PERFORM public.cleanup_stale_open_games();
  SELECT paused INTO v_paused FROM public.app_settings WHERE id = 1;
  IF COALESCE(v_paused, FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned, COALESCE(NULLIF(trim(pseudo), ''), 'Joueur') INTO v_banned, v_name
    FROM public.profiles WHERE id = v_uid;
  IF COALESCE(v_banned, FALSE) THEN RAISE EXCEPTION 'Compte banni'; END IF;
  IF _max_players NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'Joueurs invalides'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'Mise invalide'; END IF;
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
  SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id = 1;
  v_code := public._gen_room_code();
  INSERT INTO public.ludo_games(
    host_id, max_players, stake, pot, commission_pct,
    room_code, mode, match_type
  ) VALUES (
    v_uid, _max_players, _stake, _stake, COALESCE(v_commission, 10),
    v_code, COALESCE(_mode, 'classic'), COALESCE(_match_type, 'solo')
  ) RETURNING id INTO v_game_id;
  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
    VALUES (v_uid, 'stake', -_stake, v_game_id, 'Mise création partie');
  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
    VALUES (v_game_id, v_uid, 0, 'red', v_name);
  RETURN v_game_id;
END $function$;

-- 5. Drop old overloaded versions without _match_type
DROP FUNCTION IF EXISTS public.create_private_game(integer, numeric, text);
DROP FUNCTION IF EXISTS public.create_game(integer, numeric);
DROP FUNCTION IF EXISTS public.find_or_create_game(integer, numeric);
