-- ═══════════════════════════════════════════════════════════════════════
-- LUDO MODE MODERNE V2 — Améliorations complètes
--
-- Changes:
--   1. Shield protège TOUS les pions du joueur (booléen par slot)
--   2. 6 tuiles au lieu de 4, fixes avec cooldown de 3 tours
--   3. Power choice: dialog pour Boost et Lucky Star
--   4. Nouvelle fonction ludo_choose_power
--   5. Bot auto-resolve + timeout handling pour power_pending
--   6. Notifications power_event améliorées
-- ═══════════════════════════════════════════════════════════════════════

-- ═══ 1. Helper: _ludo_decrement_cooldowns ═════════════════════════════
CREATE OR REPLACE FUNCTION public._ludo_decrement_cooldowns(st jsonb)
RETURNS jsonb
LANGUAGE sql IMMUTABLE
AS $$
  SELECT CASE
    WHEN st ? 'power_tiles' AND jsonb_array_length(st->'power_tiles') > 0
    THEN jsonb_set(st, '{power_tiles}', (
      SELECT jsonb_agg(
        CASE
          WHEN (value->>'cd')::int > 0
          THEN jsonb_set(value, '{cd}', to_jsonb((value->>'cd')::int - 1))
          ELSE value
        END
      )
      FROM jsonb_array_elements(st->'power_tiles')
    ))
    ELSE st
  END
$$;

-- ═══ 2. Helper: _ludo_clear_shield (inchangé mais recréé pour être sûr) ═
CREATE OR REPLACE FUNCTION public._ludo_clear_shield(st jsonb, _slot int)
RETURNS jsonb
LANGUAGE sql IMMUTABLE
AS $$
  SELECT CASE
    WHEN st ? 'shields' AND (st->'shields') ? _slot::text
    THEN jsonb_set(st, '{shields}', (st->'shields') - _slot::text, true)
    ELSE st
  END
$$;

-- ═══ 3. _ludo_place_power_tiles — 6 tuiles avec cd ═══════════════════
CREATE OR REPLACE FUNCTION public._ludo_place_power_tiles()
RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
  v_valid int[] := public._ludo_power_valid_cells();
  v_shuffled int[];
  v_types text[] := ARRAY['boost','boost','lucky_star','lucky_star','shield','double_roll'];
  v_tiles jsonb := '[]'::jsonb;
  v_cell int;
  i int;
  v_j int;
  v_tmp int;
BEGIN
  v_shuffled := v_valid;
  FOR i IN REVERSE array_length(v_shuffled,1)..2 LOOP
    v_j := 1 + floor(random()*i)::int;
    v_tmp := v_shuffled[i]; v_shuffled[i] := v_shuffled[v_j]; v_shuffled[v_j] := v_tmp;
  END LOOP;
  FOR i IN 1..6 LOOP
    IF i > array_length(v_shuffled,1) THEN EXIT; END IF;
    v_cell := v_shuffled[i];
    v_tiles := v_tiles || jsonb_build_object('type', v_types[i], 'cell', v_cell, 'cd', 0);
  END LOOP;
  RETURN v_tiles;
END $$;

-- ═══ 4. ludo_choose_power — nouvelle fonction RPC ════════════════════
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
      IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_options) WHERE value->>'' = _choice) THEN
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

  v_bonus := (v_dice = 6) OR v_captured OR v_finished;
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
      (CASE WHEN v_captured THEN 'capture' WHEN v_finished THEN 'home' ELSE 'six' END || ':rejoue')::text));
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

