-- ═══════════════════════════════════════════════════════════════════════
-- LUDO POWER MODE v3 — Auto-activation, no dialogs, no cooldown
--
-- Changes:
-- 1. Tiles relocate IMMEDIATELY after activation (no cd/cooldown system)
-- 2. Boost: auto-activated (roll 1d6, move), NO turn bonus
-- 3. Shield: auto-activated, NO turn bonus
-- 4. Lucky Star: auto-pick random reward (no choice dialog), bonus only for double_roll/reroll
-- 5. double_roll: gives extra roll (bonus = true)
-- 6. reroll: gives extra roll (bonus = true)
-- 7. free_pawn: auto-spawn from yard, NO turn bonus
-- 8. Only double_roll, reroll, 6, and capture give bonus rolls
-- ═══════════════════════════════════════════════════════════════════════

-- 1. _ludo_decrement_cooldowns -> no-op (no cooldowns anymore)
CREATE OR REPLACE FUNCTION public._ludo_decrement_cooldowns(st jsonb)
RETURNS jsonb
LANGUAGE sql IMMUTABLE
AS $$
  SELECT st;
$$;

-- 2. _ludo_relocate_tile -- simplified: move tile to new random valid cell
--    Avoids cells occupied by other tiles AND pawns
CREATE OR REPLACE FUNCTION public._ludo_relocate_tile(_power_tiles jsonb, _type text, _game_id uuid DEFAULT NULL, _state jsonb DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
  v_valid int[] := public._ludo_power_valid_cells();
  v_occupied int[] := ARRAY[]::int[];
  v_tile jsonb;
  v_available int[];
  v_new_cell int;
  v_result jsonb := '[]'::jsonb;
  v_found boolean := false;
  v_pawns jsonb;
  v_start int;
  v_step int;
  v_slot int;
  v_count int;
  v_pawn jsonb;
BEGIN
  FOR v_tile IN SELECT value FROM jsonb_array_elements(_power_tiles) LOOP
    IF v_tile->>'type' <> _type THEN
      v_occupied := v_occupied || (v_tile->>'cell')::int;
    END IF;
  END LOOP;

  IF _game_id IS NOT NULL AND _state IS NOT NULL THEN
    FOR v_slot IN 0..3 LOOP
      v_pawns := _state->'pawns'->v_slot::text;
      IF v_pawns IS NULL THEN CONTINUE; END IF;
      v_start := public._ludo_start_for(_game_id, v_slot);
      FOR v_count IN 0..3 LOOP
        v_pawn := v_pawns->v_count;
        IF v_pawn IS NOT NULL AND v_pawn->>'s' = 'track' THEN
          v_step := (v_pawn->>'k')::int;
          IF v_step <= 50 THEN
            v_occupied := v_occupied || ((v_start + v_step) % 52);
          END IF;
        END IF;
      END LOOP;
    END LOOP;
  END IF;

  v_available := ARRAY(
    SELECT c FROM unnest(v_valid) c WHERE NOT (c = ANY(v_occupied))
  );

  IF array_length(v_available, 1) IS NULL OR array_length(v_available, 1) = 0 THEN
    FOR v_tile IN SELECT value FROM jsonb_array_elements(_power_tiles) LOOP
      IF v_tile->>'type' <> _type THEN v_result := v_result || v_tile; END IF;
    END LOOP;
    RETURN v_result;
  END IF;

  v_new_cell := v_available[1 + floor(random() * array_length(v_available, 1))::int];

  FOR v_tile IN SELECT value FROM jsonb_array_elements(_power_tiles) LOOP
    IF v_tile->>'type' = _type THEN
      v_result := v_result || jsonb_build_object('type', _type, 'cell', v_new_cell);
      v_found := true;
    ELSE
      v_result := v_result || v_tile;
    END IF;
  END LOOP;

  IF NOT v_found THEN
    v_result := v_result || jsonb_build_object('type', _type, 'cell', v_new_cell);
  END IF;

  RETURN v_result;
END $$;

-- 3. Replace ludo_move with auto-activation version
CREATE OR REPLACE FUNCTION public.ludo_move(_game_id uuid, _pawn_idx integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE st jsonb; g public.ludo_games%ROWTYPE; v_uid UUID := auth.uid();
  v_slot INT; v_dice INT; v_user UUID; v_isbot BOOLEAN; v_max INT;
  v_team INT;
  pawn jsonb; pawn_state TEXT; pawn_step INT; new_step INT; new_state TEXT;
  start_idx INT; abs_cell INT; captured BOOLEAN := FALSE; bonus BOOLEAN := FALSE;
  finished BOOLEAN := FALSE; all_done BOOLEAN; winner_uid UUID;
  rec RECORD; other_pawns jsonb; op jsonb; op_step INT; op_start INT;
  i INT; j INT; arr jsonb; same_slot_count INT;
  v_is_groupe BOOLEAN;
  v_mode TEXT; v_tile_type TEXT; v_tile jsonb;
  v_power_tiles jsonb; v_shields jsonb;
  v_has_shield BOOLEAN;
  v_power_bonus BOOLEAN := FALSE; v_now text;
  v_new_slot INT;
  v_dr_consumed BOOLEAN := FALSE;
  v_captured_list jsonb := '[]'::jsonb;
  v_seq int;
  v_qc int; v_finishers int; v_remaining int; v_next_rank int;
  v_boost_dice INT; v_boost_new_step INT; v_boost_new_state TEXT;
  v_lucky_options text[] := ARRAY['boost','shield','double_roll','free_pawn','reroll'];
  v_lucky_pick TEXT;
  v_yard_idx INT;
  v_loop_count INT := 0;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := g.state; v_slot := (st->>'turn_slot')::INT; v_max := g.max_players;
  v_is_groupe := (g.match_type = 'groupe');
  v_mode := COALESCE(g.mode, 'classic');
  SELECT user_id, is_bot, team INTO v_user, v_isbot, v_team
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF NOT (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Lancez le d''abord'; END IF;
  v_dice := (st->>'dice')::INT;
  pawn := st->'pawns'->v_slot::text->_pawn_idx;
  IF pawn IS NULL THEN RAISE EXCEPTION 'Pion inconnu'; END IF;
  pawn_state := pawn->>'s'; pawn_step := (pawn->>'k')::INT;
  IF pawn_state = 'finished' THEN RAISE EXCEPTION 'Pion deja arrive'; END IF;
  IF pawn_state = 'yard' THEN
    IF v_dice <> 6 THEN RAISE EXCEPTION 'Sortie possible avec un 6'; END IF;
    new_state := 'track'; new_step := 0;
  ELSE
    new_step := pawn_step + v_dice;
    IF new_step > 56 THEN RAISE EXCEPTION 'Depassement'; END IF;
    IF new_step = 56 THEN new_state := 'finished'; finished := TRUE;
    Else new_state := 'track'; END IF;
  END IF;
  arr := st->'pawns'->v_slot::text;
  arr := jsonb_set(arr, ARRAY[_pawn_idx::text], jsonb_build_object('s', new_state, 'k', new_step));
  st := jsonb_set(st, ARRAY['pawns', v_slot::text], arr);

  IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
    v_dr_consumed := TRUE;
    st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
  END IF;

  -- Capture check (with shield protection)
  IF new_state = 'track' AND new_step <= 50 THEN
    start_idx := public._ludo_start_for(_game_id, v_slot);
    abs_cell := (start_idx + new_step) % 52;
    IF NOT public._ludo_is_safe(abs_cell) THEN
      FOR rec IN SELECT slot, team FROM public.ludo_participants
                  WHERE game_id=_game_id AND slot <> v_slot AND forfeited=FALSE LOOP
        IF v_is_groupe AND rec.team IS NOT NULL AND rec.team = v_team THEN CONTINUE; END IF;
        op_start := public._ludo_start_for(_game_id, rec.slot);
        other_pawns := st->'pawns'->rec.slot::text;
        same_slot_count := 0;
        FOR j IN 0..3 LOOP
          op := other_pawns->j;
          IF op->>'s' = 'track' THEN
            op_step := (op->>'k')::INT;
            IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
              same_slot_count := same_slot_count + 1;
            END IF;
          END IF;
        END LOOP;
        IF same_slot_count = 1 THEN
          FOR j IN 0..3 LOOP
            op := other_pawns->j;
            IF op->>'s' = 'track' THEN
              op_step := (op->>'k')::INT;
              IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
                v_has_shield := FALSE;
                IF st ? 'shields' AND (st->'shields') ? rec.slot::text THEN
                  v_has_shield := (st->'shields'->rec.slot::text)::boolean;
                END IF;
                IF NOT v_has_shield THEN
                  other_pawns := jsonb_set(other_pawns, ARRAY[j::text], jsonb_build_object('s','yard','k',-1));
                  captured := TRUE;
                  v_captured_list := v_captured_list || jsonb_build_object('slot', rec.slot, 'pawn', j);
                END IF;
              END IF;
            END IF;
          END LOOP;
          st := jsonb_set(st, ARRAY['pawns', rec.slot::text], other_pawns);
        END IF;
      END LOOP;
    END IF;
  END IF;

  -- Power tile activation (Mode Moderne only) -- AUTO, no dialogs
  <<power_loop>>
  LOOP
    v_loop_count := v_loop_count + 1;
    IF v_loop_count > 3 THEN EXIT; END IF;

    IF v_mode = 'fast' AND new_state = 'track' AND new_step <= 50 THEN
      start_idx := public._ludo_start_for(_game_id, v_slot);
      abs_cell := (start_idx + new_step) % 52;
      v_power_tiles := COALESCE(st->'power_tiles', '[]'::jsonb);
      v_tile_type := NULL;
      FOR v_tile IN SELECT value FROM jsonb_array_elements(v_power_tiles) LOOP
        IF (v_tile->>'cell')::int = abs_cell THEN
          v_tile_type := v_tile->>'type'; EXIT;
        END IF;
      END LOOP;

      EXIT power_loop WHEN v_tile_type IS NULL;

      v_now := to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"');

      -- Relocate tile IMMEDIATELY
      v_power_tiles := public._ludo_relocate_tile(v_power_tiles, v_tile_type, _game_id, st);
      st := jsonb_set(st, '{power_tiles}', v_power_tiles, true);

      CASE v_tile_type
        WHEN 'shield' THEN
          v_shields := COALESCE(st->'shields', '{}'::jsonb);
          v_shields := jsonb_set(v_shields, ARRAY[v_slot::text], 'true'::jsonb, true);
          st := jsonb_set(st, '{shields}', v_shields, true);
          st := jsonb_set(st, '{power_event}', jsonb_build_object('type','shield','slot',v_slot,'at',v_now));
          -- NO bonus

        WHEN 'double_roll' THEN
          st := jsonb_set(st, '{double_roll_pending}', to_jsonb(v_slot));
          st := jsonb_set(st, '{power_event}', jsonb_build_object('type','double_roll','slot',v_slot,'at',v_now));
          v_power_bonus := TRUE;
          EXIT power_loop;

        WHEN 'boost' THEN
          v_boost_dice := 1 + (floor(random()*6))::INT;
          v_boost_new_step := new_step + v_boost_dice;
          IF v_boost_new_step <= 56 THEN
            IF v_boost_new_step = 56 THEN
              v_boost_new_state := 'finished';
              finished := TRUE;
              new_state := 'finished';
              new_step := 56;
            ELSE
              v_boost_new_state := 'track';
              new_step := v_boost_new_step;
            END IF;
            arr := st->'pawns'->v_slot::text;
            arr := jsonb_set(arr, ARRAY[_pawn_idx::text], jsonb_build_object('s', v_boost_new_state, 'k', v_boost_new_step));
            st := jsonb_set(st, ARRAY['pawns', v_slot::text], arr);

            IF v_boost_new_state = 'track' AND v_boost_new_step <= 50 THEN
              start_idx := public._ludo_start_for(_game_id, v_slot);
              abs_cell := (start_idx + v_boost_new_step) % 52;
              IF NOT public._ludo_is_safe(abs_cell) THEN
                FOR rec IN SELECT slot, team FROM public.ludo_participants
                            WHERE game_id=_game_id AND slot <> v_slot AND forfeited=FALSE LOOP
                  IF v_is_groupe AND rec.team IS NOT NULL AND rec.team = v_team THEN CONTINUE; END IF;
                  op_start := public._ludo_start_for(_game_id, rec.slot);
                  other_pawns := st->'pawns'->rec.slot::text;
                  same_slot_count := 0;
                  FOR j IN 0..3 LOOP
                    op := other_pawns->j;
                    IF op->>'s' = 'track' THEN
                      op_step := (op->>'k')::INT;
                      IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
                        same_slot_count := same_slot_count + 1;
                      END IF;
                    END IF;
                  END LOOP;
                  IF same_slot_count = 1 THEN
                    FOR j IN 0..3 LOOP
                      op := other_pawns->j;
                      IF op->>'s' = 'track' THEN
                        op_step := (op->>'k')::INT;
                        IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
                          v_has_shield := FALSE;
                          IF st ? 'shields' AND (st->'shields') ? rec.slot::text THEN
                            v_has_shield := (st->'shields'->rec.slot::text)::boolean;
                          END IF;
                          IF NOT v_has_shield THEN
                            other_pawns := jsonb_set(other_pawns, ARRAY[j::text], jsonb_build_object('s','yard','k',-1));
                            captured := TRUE;
                            v_captured_list := v_captured_list || jsonb_build_object('slot', rec.slot, 'pawn', j);
                          END IF;
                        END IF;
                      END IF;
                    END LOOP;
                    st := jsonb_set(st, ARRAY['pawns', rec.slot::text], other_pawns);
                  END IF;
                END LOOP;
              END IF;
            END IF;
          END IF;
          st := jsonb_set(st, '{power_event}', jsonb_build_object('type','boost','slot',v_slot,'dice',v_boost_dice,'at',v_now));
          -- NO bonus; loop continues to check if boost landed on another tile
          IF v_boost_new_state = 'finished' THEN EXIT power_loop; END IF;

        WHEN 'lucky_star' THEN
          v_lucky_pick := v_lucky_options[1 + floor(random()*5)::int];
          v_now := to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"');

          CASE v_lucky_pick
            WHEN 'boost' THEN
              v_boost_dice := 1 + (floor(random()*6))::INT;
              v_boost_new_step := new_step + v_boost_dice;
              IF v_boost_new_step <= 56 THEN
                IF v_boost_new_step = 56 THEN
                  v_boost_new_state := 'finished'; finished := TRUE; new_state := 'finished'; new_step := 56;
                ELSE v_boost_new_state := 'track'; new_step := v_boost_new_step;
                END IF;
                arr := st->'pawns'->v_slot::text;
                arr := jsonb_set(arr, ARRAY[_pawn_idx::text], jsonb_build_object('s', v_boost_new_state, 'k', v_boost_new_step));
                st := jsonb_set(st, ARRAY['pawns', v_slot::text], arr);
                IF v_boost_new_state = 'track' AND v_boost_new_step <= 50 THEN
                  start_idx := public._ludo_start_for(_game_id, v_slot);
                  abs_cell := (start_idx + v_boost_new_step) % 52;
                  IF NOT public._ludo_is_safe(abs_cell) THEN
                    FOR rec IN SELECT slot, team FROM public.ludo_participants
                                WHERE game_id=_game_id AND slot <> v_slot AND forfeited=FALSE LOOP
                      IF v_is_groupe AND rec.team IS NOT NULL AND rec.team = v_team THEN CONTINUE; END IF;
                      op_start := public._ludo_start_for(_game_id, rec.slot);
                      other_pawns := st->'pawns'->rec.slot::text;
                      same_slot_count := 0;
                      FOR j IN 0..3 LOOP
                        op := other_pawns->j;
                        IF op->>'s' = 'track' THEN
                          op_step := (op->>'k')::INT;
                          IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
                            same_slot_count := same_slot_count + 1;
                          END IF;
                        END IF;
                      END LOOP;
                      IF same_slot_count = 1 THEN
                        FOR j IN 0..3 LOOP
                          op := other_pawns->j;
                          IF op->>'s' = 'track' THEN
                            op_step := (op->>'k')::INT;
                            IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
                              v_has_shield := FALSE;
                              IF st ? 'shields' AND (st->'shields') ? rec.slot::text THEN
                                v_has_shield := (st->'shields'->rec.slot::text)::boolean;
                              END IF;
                              IF NOT v_has_shield THEN
                                other_pawns := jsonb_set(other_pawns, ARRAY[j::text], jsonb_build_object('s','yard','k',-1));
                                captured := TRUE;
                                v_captured_list := v_captured_list || jsonb_build_object('slot', rec.slot, 'pawn', j);
                              END IF;
                            END IF;
                          END IF;
                        END LOOP;
                        st := jsonb_set(st, ARRAY['pawns', rec.slot::text], other_pawns);
                      END IF;
                    END LOOP;
                  END IF;
                END IF;
              END IF;
              st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','slot',v_slot,'reward','boost','dice',v_boost_dice,'at',v_now));

            WHEN 'shield' THEN
              v_shields := COALESCE(st->'shields', '{}'::jsonb);
              v_shields := jsonb_set(v_shields, ARRAY[v_slot::text], 'true'::jsonb, true);
              st := jsonb_set(st, '{shields}', v_shields, true);
              st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','slot',v_slot,'reward','shield','at',v_now));

            WHEN 'double_roll' THEN
              st := jsonb_set(st, '{double_roll_pending}', to_jsonb(v_slot));
              st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','slot',v_slot,'reward','double_roll','at',v_now));
              v_power_bonus := TRUE;

            WHEN 'free_pawn' THEN
              arr := st->'pawns'->v_slot::text;
              v_yard_idx := -1;
              FOR i IN 0..3 LOOP
                IF (arr->i->>'s') = 'yard' THEN v_yard_idx := i; EXIT; END IF;
              END LOOP;
              IF v_yard_idx >= 0 THEN
                arr := jsonb_set(arr, ARRAY[v_yard_idx::text], jsonb_build_object('s','track','k',0));
                st := jsonb_set(st, ARRAY['pawns', v_slot::text], arr);
              END IF;
              st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','slot',v_slot,'reward','free_pawn','at',v_now));

            WHEN 'reroll' THEN
              st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','slot',v_slot,'reward','reroll','at',v_now));
              v_power_bonus := TRUE;
          END CASE;
          EXIT power_loop;
      END CASE;
    ELSE
      EXIT power_loop;
    END IF;
  END LOOP power_loop;

  -- Post-move logic
  all_done := TRUE;
  FOR i IN 0..3 LOOP
    IF (st->'pawns'->v_slot::text->i->>'s') <> 'finished' THEN all_done := FALSE; END IF;
  END LOOP;

  UPDATE public.ludo_participants SET missed_turns=0 WHERE game_id=_game_id AND slot=v_slot;

  v_now := to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"');
  v_seq := COALESCE((st->>'turn_seq')::int, 0);
  PERFORM public._ludo_push_move(_game_id, jsonb_build_object(
    'seq', v_seq, 'slot', v_slot, 'pawn', _pawn_idx, 'dice', v_dice,
    'captured', v_captured_list, 'finished', finished, 'at', v_now
  ));

  IF all_done THEN
    SELECT COALESCE(MAX(finish_rank),0)+1 INTO v_next_rank
      FROM public.ludo_participants WHERE game_id=_game_id;
    UPDATE public.ludo_participants SET finish_rank = v_next_rank
      WHERE game_id=_game_id AND slot=v_slot;
    UPDATE public.ludo_games SET state=st WHERE id=_game_id;

    v_qc := 1;
    IF g.tournament_match_id IS NOT NULL THEN
      SELECT COALESCE(qualifiers_count,1) INTO v_qc
        FROM public.tournament_matches WHERE id = g.tournament_match_id;
    END IF;

    SELECT count(*) INTO v_finishers FROM public.ludo_participants
      WHERE game_id=_game_id AND finish_rank IS NOT NULL;
    SELECT count(*) INTO v_remaining FROM public.ludo_participants
      WHERE game_id=_game_id AND finish_rank IS NULL AND forfeited=FALSE;

    IF v_finishers >= v_qc OR v_remaining <= 1 THEN
      SELECT user_id INTO winner_uid FROM public.ludo_participants
        WHERE game_id=_game_id AND finish_rank=1;
      IF v_is_groupe AND v_team IS NOT NULL THEN
        PERFORM public._ludo_finish_team(_game_id, winner_uid, v_team);
      ELSE
        PERFORM public.finish_game(_game_id, winner_uid);
      END IF;
      SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
      RETURN st;
    ELSE
      v_new_slot := public._ludo_next_slot(_game_id, v_slot, v_max);
      st := public._ludo_clear_shield(st, v_new_slot);
      st := public._ludo_decrement_cooldowns(st);
      st := jsonb_set(st,'{turn_slot}', to_jsonb(v_new_slot));
      st := jsonb_set(st,'{last_event}', to_jsonb('home:continue'));
      st := jsonb_set(st,'{must_move}','false'::jsonb);
      st := jsonb_set(st,'{dice}','null'::jsonb);
      st := st - 'no_move_display';
      st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
      UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
      PERFORM public._ludo_check_game_over(_game_id);
      RETURN st;
    END IF;
  END IF;

  -- Bonus: only 6, capture, finished, double_roll consumed, or power_bonus (double_roll/reroll)
  bonus := (v_dice = 6) OR captured OR finished;
  IF v_dr_consumed THEN bonus := TRUE; END IF;
  IF v_power_bonus THEN bonus := TRUE; END IF;

  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := jsonb_set(st,'{dice}','null'::jsonb);
  st := st - 'no_move_display';
  IF bonus THEN
    st := jsonb_set(st,'{last_event}', to_jsonb(
      (CASE WHEN captured THEN 'capture' WHEN finished THEN 'home' ELSE 'six' END || ':rejoue')::text));
  ELSE
    v_new_slot := public._ludo_next_slot(_game_id, v_slot, v_max);
    st := public._ludo_clear_shield(st, v_new_slot);
    st := public._ludo_decrement_cooldowns(st);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(v_new_slot));
    st := jsonb_set(st,'{last_event}', to_jsonb('move'::text));
    UPDATE public.ludo_participants SET consecutive_sixes=0 WHERE game_id=_game_id AND slot=v_slot;
  END IF;
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  PERFORM public._ludo_check_game_over(_game_id);
  RETURN st;
END $function$;

-- 4. ludo_choose_power -> stub (no more power_pending)
CREATE OR REPLACE FUNCTION public.ludo_choose_power(_game_id uuid, _choice text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE st jsonb;
BEGIN
  SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
  RETURN st;
END $function$;

-- 5. ludo_bot_play -> remove power_pending check
CREATE OR REPLACE FUNCTION public.ludo_bot_play(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  g public.ludo_games%ROWTYPE; st jsonb;
  v_slot INT; v_is_groupe BOOLEAN;
  v_isbot BOOLEAN; v_intel TEXT; v_bias TEXT; v_consec INT; v_team INT;
  v_dice INT; v_pawns jsonb; v_idx INT; v_choice INT;
  v_best INT; v_best_score INT; v_score INT;
  v_start INT; v_step INT; v_abs INT; v_safe BOOLEAN;
  op jsonb; op_step INT; op_start INT; op_abs INT;
  rec RECORD; j INT;
  v_can_finish BOOLEAN;
  v_yard_count INT; v_track_count INT; v_finished_count INT;
  v_must_move BOOLEAN;
  v_consec_sixes INT;
  v_smart BOOLEAN;
  v_has_double_roll BOOLEAN;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;
  v_is_groupe := (g.match_type = 'groupe');

  SELECT is_bot, bot_intelligence, bot_win_bias, consecutive_sixes, team
    INTO v_isbot, v_intel, v_bias, v_consec_sixes, v_team
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot THEN RETURN st; END IF;

  v_must_move := (st->>'must_move')::BOOLEAN;
  v_has_double_roll := st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot;

  IF NOT v_must_move THEN
    PERFORM public.ludo_roll(_game_id);
    SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
    v_dice := (st->>'dice')::INT;
    v_must_move := (st->>'must_move')::BOOLEAN;
    IF NOT v_must_move THEN RETURN st; END IF;
  ELSE
    v_dice := (st->>'dice')::INT;
  END IF;

  v_smart := (v_intel IN ('medium','hard') AND random() < 0.75);

  v_pawns := st->'pawns'->v_slot::text;
  v_best := -1; v_best_score := -100;
  v_yard_count := 0; v_track_count := 0; v_finished_count := 0;

  FOR v_idx IN 0..3 LOOP
    op := v_pawns->v_idx;
    IF op->>'s' = 'yard' THEN v_yard_count := v_yard_count + 1;
    ELSIF op->>'s' = 'finished' THEN v_finished_count := v_finished_count + 1;
    ELSE v_track_count := v_track_count + 1; END IF;
  END LOOP;

  FOR v_idx IN 0..3 LOOP
    op := v_pawns->v_idx;
    IF op->>'s' = 'finished' THEN CONTINUE; END IF;
    IF op->>'s' = 'yard' AND v_dice <> 6 THEN CONTINUE; END IF;

    v_step := (op->>'k')::INT;
    v_score := 0;
    v_can_finish := (op->>'s' = 'track' AND v_step + v_dice = 56);
    IF v_can_finish THEN v_score := v_score + 100; END IF;
    IF op->>'s' = 'yard' AND v_dice = 6 THEN v_score := v_score + 30; END IF;

    IF v_smart AND op->>'s' = 'track' AND v_step + v_dice <= 50 THEN
      v_start := public._ludo_start_for(_game_id, v_slot);
      v_abs := (v_start + v_step + v_dice) % 52;
      v_safe := public._ludo_is_safe(v_abs);
      IF NOT v_safe THEN
        FOR rec IN SELECT slot, team FROM public.ludo_participants
                    WHERE game_id=_game_id AND slot <> v_slot AND forfeited=FALSE LOOP
          IF v_is_groupe AND rec.team IS NOT NULL AND rec.team = v_team THEN CONTINUE; END IF;
          op_start := public._ludo_start_for(_game_id, rec.slot);
          FOR j IN 0..3 LOOP
            op_step := (st->'pawns'->rec.slot::text->j->>'k')::INT;
            IF st->'pawns'->rec.slot::text->j->>'s' = 'track' AND op_step <= 50
               AND ((op_start + op_step) % 52) = v_abs THEN
              v_score := v_score + 50;
            END IF;
          END LOOP;
        END LOOP;
      END IF;
    END IF;

    IF v_score > v_best_score THEN v_best_score := v_score; v_best := v_idx; END IF;
  END LOOP;

  IF v_best < 0 THEN
    PERFORM public.ludo_pass(_game_id);
    SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
    RETURN st;
  END IF;

  IF v_intel = 'easy' AND random() < 0.3 THEN
    v_best := floor(random()*4)::int;
    op := v_pawns->v_best;
    IF op->>'s' = 'finished' OR (op->>'s' = 'yard' AND v_dice <> 6) THEN
      v_best := -1;
      FOR v_idx IN 0..3 LOOP
        op := v_pawns->v_idx;
        IF op->>'s' <> 'finished' AND (op->>'s' <> 'yard' OR v_dice = 6) THEN
          v_best := v_idx; EXIT;
        END IF;
      END LOOP;
    END IF;
  END IF;

  IF v_best >= 0 THEN
    PERFORM public.ludo_move(_game_id, v_best);
  ELSE
    PERFORM public.ludo_pass(_game_id);
  END IF;

  SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
  RETURN st;
END $function$;

-- 6. Clean up: remove power_pending from any existing games
UPDATE public.ludo_games
SET state = state - 'power_pending'
WHERE state ? 'power_pending';
