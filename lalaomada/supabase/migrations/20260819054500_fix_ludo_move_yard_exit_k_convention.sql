-- ═══════════════════════════════════════════════════════════════════
-- CRITICAL FIX: ludo_move used the WRONG yard-exit convention.
--
-- Root cause: an earlier session today restored ludo_move from an OLD
-- migration file (20260813090000_restore_power_mode.sql) to fix the
-- finish_rank/victory-detection bug. That old file used the convention
-- k=0 for a pawn that just exited the yard, with abs_cell = start_idx + k
-- (no offset). But the REST of the currently deployed system (frontend
-- rendering, _ludo_movable_pawns, _ludo_count_on_cell, _ludo_is_blocked,
-- ludo_bot_move) all use the k=1 convention, with abs_cell = start_idx + k - 1.
-- This mismatch was an undocumented hotfix applied directly to the DB on
-- 2026-08-13 (see frontend commit 31a1c21) and was NEVER saved into a
-- migration file — so restoring the old file silently reintroduced the
-- k=0 bug, breaking pawn positions on yard exit and confusing turn
-- passing perception.
--
-- Fix: yard exit now sets k=1 (not 0), and every abs_cell computation
-- in ludo_move uses (start_idx + step - 1) % 52 (not + step), matching
-- the rest of the system. Also fixes the 'lucky_star' free_pawn reward
-- which set an escaping pawn directly to k=0 instead of k=1.
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ludo_move(_game_id uuid, _pawn_idx integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE st jsonb; g public.ludo_games%ROWTYPE; v_uid UUID := auth.uid();
  v_slot INT; v_dice INT; v_user UUID; v_isbot BOOLEAN; v_max INT;
  v_team INT;
  pawn jsonb; pawn_state TEXT; pawn_step INT; new_step INT; new_state TEXT;
  start_idx INT; abs_cell INT; captured BOOLEAN := FALSE; bonus BOOLEAN := FALSE;
  finished BOOLEAN := FALSE; all_done BOOLEAN; winner_uid UUID;
  rec RECORD; other_pawns jsonb; op jsonb; op_step INT; op_start INT;
  i INT; j INT; arr jsonb; same_slot_count INT;
  v_captured_list jsonb := '[]'::jsonb; v_now text; v_seq int;
  v_qc int; v_finishers int; v_remaining int; v_next_rank int;
  v_is_groupe BOOLEAN;
  v_mode TEXT; v_tile_type TEXT; v_tile jsonb;
  v_power_tiles jsonb; v_shields jsonb; v_shield_arr jsonb;
  v_boost_dice INT; v_boost_new_step INT; v_boost_new_state TEXT;
  v_lucky_reward INT; v_yard_idx INT;
  v_power_bonus BOOLEAN := FALSE; v_has_shield BOOLEAN;
  v_new_slot INT;
  v_dr_consumed BOOLEAN := FALSE;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := g.state; v_slot := (st->>'turn_slot')::INT; v_max := g.max_players;
  v_is_groupe := (g.match_type = 'groupe');
  v_mode := COALESCE(g.mode, 'classic');
  SELECT user_id, is_bot, team INTO v_user, v_isbot, v_team
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF NOT (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Lancez le dé d''abord'; END IF;
  v_dice := (st->>'dice')::INT;
  pawn := st->'pawns'->v_slot::text->_pawn_idx;
  IF pawn IS NULL THEN RAISE EXCEPTION 'Pion inconnu'; END IF;
  pawn_state := pawn->>'s'; pawn_step := (pawn->>'k')::INT;
  IF pawn_state = 'finished' THEN RAISE EXCEPTION 'Pion déjà arrivé'; END IF;
  IF pawn_state = 'yard' THEN
    IF v_dice <> 6 THEN RAISE EXCEPTION 'Sortie possible avec un 6'; END IF;
    new_state := 'track'; new_step := 1;
  ELSE
    new_step := pawn_step + v_dice;
    IF new_step > 56 THEN RAISE EXCEPTION 'Dépassement — chiffre exact requis pour entrer à l''arrivée'; END IF;
    IF new_step = 56 THEN new_state := 'finished'; finished := TRUE; ELSE new_state := 'track'; END IF;
  END IF;
  arr := st->'pawns'->v_slot::text;
  arr := jsonb_set(arr, ARRAY[_pawn_idx::text], jsonb_build_object('s', new_state, 'k', new_step));
  st := jsonb_set(st, ARRAY['pawns', v_slot::text], arr);

  -- Consume double_roll_pending BEFORE power tile activation
  IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
    v_dr_consumed := TRUE;
    st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
  END IF;

  -- Capture check (with shield protection in fast mode)
  IF new_state = 'track' AND new_step <= 50 THEN
    start_idx := public._ludo_start_for(_game_id, v_slot);
    abs_cell := (start_idx + new_step - 1) % 52;
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
            IF op_step <= 50 AND ((op_start + op_step - 1) % 52) = abs_cell THEN
              same_slot_count := same_slot_count + 1;
            END IF;
          END IF;
        END LOOP;
        IF same_slot_count = 1 THEN
          FOR j IN 0..3 LOOP
            op := other_pawns->j;
            IF op->>'s' = 'track' THEN
              op_step := (op->>'k')::INT;
              IF op_step <= 50 AND ((op_start + op_step - 1) % 52) = abs_cell THEN
                v_has_shield := FALSE;
                IF st ? 'shields' THEN
                  v_shields := st->'shields';
                  IF v_shields ? rec.slot::text THEN
                    v_shield_arr := v_shields->rec.slot::text;
                    FOR i IN 0..jsonb_array_length(v_shield_arr)-1 LOOP
                      IF (v_shield_arr->i)::int = j THEN v_has_shield := TRUE; EXIT; END IF;
                    END LOOP;
                  END IF;
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

  -- Power tile activation (Mode Moderne only)
  IF v_mode = 'fast' AND new_state = 'track' AND new_step <= 50 THEN
    start_idx := public._ludo_start_for(_game_id, v_slot);
    abs_cell := (start_idx + new_step - 1) % 52;
    v_power_tiles := COALESCE(st->'power_tiles', '[]'::jsonb);
    v_tile_type := NULL;
    FOR v_tile IN SELECT value FROM jsonb_array_elements(v_power_tiles) LOOP
      IF (v_tile->>'cell')::int = abs_cell THEN v_tile_type := v_tile->>'type'; EXIT; END IF;
    END LOOP;
    IF v_tile_type IS NOT NULL THEN
      v_power_tiles := (
        SELECT COALESCE(jsonb_agg(value), '[]'::jsonb)
        FROM jsonb_array_elements(v_power_tiles)
        WHERE (value->>'cell')::int <> abs_cell OR value->>'type' <> v_tile_type
      );
      v_now := to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"');
      CASE v_tile_type
        WHEN 'boost' THEN
          v_boost_dice := 1 + (floor(random()*6))::INT;
          v_boost_new_step := new_step + v_boost_dice;
          IF v_boost_new_step <= 56 THEN
            IF v_boost_new_step = 56 THEN v_boost_new_state := 'finished'; finished := TRUE;
            ELSE v_boost_new_state := 'track'; END IF;
            arr := st->'pawns'->v_slot::text;
            arr := jsonb_set(arr, ARRAY[_pawn_idx::text], jsonb_build_object('s', v_boost_new_state, 'k', v_boost_new_step));
            st := jsonb_set(st, ARRAY['pawns', v_slot::text], arr);
            IF v_boost_new_state = 'track' AND v_boost_new_step <= 50 THEN
              abs_cell := (start_idx + v_boost_new_step - 1) % 52;
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
                      IF op_step <= 50 AND ((op_start + op_step - 1) % 52) = abs_cell THEN
                        same_slot_count := same_slot_count + 1;
                      END IF;
                    END IF;
                  END LOOP;
                  IF same_slot_count = 1 THEN
                    FOR j IN 0..3 LOOP
                      op := other_pawns->j;
                      IF op->>'s' = 'track' THEN
                        op_step := (op->>'k')::INT;
                        IF op_step <= 50 AND ((op_start + op_step - 1) % 52) = abs_cell THEN
                          v_has_shield := FALSE;
                          IF st ? 'shields' THEN
                            v_shields := st->'shields';
                            IF v_shields ? rec.slot::text THEN
                              v_shield_arr := v_shields->rec.slot::text;
                              FOR i IN 0..jsonb_array_length(v_shield_arr)-1 LOOP
                                IF (v_shield_arr->i)::int = j THEN v_has_shield := TRUE; EXIT; END IF;
                              END LOOP;
                            END IF;
                          END IF;
                          IF NOT v_has_shield THEN
                            other_pawns := jsonb_set(other_pawns, ARRAY[j::text], jsonb_build_object('s','yard','k',-1));
                            captured := TRUE;
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
          st := jsonb_set(st, '{power_event}', jsonb_build_object('type','boost','slot',v_slot,'pawn',_pawn_idx,'dice',v_boost_dice,'at',v_now));
        WHEN 'shield' THEN
          v_shields := COALESCE(st->'shields', '{}'::jsonb);
          v_shield_arr := COALESCE(v_shields->v_slot::text, '[]'::jsonb) || to_jsonb(_pawn_idx);
          v_shields := jsonb_set(v_shields, ARRAY[v_slot::text], v_shield_arr, true);
          st := jsonb_set(st, '{shields}', v_shields, true);
          st := jsonb_set(st, '{power_event}', jsonb_build_object('type','shield','slot',v_slot,'pawn',_pawn_idx,'at',v_now));
        WHEN 'double_roll' THEN
          st := jsonb_set(st, '{double_roll_pending}', to_jsonb(v_slot));
          st := jsonb_set(st, '{power_event}', jsonb_build_object('type','double_roll','slot',v_slot,'at',v_now));
        WHEN 'lucky_star' THEN
          v_lucky_reward := 1 + (floor(random()*5))::INT;
          CASE v_lucky_reward
            WHEN 1 THEN
              v_boost_dice := 1 + (floor(random()*6))::INT;
              v_boost_new_step := new_step + v_boost_dice;
              IF v_boost_new_step <= 56 THEN
                IF v_boost_new_step = 56 THEN v_boost_new_state := 'finished'; finished := TRUE;
                ELSE v_boost_new_state := 'track'; END IF;
                arr := st->'pawns'->v_slot::text;
                arr := jsonb_set(arr, ARRAY[_pawn_idx::text], jsonb_build_object('s', v_boost_new_state, 'k', v_boost_new_step));
                st := jsonb_set(st, ARRAY['pawns', v_slot::text], arr);
              END IF;
              st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','reward','boost','dice',v_boost_dice,'slot',v_slot,'at',v_now));
            WHEN 2 THEN
              v_shields := COALESCE(st->'shields', '{}'::jsonb);
              v_shield_arr := COALESCE(v_shields->v_slot::text, '[]'::jsonb) || to_jsonb(_pawn_idx);
              v_shields := jsonb_set(v_shields, ARRAY[v_slot::text], v_shield_arr, true);
              st := jsonb_set(st, '{shields}', v_shields, true);
              st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','reward','shield','slot',v_slot,'at',v_now));
            WHEN 3 THEN
              st := jsonb_set(st, '{double_roll_pending}', to_jsonb(v_slot));
              st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','reward','double_roll','slot',v_slot,'at',v_now));
            WHEN 4 THEN
              v_power_bonus := TRUE;
              st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','reward','reroll','slot',v_slot,'at',v_now));
            WHEN 5 THEN
              arr := st->'pawns'->v_slot::text;
              v_yard_idx := -1;
              FOR i IN 0..3 LOOP
                IF (arr->i->>'s') = 'yard' AND i <> _pawn_idx THEN v_yard_idx := i; EXIT; END IF;
              END LOOP;
              IF v_yard_idx >= 0 THEN
                arr := jsonb_set(arr, ARRAY[v_yard_idx::text], jsonb_build_object('s','track','k',1));
                st := jsonb_set(st, ARRAY['pawns', v_slot::text], arr);
              END IF;
              st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','reward','free_pawn','slot',v_slot,'pawn',v_yard_idx,'at',v_now));
          END CASE;
      END CASE;
      v_power_tiles := public._ludo_relocate_tile(v_power_tiles, v_tile_type, _game_id, st, abs_cell);
      st := jsonb_set(st, '{power_tiles}', v_power_tiles, true);
    END IF;
  END IF;

  all_done := TRUE;
  FOR i IN 0..3 LOOP
    IF (st->'pawns'->v_slot::text->i->>'s') <> 'finished' THEN all_done := FALSE; END IF;
  END LOOP;
  UPDATE public.ludo_participants SET missed_turns=0 WHERE game_id=_game_id AND slot=v_slot;
  UPDATE public.ludo_games SET state=st WHERE id=_game_id;
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
    v_qc := 1;
    IF g.tournament_match_id IS NOT NULL THEN
      SELECT COALESCE(qualifiers_count,1) INTO v_qc FROM public.tournament_matches WHERE id = g.tournament_match_id;
    END IF;
    SELECT count(*) INTO v_finishers FROM public.ludo_participants
      WHERE game_id=_game_id AND finish_rank IS NOT NULL;
    SELECT count(*) INTO v_remaining FROM public.ludo_participants
      WHERE game_id=_game_id AND finish_rank IS NULL AND forfeited=FALSE;
    IF v_finishers >= v_qc OR v_remaining <= 1 THEN
      SELECT user_id INTO winner_uid FROM public.ludo_participants
        WHERE game_id=_game_id AND finish_rank=1;
      PERFORM public.finish_game(_game_id, winner_uid);
      SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
      RETURN st;
    ELSE
      RETURN public._ludo_advance_turn(
        _game_id, public._ludo_next_slot(_game_id, v_slot, v_max), 'home:continue'
      );
    END IF;
  END IF;

  bonus := (v_dice = 6) OR captured OR finished;
  IF v_dr_consumed THEN bonus := TRUE; END IF;
  IF v_power_bonus THEN bonus := TRUE; END IF;
  IF NOT bonus THEN
    UPDATE public.ludo_participants SET consecutive_sixes=0 WHERE game_id=_game_id AND slot=v_slot;
  END IF;
  RETURN public._ludo_advance_turn(
    _game_id,
    CASE WHEN bonus THEN v_slot ELSE public._ludo_next_slot(_game_id, v_slot, v_max) END,
    CASE WHEN bonus THEN (CASE WHEN captured THEN 'capture' WHEN finished THEN 'home' ELSE 'six' END || ':rejoue') ELSE 'move' END
  );
END $function$

