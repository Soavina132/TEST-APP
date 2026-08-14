-- ============================================================
-- Règles officielles des échecs — réclamables vs automatiques
--
-- Changements:
-- 1. Règle des 50 coups (halfmove >= 100) → RÉCLAMABLE (ne pas auto-settle)
-- 2. Règle des 75 coups (halfmove >= 150) → AUTOMATIQUE (auto-settle)
-- 3. Répétition triple (count >= 3) → RÉCLAMABLE (ne pas auto-settle)
-- 4. Répétition quintuple (count >= 5) → AUTOMATIQUE (auto-settle)
-- 5. chess_claim_draw — nouvelle fonction pour réclamer la nulle (50 coups ou triple)
-- 6. _chess_can_claim_draw — vérifie si une nulle est réclamable
-- 7. _chess_has_mating_material — vérifie si un joueur a assez de matériel pour mater
-- 8. chess_auto_timeout — ne fait perdre que si l'adversaire a le matériel pour mater
-- 9. Position morte — extension de _chess_insufficient_material
-- ============================================================

-- ============================================================
-- 1. Matériel suffisant pour mater (côté gagnant au timeout)
-- ============================================================
CREATE OR REPLACE FUNCTION public._chess_has_mating_material(_fen text, _color text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  placement text;
  rows text[];
  row_str text;
  ch text;
  i int;
  j int;
  has_pawn boolean := false;
  has_rook boolean := false;
  has_queen boolean := false;
  has_knight int := 0;
  has_bishop int := 0;
  bishop_colors text := '';
  is_white boolean;
BEGIN
  placement := split_part(_fen, ' ', 1);
  is_white := (_color = 'w');
  i := 0;
  rows := string_to_array(placement, '/');

  FOREACH row_str IN ARRAY rows LOOP
    FOR j IN 1..length(row_str) LOOP
      ch := substring(row_str, j, 1);
      IF ch ~ '[1-8]' THEN
        i := i + ch::int;
      ELSIF ch IN ('K', 'k') THEN
        i := i + 1;
      ELSIF is_white AND ch IN ('P','R','Q','N','B') THEN
        IF ch = 'P' THEN has_pawn := true;
        ELSIF ch = 'R' THEN has_rook := true;
        ELSIF ch = 'Q' THEN has_queen := true;
        ELSIF ch = 'N' THEN has_knight := has_knight + 1;
        ELSIF ch = 'B' THEN
          has_bishop := has_bishop + 1;
          bishop_colors := bishop_colors || CASE WHEN (i / 8 + i % 8) % 2 = 0 THEN 'L' ELSE 'D' END;
        END IF;
        i := i + 1;
      ELSIF NOT is_white AND ch IN ('p','r','q','n','b') THEN
        IF ch = 'p' THEN has_pawn := true;
        ELSIF ch = 'r' THEN has_rook := true;
        ELSIF ch = 'q' THEN has_queen := true;
        ELSIF ch = 'n' THEN has_knight := has_knight + 1;
        ELSIF ch = 'b' THEN
          has_bishop := has_bishop + 1;
          bishop_colors := bishop_colors || CASE WHEN (i / 8 + i % 8) % 2 = 0 THEN 'L' ELSE 'D' END;
        END IF;
        i := i + 1;
      ELSE
        i := i + 1;
      END IF;
    END LOOP;
  END LOOP;

  -- Pion, tour ou dame → peut toujours mater
  IF has_pawn OR has_rook OR has_queen THEN RETURN true; END IF;

  -- 2 cavaliers + 0 fou → peut mater (mate possible même si non forçable)
  IF has_knight >= 2 AND has_bishop = 0 THEN RETURN true; END IF;

  -- Fou + cavalier → peut mater
  IF has_bishop >= 1 AND has_knight >= 1 THEN RETURN true; END IF;

  -- 2 fous de couleurs différentes → peut mater
  IF has_bishop >= 2 AND position('L' in bishop_colors) > 0 AND position('D' in bishop_colors) > 0 THEN RETURN true; END IF;

  -- 1 cavalier → ne peut pas mater seul
  -- 1 fou → ne peut pas mater seul
  -- Rien → ne peut pas mater
  RETURN false;
END $$;

-- ============================================================
-- 2. Vérifier si une nulle est réclamable (50 coups ou triple répétition)
-- ============================================================
CREATE OR REPLACE FUNCTION public._chess_can_claim_draw(_game_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_g chess_games%ROWTYPE;
  v_halfmove int;
  v_pos_key text;
  v_pos_count int;
  v_history jsonb;
BEGIN
  SELECT * INTO v_g FROM chess_games WHERE id = _game_id FOR UPDATE;
  IF v_g.id IS NULL OR v_g.status <> 'playing' THEN
    RETURN jsonb_build_object('can_claim', false);
  END IF;

  v_halfmove := public._chess_halfmove_clock(v_g.fen);

  -- Vérifier répétition triple
  v_pos_key := public._chess_position_key(v_g.fen);
  v_history := COALESCE(v_g.position_history, '[]'::jsonb);
  SELECT count(*) INTO v_pos_count
  FROM jsonb_array_elements(v_history) AS pos
  WHERE pos::text = to_jsonb(v_pos_key)::text;

  RETURN jsonb_build_object(
    'can_claim', (v_halfmove >= 100 OR v_pos_count >= 3),
    'fifty_move', v_halfmove >= 100,
    'threefold', v_pos_count >= 3,
    'halfmove_clock', v_halfmove,
    'repetition_count', v_pos_count
  );
END $$;

-- ============================================================
-- 3. Réclamer la nulle (50 coups ou triple répétition)
-- ============================================================
CREATE OR REPLACE FUNCTION public.chess_claim_draw(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_g chess_games%ROWTYPE;
  v_halfmove int;
  v_pos_key text;
  v_pos_count int;
  v_history jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id = _game_id FOR UPDATE;
  IF v_g.id IS NULL THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  IF v_g.white_id <> v_uid AND v_g.black_id <> v_uid THEN RAISE EXCEPTION 'not a participant'; END IF;

  v_halfmove := public._chess_halfmove_clock(v_g.fen);
  v_pos_key := public._chess_position_key(v_g.fen);
  v_history := COALESCE(v_g.position_history, '[]'::jsonb);
  SELECT count(*) INTO v_pos_count
  FROM jsonb_array_elements(v_history) AS pos
  WHERE pos::text = to_jsonb(v_pos_key)::text;

  IF v_halfmove >= 100 THEN
    PERFORM public._chess_settle(_game_id, NULL, true, 'fifty_move_rule');
  ELSIF v_pos_count >= 3 THEN
    PERFORM public._chess_settle(_game_id, NULL, true, 'threefold_repetition');
  ELSE
    RAISE EXCEPTION 'no claimable draw available';
  END IF;
END $$;

-- ============================================================
-- 4. Mettre à jour _chess_check_game_end — réclamable vs automatique
-- ============================================================
CREATE OR REPLACE FUNCTION public._chess_check_game_end(_game_id uuid, _fen_after text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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

  v_halfmove := public._chess_halfmove_clock(_fen_after);

  -- Matériel insuffisant / position morte → AUTOMATIQUE
  v_insufficient := public._chess_insufficient_material(_fen_after);
  IF v_insufficient THEN
    PERFORM public._chess_settle(_game_id, NULL, true, 'insufficient_material');
    RETURN;
  END IF;

  -- Règle des 75 coups (halfmove >= 150) → AUTOMATIQUE
  IF v_halfmove >= 150 THEN
    PERFORM public._chess_settle(_game_id, NULL, true, 'seventyfive_move_rule');
    RETURN;
  END IF;

  -- Règle des 50 coups (halfmove >= 100) → RÉCLAMABLE (ne pas auto-settle)

  -- Répétition
  v_pos_key := public._chess_position_key(_fen_after);
  v_history := COALESCE(v_g.position_history, '[]'::jsonb);
  v_history := v_history || to_jsonb(v_pos_key);
  SELECT count(*) INTO v_pos_count
  FROM jsonb_array_elements(v_history) AS pos
  WHERE pos::text = to_jsonb(v_pos_key)::text;
  UPDATE chess_games SET position_history = v_history WHERE id = _game_id;

  -- Répétition quintuple (count >= 5) → AUTOMATIQUE
  IF v_pos_count >= 5 THEN
    PERFORM public._chess_settle(_game_id, NULL, true, 'fivefold_repetition');
    RETURN;
  END IF;

  -- Répétition triple (count >= 3) → RÉCLAMABLE (ne pas auto-settle)
END $$;

-- ============================================================
-- 5. Mettre à jour chess_auto_timeout — vérifier le matériel
-- ============================================================
CREATE OR REPLACE FUNCTION public.chess_auto_timeout(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_g chess_games%ROWTYPE;
  v_elapsed_ms int;
  v_remaining int;
  v_winner uuid;
  v_loser_color text;
  v_winner_color text;
  v_winner_has_material boolean;
BEGIN
  SELECT * INTO v_g FROM chess_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND OR v_g.status <> 'playing' THEN RETURN; END IF;
  IF coalesce(v_g.paused, false) THEN RETURN; END IF;
  IF v_g.time_control_min <= 0 THEN RETURN; END IF;

  v_elapsed_ms := greatest(0, floor(extract(epoch FROM (now() - coalesce(v_g.last_move_at, v_g.started_at, now())))*1000)::int);

  IF v_g.turn = 'w' THEN
    v_remaining := v_g.white_time_ms - v_elapsed_ms;
    v_winner := v_g.black_id;
    v_loser_color := 'w';
    v_winner_color := 'b';
  ELSE
    v_remaining := v_g.black_time_ms - v_elapsed_ms;
    v_winner := v_g.white_id;
    v_loser_color := 'b';
    v_winner_color := 'w';
  END IF;

  IF v_remaining <= 0 THEN
    -- Vérifier si l'adversaire (le gagnant) a assez de matériel pour mater
    v_winner_has_material := public._chess_has_mating_material(v_g.fen, v_winner_color);

    IF v_winner_has_material THEN
      -- L'adversaire peut mater → victoire par timeout
      PERFORM public._chess_settle(_game_id, v_winner, false, 'timeout');
    ELSE
      -- L'adversaire ne peut pas mater → nulle par timeout
      PERFORM public._chess_settle(_game_id, NULL, true, 'timeout_insufficient_material');
    END IF;
  END IF;
END $$;

-- ============================================================
-- 6. Révoquer l'accès aux fonctions internes
-- ============================================================
REVOKE EXECUTE ON FUNCTION public._chess_has_mating_material(text, text) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._chess_can_claim_draw(uuid) FROM anon, authenticated;
