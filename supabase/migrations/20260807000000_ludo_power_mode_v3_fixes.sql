-- ═══════════════════════════════════════════════════════════════════════
-- LUDO MODE MODERNE — BUG FIXES V3
--
-- Bugs corrigés :
--   1. CRITIQUE : ludo_choose_power — validation lucky_star always fails
--      `value->>'' = _choice` returns NULL for JSON string scalars
--      Fix: use `value#>>'{}' = _choice` instead
--   2. CRITIQUE : ludo_roll no-move consumes double_roll_pending instead of
--      giving the player their second roll
--      Fix: if double_roll_pending is set, don't advance turn — let player roll again
--   3. MOYEN : ludo_roll no-move path doesn't clear shields or decrement cooldowns
--      Fix: add _ludo_clear_shield + _ludo_decrement_cooldowns
--   4. MOYEN : ludo_roll triple-sixes path doesn't clear shields or decrement cooldowns
--      Fix: same as above
--   5. MOYEN : _ludo_advance_turn doesn't decrement cooldowns (V1 function)
--      Fix: add _ludo_decrement_cooldowns call
--   6. MINEUR : ludo_choose_power — when boost is activated, captures from the
--      original ludo_move are not tracked, so bonus turn logic may miss capture bonus
--      Fix: check if any opponent pawn was sent to yard during this turn
-- ═══════════════════════════════════════════════════════════════════════

