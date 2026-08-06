-- ═══════════════════════════════════════════════════════════════════════
-- LUDO MODE MODERNE (POWER MODE)
-- Cases spéciales : Boost, Bouclier, Deuxième lancer, Étoile Chance
-- ═══════════════════════════════════════════════════════════════════════

-- 1. Helper : cases valides pour les power tiles (path indices 0-51)
--    Exclut : bases, cases de départ, cases de sécurité, colonnes/arrivée
CREATE OR REPLACE FUNCTION public._ludo_power_valid_cells()
RETURNS int[]
LANGUAGE sql IMMUTABLE
AS $$
  SELECT ARRAY(
    SELECT i FROM generate_series(0,51) i
    WHERE i NOT IN (0, 8, 13, 21, 26, 34, 39, 47)
  )
$$;

-- 2. Helper : place 4 power tiles sur des cases valides aléatoires
CREATE OR REPLACE FUNCTION public._ludo_place_power_tiles()
RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
  v_valid int[] := public._ludo_power_valid_cells();
  v_shuffled int[];
  v_types text[] := ARRAY['boost','shield','double_roll','lucky_star'];
  v_tiles jsonb := '[]'::jsonb;
  v_cell int;
  i int;
BEGIN
  v_shuffled := v_valid;
  FOR i IN REVERSE array_length(v_shuffled,1)..2 LOOP
    DECLARE
      v_j int := 1 + floor(random()*i)::int;
      v_tmp int;
    BEGIN
      v_tmp := v_shuffled[i]; v_shuffled[i] := v_shuffled[v_j]; v_shuffled[v_j] := v_tmp;
    END;
  END LOOP;
  FOR i IN 1..4 LOOP
    v_cell := v_shuffled[i];
    v_tiles := v_tiles || jsonb_build_object('type', v_types[i], 'cell', v_cell);
  END LOOP;
  RETURN v_tiles;
END $$;

-- 3. Helper : relocaliser une tuile après activation
CREATE OR REPLACE FUNCTION public._ludo_relocate_tile(_power_tiles jsonb, _type text)
RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
  v_valid int[] := public._ludo_power_valid_cells();
  v_occupied int[];
  v_tile jsonb;
  v_available int[];
  v_new_cell int;
  v_result jsonb := '[]'::jsonb;
  v_found boolean := false;
BEGIN
  v_occupied := ARRAY[]::int[];
  FOR v_tile IN SELECT value FROM jsonb_array_elements(_power_tiles) LOOP
    IF v_tile->>'type' <> _type THEN
      v_occupied := v_occupied || (v_tile->>'cell')::int;
    END IF;
  END LOOP;
  v_available := ARRAY(
    SELECT c FROM unnest(v_valid) c WHERE NOT (c = ANY(v_occupied))
  );
  IF array_length(v_available,1) IS NULL OR array_length(v_available,1) = 0 THEN
    FOR v_tile IN SELECT value FROM jsonb_array_elements(_power_tiles) LOOP
      IF v_tile->>'type' <> _type THEN v_result := v_result || v_tile; END IF;
    END LOOP;
    RETURN v_result;
  END IF;
  v_new_cell := v_available[1 + floor(random()*array_length(v_available,1))::int];
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

-- 4. Modify _ludo_init_state to accept mode and add power tiles for 'fast' mode
DROP FUNCTION IF EXISTS public._ludo_init_state(integer);
CREATE OR REPLACE FUNCTION public._ludo_init_state(_max_players integer, _mode text DEFAULT 'classic')
RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE p jsonb := '{}'::jsonb; i INT; v_st jsonb;
BEGIN
  FOR i IN 0.._max_players-1 LOOP
    p := p || jsonb_build_object(i::text,
      jsonb_build_array(
        jsonb_build_object('s','yard','k',-1),
        jsonb_build_object('s','yard','k',-1),
        jsonb_build_object('s','yard','k',-1),
        jsonb_build_object('s','yard','k',-1)
      ));
  END LOOP;
  v_st := jsonb_build_object(
    'pawns', p, 'turn_slot', 0, 'dice', NULL, 'must_move', false,
    'turn_started_at', to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'turn_seq', 0, 'phase', 'spinning',
    'phase_started_at', to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'spin_ms', 0, 'last_event', 'start');
  IF _mode = 'fast' THEN
    v_st := v_st || jsonb_build_object(
      'power_tiles', public._ludo_place_power_tiles(),
      'shields', '{}'::jsonb,
      'double_roll_pending', 'null'::jsonb
    );
  END IF;
  RETURN v_st;