-- ═══ 5. ludo_move — shield booléen + power_pending pour boost/lucky_star ═
CREATE OR REPLACE FUNCTION public.ludo_move(_game_id uuid, _pawn_idx integer)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $$
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
  v_lucky_options text[] := ARRAY['boost','shield','double_roll','free_pawn','reroll'];
  v_shuffled_options text[];
  v_3_options jsonb;
  v_tmp text;
  v_j int;
  v_pending_set BOOLEAN := FALSE;
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
    ELSE new_state := 'track'; END IF;
  END IF;
  arr := st->'pawns'->v_slot::text;
  arr := jsonb_set(arr, ARRAY[_pawn_idx::text], jsonb_build_object('s', new_state, 'k', new_step));
  st := jsonb_set(st, ARRAY['pawns', v_slot::text], arr);

  IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
    v_dr_consumed := TRUE;
    st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
  END IF;

  -- Capture check (with shield protection — boolean per slot)
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

  -- Power tile activation (Mode Moderne only)
  IF v_mode = 'fast' AND new_state = 'track' AND new_step <= 50 THEN
    start_idx := public._ludo_start_for(_game_id, v_slot);
    abs_cell := (start_idx + new_step) % 52;
    v_power_tiles := COALESCE(st->'power_tiles', '[]'::jsonb);
    v_tile_type := NULL;
    FOR v_tile IN SELECT value FROM jsonb_array_elements(v_power_tiles) LOOP
      IF (v_tile->>'cell')::int = abs_cell AND COALESCE((v_tile->>'cd')::int, 0) = 0 THEN
        v_tile_type := v_tile->>'type'; EXIT;
      END IF;
    END LOOP;

    IF v_tile_type IS NOT NULL THEN
      v_power_tiles := (
        SELECT jsonb_agg(
          CASE
            WHEN (value->>'cell')::int = abs_cell AND COALESCE((value->>'cd')::int,0) = 0 AND value->>'type' = v_tile_type
            THEN jsonb_set(value, '{cd}', '3'::jsonb)
            ELSE value
          END
        )
        FROM jsonb_array_elements(v_power_tiles)
      );
      st := jsonb_set(st, '{power_tiles}', v_power_tiles, true);
      v_now := to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"');

      CASE v_tile_type
        WHEN 'shield' THEN
          v_shields := COALESCE(st->'shields', '{}'::jsonb);
          v_shields := jsonb_set(v_shields, ARRAY[v_slot::text], 'true'::jsonb, true);
          st := jsonb_set(st, '{shields}', v_shields, true);
          st := jsonb_set(st, '{power_event}', jsonb_build_object('type','shield','slot',v_slot,'at',v_now));
          v_power_bonus := TRUE;

        WHEN 'double_roll' THEN
          st := jsonb_set(st, '{double_roll_pending}', to_jsonb(v_slot));
          st := jsonb_set(st, '{power_event}', jsonb_build_object('type','double_roll','slot',v_slot,'at',v_now));
          v_power_bonus := TRUE;

        WHEN 'boost' THEN
          st := jsonb_set(st, '{power_pending}', jsonb_build_object(
            'slot', v_slot, 'pawn_idx', _pawn_idx, 'tile_type', 'boost', 'cell', abs_cell, 'at', v_now
          ), true);
          st := jsonb_set(st, '{power_event}', jsonb_build_object('type','boost','slot',v_slot,'pending',true,'at',v_now));
          v_pending_set := TRUE;

        WHEN 'lucky_star' THEN
          v_shuffled_options := v_lucky_options;
          FOR i IN REVERSE 5..2 LOOP
            v_j := 1 + floor(random()*i)::int;
            v_tmp := v_shuffled_options[i]; v_shuffled_options[i] := v_shuffled_options[v_j]; v_shuffled_options[v_j] := v_tmp;
          END LOOP;
          v_3_options := to_jsonb(v_shuffled_options[1:3]);
          st := jsonb_set(st, '{power_pending}', jsonb_build_object(
            'slot', v_slot, 'pawn_idx', _pawn_idx, 'tile_type', 'lucky_star', 'cell', abs_cell,
            'options', v_3_options, 'at', v_now
          ), true);
          st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','slot',v_slot,'pending',true,'at',v_now));
          v_pending_set := TRUE;
      END CASE;
    END IF;
  END IF;

  IF v_pending_set THEN
    UPDATE public.ludo_games SET state=st WHERE id=_game_id;
    RETURN st;
  END IF;

  -- Post-move logic (same as before)
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
END $$;

