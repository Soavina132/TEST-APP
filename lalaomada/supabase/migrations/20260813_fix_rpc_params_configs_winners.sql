-- Migration: Fix RPC functions, game configs, and backfill winners
-- Date: 2026-08-13
-- Description: Fix parameter mismatches between frontend and Supabase RPC functions
--              Add missing game configs, fix cover URLs, backfill winner_id

-- 1. Fix create_public_game: add _match_type parameter
CREATE OR REPLACE FUNCTION public.create_public_game(
  _max_players integer, _stake numeric, _mode text DEFAULT 'classic', _match_type text DEFAULT 'solo'
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_uid uuid := auth.uid(); v_balance numeric; v_id uuid; v_mode text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  v_mode := CASE WHEN _mode = 'fast' THEN 'fast' ELSE 'classic' END;
  IF _stake > 0 THEN
    SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
    IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
    UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
    INSERT INTO public.transactions(user_id, type, amount, note) VALUES (v_uid, 'ludo_stake', -_stake, 'Mise Ludo');
  END IF;
  INSERT INTO public.ludo_games(host_id, max_players, stake, status, is_private, pot, mode, match_type)
    VALUES (v_uid, _max_players, _stake, 'open', false, _stake, v_mode, COALESCE(_match_type, 'solo'))
    RETURNING id INTO v_id;
  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
    SELECT v_id, v_uid, 0, 'red', pseudo FROM public.profiles WHERE id = v_uid;
  RETURN v_id;
END $function$;

-- 2. Fix create_private_game: add _match_type parameter
CREATE OR REPLACE FUNCTION public.create_private_game(
  _max_players integer, _stake numeric, _mode text DEFAULT 'classic', _match_type text DEFAULT 'solo'
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_uid UUID := auth.uid(); v_balance NUMERIC; v_game_id UUID;
  v_commission NUMERIC; v_paused BOOLEAN; v_banned BOOLEAN; v_code TEXT; v_name text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  PERFORM public.cleanup_stale_open_games();
  SELECT paused INTO v_paused FROM public.app_settings WHERE id=1;
  IF COALESCE(v_paused,FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned, pseudo INTO v_banned, v_name FROM public.profiles WHERE id=v_uid;
  IF COALESCE(v_banned,FALSE) THEN RAISE EXCEPTION 'Compte banni'; END IF;
  IF _max_players NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'Joueurs invalides'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'Mise invalide'; END IF;
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
  SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id=1;
  v_code := public._gen_room_code();
  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, room_code, is_private, mode, match_type)
    VALUES (v_uid, _max_players, _stake, _stake, COALESCE(v_commission,10), v_code, TRUE, COALESCE(_mode,'classic'), COALESCE(_match_type,'solo'))
    RETURNING id INTO v_game_id;
  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id,type,amount,ref_id,note) VALUES (v_uid,'stake',-_stake,v_game_id,'Mise création partie privée');
  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name)
    VALUES (v_game_id, v_uid, 0, 'red', v_name);
  RETURN v_game_id;
END $function$;

-- 3. Fix create_game: add _mode and _match_type parameters
CREATE OR REPLACE FUNCTION public.create_game(
  _max_players integer, _stake numeric, _mode text DEFAULT 'classic', _match_type text DEFAULT 'solo'
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_uid UUID := auth.uid(); v_balance NUMERIC; v_game_id UUID;
  v_commission NUMERIC; v_paused BOOLEAN; v_banned BOOLEAN; v_code TEXT; v_name text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  PERFORM public.cleanup_stale_open_games();
  SELECT paused INTO v_paused FROM public.app_settings WHERE id=1;
  IF COALESCE(v_paused,FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned, pseudo INTO v_banned, v_name FROM public.profiles WHERE id=v_uid;
  IF COALESCE(v_banned,FALSE) THEN RAISE EXCEPTION 'Compte banni'; END IF;
  IF _max_players NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'Joueurs invalides'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'Mise invalide'; END IF;
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
  SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id=1;
  v_code := public._gen_room_code();
  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, room_code, mode, match_type)
    VALUES (v_uid, _max_players, _stake, _stake, COALESCE(v_commission,10), v_code, COALESCE(_mode,'classic'), COALESCE(_match_type,'solo'))
    RETURNING id INTO v_game_id;
  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id,type,amount,ref_id,note) VALUES (v_uid,'stake',-_stake,v_game_id,'Mise création partie');
  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name)
    VALUES (v_game_id, v_uid, 0, 'red', v_name);
  RETURN v_game_id;
END $function$;