END $$;

-- 5. Modify _ludo_ensure_state to pass mode
CREATE OR REPLACE FUNCTION public._ludo_ensure_state(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE g public.ludo_games%ROWTYPE; st jsonb;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  IF (g.state ? 'pawns') IS NOT TRUE OR g.state->'pawns' = '{}'::jsonb THEN
    st := public._ludo_init_state(g.max_players, COALESCE(g.mode,'classic'));
    UPDATE public.ludo_games SET state=st, current_turn=0 WHERE id=_game_id;
    RETURN st;
  END IF;
  RETURN g.state;
END $$;

-- 6. Modify ludo_set_ready to pass mode
CREATE OR REPLACE FUNCTION public.ludo_set_ready(_game_id uuid, _ready boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $$
DECLARE v_uid UUID := auth.uid(); v_game public.ludo_games%ROWTYPE;
  v_total int; v_ready int; v_verified boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT phone_verified INTO v_verified FROM public.profiles WHERE id=v_uid;
  IF _ready AND NOT COALESCE(v_verified,false) THEN
    RAISE EXCEPTION 'Vérifiez votre numéro de téléphone dans votre profil';
  END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL OR v_game.status <> 'open' THEN RAISE EXCEPTION 'Partie non ouverte'; END IF;
  UPDATE public.ludo_participants SET ready=_ready, last_seen=now()
    WHERE game_id=_game_id AND user_id=v_uid;
  SELECT count(*), count(*) FILTER (WHERE ready OR is_bot)
    INTO v_total, v_ready FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_total = v_game.max_players AND v_ready = v_total THEN
    UPDATE public.ludo_games SET status='playing', started_at=now(),
      state=public._ludo_init_state(v_game.max_players, COALESCE(v_game.mode,'classic')) WHERE id=_game_id;
  END IF;
END $$;

-- 7. Modify _ludo_advance_turn to clear shields for the new player
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
  st := st - 'power_event';
  UPDATE public.ludo_games SET state=st, current_turn=_new_slot WHERE id=_game_id;
  RETURN st;
END $$;

-- 8. Modify ludo_roll to clear double_roll_pending on no-move / triple-six
CREATE OR REPLACE FUNCTION public.ludo_roll(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $$
DECLARE st jsonb; g public.ludo_games%ROWTYPE; v_uid UUID := auth.uid();
  v_slot INT; v_user UUID; v_isbot BOOLEAN; v_bias INT; v_dice INT;
  arr jsonb; pawn jsonb; i INT; pstate TEXT; pstep INT; has_move BOOLEAN := FALSE;
  v_consec INT; v_override int; v_display jsonb;
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
  IF v_dice = 6 THEN v_consec := COALESCE(v_consec,0) + 1; ELSE v_consec := 0; END IF;
  UPDATE public.ludo_participants SET consecutive_sixes=v_consec WHERE game_id=_game_id AND slot=v_slot;
  IF v_consec >= 3 THEN
    UPDATE public.ludo_participants SET consecutive_sixes=0 WHERE game_id=_game_id AND slot=v_slot;
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st,'{dice}','null'::jsonb);
    IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
      st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
    END IF;
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('triple_six:cancel'::text));
    st := st - 'no_move_display';
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
    PERFORM public._ludo_check_game_over(_game_id);
    RETURN st;
  END IF;
  st := jsonb_set(st,'{dice}', to_jsonb(v_dice));
  st := jsonb_set(st,'{must_move}','true'::jsonb);
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('roll:'||v_dice));
  st := st - 'no_move_display';
  arr := st->'pawns'->v_slot::text;
  FOR i IN 0..3 LOOP
    pawn := arr->i; pstate := pawn->>'s'; pstep := (pawn->>'k')::INT;
    IF pstate='finished' THEN CONTINUE; END IF;
    IF pstate='yard' THEN IF v_dice=6 THEN has_move:=TRUE; EXIT; END IF;
    ELSE IF pstep + v_dice <= 56 THEN has_move:=TRUE; EXIT; END IF; END IF;
  END LOOP;
  IF NOT has_move THEN
    IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
      st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
    END IF;
    v_display := jsonb_build_object('slot', v_slot, 'dice', v_dice,
      'until', to_char((now() + interval '1.5 seconds') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
    UPDATE public.ludo_participants SET consecutive_sixes=0 WHERE game_id=_game_id AND slot=v_slot;
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('roll:'||v_dice||':no_move'));
    st := jsonb_set(st,'{no_move_display}', v_display);
    st := jsonb_set(st,'{dice}','null'::jsonb);
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
    PERFORM public._ludo_check_game_over(_game_id);
  ELSE
    UPDATE public.ludo_games SET state=st WHERE id=_game_id;
  END IF;
  RETURN st;
END $$;

-- 9. Modify ludo_move to handle power tiles
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
  v_power_tiles jsonb; v_shields jsonb; v_shield_arr jsonb;
  v_boost_dice INT; v_boost_new_step INT; v_boost_new_state TEXT;
  v_lucky_reward INT; v_yard_idx INT;
  v_power_bonus BOOLEAN := FALSE; v_now text; v_has_shield BOOLEAN;
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

  -- Capture check (with shield protection in fast mode)
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
                -- Check shield
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

  -- Power tile activation (Mode Moderne only)
  IF v_mode = 'fast' AND new_state = 'track' AND new_step <= 50 THEN
    start_idx := public._ludo_start_for(_game_id, v_slot);
    abs_cell := (start_idx + new_step) % 52;
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
            WHEN 1 THEN -- Boost
              v_boost_dice := 1 + (floor(random()*6))::INT;
              v_boost_new_step := new_step + v_boost_dice;
              IF v_boost_new_step <= 56 THEN
                IF v_boost_new_step = 56 THEN v_boost_new_state := 'finished'; finished := TRUE;
                ELSE v_boost_new_state := 'track'; END IF;
                arr := st->'pawns'->v_slot::text;
                arr := jsonb_set(arr, ARRAY[_pawn_idx::text], jsonb_build_object('s', v_boost_new_state, 'k', v_boost_new_step));
                st := jsonb_set(st, ARRAY['pawns', v_slot::text], arr);
                IF v_boost_new_state = 'track' AND v_boost_new_step <= 50 THEN
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
              st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','reward','boost','dice',v_boost_dice,'slot',v_slot,'at',v_now));
            WHEN 2 THEN -- Shield
              v_shields := COALESCE(st->'shields', '{}'::jsonb);
              v_shield_arr := COALESCE(v_shields->v_slot::text, '[]'::jsonb) || to_jsonb(_pawn_idx);
              v_shields := jsonb_set(v_shields, ARRAY[v_slot::text], v_shield_arr, true);
              st := jsonb_set(st, '{shields}', v_shields, true);
              st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','reward','shield','slot',v_slot,'at',v_now));
            WHEN 3 THEN -- Double roll
              st := jsonb_set(st, '{double_roll_pending}', to_jsonb(v_slot));
              st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','reward','double_roll','slot',v_slot,'at',v_now));
            WHEN 4 THEN -- Re-roll
              v_power_bonus := TRUE;
              st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','reward','reroll','slot',v_slot,'at',v_now));
            WHEN 5 THEN -- Free pawn out
              arr := st->'pawns'->v_slot::text;
              v_yard_idx := -1;
              FOR i IN 0..3 LOOP
                IF (arr->i->>'s') = 'yard' AND i <> _pawn_idx THEN v_yard_idx := i; EXIT; END IF;
              END LOOP;
              IF v_yard_idx >= 0 THEN
                arr := jsonb_set(arr, ARRAY[v_yard_idx::text], jsonb_build_object('s','track','k',0));
                st := jsonb_set(st, ARRAY['pawns', v_slot::text], arr);
              END IF;
              st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','reward','free_pawn','slot',v_slot,'pawn',v_yard_idx,'at',v_now));
          END CASE;
      END CASE;
      v_power_tiles := public._ludo_relocate_tile(v_power_tiles, v_tile_type);
      st := jsonb_set(st, '{power_tiles}', v_power_tiles, true);
    END IF;
  END IF;

  -- Check all pawns finished
  all_done := TRUE;
  FOR i IN 0..3 LOOP
    IF (st->'pawns'->v_slot::text->i->>'s') <> 'finished' THEN all_done := FALSE; END IF;
  END LOOP;
  UPDATE public.ludo_participants SET missed_turns=0 WHERE game_id=_game_id AND slot=v_slot;
  IF all_done THEN
    SELECT user_id INTO winner_uid FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
    UPDATE public.ludo_games SET state=st WHERE id=_game_id;
    IF v_is_groupe AND v_team IS NOT NULL THEN
      PERFORM public._ludo_finish_team(_game_id, winner_uid, v_team);
    ELSE
      PERFORM public.finish_game(_game_id, winner_uid);
    END IF;
    RETURN st;
  END IF;

  -- Bonus & turn advancement
  bonus := (v_dice = 6) OR captured OR finished;
  IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
    bonus := TRUE;
    st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
  END IF;
  IF v_power_bonus THEN bonus := TRUE; END IF;

  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := jsonb_set(st,'{dice}','null'::jsonb);
  st := st - 'no_move_display';
  IF bonus THEN
    st := jsonb_set(st,'{last_event}', to_jsonb(
      (CASE WHEN captured THEN 'capture' WHEN finished THEN 'home' ELSE 'six' END || ':rejoue')::text));
  ELSE
    st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, v_max)));
    st := jsonb_set(st,'{last_event}', to_jsonb('move'::text));
    UPDATE public.ludo_participants SET consecutive_sixes=0 WHERE game_id=_game_id AND slot=v_slot;
  END IF;
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  PERFORM public._ludo_check_game_over(_game_id);
  RETURN st;
