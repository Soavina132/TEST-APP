-- ════════════════════════════════════════════════════════════════════
-- MIGRATION: Fix jsonb_set path argument type
-- Bug: jsonb_set(jsonb, text, jsonb) does not exist
-- Cause: 2nd arg must be text[], not text. Several calls in
--   20260811180000_server_authoritative_game_state.sql used:
--     - bare strings without braces: 'pawns'
--     - text variables: _pawn_idx::text, v_slot::text, etc.
-- Fix: wrap path args in ARRAY[...] or use '{key}' literal syntax.
-- Affected functions: ludo_move, _domino_visible, domino_play
-- ════════════════════════════════════════════════════════════════════

-- ─── Fix 1: ludo_move — path args were text instead of text[] ───────
CREATE OR REPLACE FUNCTION public.ludo_move(_game_id uuid, _pawn_idx integer)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $$
DECLARE
  g public.ludo_games%ROWTYPE;
  st jsonb;
  v_slot INT;
  v_uid UUID := auth.uid();
  v_user UUID;
  v_isbot BOOLEAN;
  arr jsonb;
  pawn jsonb;
  new_k INT;
  new_state TEXT;
  v_dice INT;
  v_new_slot INT;
  v_consec INT;
  captured BOOLEAN := FALSE;
  v_arr_idx INT;
  v_target_slot INT;
  v_target_pawn jsonb;
  v_step INT;
  v_path_idx INT;
  v_home_stretch_idx INT;
  v_movable jsonb;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := g.state;
  v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot, consecutive_sixes INTO v_user, v_isbot, v_consec
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF NOT (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Lancez le dé d''abord'; END IF;
  v_dice := (st->>'dice')::INT;
  IF v_dice IS NULL THEN RAISE EXCEPTION 'Lancez le dé d''abord'; END IF;

  -- Server-side validation that the pawn is actually movable
  v_movable := public._ludo_movable_pawns(st, v_slot, v_dice);
  IF NOT (v_movable @> to_jsonb(_pawn_idx)) THEN
    RAISE EXCEPTION 'Pion non jouable';
  END IF;

  arr := st->'pawns'->v_slot::text;
  pawn := arr->_pawn_idx;
  IF pawn IS NULL THEN RAISE EXCEPTION 'Pion inconnu'; END IF;
  IF pawn->>'s' = 'finished' THEN RAISE EXCEPTION 'Pion deja arrive'; END IF;

  IF pawn->>'s' = 'yard' THEN
    IF v_dice <> 6 THEN RAISE EXCEPTION 'Sortie possible avec un 6'; END IF;
    new_state := 'track';
    new_k := 1;
  ELSE
    new_k := (pawn->>'k')::INT + v_dice;
    IF new_k > 56 THEN RAISE EXCEPTION 'Depassement'; END IF;
    IF new_k = 56 THEN
      new_state := 'finished';
    ELSE
      new_state := 'track';
    END IF;
  END IF;

  -- Update the pawn position  (FIX: ARRAY[...] for jsonb_set path)
  arr := jsonb_set(arr, ARRAY[_pawn_idx::text], jsonb_build_object('s', new_state, 'k', new_k));
  st := jsonb_set(st, '{pawns}', jsonb_set(st->'pawns', ARRAY[v_slot::text], arr));

  -- Check for captures (only on track, not home stretch, not safe cells)
  IF new_state = 'track' AND new_k <= 50 THEN
    v_path_idx := (public._ludo_start_idx(v_slot) + new_k - 1) % 52;
    FOR v_target_slot IN 0..3 LOOP
      IF v_target_slot = v_slot THEN CONTINUE; END IF;
      IF public._ludo_is_safe(v_path_idx) THEN CONTINUE; END IF;
      IF st->'shields' ? v_target_slot::text AND (st->'shields'->>v_target_slot::text)::BOOLEAN THEN
        CONTINUE;
      END IF;
      arr := st->'pawns'->v_target_slot::text;
      IF arr IS NULL THEN CONTINUE; END IF;
      FOR v_arr_idx IN 0..3 LOOP
        v_target_pawn := arr->v_arr_idx;
        IF v_target_pawn IS NULL THEN CONTINUE; END IF;
        IF v_target_pawn->>'s' = 'track' THEN
          v_step := (v_target_pawn->>'k')::INT;
          IF v_step <= 50 THEN
            v_path_idx := (public._ludo_start_idx(v_target_slot) + v_step - 1) % 52;
            IF (public._ludo_start_idx(v_slot) + new_k - 1) % 52 = v_path_idx THEN
              -- Send the captured pawn back to yard  (FIX: ARRAY[...])
              arr := jsonb_set(arr, ARRAY[v_arr_idx::text], jsonb_build_object('s', 'yard', 'k', 0));
              st := jsonb_set(st, '{pawns}', jsonb_set(st->'pawns', ARRAY[v_target_slot::text], arr));
              captured := TRUE;
            END IF;
          END IF;
        END IF;
      END LOOP;
    END LOOP;
  END IF;

  -- Power tile effects
  IF st ? 'power_tiles' AND new_state = 'track' AND new_k <= 50 THEN
    v_path_idx := (public._ludo_start_idx(v_slot) + new_k - 1) % 52;
    SELECT elem->>'type' INTO v_target_slot FROM (
      SELECT (jsonb_array_elements(st->'power_tiles')) AS elem
    ) sub WHERE (elem->>'cell')::INT = v_path_idx LIMIT 1;
  END IF;

  -- Clear movable_pawns
  st := st - 'movable_pawns';

  -- Determine if player gets another turn (rolled 6, captured, or finished)
  IF v_dice = 6 OR captured OR new_state = 'finished' THEN
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb(CASE
      WHEN captured AND new_state = 'finished' THEN 'capture:home'
      WHEN captured THEN 'capture'
      WHEN new_state = 'finished' THEN 'home'
      ELSE 'six'
    END));
  ELSE
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{dice}','null'::jsonb);
    v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
    st := public._ludo_clear_shield(st, v_new_slot);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(v_new_slot));
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('move'));
  END IF;

  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  PERFORM public._ludo_check_game_over(_game_id);
  RETURN st;
