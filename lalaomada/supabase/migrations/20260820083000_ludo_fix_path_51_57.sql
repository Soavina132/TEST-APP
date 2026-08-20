-- ============================================================
-- Fix: Corriger le parcours du Ludo
-- Le circuit principal passe de 50 à 51 cases (case 51 accessible)
-- La home stretch passe de k=52-57 (au lieu de k=51-56)
-- k=57 = finished (au lieu de k=56)
-- La case 52 (derrière la case de départ) n'est jamais atteinte
-- ============================================================

-- ── 1. _ludo_movable_pawns ──
CREATE OR REPLACE FUNCTION public._ludo_movable_pawns(st jsonb, _slot int, _dice int)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  arr jsonb; pawn jsonb; i INT; pstate TEXT; pstep INT;
  result jsonb := '[]'::jsonb;
  v_new_k INT;
  v_path_idx INT;
  v_max_players INT;
  v_start INT;
BEGIN
  IF _dice IS NULL OR _dice < 1 OR _dice > 6 THEN RETURN '[]'::jsonb; END IF;
  IF _slot IS NULL THEN RETURN '[]'::jsonb; END IF;
  arr := st->'pawns'->_slot::text;
  IF arr IS NULL OR arr = 'null'::jsonb THEN RETURN '[]'::jsonb; END IF;
  v_max_players := COALESCE((st->>'max_players')::int, 4);
  v_start := public._ludo_start_from_state(st, _slot);

  FOR i IN 0..3 LOOP
    pawn := arr->i;
    IF pawn IS NULL THEN CONTINUE; END IF;
    pstate := pawn->>'s';
    pstep := COALESCE((pawn->>'k')::INT, -1);
    IF pstate = 'finished' THEN CONTINUE; END IF;
    IF pstate = 'yard' THEN
      IF _dice = 6 THEN
        result := result || to_jsonb(i);
      END IF;
    ELSIF pstate = 'track' THEN
      v_new_k := pstep + _dice;
      IF v_new_k <= 57 THEN
        IF v_new_k <= 51 THEN
          v_path_idx := (v_start + v_new_k - 1) % 52;
          IF NOT public._ludo_is_blocked(st, _slot, v_path_idx, v_max_players) THEN
            result := result || to_jsonb(i);
          END IF;
        ELSE
          -- Zone d'arrivée (52-57): toujours jouable
          result := result || to_jsonb(i);
        END IF;
      END IF;
    END IF;
  END LOOP;
  RETURN result;
END $$;