-- ═══ 1. FIX _ludo_advance_turn — add cooldown decrement ══════════════
CREATE OR REPLACE FUNCTION public._ludo_advance_turn(_game_id uuid, _new_slot integer, _last_event text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_isbot boolean;
  v_spin_ms int; v_seq int; v_now text; v_shields jsonb;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id;
  st := g.state;
  v_now := to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"');
  SELECT is_bot INTO v_isbot FROM public.ludo_participants WHERE game_id=_game_id AND slot=_new_slot;
  v_spin_ms := CASE WHEN COALESCE(v_isbot, FALSE) THEN 2500 ELSE 0 END;
  v_seq := COALESCE((st->>'turn_seq')::int, 0) + 1;
  st := jsonb_set(st, '{turn_slot}', to_jsonb(_new_slot));
  st := jsonb_set(st, '{turn_started_at}', to_jsonb(v_now));
  st := jsonb_set(st, '{turn_seq}', to_jsonb(v_seq));
  st := jsonb_set(st, '{phase}', to_jsonb('spinning'::text));
  st := jsonb_set(st, '{phase_started_at}', to_jsonb(v_now));
  st := jsonb_set(st, '{spin_ms}', to_jsonb(v_spin_ms));
  st := jsonb_set(st, '{dice}', 'null'::jsonb);
  st := jsonb_set(st, '{must_move}', 'false'::jsonb);
  st := jsonb_set(st, '{last_event}', to_jsonb(_last_event));
  -- Mode Moderne: clear shields for new player (expires at owner next turn)
  IF st ? 'shields' THEN
    v_shields := st->'shields';
    IF v_shields ? _new_slot::text THEN
      v_shields := v_shields - _new_slot::text;
      st := jsonb_set(st, '{shields}', v_shields, true);
    END IF;
  END IF;
  -- FIX 5: Decrement power tile cooldowns on every turn advance
  st := public._ludo_decrement_cooldowns(st);
  st := st - 'power_event';
  UPDATE public.ludo_games SET state=st, current_turn=_new_slot WHERE id=_game_id;
  RETURN st;
END $$;


-- ═══ 2. FIX ludo_roll — handle double_roll_pending + shields + cooldowns ═
CREATE OR REPLACE FUNCTION public.ludo_roll(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $$
DECLARE st jsonb; g public.ludo_games%ROWTYPE; v_uid UUID := auth.uid();
  v_slot INT; v_user UUID; v_isbot BOOLEAN; v_bias INT; v_dice INT;
  arr jsonb; pawn jsonb; i INT; pstate TEXT; pstep INT; has_move BOOLEAN := FALSE;
  v_consec INT; v_override int; v_display jsonb;
  v_new_slot INT; v_has_double_roll BOOLEAN := FALSE;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot, bot_win_bias, consecutive_sixes INTO v_user, v_isbot, v_bias, v_consec
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Déjà lancé, déplacez un pion'; END IF;
  v_override := NULLIF(g.dice_override->>v_slot::text,'')::int;
  IF v_override IS NOT NULL AND v_override BETWEEN 1 AND 6 THEN
    v_dice := v_override;
    UPDATE public.ludo_games SET dice_override = dice_override - v_slot::text WHERE id=_game_id;
  ELSE
    v_dice := 1 + (floor(random()*6))::INT;
    IF v_isbot AND COALESCE(v_bias,0) > 0 AND (random()*100) < v_bias THEN v_dice := 6; END IF;
  END IF;

  -- Check if player has double_roll pending
  IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
    v_has_double_roll := TRUE;
  END IF;

  IF v_dice = 6 THEN v_consec := COALESCE(v_consec,0) + 1; ELSE v_consec := 0; END IF;
  UPDATE public.ludo_participants SET consecutive_sixes=v_consec WHERE game_id=_game_id AND slot=v_slot;

  -- Triple sixes: cancel turn (but double_roll still consumed)
  IF v_consec >= 3 THEN
    UPDATE public.ludo_participants SET consecutive_sixes=0 WHERE game_id=_game_id AND slot=v_slot;
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
    -- FIX 4: clear shield + decrement cooldowns for new player
    st := public._ludo_clear_shield(st, v_new_slot);
    st := public._ludo_decrement_cooldowns(st);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(v_new_slot));
    st := jsonb_set(st,'{dice}','null'::jsonb);
    IF v_has_double_roll THEN
      st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
    END IF;
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('triple_six:cancel'::text));
    st := st - 'no_move_display';
    st := st - 'power_event';
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
    PERFORM public._ludo_check_game_over(_game_id);
    RETURN st;
  END IF;

  st := jsonb_set(st,'{dice}', to_jsonb(v_dice));
  st := jsonb_set(st,'{must_move}','true'::jsonb);
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('roll:'||v_dice));
  st := st - 'no_move_display';

  -- Check if player can move
  arr := st->'pawns'->v_slot::text;
  FOR i IN 0..3 LOOP
    pawn := arr->i; pstate := pawn->>'s'; pstep := (pawn->>'k')::INT;
    IF pstate='finished' THEN CONTINUE; END IF;
    IF pstate='yard' THEN IF v_dice=6 THEN has_move:=TRUE; EXIT; END IF;
    ELSE IF pstep + v_dice <= 56 THEN has_move:=TRUE; EXIT; END IF; END IF;
  END LOOP;

  IF NOT has_move THEN
    -- FIX 2: If player has double_roll_pending, give them the second roll
    -- instead of consuming it and advancing the turn
    IF v_has_double_roll THEN
      st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
      st := jsonb_set(st,'{must_move}','false'::jsonb);
      st := jsonb_set(st,'{dice}','null'::jsonb);
      st := jsonb_set(st,'{turn_slot}', to_jsonb(v_slot));
      st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
      st := jsonb_set(st,'{last_event}', to_jsonb('double_roll:rejoue'));
      st := st - 'no_move_display';
      st := st - 'power_event';
      UPDATE public.ludo_games SET state=st WHERE id=_game_id;
      RETURN st;
    END IF;

    -- Normal no-move: advance turn
    v_display := jsonb_build_object('slot', v_slot, 'dice', v_dice,
      'until', to_char((now() + interval '1.5 seconds') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
    UPDATE public.ludo_participants SET consecutive_sixes=0 WHERE game_id=_game_id AND slot=v_slot;
    v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
    -- FIX 3: clear shield + decrement cooldowns for new player
    st := public._ludo_clear_shield(st, v_new_slot);
    st := public._ludo_decrement_cooldowns(st);
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(v_new_slot));
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('roll:'||v_dice||':no_move'));
    st := jsonb_set(st,'{no_move_display}', v_display);
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := st - 'power_event';
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
    PERFORM public._ludo_check_game_over(_game_id);
  ELSE
    UPDATE public.ludo_games SET state=st WHERE id=_game_id;
  END IF;
  RETURN st;
