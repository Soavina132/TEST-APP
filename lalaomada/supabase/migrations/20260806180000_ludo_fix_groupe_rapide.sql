-- ═══════════════════════════════════════════════════════════════════════
-- FIX: 4 bugs Mode Groupe + Mode Rapide
--   A. ludo_start_solo_bot obsolète (params manquants)
--   B. find_or_create_game ne filtre pas par match_type
--   C. player_add_bot / admin_add_bot ignore le mode pour power tiles
--   D. Overload orphelin find_or_create_game(integer, numeric, text)
-- ═══════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════
-- BUG A: ludo_start_solo_bot — accepter _stake, _mode, _match_type
-- ═══════════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.ludo_start_solo_bot(integer, text);

CREATE OR REPLACE FUNCTION public.ludo_start_solo_bot(
  _max_players integer DEFAULT 2,
  _stake numeric DEFAULT 0,
  _mode text DEFAULT 'classic',
  _match_type text DEFAULT 'solo'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_game_id uuid;
  v_name text;
  v_intel int := 70;
  v_colors4 text[] := ARRAY['red','blue','green','yellow'];
  v_colors3 text[] := ARRAY['red','green','yellow'];
  v_colors2 text[] := ARRAY['red','yellow'];
  v_color text;
  i int;
  v_bot_names text[] := ARRAY['Bot Rina','Bot Naina','Bot Toky','Bot Sanda'];
  v_balance numeric;
  v_commission numeric;
  v_team int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _max_players < 2 OR _max_players > 4 THEN
    RAISE EXCEPTION 'max_players doit être entre 2 et 4';
  END IF;
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id=1;

  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct,
                                is_private, mode, match_type, status, is_solo)
  VALUES (v_uid, _max_players, _stake, _stake, COALESCE(v_commission,0),
          TRUE, COALESCE(_mode,'classic'), COALESCE(_match_type,'solo'), 'open', TRUE)
  RETURNING id INTO v_game_id;

  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_uid,'stake',-_stake,v_game_id,'Mise création partie solo bot');
  END IF;

  SELECT COALESCE(NULLIF(trim(pseudo),''),'Joueur') INTO v_name
    FROM public.profiles WHERE id = v_uid;

  -- Humain toujours slot 0 = 'red', team 1 in groupe mode
  IF _match_type = 'groupe' THEN v_team := 1; ELSE v_team := NULL; END IF;

  IF _max_players = 2 THEN v_color := v_colors2[1];
  ELSIF _max_players = 3 THEN v_color := v_colors3[1];
  ELSE v_color := v_colors4[1];
  END IF;

  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name, ready, team)
  VALUES (v_game_id, v_uid, 0, v_color, COALESCE(v_name,'Joueur'), TRUE, v_team);

  FOR i IN 1..(_max_players-1) LOOP
    IF _max_players = 2 THEN v_color := v_colors2[i+1];
    ELSIF _max_players = 3 THEN v_color := v_colors3[i+1];
    ELSE v_color := v_colors4[i+1];
    END IF;
    -- In groupe mode: even slots = team 1, odd slots = team 2
    IF _match_type = 'groupe' THEN
      v_team := CASE WHEN i % 2 = 0 THEN 1 ELSE 2 END;
    ELSE
      v_team := NULL;
    END IF;
    INSERT INTO public.ludo_participants(
      game_id, user_id, slot, color, is_bot, bot_name, display_name,
      bot_intelligence, bot_win_bias, ready, team
    ) VALUES (
      v_game_id, NULL, i, v_color, TRUE,
      v_bot_names[i], v_bot_names[i], v_intel, 0, TRUE, v_team
    );
  END LOOP;

  RETURN v_game_id;
END $$;

REVOKE EXECUTE ON FUNCTION public.ludo_start_solo_bot(integer, numeric, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.ludo_start_solo_bot(integer, numeric, text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- BUG B: find_or_create_game — ajouter match_type dans le WHERE
-- BUG D: Drop l'overload orphelin à 3 params
-- ═══════════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.find_or_create_game(integer, numeric, text);

CREATE OR REPLACE FUNCTION public.find_or_create_game(
  _max_players integer,
  _stake numeric,
  _mode text DEFAULT 'classic',
  _match_type text DEFAULT 'solo'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_game_id UUID;
  v_balance NUMERIC;
  v_count INT;
  v_commission NUMERIC;
  v_paused BOOLEAN;
  v_banned BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT paused INTO v_paused FROM public.app_settings WHERE id = 1;
  IF COALESCE(v_paused, FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned INTO v_banned FROM public.profiles WHERE id = v_uid;
  IF COALESCE(v_banned, FALSE) THEN RAISE EXCEPTION 'Compte banni'; END IF;
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  -- Try to find an existing open public game with same params (incl. mode AND match_type)
  SELECT id INTO v_game_id FROM public.ludo_games
    WHERE status = 'open'
      AND is_private = false
      AND max_players = _max_players
      AND stake = _stake
      AND COALESCE(mode, 'classic') = COALESCE(_mode, 'classic')
      AND COALESCE(match_type, 'solo') = COALESCE(_match_type, 'solo')
    ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED;

  IF v_game_id IS NULL THEN
    SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id = 1;
    INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, mode, match_type)
      VALUES (v_uid, _max_players, _stake, _stake, COALESCE(v_commission, 10), COALESCE(_mode, 'classic'), COALESCE(_match_type, 'solo'))
      RETURNING id INTO v_game_id;
    UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'stake', -_stake, v_game_id, 'Mise création partie');
    INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
      SELECT v_game_id, v_uid, 0, 'red', pseudo FROM public.profiles WHERE id = v_uid;
  ELSE
    SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = v_game_id;
    IF v_count >= _max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;
    PERFORM public.join_game(v_game_id);
  END IF;

  RETURN v_game_id;
END $$;

REVOKE ALL ON FUNCTION public.find_or_create_game(integer, numeric, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.find_or_create_game(integer, numeric, text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- BUG C: player_add_bot — passer le mode à _ludo_init_state
-- ═══════════════════════════════════════════════════════════════════════
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

  IF v_game.stake > 0 AND NOT v_game.is_private THEN
    RAISE EXCEPTION 'Bots réservés aux parties amicales (mise 0) ou privées';
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
    70, 0, TRUE, v_team
  );

  -- Auto-start if full — BUG C FIX: pass mode to _ludo_init_state
  IF v_count + 1 = v_game.max_players THEN
    UPDATE public.ludo_games
      SET status = 'playing',
          started_at = now(),
          state = public._ludo_init_state(v_game.max_players, COALESCE(v_game.mode, 'classic')),
          current_turn = 0
      WHERE id = _game_id;
  END IF;
END $$;

REVOKE EXECUTE ON FUNCTION public.player_add_bot(UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.player_add_bot(UUID, TEXT) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- BUG C: admin_add_bot — passer le mode à _ludo_init_state
-- ═══════════════════════════════════════════════════════════════════════
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

  -- Auto-start if full — BUG C FIX: pass mode to _ludo_init_state
  IF v_count + 1 = v_game.max_players THEN
    UPDATE public.ludo_games
      SET status = 'playing',
          started_at = now(),
          state = public._ludo_init_state(v_game.max_players, COALESCE(v_game.mode, 'classic')),
          current_turn = 0
      WHERE id = _game_id;
  END IF;
END $$;

REVOKE EXECUTE ON FUNCTION public.admin_add_bot(UUID, TEXT, INT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_add_bot(UUID, TEXT, INT, INT) TO authenticated;