END $$;

-- ─── Fix 2: _domino_visible — i::text → ARRAY[i::text] ──────────────
CREATE OR REPLACE FUNCTION public._domino_visible(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $$
DECLARE
  g public.domino_games%ROWTYPE;
  st jsonb;
  v_slot INT;
  v_visible jsonb;
  v_playable jsonb;
  v_hands_visible jsonb;
  i INT;
  hand jsonb;
  v_uid UUID := auth.uid();
  v_part record;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id=_game_id;
  st := g.state;
  v_slot := (st->>'turn_slot')::INT;

  v_visible := jsonb_build_object(
    'board', st->'board',
    'left_end', st->'left_end',
    'right_end', st->'right_end',
    'turn_slot', v_slot,
    'passes', st->'passes',
    'last_pass_by', st->'last_pass_by',
    'round', st->'round',
    'target_score', st->'target_score',
    'draw_mode', st->'draw_mode',
    'first_tile_rule', COALESCE(st->'first_tile_rule','libre'),
    'first_move_double', st->'first_move_double',
    'round_winner_slot', st->'round_winner_slot',
    'round_scores', st->'round_scores',
    'stock_size', COALESCE(jsonb_array_length(st->'stock'), 0)
  );

  v_playable := public._domino_playable_tiles(st, v_slot);
  v_visible := jsonb_set(v_visible, '{playable_tiles}', v_playable);

  SELECT * INTO v_part FROM public.domino_participants
    WHERE game_id=_game_id AND user_id=v_uid LIMIT 1;

  v_hands_visible := '{}'::jsonb;
  FOR i IN 0..20 LOOP
    IF v_part IS NOT NULL AND i = v_part.slot THEN
      hand := st->'hands'->i::text;
      -- FIX: ARRAY[i::text] instead of i::text
      v_hands_visible := jsonb_set(v_hands_visible, ARRAY[i::text], COALESCE(hand, '[]'::jsonb));
    ELSIF st->'hands' ? i::text THEN
      -- FIX: ARRAY[i::text] instead of i::text
      v_hands_visible := jsonb_set(v_hands_visible, ARRAY[i::text],
        to_jsonb(jsonb_array_length(st->'hands'->i::text)));
    END IF;
  END LOOP;

  v_visible := jsonb_set(v_visible, '{hands}', v_hands_visible);
  RETURN v_visible;
END $$;

-- ─── Fix 3: domino_play — v_slot::text → ARRAY[v_slot::text] ───────
CREATE OR REPLACE FUNCTION public.domino_play(_game_id uuid, _move jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $$
DECLARE
  g public.domino_games%ROWTYPE;
  st jsonb;
  v_slot INT;
  v_uid UUID := auth.uid();
  v_part record;
  v_action TEXT;
  v_tile_idx INT;
  v_side TEXT;
  v_playable jsonb;
  hand jsonb;
  tile jsonb;
  a INT; b INT;
  left_end INT; right_end INT;
  board jsonb;
  first_move_double INT;
  first_tile_rule TEXT;
  v_new_left INT; v_new_right INT;
  v_board_entry jsonb;
  v_passes INT;
  v_last_pass INT;
  v_next_slot INT;
  v_stock_len INT;
  v_draw_mode TEXT;
  v_target INT;
  v_round_scores jsonb;
  v_hands jsonb;
  i INT;
  v_lowest_pips INT;
  v_lowest_slot INT;
  v_pips INT;
  v_winner_slot INT;
  v_hand_pips INT;
  v_round INT;
  v_all_blocked BOOLEAN;
  v_active_count INT;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;

  st := g.state;
  v_slot := (st->>'turn_slot')::INT;
  SELECT * INTO v_part FROM public.domino_participants
    WHERE game_id=_game_id AND slot=v_slot;

  IF v_part.user_id IS NOT NULL AND v_part.user_id <> v_uid THEN
    RAISE EXCEPTION 'Pas votre tour';
  END IF;

  v_action := _move->>'action';

  -- ─── PLAY action ──────────────────────────────────────────────
  IF v_action = 'play' THEN
    v_tile_idx := (_move->>'tile_idx')::INT;
    v_side := COALESCE(_move->>'side', 'auto');

    v_playable := public._domino_playable_tiles(st, v_slot);
    IF NOT (v_playable @> to_jsonb(v_tile_idx)) THEN
      RAISE EXCEPTION 'Tuile non jouable';
    END IF;

    hand := st->'hands'->v_slot::text;
    tile := hand->v_tile_idx;
    a := (tile->>0)::INT;
    b := (tile->>1)::INT;
    board := st->'board';
    left_end := NULLIF(st->'left_end','')::INT;
    right_end := NULLIF(st->'right_end','')::INT;
    first_move_double := NULLIF(st->>'first_move_double','')::INT;
    first_tile_rule := COALESCE(st->>'first_tile_rule', 'libre');

    IF jsonb_array_length(board) = 0 THEN
      IF first_move_double IS NOT NULL THEN
        IF NOT (a = first_move_double AND b = first_move_double) THEN
          RAISE EXCEPTION 'Doit jouer le double %', first_move_double;
        END IF;
      ELSIF first_tile_rule = 'under6' THEN
        IF a + b >= 6 THEN RAISE EXCEPTION 'Somme doit etre < 6'; END IF;
      END IF;
      v_new_left := a;
      v_new_right := b;
      v_board_entry := jsonb_build_array(jsonb_build_object('t', jsonb_build_array(a,b), 'slot', v_slot));
      st := jsonb_set(st, '{board}', v_board_entry);
      st := jsonb_set(st, '{left_end}', to_jsonb(v_new_left));
      st := jsonb_set(st, '{right_end}', to_jsonb(v_new_right));
      st := st - 'first_move_double';
    ELSE
      IF v_side = 'left' OR (v_side = 'auto' AND (a = left_end OR b = left_end)) THEN
        IF b = left_end THEN
          v_board_entry := jsonb_build_array(jsonb_build_object('t', jsonb_build_array(b,a), 'slot', v_slot)) || board;
        ELSIF a = left_end THEN
          v_board_entry := jsonb_build_array(jsonb_build_object('t', jsonb_build_array(a,b), 'slot', v_slot)) || board;
        ELSE
          RAISE EXCEPTION 'Ne match pas le côté gauche';
        END IF;
        v_new_left := CASE WHEN b = left_end THEN a ELSE b END;
        v_new_right := right_end;
        st := jsonb_set(st, '{board}', v_board_entry);
        st := jsonb_set(st, '{left_end}', to_jsonb(v_new_left));
      ELSIF v_side = 'right' OR (v_side = 'auto' AND (a = right_end OR b = right_end)) THEN
        IF a = right_end THEN
          v_board_entry := board || jsonb_build_array(jsonb_build_object('t', jsonb_build_array(a,b), 'slot', v_slot));
        ELSIF b = right_end THEN
          v_board_entry := board || jsonb_build_array(jsonb_build_object('t', jsonb_build_array(b,a), 'slot', v_slot));
        ELSE
          RAISE EXCEPTION 'Ne match pas le côté droit';
        END IF;
        v_new_left := left_end;
        v_new_right := CASE WHEN a = right_end THEN b ELSE a END;
        st := jsonb_set(st, '{board}', v_board_entry);
        st := jsonb_set(st, '{right_end}', to_jsonb(v_new_right));
      ELSE
        RAISE EXCEPTION 'Tuile ne match ni gauche ni droite';
      END IF;
    END IF;

    -- Remove tile from hand
    hand := hand - v_tile_idx;
    -- FIX: ARRAY[v_slot::text] instead of v_slot::text
    st := jsonb_set(st->'hands', ARRAY[v_slot::text], hand);
    st := jsonb_set(st, '{hands}', st->'hands');

    -- Reset passes
    st := jsonb_set(st, '{passes}', '0'::jsonb);
    st := jsonb_set(st, '{last_pass_by}', 'null'::jsonb);

    -- Check if hand is empty (round winner)
    IF jsonb_array_length(hand) = 0 THEN
      PERFORM public._domino_end_round(_game_id, v_slot);
      RETURN public._domino_visible(_game_id);
    END IF;

    -- Advance turn
    v_next_slot := public._domino_next_playable_slot(_game_id, v_slot, st);
    st := jsonb_set(st, '{turn_slot}', to_jsonb(v_next_slot));
    st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    v_playable := public._domino_playable_tiles(st, v_next_slot);
    st := jsonb_set(st, '{playable_tiles}', v_playable);
    st := jsonb_set(st, '{last_event}', to_jsonb('play'));

    UPDATE public.domino_games SET state=st, current_turn=v_next_slot WHERE id=_game_id;
    RETURN public._domino_visible(_game_id);

  -- ─── DRAW action ──────────────────────────────────────────────
  ELSIF v_action = 'draw' THEN
    v_stock_len := COALESCE(jsonb_array_length(st->'stock'), 0);
    IF v_stock_len = 0 THEN RAISE EXCEPTION 'Stock vide'; END IF;
    hand := st->'hands'->v_slot::text;
    tile := st->'stock'->0;
    st := jsonb_set(st, '{stock}', st->'stock' - 0);
    hand := hand || tile;
    -- FIX: ARRAY[v_slot::text] instead of v_slot::text
    st := jsonb_set(st->'hands', ARRAY[v_slot::text], hand);
    v_playable := public._domino_playable_tiles(st, v_slot);
    st := jsonb_set(st, '{playable_tiles}', v_playable);
    st := jsonb_set(st, '{last_event}', to_jsonb('draw'));
    UPDATE public.domino_games SET state=st WHERE id=_game_id;
    RETURN public._domino_visible(_game_id);

  -- ─── PASS action ───────────────────────────────────────────────
  ELSIF v_action = 'pass' THEN
    v_playable := public._domino_playable_tiles(st, v_slot);
    IF jsonb_array_length(v_playable) > 0 THEN
      RAISE EXCEPTION 'Vous avez un domino jouable';
    END IF;
    v_draw_mode := COALESCE(st->>'draw_mode', 'with');
    v_stock_len := COALESCE(jsonb_array_length(st->'stock'), 0);
    IF v_draw_mode = 'with' AND v_stock_len > 0 THEN
      RAISE EXCEPTION 'Vous devez piocher avant de passer';
    END IF;

    v_passes := COALESCE((st->>'passes')::INT, 0) + 1;
    v_last_pass := v_slot;
    st := jsonb_set(st, '{passes}', to_jsonb(v_passes));
    st := jsonb_set(st, '{last_pass_by}', to_jsonb(v_last_pass));

    SELECT count(*) INTO v_active_count FROM public.domino_participants
      WHERE game_id=_game_id AND NOT forfeited;
    IF v_passes >= v_active_count THEN
      PERFORM public._domino_end_round(_game_id, public._domino_lowest_pip_slot(_game_id, st));
      RETURN public._domino_visible(_game_id);
    END IF;

    v_next_slot := public._domino_next_playable_slot(_game_id, v_slot, st);
    st := jsonb_set(st, '{turn_slot}', to_jsonb(v_next_slot));
    st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    v_playable := public._domino_playable_tiles(st, v_next_slot);
    st := jsonb_set(st, '{playable_tiles}', v_playable);
    st := jsonb_set(st, '{last_event}', to_jsonb('pass'));
    UPDATE public.domino_games SET state=st, current_turn=v_next_slot WHERE id=_game_id;
    RETURN public._domino_visible(_game_id);

  ELSE
    RAISE EXCEPTION 'Action inconnue: %', v_action;
  END IF;
END $$;