END $$;

REVOKE EXECUTE ON FUNCTION public.ludo_roll(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.ludo_roll(uuid) TO authenticated;


-- ═══ 3. FIX ludo_choose_power — lucky_star validation + capture tracking ═
CREATE OR REPLACE FUNCTION public.ludo_choose_power(_game_id uuid, _choice text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $$
DECLARE
  st jsonb; g public.ludo_games%ROWTYPE; v_uid UUID := auth.uid();
  v_slot INT; v_dice INT; v_user UUID; v_isbot BOOLEAN; v_max INT;
  v_team INT; v_is_groupe BOOLEAN;
  v_pending jsonb; v_tile_type TEXT; v_pawn_idx INT; v_cell INT;
  v_options jsonb;
  v_boost_dice INT; v_boost_new_step INT; v_boost_new_state TEXT;
  v_captured BOOLEAN := FALSE; v_finished BOOLEAN := FALSE;
  v_bonus BOOLEAN := FALSE; v_power_bonus BOOLEAN := FALSE;
  v_all_done BOOLEAN; v_winner_uid UUID;
  arr jsonb; pawn jsonb; pawn_state TEXT; pawn_step INT;
  start_idx INT; abs_cell INT;
  rec RECORD; other_pawns jsonb; op jsonb; op_step INT; op_start INT;
  i INT; j INT; same_slot_count INT;
  v_shields jsonb;
  v_has_shield BOOLEAN;
  v_yard_idx INT;
  v_new_slot INT;
  v_captured_list jsonb := '[]'::jsonb;
  v_now text; v_seq int;
  v_qc int; v_finishers int; v_remaining int; v_next_rank int;
  v_dr_consumed BOOLEAN := FALSE;
  v_pre_move_captures INT := 0;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := g.state;

  v_pending := st->'power_pending';
  IF v_pending IS NULL THEN RAISE EXCEPTION 'Aucun pouvoir en attente'; END IF;

  v_slot := (v_pending->>'slot')::INT;
  v_tile_type := v_pending->>'tile_type';
  v_pawn_idx := (v_pending->>'pawn_idx')::INT;
  v_max := g.max_players;
  v_is_groupe := (g.match_type = 'groupe');

  SELECT user_id, is_bot, team INTO v_user, v_isbot, v_team
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre pouvoir'; END IF;

  v_dice := COALESCE((st->>'dice')::INT, 0);
  v_now := to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"');

  -- FIX 6: Check if the original move (in ludo_move) already captured opponents
  IF st ? 'last_event' AND (st->>'last_event') LIKE 'capture%' THEN
    v_pre_move_captures := 1;
  END IF;

  st := st - 'power_pending';

  CASE v_tile_type
    WHEN 'boost' THEN
      IF _choice = 'activate' THEN
        v_boost_dice := 1 + (floor(random()*6))::INT;
        v_boost_new_step := (st->'pawns'->v_slot::text->v_pawn_idx->>'k')::INT + v_boost_dice;

        IF v_boost_new_step <= 56 THEN
          IF v_boost_new_step = 56 THEN
            v_boost_new_state := 'finished'; v_finished := TRUE;
          ELSE
            v_boost_new_state := 'track';
          END IF;
          arr := st->'pawns'->v_slot::text;
          arr := jsonb_set(arr, ARRAY[v_pawn_idx::text], jsonb_build_object('s', v_boost_new_state, 'k', v_boost_new_step));
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
                          v_captured := TRUE;
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
        v_power_bonus := TRUE;
      ELSE
        st := jsonb_set(st, '{power_event}', jsonb_build_object('type','boost','slot',v_slot,'skipped',true,'at',v_now));
      END IF;

    WHEN 'lucky_star' THEN
      v_options := COALESCE(v_pending->'options', '[]'::jsonb);
      -- FIX 1: Use #>>'{}' instead of ->>'' for JSON string scalars
      IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_options) WHERE value#>>'{}' = _choice) THEN
        RAISE EXCEPTION 'Choix invalide';
      END IF;

      CASE _choice
        WHEN 'boost' THEN
          v_boost_dice := 1 + (floor(random()*6))::INT;
          pawn := st->'pawns'->v_slot::text->v_pawn_idx;
          v_boost_new_step := (pawn->>'k')::INT + v_boost_dice;
          IF v_boost_new_step <= 56 THEN
            IF v_boost_new_step = 56 THEN v_boost_new_state := 'finished'; v_finished := TRUE;
            ELSE v_boost_new_state := 'track'; END IF;
            arr := st->'pawns'->v_slot::text;
            arr := jsonb_set(arr, ARRAY[v_pawn_idx::text], jsonb_build_object('s', v_boost_new_state, 'k', v_boost_new_step));
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
                            v_captured := TRUE;
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
          st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','slot',v_slot,'reward','free_pawn','pawn',v_yard_idx,'at',v_now));

        WHEN 'reroll' THEN
          st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','slot',v_slot,'reward','reroll','at',v_now));
      END CASE;
      v_power_bonus := TRUE;
  END CASE;

  -- Post-move logic
  v_all_done := TRUE;
  FOR i IN 0..3 LOOP
    IF (st->'pawns'->v_slot::text->i->>'s') <> 'finished' THEN v_all_done := FALSE; END IF;
  END LOOP;

  UPDATE public.ludo_participants SET missed_turns=0 WHERE game_id=_game_id AND slot=v_slot;

  v_seq := COALESCE((st->>'turn_seq')::int, 0);
  PERFORM public._ludo_push_move(_game_id, jsonb_build_object(
    'seq', v_seq, 'slot', v_slot, 'pawn', v_pawn_idx, 'dice', v_dice,
    'captured', v_captured_list, 'finished', v_finished, 'power', v_tile_type, 'at', v_now
  ));

  IF v_all_done THEN
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
      SELECT user_id INTO v_winner_uid FROM public.ludo_participants
        WHERE game_id=_game_id AND finish_rank=1;
      IF v_is_groupe AND v_team IS NOT NULL THEN
        PERFORM public._ludo_finish_team(_game_id, v_winner_uid, v_team);
      ELSE
        PERFORM public.finish_game(_game_id, v_winner_uid);
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

  -- FIX 6: Include pre-move captures in bonus calculation
  v_bonus := (v_dice = 6) OR v_captured OR v_finished OR (v_pre_move_captures > 0);
  IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
    v_bonus := TRUE;
    st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
  END IF;
  IF v_power_bonus THEN v_bonus := TRUE; END IF;

  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := jsonb_set(st,'{dice}','null'::jsonb);
  st := st - 'no_move_display';
  IF v_bonus THEN
    st := jsonb_set(st,'{last_event}', to_jsonb(
      (CASE WHEN v_captured OR v_pre_move_captures > 0 THEN 'capture' WHEN v_finished THEN 'home' ELSE 'six' END || ':rejoue')::text));
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
END $$;

REVOKE EXECUTE ON FUNCTION public.ludo_choose_power(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.ludo_choose_power(uuid, text) TO authenticated;

-- ═══ 4. Update rules_markdown with clarification ════════════════════
UPDATE public.game_configs
SET rules_markdown = 'Mode Classique : règles standard du Ludo.

Mode Moderne (Power Mode) :
6 cases spéciales placées sur le plateau. Après activation, une case entre en cooldown pendant 3 tours avant de redevenir active.

🚀 Boost : choix d''activer ou non. Avance de 1 à 6 cases supplémentaires.
🛡️ Bouclier : protège TOUS vos pions pendant 1 tour. Indiqué par un anneau orange sur vos pions.
⚡ Deuxième lancer : deux lancers de dé au prochain tour. Si le premier lancer ne permet pas de jouer, le deuxième lancer est automatiquement accordé. Badge ⚡2x visible sur votre carte.
⭐ Étoile Chance : choisissez 1 récompense parmi 3 options aléatoires (boost, bouclier, double lancer, pion gratuit, re-lancer).

Les cases spéciales ne peuvent pas apparaître sur les bases, cases de départ, cases de sécurité, colonnes ou arrivée.'
WHERE slug = 'ludo';
