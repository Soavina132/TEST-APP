-- ========================================
-- 2-player symmetric corners: Red vs Yellow (diagonally opposite)
-- 3-player: Red, Yellow, Blue (every other corner)
-- 4-player: Red, Green, Yellow, Blue (all corners)
-- ========================================

-- Fix join_game: assign colors based on max_players
CREATE OR REPLACE FUNCTION public.join_game(_game_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_balance NUMERIC;
  v_game public.ludo_games%ROWTYPE;
  v_count INT;
  v_slot INT;
  v_color TEXT;
  v_colors TEXT[];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF v_game.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_game.status <> 'open' THEN RAISE EXCEPTION 'Partie déjà commencée'; END IF;

  IF EXISTS (SELECT 1 FROM public.ludo_participants WHERE game_id = _game_id AND user_id = v_uid) THEN
    RAISE EXCEPTION 'Déjà inscrit';
  END IF;

  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < v_game.stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = _game_id;
  IF v_count >= v_game.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;

  v_slot := v_count;
  
  -- Symmetric color assignment based on player count
  v_colors := CASE v_game.max_players
    WHEN 2 THEN ARRAY['red', 'yellow']    -- opposite corners (0 vs 26)
    WHEN 3 THEN ARRAY['red', 'yellow', 'blue']  -- every other corner
    ELSE ARRAY['red', 'green', 'yellow', 'blue']  -- all corners
  END;
  v_color := v_colors[v_slot + 1];

  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
  SELECT _game_id, v_uid, v_slot, v_color, pseudo FROM public.profiles WHERE id = v_uid;

  UPDATE public.profiles SET balance_ar = balance_ar - v_game.stake WHERE id = v_uid;
  UPDATE public.ludo_games SET pot = pot + v_game.stake WHERE id = _game_id;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
    VALUES (v_uid, 'stake', -v_game.stake, _game_id, 'Mise rejoindre partie');

  -- Start game if full
  IF v_count + 1 = v_game.max_players THEN
    UPDATE public.ludo_games SET status = 'playing', started_at = now(),
      state = public._ludo_init_state(v_game.max_players) WHERE id = _game_id;
  END IF;
END $function$;

-- Fix join_game_bot: same symmetric color logic
CREATE OR REPLACE FUNCTION public.join_game_bot(_game_id uuid, _bot_name text, _intelligence int DEFAULT 75, _win_bias int DEFAULT 0)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_game public.ludo_games%ROWTYPE;
  v_count INT;
  v_slot INT;
  v_color TEXT;
  v_colors TEXT[];
BEGIN
  SELECT * INTO v_game FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF v_game.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_game.status <> 'open' THEN RAISE EXCEPTION 'Partie déjà commencée'; END IF;

  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = _game_id;
  IF v_count >= v_game.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;

  v_slot := v_count;
  v_colors := CASE v_game.max_players
    WHEN 2 THEN ARRAY['red', 'yellow']
    WHEN 3 THEN ARRAY['red', 'yellow', 'blue']
    ELSE ARRAY['red', 'green', 'yellow', 'blue']
  END;
  v_color := v_colors[v_slot + 1];

  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, is_bot, bot_name, display_name, bot_intelligence, bot_win_bias)
  VALUES (_game_id, NULL, v_slot, v_color, TRUE, _bot_name, _bot_name,
    GREATEST(0, LEAST(100, _intelligence)), GREATEST(0, LEAST(100, _win_bias)));

  -- Start game if full
  IF v_count + 1 = v_game.max_players THEN
    UPDATE public.ludo_games SET status = 'playing', started_at = now(),
      state = public._ludo_init_state(v_game.max_players) WHERE id = _game_id;
  END IF;
END $function$;