REVOKE EXECUTE ON FUNCTION public.ludo_move(uuid, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.ludo_move(uuid, integer) TO authenticated;

-- ═══ 6. ludo_bot_play — auto-resolve power_pending ═══════════════════
CREATE OR REPLACE FUNCTION public.ludo_bot_play(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  g public.ludo_games%ROWTYPE; st jsonb; v_slot INT;
  v_isbot BOOLEAN; v_intel INT; v_bias INT; v_dice INT;
  arr jsonb; pawn jsonb; i INT; k INT; best INT := -1; best_score INT := -1;
  sc INT; pstate TEXT; pstep INT; abs_cell INT; start_idx INT;
  rec RECORD; op jsonb; op_step INT; op_start INT; op_abs INT;
  would_capture BOOLEAN; op_count INT;
  candidates INT[] := ARRAY[]::INT[];
  v_consec INT; v_team INT; v_is_groupe BOOLEAN;
  v_yard_count INT; v_onboard_count INT; v_finished_count INT;
  op_dist_behind INT; v_new_slot INT; v_choice text;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;
  v_is_groupe := (g.match_type = 'groupe');

  -- Auto-resolve power_pending if set
  IF st ? 'power_pending' THEN
    IF (st->'power_pending'->>'slot')::int = v_slot THEN
      IF (st->'power_pending'->>'tile_type') = 'boost' THEN
        v_choice := 'activate';
      ELSE
        v_choice := (st->'power_pending'->'options'->>0);
      END IF;
      PERFORM public.ludo_choose_power(_game_id, v_choice);
      SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
      RETURN st;
    END IF;
  END IF;

  SELECT is_bot, bot_intelligence, bot_win_bias, consecutive_sixes, team
    INTO v_isbot, v_intel, v_bias, v_consec, v_team
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot THEN RETURN st; END IF;

  IF NOT (st->>'must_move')::BOOLEAN THEN
    st := public.ludo_roll(_game_id);
    RETURN st;
  END IF;

  SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
  v_dice := (st->>'dice')::INT;
  IF v_dice IS NULL THEN RETURN st; END IF;

  arr := st->'pawns'->v_slot::text;
  start_idx := public._ludo_start_for(_game_id, v_slot);
  v_yard_count := 0; v_onboard_count := 0; v_finished_count := 0;
  FOR i IN 0..3 LOOP
    pawn := arr->i; pstate := pawn->>'s';
    IF pstate = 'yard' THEN v_yard_count := v_yard_count + 1;
    ELSIF pstate = 'finished' THEN v_finished_count := v_finished_count + 1;
    ELSE v_onboard_count := v_onboard_count + 1; END IF;
  END LOOP;

  FOR i IN 0..3 LOOP
    pawn := arr->i; pstate := pawn->>'s'; pstep := (pawn->>'k')::INT;
    IF pstate = 'finished' THEN CONTINUE; END IF;
    IF pstate = 'yard' THEN
      IF v_dice = 6 THEN candidates := candidates || i; END IF;
    ELSE
      IF pstep + v_dice <= 56 THEN candidates := candidates || i; END IF;
    END IF;
  END LOOP;

  IF array_length(candidates,1) IS NULL THEN
    UPDATE public.ludo_participants SET consecutive_sixes = 0 WHERE game_id = _game_id AND slot = v_slot;
    IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
      st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
    END IF;
    st := st - 'power_event'; st := st - 'no_move_display';
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{dice}','null'::jsonb);
    v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
    st := public._ludo_clear_shield(st, v_new_slot);
    st := public._ludo_decrement_cooldowns(st);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(v_new_slot));
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('bot:pass'));
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
    RETURN st;
  END IF;

  IF (random()*100) < COALESCE(v_intel,70) THEN
    FOREACH i IN ARRAY candidates LOOP
      pawn := arr->i; pstate := pawn->>'s'; pstep := (pawn->>'k')::INT; sc := 0;
      IF pstate = 'yard' AND v_dice = 6 THEN
        sc := 50;
        IF v_yard_count >= 3 THEN sc := sc + 30; END IF;
        IF v_yard_count = 4 THEN sc := sc + 20; END IF;
        IF v_onboard_count = 0 THEN sc := sc + 25; END IF;
      ELSIF pstep + v_dice = 56 THEN
        sc := 200;
      ELSE
        sc := pstep + v_dice;
        would_capture := FALSE;
        IF pstep + v_dice <= 50 THEN
          abs_cell := (start_idx + pstep + v_dice) % 52;
          IF NOT public._ludo_is_safe(abs_cell) THEN
            op_count := 0;
            FOR rec IN SELECT slot, team FROM public.ludo_participants
                        WHERE game_id=_game_id AND slot <> v_slot AND forfeited=FALSE LOOP
              IF v_is_groupe AND rec.team IS NOT NULL AND rec.team = v_team THEN CONTINUE; END IF;
              op_start := public._ludo_start_for(_game_id, rec.slot);
              FOR k IN 0..3 LOOP
                op := st->'pawns'->rec.slot::text->k;
                IF op->>'s' = 'track' THEN
                  op_step := (op->>'k')::INT;
                  IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN op_count := op_count + 1; END IF;
                END IF;
              END LOOP;
            END LOOP;
            would_capture := (op_count = 1);
          END IF;
        END IF;
        IF would_capture THEN
          sc := sc + 80;
          FOR rec IN SELECT slot, team FROM public.ludo_participants
                      WHERE game_id=_game_id AND slot <> v_slot AND forfeited=FALSE LOOP
            IF v_is_groupe AND rec.team IS NOT NULL AND rec.team = v_team THEN CONTINUE; END IF;
            op_start := public._ludo_start_for(_game_id, rec.slot);
            FOR k IN 0..3 LOOP
              op := st->'pawns'->rec.slot::text->k;
              IF op->>'s' = 'track' THEN
                op_step := (op->>'k')::INT;
                IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN sc := sc + op_step; END IF;
              END IF;
            END LOOP;
          END LOOP;
        END IF;
        IF pstep + v_dice <= 50 THEN
          abs_cell := (start_idx + pstep + v_dice) % 52;
          IF public._ludo_is_safe(abs_cell) THEN sc := sc + 25; END IF;
        END IF;
        IF pstate = 'track' AND pstep <= 50 THEN
          abs_cell := (start_idx + pstep) % 52;
          IF NOT public._ludo_is_safe(abs_cell) THEN
            FOR rec IN SELECT slot, team FROM public.ludo_participants
                        WHERE game_id=_game_id AND slot <> v_slot AND forfeited=FALSE LOOP
              IF v_is_groupe AND rec.team IS NOT NULL AND rec.team = v_team THEN CONTINUE; END IF;
              op_start := public._ludo_start_for(_game_id, rec.slot);
              FOR k IN 0..3 LOOP
                op := st->'pawns'->rec.slot::text->k;
                IF op->>'s' = 'track' THEN
                  op_step := (op->>'k')::INT;
                  op_abs := (op_start + op_step) % 52;
                  op_dist_behind := (abs_cell - op_abs + 52) % 52;
                  IF op_dist_behind >= 1 AND op_dist_behind <= 6 THEN sc := sc + 40; END IF;
                END IF;
              END LOOP;
            END LOOP;
          END IF;
        END IF;
        IF pstep > 50 THEN sc := sc + 15; END IF;
        sc := sc + (pstep * 2);
      END IF;
      IF sc > best_score THEN best_score := sc; best := i; END IF;
    END LOOP;
  ELSE
    best := candidates[1 + floor(random() * array_length(candidates,1))::INT];
  END IF;
  IF best < 0 THEN best := candidates[1]; END IF;

  PERFORM public.ludo_move(_game_id, best);

  -- Auto-resolve power_pending after move
  SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
  IF st ? 'power_pending' THEN
    IF (st->'power_pending'->>'tile_type') = 'boost' THEN
      v_choice := 'activate';
    ELSE
      v_choice := (st->'power_pending'->'options'->>0);
    END IF;
    PERFORM public.ludo_choose_power(_game_id, v_choice);
    SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
  END IF;

  RETURN st;