-- ── 2. ludo_move ──
CREATE OR REPLACE FUNCTION public.ludo_move(_game_id uuid, _pawn_idx int)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
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
  v_moving_path_idx INT;
  v_target_path_idx INT;
  v_movable jsonb;
  v_target_count INT;
  v_max_players INT;
  v_start_idx INT;
  v_has_power_tiles BOOLEAN;
  v_power_type TEXT;
  v_got_double_roll BOOLEAN := FALSE;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := g.state;
  v_slot := (st->>'turn_slot')::INT;
  v_max_players := g.max_players;
  SELECT user_id, is_bot, consecutive_sixes INTO v_user, v_isbot, v_consec
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF NOT (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Lancez le de d''abord'; END IF;
  v_dice := (st->>'dice')::INT;
  IF v_dice IS NULL THEN RAISE EXCEPTION 'Lancez le de d''abord'; END IF;
  v_movable := public._ludo_movable_pawns(st, v_slot, v_dice);
  IF NOT (v_movable @> to_jsonb(_pawn_idx)) THEN
    RAISE EXCEPTION 'Pion non jouable';
  END IF;
  
  st := st - 'power_event';
  
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
    IF new_k > 57 THEN RAISE EXCEPTION 'Depassement'; END IF;
    IF new_k = 57 THEN
      new_state := 'finished';
    ELSE
      new_state := 'track';
    END IF;
  END IF;
  arr := jsonb_set(arr, ARRAY[_pawn_idx::text], jsonb_build_object('s', new_state, 'k', new_k));
  st := jsonb_set(st, '{pawns}', jsonb_set(st->'pawns', ARRAY[v_slot::text], arr));

  -- Capture check
  IF new_state = 'track' AND new_k <= 51 THEN
    v_moving_path_idx := (public._ludo_start_from_state(st, v_slot) + new_k - 1) % 52;
    IF NOT public._ludo_is_safe(v_moving_path_idx) THEN
      FOR v_target_slot IN 0..3 LOOP
        IF v_target_slot = v_slot THEN CONTINUE; END IF;
        IF v_target_slot >= v_max_players THEN CONTINUE; END IF;
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
            IF v_step <= 51 THEN
              v_target_path_idx := (public._ludo_start_from_state(st, v_target_slot) + v_step - 1) % 52;
              IF v_moving_path_idx = v_target_path_idx THEN
                v_target_count := public._ludo_count_on_cell(st, v_target_slot, v_target_path_idx);
                IF v_target_count >= 2 THEN CONTINUE; END IF;
                arr := jsonb_set(arr, ARRAY[v_arr_idx::text], jsonb_build_object('s', 'yard', 'k', 0));
                st := jsonb_set(st, '{pawns}', jsonb_set(st->'pawns', ARRAY[v_target_slot::text], arr));
                captured := TRUE;
              END IF;
            END IF;
          END IF;
        END LOOP;
      END LOOP;
    END IF;
  END IF;

  -- Power tile check (Mode Moderne)
  v_start_idx := public._ludo_start_from_state(st, v_slot);
  v_has_power_tiles := (st ? 'power_tiles') AND jsonb_array_length(st->'power_tiles') > 0;
  
  IF v_has_power_tiles AND new_state = 'track' AND new_k <= 51 THEN
    st := public._ludo_check_power_tile(st, v_slot, _pawn_idx, new_k, v_start_idx);
    
    IF st ? 'power_event' THEN
      arr := st->'pawns'->v_slot::text;
      pawn := arr->_pawn_idx;
      new_k := (pawn->>'k')::INT;
      new_state := pawn->>'s';
        
        IF new_state = 'track' AND new_k <= 51 THEN
          v_moving_path_idx := (v_start_idx + new_k - 1) % 52;
          IF NOT public._ludo_is_safe(v_moving_path_idx) THEN
            FOR v_target_slot IN 0..3 LOOP
              IF v_target_slot = v_slot THEN CONTINUE; END IF;
              IF v_target_slot >= v_max_players THEN CONTINUE; END IF;
              IF st->'shields' ? v_target_slot::text AND (st->'shields'->>v_target_slot::text)::BOOLEAN THEN CONTINUE; END IF;
              arr := st->'pawns'->v_target_slot::text;
              IF arr IS NULL THEN CONTINUE; END IF;
              FOR v_arr_idx IN 0..3 LOOP
                v_target_pawn := arr->v_arr_idx;
                IF v_target_pawn IS NULL THEN CONTINUE; END IF;
                IF v_target_pawn->>'s' = 'track' THEN
                  v_step := (v_target_pawn->>'k')::INT;
                  IF v_step <= 51 THEN
                    v_target_path_idx := (public._ludo_start_from_state(st, v_target_slot) + v_step - 1) % 52;
                    IF v_moving_path_idx = v_target_path_idx THEN
                      v_target_count := public._ludo_count_on_cell(st, v_target_slot, v_target_path_idx);
                      IF v_target_count >= 2 THEN CONTINUE; END IF;
                      arr := jsonb_set(arr, ARRAY[v_arr_idx::text], jsonb_build_object('s', 'yard', 'k', 0));
                      st := jsonb_set(st, '{pawns}', jsonb_set(st->'pawns', ARRAY[v_target_slot::text], arr));
                      captured := TRUE;
                    END IF;
                  END IF;
                END IF;
              END LOOP;
            END LOOP;
          END IF;
      END IF;
      
      IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::INT = v_slot THEN
        v_got_double_roll := TRUE;
      END IF;
    END IF;
  END IF;

  st := jsonb_set(st, '{no_move_streak}', '0'::jsonb);
  st := st - 'movable_pawns';
  
  -- Turn continuation
  IF v_dice = 6 OR captured OR new_state = 'finished' OR v_got_double_roll THEN
    IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::INT = v_slot THEN
      st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
    END IF;
    
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st,'{turn_seq}', to_jsonb(COALESCE((st->>'turn_seq')::int, 0) + 1));
    st := jsonb_set(st,'{last_event}', to_jsonb(CASE
      WHEN captured AND new_state = 'finished' THEN 'capture:home'
      WHEN captured THEN 'capture'
      WHEN new_state = 'finished' THEN 'home'
      WHEN v_got_double_roll AND st ? 'power_event' AND (st->'power_event'->>'type') = 'lucky_star' THEN 'lucky_star:rejoue'
      WHEN v_got_double_roll THEN 'double_roll:rejoue'
      ELSE 'six'
    END));
  ELSE
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{dice}','null'::jsonb);
    v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
    st := public._ludo_clear_shield(st, v_new_slot);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(v_new_slot));
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st,'{turn_seq}', to_jsonb(COALESCE((st->>'turn_seq')::int, 0) + 1));
    st := jsonb_set(st,'{last_event}', to_jsonb('move'::text));
  END IF;
  
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  PERFORM public._ludo_check_game_over(_game_id);
  RETURN st;
