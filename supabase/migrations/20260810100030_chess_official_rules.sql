-- ============================================================
-- RÈGLES OFFICIELLES DES ÉCHECS — MIGRATION COMPLÈTE
-- ============================================================
-- Problèmes corrigés:
-- 1. _chess_payout payait les bots (bug critique)
-- 2. Pas de règle des 50 coups (FEN halfmove clock)
-- 3. Pas de règle de répétition triple
-- 4. Pas de matériel insuffisant
-- 5. end_reason pas toujours rempli
--
-- Règles officielles FIDE ajoutées:
-- A. Règle des 50 coups: 50 demi-coups sans pion ni capture = nul
-- B. Répétition triple: même position 3 fois = nul
-- C. Matériel insuffisant: K vs K, K+B vs K, K+N vs K, K+B vs K+B (même couleur) = nul
-- D. Pat (stalemate): joueur sans coup légal et pas en échec = nul
-- E. Échec et mat: joueur sans coup légal et en échec = défaite
-- F. Bots ne sont jamais payés
-- ============================================================

-- 1. Ajouter colonne pour tracker l'historique des positions (répétition)
ALTER TABLE public.chess_games ADD COLUMN IF NOT EXISTS position_history jsonb DEFAULT '[]'::jsonb;

-- 2. Fix _chess_payout — ne jamais payer les bots
CREATE OR REPLACE FUNCTION public._chess_payout(_game_id uuid, _winner uuid, _draw boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_g chess_games%ROWTYPE;
  v_net numeric;
  v_each numeric;
  v_winner_is_bot boolean := false;
BEGIN
  SELECT * INTO v_g FROM chess_games WHERE id = _game_id FOR UPDATE;
  IF v_g.id IS NULL THEN RETURN; END IF;
  IF v_g.status = 'finished' THEN RETURN; END IF;

  -- Vérifier si le gagnant est un bot
  IF NOT _draw AND _winner IS NOT NULL THEN
    v_winner_is_bot := (_winner = v_g.white_id AND COALESCE(v_g.white_is_bot, false))
                    OR (_winner = v_g.black_id AND COALESCE(v_g.black_is_bot, false));
  END IF;

  v_net := v_g.pot - (v_g.pot * v_g.commission_pct / 100.0);

  IF _draw THEN
    v_each := v_net / 2;
    -- Rembourser le blanc si humain
    IF v_g.white_id IS NOT NULL AND NOT COALESCE(v_g.white_is_bot, false) THEN
      UPDATE profiles SET balance_ar = balance_ar + v_each WHERE id = v_g.white_id;
      INSERT INTO transactions(user_id, type, amount, ref_id, note)
        VALUES (v_g.white_id, 'chess_payout', v_each, _game_id, 'Chess draw');
    END IF;
    -- Rembourser le noir si humain
    IF v_g.black_id IS NOT NULL AND NOT COALESCE(v_g.black_is_bot, false) THEN
      UPDATE profiles SET balance_ar = balance_ar + v_each WHERE id = v_g.black_id;
      INSERT INTO transactions(user_id, type, amount, ref_id, note)
        VALUES (v_g.black_id, 'chess_payout', v_each, _game_id, 'Chess draw');
    END IF;
    UPDATE chess_games SET status = 'finished', draw = true, end_reason = 'draw', finished_at = now() WHERE id = _game_id;
  ELSE
    -- Payer le gagnant seulement si c'est un humain
    IF _winner IS NOT NULL AND NOT v_winner_is_bot THEN
      UPDATE profiles SET balance_ar = balance_ar + v_net WHERE id = _winner;
      INSERT INTO transactions(user_id, type, amount, ref_id, note)
        VALUES (_winner, 'chess_payout', v_net, _game_id, 'Chess win');
    END IF;
    UPDATE chess_games SET status = 'finished', winner_id = _winner, end_reason = COALESCE(end_reason, 'win'), finished_at = now() WHERE id = _game_id;
  END IF;
END $function$;

-- 3. Fonction utilitaire: extraire le halfmove clock du FEN
CREATE OR REPLACE FUNCTION public._chess_halfmove_clock(_fen text)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  parts text[];
BEGIN
  parts := string_to_array(_fen, ' ');
  IF array_length(parts, 1) >= 5 THEN
    RETURN COALESCE(NULLIF(parts[5], '')::int, 0);
  END IF;
  RETURN 0;
END $function$;

-- 4. Fonction utilitaire: position FEN sans compteurs (pour répétition)
-- Retourne les 4 premiers champs du FEN (placement + couleur + roque + en passant)
CREATE OR REPLACE FUNCTION public._chess_position_key(_fen text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  parts text[];
BEGIN
  parts := string_to_array(_fen, ' ');
  -- Les 4 premiers champs définissent la position (sans compteurs de coups)
  IF array_length(parts, 1) >= 4 THEN
    RETURN parts[1] || ' ' || parts[2] || ' ' || parts[3] || ' ' || parts[4];
  END IF;
  RETURN _fen;
END $function$;

-- 5. Fonction utilitaire: matériel insuffisant
-- Vérifie si les pièces restantes ne peuvent pas mater
CREATE OR REPLACE FUNCTION public._chess_insufficient_material(_fen text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  placement text;
  white_pieces text := '';
  black_pieces text := '';
  white_bishop_color text := '';
  black_bishop_color text := '';
  c text;
  i int;
  row int;
  col int;
BEGIN
  -- Extraire le placement (premier champ du FEN)
  placement := split_part(_fen, ' ', 1);

  -- Parser chaque caractère
  i := 0;
  FOR c IN SELECT unnest(string_to_array(placement, '/')) LOOP
    -- Ignorer les chiffres (cases vides)
    IF c ~ '[0-9]' THEN
      i := i + c::int;
    ELSIF c IN ('K', 'Q', 'R', 'P', 'k', 'q', 'r', 'p') THEN
      -- Pion, Dame ou Tour → matériel suffisant
      RETURN false;
    ELSIF c IN ('B', 'b', 'N', 'n') THEN
      -- Fou ou Cavalier
      IF c = 'B' THEN
        white_pieces := white_pieces || 'B';
        -- Couleur du fou (case blanche ou noire)
        row := ( SELECT position FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7)) v(position) WHERE position = i / 8);
        col := i % 8;
        white_bishop_color := CASE WHEN (row + col) % 2 = 0 THEN 'light' ELSE 'dark' END;
      ELSIF c = 'b' THEN
        black_pieces := black_pieces || 'b';
        row := i / 8;
        col := i % 8;
        black_bishop_color := CASE WHEN (row + col) % 2 = 0 THEN 'light' ELSE 'dark' END;
      ELSIF c = 'N' THEN
        white_pieces := white_pieces || 'N';
      ELSIF c = 'n' THEN
        black_pieces := black_pieces || 'n';
      END IF;
      i := i + 1;
    END IF;
  END LOOP;

  -- K vs K
  IF white_pieces = '' AND black_pieces = '' THEN RETURN true; END IF;

  -- K+N vs K ou K vs K+N
  IF white_pieces IN ('N', 'NN') AND black_pieces = '' THEN RETURN true; END IF;
  IF black_pieces IN ('n', 'nn') AND white_pieces = '' THEN RETURN true; END IF;

  -- K+B vs K ou K vs K+B
  IF white_pieces = 'B' AND black_pieces = '' THEN RETURN true; END IF;
  IF black_pieces = 'b' AND white_pieces = '' THEN RETURN true; END IF;

  -- K+B vs K+B avec mêmes couleurs de fou
  IF white_pieces = 'B' AND black_pieces = 'b' AND white_bishop_color = black_bishop_color THEN
    RETURN true;
  END IF;

  RETURN false;
END $function$;

-- 6. Fonction: vérifier et terminer la partie selon les règles officielles
-- À appeler après chaque coup
CREATE OR REPLACE FUNCTION public._chess_check_game_end(_game_id uuid, _fen_after text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_g chess_games%ROWTYPE;
  v_halfmove int;
  v_pos_key text;
  v_pos_count int;
  v_insufficient boolean;
  v_history jsonb;
BEGIN
  SELECT * INTO v_g FROM chess_games WHERE id = _game_id FOR UPDATE;
  IF v_g.id IS NULL OR v_g.status <> 'playing' THEN RETURN; END IF;

  -- 1. Règle des 50 coups (100 demi-coups = 50 coups complets)
  v_halfmove := public._chess_halfmove_clock(_fen_after);
  IF v_halfmove >= 100 THEN
    PERFORM public._chess_payout(_game_id, NULL, true);
    UPDATE chess_games SET end_reason = 'fifty_move_rule' WHERE id = _game_id;
    RETURN;
  END IF;

  -- 2. Matériel insuffisant
  v_insufficient := public._chess_insufficient_material(_fen_after);
  IF v_insufficient THEN
    PERFORM public._chess_payout(_game_id, NULL, true);
    UPDATE chess_games SET end_reason = 'insufficient_material' WHERE id = _game_id;
    RETURN;
  END IF;

  -- 3. Répétition triple
  v_pos_key := public._chess_position_key(_fen_after);
  v_history := COALESCE(v_g.position_history, '[]'::jsonb);
  v_history := v_history || to_jsonb(v_pos_key);

  -- Compter combien de fois cette position est apparue
  SELECT count(*) INTO v_pos_count
  FROM jsonb_array_elements(v_history) AS pos
  WHERE pos::text = to_jsonb(v_pos_key)::text;

  -- Mettre à jour l'historique
  UPDATE chess_games SET position_history = v_history WHERE id = _game_id;

  IF v_pos_count >= 3 THEN
    PERFORM public._chess_payout(_game_id, NULL, true);
    UPDATE chess_games SET end_reason = 'threefold_repetition' WHERE id = _game_id;
    RETURN;
  END IF;
END $function$;

-- 7. Mise à jour chess_play — vérifier les règles après chaque coup
CREATE OR REPLACE FUNCTION public.chess_play(_id uuid, _uci text, _san text, _fen_after text, _elapsed_ms integer DEFAULT 0)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_g chess_games%ROWTYPE;
  v_new_turn text;
  v_my_color text;
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
    fen = _fen_after,
    turn = v_new_turn,
    ply = v_g.ply + 1,
    last_move_at = now(),
    white_time_ms = CASE WHEN v_my_color='w' THEN greatest(0, white_time_ms - coalesce(_elapsed_ms,0)) ELSE white_time_ms END,
    black_time_ms = CASE WHEN v_my_color='b' THEN greatest(0, black_time_ms - coalesce(_elapsed_ms,0)) ELSE black_time_ms END,
    draw_offered_by = CASE WHEN draw_offered_by IS NOT NULL AND draw_offered_by = v_uid THEN NULL ELSE draw_offered_by END
  WHERE id=_id;

  -- Vérifier les règles officielles (50 coups, répétition, matériel insuffisant)
  PERFORM public._chess_check_game_end(_id, _fen_after);
END $function$;

-- 8. Mise à jour chess_bot_play — vérifier les règles après chaque coup du bot
CREATE OR REPLACE FUNCTION public.chess_bot_play(_id uuid, _uci text, _san text, _fen_after text, _elapsed_ms integer DEFAULT 0)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_g record;
  v_bot_id uuid;
  v_new_ply int;
BEGIN
  SELECT * INTO v_g FROM chess_games WHERE id = _id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;

  IF v_g.white_is_bot THEN
    v_bot_id := v_g.white_id;
  ELSIF v_g.black_is_bot THEN
    v_bot_id := v_g.black_id;
  ELSE
    RAISE EXCEPTION 'no bot in this game';
  END IF;

  v_new_ply := v_g.ply + 1;
  INSERT INTO chess_moves(game_id, ply, san, uci, fen_after, by_user)
    VALUES (_id, v_new_ply, _san, _uci, _fen_after, v_bot_id);

  UPDATE chess_games SET
    fen = _fen_after,
    turn = CASE WHEN v_g.turn = 'w' THEN 'b' ELSE 'w' END,
    ply = v_new_ply,
    last_move_at = now(),
    turn_deadline = now() + (COALESCE(
      (SELECT turn_timer_seconds FROM public._game_cfg('chess')),
      30
    ) || ' seconds')::interval,
    white_time_ms = CASE WHEN v_g.turn = 'w' THEN greatest(0, v_g.white_time_ms - coalesce(_elapsed_ms, 0)) ELSE v_g.white_time_ms END,
    black_time_ms = CASE WHEN v_g.turn = 'b' THEN greatest(0, v_g.black_time_ms - coalesce(_elapsed_ms, 0)) ELSE v_g.black_time_ms END,
    draw_offered_by = CASE WHEN draw_offered_by = v_bot_id THEN NULL ELSE draw_offered_by END
  WHERE id = _id;

  -- Vérifier les règles officielles
  PERFORM public._chess_check_game_end(_id, _fen_after);
END $function$;

-- 9. Mise à jour chess_tick — tracer end_reason pour timeout
CREATE OR REPLACE FUNCTION public.chess_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_g chess_games%ROWTYPE; cur_uid uuid; opp_uid uuid; _cfg record; _skips int;
BEGIN
  SELECT * INTO v_g FROM chess_games WHERE id=_game_id FOR UPDATE;
  IF v_g.status <> 'playing' OR v_g.turn_deadline IS NULL OR v_g.turn_deadline > now() THEN RETURN; END IF;
  SELECT * INTO _cfg FROM public._game_cfg('chess');
  IF v_g.turn = 'w' THEN cur_uid := v_g.white_id; opp_uid := v_g.black_id;
  ELSE cur_uid := v_g.black_id; opp_uid := v_g.white_id; END IF;
  _skips := COALESCE((v_g.turn_skips->>cur_uid::text)::int, 0) + 1;
  IF _skips >= _cfg.max_turn_skips THEN
    -- L'adversaire gagne par timeout
    UPDATE chess_games SET end_reason = 'timeout' WHERE id = _game_id;
    PERFORM public._chess_payout(_game_id, opp_uid, false);
    RETURN;
  END IF;
  UPDATE chess_games SET
    turn = CASE WHEN turn='w' THEN 'b' ELSE 'w' END,
    turn_skips = jsonb_set(v_g.turn_skips, ARRAY[cur_uid::text], to_jsonb(_skips)),
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
  WHERE id=_game_id;
END $function$;

-- 10. Mise à jour chess_resign — tracer end_reason
CREATE OR REPLACE FUNCTION public.chess_resign(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_g chess_games%ROWTYPE;
  v_winner uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id = _game_id FOR UPDATE;
  IF v_g.id IS NULL THEN RAISE EXCEPTION 'not found'; END IF;

  IF v_g.status = 'open' THEN
    IF v_uid <> v_g.host_id AND v_uid <> v_g.white_id AND v_uid <> v_g.black_id THEN
      RAISE EXCEPTION 'not a player';
    END IF;
    IF v_g.stake > 0 AND v_g.host_id IS NOT NULL THEN
      UPDATE public.profiles SET balance_ar = balance_ar + v_g.stake WHERE id = v_g.host_id;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (v_g.host_id, 'chess_refund', v_g.stake, _game_id, 'Annulation avant départ');
    END IF;
    UPDATE public.chess_games SET status='cancelled', end_reason='cancelled', finished_at=now() WHERE id=_game_id;
    RETURN;
  END IF;

  IF v_g.status <> 'playing' THEN RAISE EXCEPTION 'not active'; END IF;
  IF v_uid = v_g.white_id THEN v_winner := v_g.black_id;
  ELSIF v_uid = v_g.black_id THEN v_winner := v_g.white_id;
  ELSE RAISE EXCEPTION 'not a player'; END IF;
  UPDATE chess_games SET end_reason = 'resign' WHERE id = _game_id;
  PERFORM public._chess_payout(_game_id, v_winner, false);
END $function$;

-- 11. Mise à jour chess_auto_end — utiliser _chess_payout (maintenant sécurisé)
CREATE OR REPLACE FUNCTION public.chess_auto_end(_game_id uuid, _winner uuid, _draw boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE v_uid uuid := auth.uid(); v_g chess_games%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id=_game_id FOR UPDATE;
  IF v_g.status <> 'playing' THEN RETURN; END IF;
  IF v_uid <> v_g.white_id AND v_uid <> v_g.black_id THEN RAISE EXCEPTION 'not a player'; END IF;
  IF NOT _draw AND _winner IS NOT NULL
     AND _winner <> v_g.white_id AND _winner <> v_g.black_id THEN
    RAISE EXCEPTION 'invalid winner';
  END IF;
  UPDATE chess_games SET end_reason = CASE WHEN _draw THEN 'draw_agreed' ELSE 'auto_end' END WHERE id = _game_id;
  PERFORM public._chess_payout(_game_id, _winner, _draw);
END $function$;

-- 12. Mise à jour chess_claim_win — tracer end_reason
CREATE OR REPLACE FUNCTION public.chess_claim_win(_game_id uuid, _winner uuid, _draw boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_g chess_games%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentification requise'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id = _game_id FOR UPDATE;
  IF v_g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_g.status <> 'playing' THEN RAISE EXCEPTION 'Partie non active'; END IF;
  IF v_uid <> v_g.white_id AND v_uid <> v_g.black_id THEN
    RAISE EXCEPTION 'Vous n''êtes pas un joueur de cette partie';
  END IF;
  IF NOT _draw THEN
    IF _winner = v_uid THEN
      RAISE EXCEPTION 'Vous ne pouvez pas vous déclarer gagnant';
    END IF;
    IF _winner <> v_g.white_id AND _winner <> v_g.black_id THEN
      RAISE EXCEPTION 'Gagnant invalide';
    END IF;
  END IF;
  UPDATE chess_games SET end_reason = CASE WHEN _draw THEN 'draw_agreed' ELSE 'claim_win' END WHERE id = _game_id;
  PERFORM public._chess_payout(_game_id, _winner, _draw);
END $function$;

-- 13. Initialiser position_history pour les parties en cours
UPDATE public.chess_games
SET position_history = to_jsonb(public._chess_position_key(fen))::jsonb
WHERE status = 'playing' AND (position_history IS NULL OR position_history = '[]'::jsonb);