END $$;

-- 10. Modify ludo_check_timeout to clear double_roll_pending
CREATE OR REPLACE FUNCTION public.ludo_check_timeout(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_slot int; v_started timestamptz;
  v_uid uuid; v_isbot boolean; v_secs int;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := g.state; v_slot := (st->>'turn_slot')::INT;
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
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('timeout'::text));
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  IF NOT v_isbot THEN PERFORM public._ludo_check_afk(_game_id, v_slot); END IF;
  RETURN st;
END $$;

-- 11. Update game_configs rules_markdown for ludo Mode Moderne
UPDATE public.game_configs
SET rules_markdown = 'Mode Classique : règles standard du Ludo.

Mode Moderne (Power Mode) :
Cases spéciales placées aléatoirement, qui changent de position après activation.

🚀 Boost : avance automatiquement de 1 à 6 cases.
🛡️ Bouclier : protège de la capture jusqu''à votre prochain tour.
⚡ Deuxième lancer : deux lancers de dé au prochain tour.
⭐ Étoile Chance : récompense aléatoire (boost, bouclier, double lancer, relance, ou sortie gratuite de pion).

Les cases spéciales ne peuvent pas apparaître sur les bases, cases de départ, cases de sécurité, colonnes ou arrivée.'
WHERE slug = 'ludo';