END $$;


-- ── 3. _ludo_check_power_tile ──
CREATE OR REPLACE FUNCTION public._ludo_check_power_tile(st jsonb, _slot int, _pawn_idx int, _new_k int, _start_idx int)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  tiles jsonb;
  i INT;
  tile_type TEXT;
  tile_cell INT;
  landing_cell INT;
  new_st jsonb := st;
  power_event jsonb;
  reward_type TEXT;
  arr jsonb;
  pawn jsonb;
  new_k INT;
  boost_amount INT;
  free_pawn_idx INT := -1;
  j INT;
  current_k INT := _new_k;
  loop_count INT := 0;
  found_tile BOOLEAN;
BEGIN
  -- Only check if on main track (k <= 51)
  IF _new_k > 51 THEN RETURN st; END IF;

  LOOP
    loop_count := loop_count + 1;
    IF loop_count > 10 THEN EXIT; END IF;

    IF current_k > 51 THEN EXIT; END IF;

    tiles := new_st->'power_tiles';
    IF tiles IS NULL OR jsonb_array_length(tiles) = 0 THEN EXIT; END IF;

    landing_cell := (_start_idx + current_k - 1) % 52;

    found_tile := FALSE;

    FOR i IN 0..jsonb_array_length(tiles) - 1 LOOP
      tile_type := tiles->i->>'type';
      tile_cell := (tiles->i->>'cell')::INT;
      IF tile_cell = landing_cell THEN
        found_tile := TRUE;

        IF tile_type = 'lucky_star' THEN
          reward_type := (ARRAY['boost','shield','double_roll','free_pawn'])[1 + floor(random() * 4)::INT];
        ELSE
          reward_type := tile_type;
        END IF;

        IF reward_type = 'boost' THEN
          boost_amount := 1 + floor(random() * 6)::INT;
          arr := new_st->'pawns'->_slot::text;
          pawn := arr->_pawn_idx;
          new_k := current_k + boost_amount;
          IF new_k > 57 THEN new_k := 57; END IF;
          IF new_k = 57 THEN
            arr := jsonb_set(arr, ARRAY[_pawn_idx::text], jsonb_build_object('s','finished','k',new_k));
          ELSE
            arr := jsonb_set(arr, ARRAY[_pawn_idx::text], jsonb_build_object('s','track','k',new_k));
          END IF;
          new_st := jsonb_set(new_st, '{pawns}', jsonb_set(new_st->'pawns', ARRAY[_slot::text], arr));
          current_k := new_k;

        ELSIF reward_type = 'shield' THEN
          IF new_st->'shields' IS NULL THEN
            new_st := jsonb_set(new_st, '{shields}', jsonb_build_object(_slot::text, true));
          ELSE
            new_st := jsonb_set(new_st, ARRAY['shields', _slot::text], 'true'::jsonb);
          END IF;

        ELSIF reward_type = 'double_roll' THEN
          new_st := jsonb_set(new_st, '{double_roll_pending}', to_jsonb(_slot));

        ELSIF reward_type = 'free_pawn' THEN
          arr := new_st->'pawns'->_slot::text;
          FOR j IN 0..3 LOOP
            IF (arr->j->>'s') = 'yard' THEN
              free_pawn_idx := j;
              EXIT;
            END IF;
          END LOOP;
          IF free_pawn_idx >= 0 THEN
            arr := jsonb_set(arr, ARRAY[free_pawn_idx::text], jsonb_build_object('s','track','k',1));
            new_st := jsonb_set(new_st, '{pawns}', jsonb_set(new_st->'pawns', ARRAY[_slot::text], arr));
          END IF;
        END IF;

        IF tile_type = 'lucky_star' THEN
          power_event := jsonb_build_object(
            'type', 'lucky_star',
            'reward', reward_type,
            'slot', _slot,
            'pawn', _pawn_idx,
            'free_pawn_idx', CASE WHEN reward_type = 'free_pawn' THEN free_pawn_idx ELSE NULL END,
            'cell', landing_cell,
            'dice', CASE WHEN reward_type = 'boost' THEN boost_amount ELSE NULL END,
            'at', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
          );
        ELSE
          power_event := jsonb_build_object(
            'type', tile_type,
            'slot', _slot,
            'pawn', _pawn_idx,
            'free_pawn_idx', CASE WHEN tile_type = 'free_pawn' THEN free_pawn_idx ELSE NULL END,
            'cell', landing_cell,
            'dice', CASE WHEN tile_type = 'boost' THEN boost_amount ELSE NULL END,
            'at', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
          );
        END IF;
        new_st := jsonb_set(new_st, '{power_event}', power_event);

        new_st := public._ludo_relocate_power_tile(new_st, landing_cell);

        EXIT;
      END IF;
    END LOOP;

    IF NOT found_tile THEN EXIT; END IF;

    IF current_k >= 57 THEN EXIT; END IF;

    free_pawn_idx := -1;
  END LOOP;

  RETURN new_st;
