-- ============================================================
-- FIX: Règles officielles des échecs — migration appliquée à la DB
-- Adaptée pour utiliser _chess_settle (déjà présent en DB avec gestion des bots)
--
-- Problèmes corrigés:
-- 1. Pas de règle des 50 coups (FEN halfmove clock)
-- 2. Pas de règle de répétition triple
-- 3. Pas de matériel insuffisant
-- 4. chess_play ne vérifiait pas les règles après chaque coup
-- 5. chess_bot_play ne vérifiait pas les règles après chaque coup
-- 6. Pas de timeout automatique côté serveur (chess_auto_timeout)
-- ============================================================

-- 1. Extraire le halfmove clock du FEN
CREATE OR REPLACE FUNCTION public._chess_halfmove_clock(_fen text)
RETURNS integer LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE parts text[];
BEGIN
  parts := string_to_array(_fen, ' ');
  IF array_length(parts, 1) >= 5 THEN
    RETURN COALESCE(NULLIF(parts[5], '')::int, 0);
  END IF;
  RETURN 0;
END $$;

-- 2. Clé de position pour répétition (4 premiers champs du FEN)
CREATE OR REPLACE FUNCTION public._chess_position_key(_fen text)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE parts text[];
BEGIN
  parts := string_to_array(_fen, ' ');
  IF array_length(parts, 1) >= 4 THEN
    RETURN parts[1] || ' ' || parts[2] || ' ' || parts[3] || ' ' || parts[4];
  END IF;
  RETURN _fen;
END $$;