-- 4. Fix find_or_create_game: add _mode and _match_type parameters
CREATE OR REPLACE FUNCTION public.find_or_create_game(
  _max_players integer, _stake numeric, _mode text DEFAULT 'classic', _match_type text DEFAULT 'solo'
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_uid UUID := auth.uid(); v_target UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  PERFORM public.ludo_cleanup_empty_rooms();
  SELECT g.id INTO v_target
    FROM public.ludo_games g
    WHERE g.status='open' AND g.is_private=false AND g.max_players=_max_players AND g.stake=_stake
      AND (SELECT count(*) FROM public.ludo_participants p WHERE p.game_id=g.id) > 0
      AND (SELECT count(*) FROM public.ludo_participants p WHERE p.game_id=g.id) < g.max_players
      AND NOT EXISTS (SELECT 1 FROM public.ludo_participants p WHERE p.game_id=g.id AND p.user_id=v_uid)
    ORDER BY (SELECT count(*) FROM public.ludo_participants p WHERE p.game_id=g.id) DESC, g.created_at ASC
    LIMIT 1;
  IF v_target IS NOT NULL THEN
    PERFORM public.join_game(v_target);
    RETURN v_target;
  END IF;
  RETURN public.create_game(_max_players, _stake, _mode, _match_type);
END $function$;

-- 5. Fix ludo_start_solo_bot: add _stake, _mode, _match_type parameters
CREATE OR REPLACE FUNCTION public.ludo_start_solo_bot(
  _max_players integer DEFAULT 2, _difficulty text DEFAULT 'medium',
  _stake numeric DEFAULT 0, _mode text DEFAULT 'classic', _match_type text DEFAULT 'solo'
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_uid uuid := auth.uid(); v_game_id uuid; v_name text; v_intel int;
  v_colors4 text[] := ARRAY['red','blue','green','yellow'];
  v_colors3 text[] := ARRAY['red','green','yellow'];
  v_colors2 text[] := ARRAY['red','yellow'];
  v_color text; i int;
  v_bot_names text[] := ARRAY['Bot Rina','Bot Naina','Bot Toky','Bot Sanda'];
  v_mode text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _max_players < 2 OR _max_players > 4 THEN
    RAISE EXCEPTION 'max_players doit être entre 2 et 4';
  END IF;
  v_intel := CASE _difficulty WHEN 'easy' THEN 40 WHEN 'hard' THEN 90 ELSE 70 END;
  v_mode := CASE WHEN _mode = 'fast' THEN 'fast' ELSE 'classic' END;
  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct,
                                is_private, mode, match_type, status, is_solo)
  VALUES (v_uid, _max_players, _stake, _stake, 0, TRUE, v_mode, COALESCE(_match_type,'solo'), 'open', TRUE)
  RETURNING id INTO v_game_id;
  SELECT COALESCE(NULLIF(trim(pseudo),''),'Joueur') INTO v_name
    FROM public.profiles WHERE id = v_uid;
  IF _max_players = 2 THEN v_color := v_colors2[1];
  ELSIF _max_players = 3 THEN v_color := v_colors3[1];
  ELSE v_color := v_colors4[1];
  END IF;
  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name, ready)
  VALUES (v_game_id, v_uid, 0, v_color, COALESCE(v_name,'Joueur'), TRUE);
  FOR i IN 1..(_max_players-1) LOOP
    IF _max_players = 2 THEN v_color := v_colors2[i+1];
    ELSIF _max_players = 3 THEN v_color := v_colors3[i+1];
    ELSE v_color := v_colors4[i+1];
    END IF;
    INSERT INTO public.ludo_participants(
      game_id, user_id, slot, color, is_bot, bot_name, display_name,
      bot_intelligence, bot_win_bias, ready
    ) VALUES (
      v_game_id, NULL, i, v_color, TRUE,
      v_bot_names[i], v_bot_names[i], v_intel, 0, TRUE
    );
  END LOOP;
  RETURN v_game_id;
END $function$;

-- 6. Add missing game_config for poker
INSERT INTO public.game_configs (slug, display_name, turn_timer_seconds, max_turn_skips, rules_markdown, cover_url, max_online_capacity, instructions_dismissible, tournament_join_timeout_secs)
VALUES ('poker', 'Poker', 30, 5, 'Texas Hold''em Poker. Mises, relances, bluffs et stratégies. Meilleure main gagne le pot.', '/covers/cover_poker.png', 1000, true, 240)
ON CONFLICT (slug) DO UPDATE SET display_name = EXCLUDED.display_name, rules_markdown = EXCLUDED.rules_markdown, cover_url = EXCLUDED.cover_url;

-- 7. Fix petanque cover_url
UPDATE public.game_configs SET cover_url = '/covers/cover_petanque.png' WHERE slug = 'petanque' AND (cover_url = '' OR cover_url IS NULL);

-- 8. Add created_at to ludo_participants
ALTER TABLE public.ludo_participants ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

-- 9. Backfill winner_id for finished domino games
UPDATE public.domino_games g SET winner_id = (
  SELECT p.user_id FROM public.domino_participants p
  WHERE p.game_id = g.id AND p.forfeited = false AND p.user_id IS NOT NULL
  ORDER BY p.score DESC, p.slot ASC LIMIT 1
) WHERE g.status = 'finished' AND g.winner_id IS NULL
  AND EXISTS (SELECT 1 FROM public.domino_participants p WHERE p.game_id = g.id AND p.forfeited = false AND p.user_id IS NOT NULL);

-- 10. Backfill winner_id for finished ludo games
UPDATE public.ludo_games g SET winner_id = (
  SELECT p.user_id FROM public.ludo_participants p
  WHERE p.game_id = g.id AND p.forfeited = false AND p.user_id IS NOT NULL
  ORDER BY p.finish_rank ASC NULLS LAST, p.slot ASC LIMIT 1
) WHERE g.status = 'finished' AND g.winner_id IS NULL
  AND EXISTS (SELECT 1 FROM public.ludo_participants p WHERE p.game_id = g.id AND p.forfeited = false AND p.user_id IS NOT NULL);