END $$;


-- ── 4. _ludo_relocate_power_tile ──
CREATE OR REPLACE FUNCTION public._ludo_relocate_power_tile(st jsonb, _old_cell int)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  tiles jsonb;
  new_cell INT;
  i INT;
  used_cells INT[] := ARRAY[]::INT[];
  cell INT;
  v_slot INT;
  v_pawns jsonb;
  v_pawn jsonb;
  v_k INT;
  v_start INT;
  v_start_positions INT[] := ARRAY[0, 13, 26, 39];
  v_abs_cell INT;
BEGIN
  tiles := st->'power_tiles';
  IF tiles IS NULL OR jsonb_array_length(tiles) = 0 THEN RETURN st; END IF;

  FOR i IN 0..jsonb_array_length(tiles) - 1 LOOP
    IF (tiles->i->>'cell')::INT <> _old_cell THEN
      used_cells := used_cells || (tiles->i->>'cell')::INT;
    END IF;
  END LOOP;

  FOR v_slot IN 0..3 LOOP
    v_pawns := st->'pawns'->v_slot::text;
    IF v_pawns IS NULL THEN CONTINUE; END IF;
    v_start := v_start_positions[v_slot + 1];
    FOR i IN 0..3 LOOP
      v_pawn := v_pawns->i;
      IF v_pawn IS NOT NULL AND v_pawn->>'s' = 'track' THEN
        v_k := (v_pawn->>'k')::INT;
        IF v_k >= 1 AND v_k <= 51 THEN
          v_abs_cell := (v_start + v_k - 1) % 52;
          used_cells := used_cells || v_abs_cell;
        END IF;
      END IF;
    END LOOP;
  END LOOP;

  LOOP
    new_cell := floor(random() * 52)::INT;
    EXIT WHEN NOT public._ludo_is_safe(new_cell)
          AND new_cell NOT IN (0, 13, 26, 39)
          AND NOT (new_cell = ANY(used_cells));
  END LOOP;

  FOR i IN 0..jsonb_array_length(tiles) - 1 LOOP
    IF (tiles->i->>'cell')::INT = _old_cell THEN
      tiles := jsonb_set(tiles, ARRAY[i::text, 'cell'], to_jsonb(new_cell));
      EXIT;
    END IF;
  END LOOP;

  RETURN jsonb_set(st, '{power_tiles}', tiles);
END $$;