END $$;

REVOKE EXECUTE ON FUNCTION public.ludo_bot_play(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.ludo_bot_play(uuid) TO authenticated;

-- ═══ 7. ludo_check_timeout — handle power_pending ════════════════════
CREATE OR REPLACE FUNCTION public.ludo_check_timeout(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_slot int; v_started timestamptz;
  v_uid uuid; v_isbot boolean; v_secs int; v_choice text;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := g.state; v_slot := (st->>'turn_slot')::INT;

  -- Auto-resolve power_pending on timeout
  IF st ? 'power_pending' THEN
    IF (st->'power_pending'->>'tile_type') = 'boost' THEN
      v_choice := 'skip';
    ELSE
      v_choice := (st->'power_pending'->'options'->>0);
    END IF;
    PERFORM public.ludo_choose_power(_game_id, v_choice);
    SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
    RETURN st;
  END IF;

  SELECT user_id, is_bot INTO v_uid, v_isbot
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  SELECT COALESCE(turn_seconds,30) INTO v_secs FROM public.app_settings WHERE id=1;
  v_started := (st->>'turn_started_at')::timestamptz;
  IF now() - v_started < (v_secs || ' seconds')::interval THEN RETURN st; END IF;
  IF NOT COALESCE(v_isbot,false) AND COALESCE((st->>'must_move')::boolean, false) AND COALESCE(g.auto_move, false) THEN
    IF public._ludo_auto_move(_game_id, v_slot) THEN
      SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
      RETURN st;
    END IF;
  END IF;
  IF NOT v_isbot AND NOT (st->>'must_move')::BOOLEAN THEN
    UPDATE public.ludo_participants SET afk_t1 = afk_t1 + 1 WHERE game_id=_game_id AND slot=v_slot;
  END IF;
  IF NOT v_isbot AND (st->>'must_move')::BOOLEAN THEN
    UPDATE public.ludo_participants SET afk_t2 = afk_t2 + 1 WHERE game_id=_game_id AND slot=v_slot;
  END IF;
  IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
    st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
  END IF;
  st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
  st := jsonb_set(st,'{dice}','null'::jsonb);
  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := public._ludo_decrement_cooldowns(st);
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('timeout'::text));
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  IF NOT v_isbot THEN PERFORM public._ludo_check_afk(_game_id, v_slot); END IF;
  RETURN st;
END $$;

REVOKE EXECUTE ON FUNCTION public.ludo_check_timeout(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.ludo_check_timeout(uuid) TO authenticated;

-- ═══ 8. Update rules_markdown ════════════════════════════════════════
UPDATE public.game_configs
SET rules_markdown = 'Mode Classique : règles standard du Ludo.

Mode Moderne (Power Mode) :
6 cases spéciales placées sur le plateau. Après activation, une case entre en cooldown pendant 3 tours avant de redevenir active.

🚀 Boost : choix d''activer ou non. Avance de 1 à 6 cases supplémentaires.
🛡️ Bouclier : protège TOUS vos pions pendant 1 tour. Indiqué par un anneau orange sur vos pions.
⚡ Deuxième lancer : deux lancers de dé au prochain tour. Badge ⚡2x visible sur votre carte.
⭐ Étoile Chance : choisissez 1 récompense parmi 3 options aléatoires (boost, bouclier, double lancer, pion gratuit, re-lancer).

Les cases spéciales ne peuvent pas apparaître sur les bases, cases de départ, cases de sécurité, colonnes ou arrivée.'
WHERE slug = 'ludo';