-- 3. Matériel insuffisant
CREATE OR REPLACE FUNCTION public._chess_insufficient_material(_fen text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  placement text; white_pieces text := ''; black_pieces text := '';
  white_bishop_color text := ''; black_bishop_color text := '';
  c text; i int; row int; col int;
BEGIN
  placement := split_part(_fen, ' ', 1);
  i := 0;
  FOR c IN SELECT unnest(string_to_array(placement, '/')) LOOP
    IF c ~ '[0-9]' THEN i := i + c::int;
    ELSIF c IN ('K','Q','R','P','k','q','r','p') THEN RETURN false;
    ELSIF c IN ('B','b','N','n') THEN
      IF c = 'B' THEN
        white_pieces := white_pieces || 'B';
        row := i / 8; col := i % 8;
        white_bishop_color := CASE WHEN (row + col) % 2 = 0 THEN 'light' ELSE 'dark' END;
      ELSIF c = 'b' THEN
        black_pieces := black_pieces || 'b';
        row := i / 8; col := i % 8;
        black_bishop_color := CASE WHEN (row + col) % 2 = 0 THEN 'light' ELSE 'dark' END;
      ELSIF c = 'N' THEN white_pieces := white_pieces || 'N';
      ELSIF c = 'n' THEN black_pieces := black_pieces || 'n';
      END IF;
      i := i + 1;
    END IF;
  END LOOP;
  IF white_pieces = '' AND black_pieces = '' THEN RETURN true; END IF;
  IF white_pieces IN ('N','NN') AND black_pieces = '' THEN RETURN true; END IF;
  IF black_pieces IN ('n','nn') AND white_pieces = '' THEN RETURN true; END IF;
  IF white_pieces = 'B' AND black_pieces = '' THEN RETURN true; END IF;
  IF black_pieces = 'b' AND white_pieces = '' THEN RETURN true; END IF;
  IF white_pieces = 'B' AND black_pieces = 'b' AND white_bishop_color = black_bishop_color THEN RETURN true; END IF;
  RETURN false;
END $$;

-- 4. Vérifier et terminer la partie (utilise _chess_settle avec gestion des bots)
CREATE OR REPLACE FUNCTION public._chess_check_game_end(_game_id uuid, _fen_after text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_g chess_games%ROWTYPE; v_halfmove int; v_pos_key text;
  v_pos_count int; v_insufficient boolean; v_history jsonb;
BEGIN
  SELECT * INTO v_g FROM chess_games WHERE id = _game_id FOR UPDATE;
  IF v_g.id IS NULL OR v_g.status <> 'playing' THEN RETURN; END IF;
  v_halfmove := public._chess_halfmove_clock(_fen_after);
  IF v_halfmove >= 100 THEN
    PERFORM public._chess_settle(_game_id, NULL, true, 'fifty_move_rule'); RETURN;
  END IF;
  v_insufficient := public._chess_insufficient_material(_fen_after);
  IF v_insufficient THEN
    PERFORM public._chess_settle(_game_id, NULL, true, 'insufficient_material'); RETURN;
  END IF;
  v_pos_key := public._chess_position_key(_fen_after);
  v_history := COALESCE(v_g.position_history, '[]'::jsonb);
  v_history := v_history || to_jsonb(v_pos_key);
  SELECT count(*) INTO v_pos_count FROM jsonb_array_elements(v_history) AS pos WHERE pos::text = to_jsonb(v_pos_key)::text;
  UPDATE chess_games SET position_history = v_history WHERE id = _game_id;
  IF v_pos_count >= 3 THEN
    PERFORM public._chess_settle(_game_id, NULL, true, 'threefold_repetition'); RETURN;
  END IF;
END $$;

-- 5. chess_play — appeler _chess_check_game_end après chaque coup
CREATE OR REPLACE FUNCTION public.chess_play(_id uuid, _uci text, _san text, _fen_after text, _elapsed_ms integer DEFAULT 0)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid(); v_g chess_games%ROWTYPE; v_new_turn text; v_my_color text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id=_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  IF v_g.white_id = v_uid THEN v_my_color := 'w';
  ELSIF v_g.black_id = v_uid THEN v_my_color := 'b';
  ELSE RAISE EXCEPTION 'not a participant'; END IF;
  IF v_g.turn <> v_my_color THEN RAISE EXCEPTION 'not your turn'; END IF;
  v_new_turn := CASE WHEN v_g.turn='w' THEN 'b' ELSE 'w' END;
  INSERT INTO chess_moves(game_id, ply, san, uci, fen_after, by_user)
    VALUES (_id, v_g.ply+1, _san, _uci, _fen_after, v_uid);
  UPDATE chess_games SET
    fen = _fen_after, turn = v_new_turn, ply = v_g.ply + 1, last_move_at = now(),
    white_time_ms = CASE WHEN v_my_color='w' THEN greatest(0, white_time_ms - coalesce(_elapsed_ms,0)) ELSE white_time_ms END,
    black_time_ms = CASE WHEN v_my_color='b' THEN greatest(0, black_time_ms - coalesce(_elapsed_ms,0)) ELSE black_time_ms END,
    draw_offered_by = CASE WHEN draw_offered_by IS NOT NULL AND draw_offered_by = v_uid THEN NULL ELSE draw_offered_by END
  WHERE id=_id;
  PERFORM public._chess_check_game_end(_id, _fen_after);
END $$;

-- 6. chess_bot_play — appeler _chess_check_game_end après chaque coup
CREATE OR REPLACE FUNCTION public.chess_bot_play(_id uuid, _uci text, _san text, _fen_after text, _elapsed_ms integer DEFAULT 0)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid(); v_g chess_games%ROWTYPE; v_bot uuid; v_bot_color text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id=_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.mode <> 'solo' THEN RAISE EXCEPTION 'not a solo game'; END IF;
  IF v_g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  IF v_g.white_id = v_uid AND v_g.black_is_bot THEN v_bot := v_g.black_id; v_bot_color := 'b';
  ELSIF v_g.black_id = v_uid AND v_g.white_is_bot THEN v_bot := v_g.white_id; v_bot_color := 'w';
  ELSE RAISE EXCEPTION 'not a solo-bot game'; END IF;
  IF v_g.turn <> v_bot_color THEN RAISE EXCEPTION 'not bot turn'; END IF;
  INSERT INTO chess_moves(game_id, ply, san, uci, fen_after, by_user)
    VALUES (_id, v_g.ply+1, _san, _uci, _fen_after, v_bot);
  UPDATE chess_games SET
    fen = _fen_after, turn = CASE WHEN v_g.turn='w' THEN 'b' ELSE 'w' END, ply = v_g.ply + 1, last_move_at = now(),
    white_time_ms = CASE WHEN v_bot_color='w' THEN greatest(0, white_time_ms - coalesce(_elapsed_ms,0)) ELSE white_time_ms END,
    black_time_ms = CASE WHEN v_bot_color='b' THEN greatest(0, black_time_ms - coalesce(_elapsed_ms,0)) ELSE black_time_ms END
  WHERE id=_id;
  PERFORM public._chess_check_game_end(_id, _fen_after);
END $$;

-- 7. chess_auto_timeout — settle les parties où le temps a expiré
CREATE OR REPLACE FUNCTION public.chess_auto_timeout(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_g chess_games%ROWTYPE; v_elapsed_ms int; v_remaining int; v_winner uuid;
BEGIN
  SELECT * INTO v_g FROM chess_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND OR v_g.status <> 'playing' THEN RETURN; END IF;
  IF coalesce(v_g.paused, false) THEN RETURN; END IF;
  IF v_g.time_control_min <= 0 THEN RETURN; END IF;
  v_elapsed_ms := greatest(0, floor(extract(epoch FROM (now() - coalesce(v_g.last_move_at, v_g.started_at, now())))*1000)::int);
  IF v_g.turn = 'w' THEN
    v_remaining := v_g.white_time_ms - v_elapsed_ms; v_winner := v_g.black_id;
  ELSE
    v_remaining := v_g.black_time_ms - v_elapsed_ms; v_winner := v_g.white_id;
  END IF;
  IF v_remaining <= 0 THEN
    PERFORM public._chess_settle(_game_id, v_winner, false, 'timeout');
  END IF;
END $$;

-- 8. Initialiser position_history pour les parties en cours
UPDATE public.chess_games
SET position_history = to_jsonb(public._chess_position_key(fen))::jsonb
WHERE status = 'playing' AND (position_history IS NULL OR position_history = '[]'::jsonb);
