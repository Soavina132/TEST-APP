-- ============================================================
-- Migration: Fix 2v2 groupe mode with bots
--
-- PROBLEMS:
--   1. player_add_bot doesn't assign team in groupe mode → 2v2 broken
--   2. admin_add_bot doesn't assign team in groupe mode
--   3. find_or_create_game doesn't accept _match_type → public games stuck as 'groupe'
--
-- TEAM ASSIGNMENT: slots 0+2 = Team 1, slots 1+3 = Team 2
-- (red+yellow vs green+blue — opposite corners on the board)
-- ============================================================

-- 1. Fix player_add_bot: assign team in groupe mode
CREATE OR REPLACE FUNCTION public.player_add_bot(_game_id UUID, _bot_name TEXT DEFAULT 'Bot')
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_game public.ludo_games%ROWTYPE;
  v_count INT;
  v_slot INT;
  v_color TEXT;
  v_colors TEXT[] := ARRAY['red','green','yellow','blue'];
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

  -- Allow bots on free games or private games (including solo)
  IF v_game.stake > 0 AND NOT v_game.is_private THEN
    RAISE EXCEPTION 'Bots réservés aux parties amicales (mise 0) ou privées';
  END IF;

  v_slot := v_count;
  v_color := v_colors[v_slot + 1];

  -- Assign team in groupe mode (even slots = team 1, odd slots = team 2)
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

  -- Auto-start if full
  IF v_count + 1 = v_game.max_players THEN
    UPDATE public.ludo_games
      SET status = 'playing',
          started_at = now(),
          state = public._ludo_init_state(v_game.max_players),
          current_turn = 0
      WHERE id = _game_id;
  END IF;
END $$;

REVOKE EXECUTE ON FUNCTION public.player_add_bot(UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.player_add_bot(UUID, TEXT) TO authenticated;


-- 2. Fix admin_add_bot: assign team in groupe mode
CREATE OR REPLACE FUNCTION public.admin_add_bot(_game_id UUID, _bot_name TEXT, _intelligence INT DEFAULT 70, _win_bias INT DEFAULT 0)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_game public.ludo_games%ROWTYPE;
  v_count INT;
  v_slot INT;
  v_color TEXT;
  v_colors TEXT[] := ARRAY['red','green','yellow','blue'];
  v_team INT;
BEGIN
  SELECT * INTO v_game FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF v_game.id IS NULL OR v_game.status NOT IN ('open','waiting') THEN
    RAISE EXCEPTION 'Partie non ouverte';
  END IF;

  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = _game_id;
  IF v_count >= v_game.max_players THEN
    RAISE EXCEPTION 'Partie pleine';
  END IF;

  v_slot := v_count;
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
    _intelligence, _win_bias, TRUE, v_team
  );

  -- Auto-start if full
  IF v_count + 1 = v_game.max_players THEN
    UPDATE public.ludo_games
      SET status = 'playing',
          started_at = now(),
          state = public._ludo_init_state(v_game.max_players),
          current_turn = 0
      WHERE id = _game_id;
  END IF;
END $$;

REVOKE EXECUTE ON FUNCTION public.admin_add_bot(UUID, TEXT, INT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_add_bot(UUID, TEXT, INT, INT) TO authenticated;


-- 3. Fix find_or_create_game: accept _match_type
CREATE OR REPLACE FUNCTION public.find_or_create_game(_max_players integer, _stake numeric, _match_type text DEFAULT 'solo')
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_game_id UUID; v_balance NUMERIC; v_count INT;
  v_commission NUMERIC; v_paused BOOLEAN; v_banned BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT paused INTO v_paused FROM public.app_settings WHERE id=1;
  IF COALESCE(v_paused,FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned INTO v_banned FROM public.profiles WHERE id=v_uid;
  IF COALESCE(v_banned,FALSE) THEN RAISE EXCEPTION 'Compte banni'; END IF;
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id=v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
  
  -- Try to find an existing open game with same params
  SELECT id INTO v_game_id FROM public.ludo_games
    WHERE status='open' AND is_private=false AND max_players=_max_players AND stake=_stake
      AND match_type = COALESCE(_match_type, 'solo')
    ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED;
    
  IF v_game_id IS NULL THEN
    SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id=1;
    INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, match_type)
      VALUES (v_uid, _max_players, _stake, _stake, COALESCE(v_commission,10), COALESCE(_match_type,'solo'))
      RETURNING id INTO v_game_id;
    UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note) VALUES (v_uid,'stake',-_stake,v_game_id,'Mise création partie');
    INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name)
      SELECT v_game_id, v_uid, 0, 'red', pseudo FROM public.profiles WHERE id = v_uid;
  ELSE
    SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id=v_game_id;
    IF v_count >= _max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;
    PERFORM public.join_game(v_game_id);
  END IF;
  RETURN v_game_id;
END $function$;

REVOKE ALL ON FUNCTION public.find_or_create_game(integer, numeric, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.find_or_create_game(integer, numeric, text) TO authenticated;
