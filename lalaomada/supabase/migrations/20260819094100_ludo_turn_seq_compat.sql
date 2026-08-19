-- ============================================================
-- Fix: Add turn_seq increment for TEST-APP frontend realtime compatibility
-- The TEST-APP use-fast-realtime.ts hook uses turn_seq to validate
-- that realtime events are genuinely newer. Without turn_seq, bot moves
-- and turn changes are rejected by the frontend, causing the bot to
-- appear "stuck".
-- ============================================================

-- ludo_move: increment turn_seq on both branches (extra turn AND turn change)
CREATE OR REPLACE FUNCTION public.ludo_move(_game_id uuid, _pawn_idx integer)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
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
    IF new_k > 56 THEN RAISE EXCEPTION 'Depassement'; END IF;
    IF new_k = 56 THEN
      new_state := 'finished';
    ELSE
      new_state := 'track';
    END IF;
  END IF;
  arr := jsonb_set(arr, ARRAY[_pawn_idx::text], jsonb_build_object('s', new_state, 'k', new_k));
  st := jsonb_set(st, '{pawns}', jsonb_set(st->'pawns', ARRAY[v_slot::text], arr));

  IF new_state = 'track' AND new_k <= 50 THEN
    v_moving_path_idx := (public._ludo_start_idx(v_slot) + new_k - 1) % 52;
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
            IF v_step <= 50 THEN
              v_target_path_idx := (public._ludo_start_idx(v_target_slot) + v_step - 1) % 52;
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

  v_start_idx := public._ludo_start_idx(v_slot);
  v_has_power_tiles := (st ? 'power_tiles') AND jsonb_array_length(st->'power_tiles') > 0;
  
  IF v_has_power_tiles AND new_state = 'track' AND new_k <= 50 THEN
    st := public._ludo_check_power_tile(st, v_slot, _pawn_idx, new_k, v_start_idx);
    
    IF st ? 'power_event' THEN
      arr := st->'pawns'->v_slot::text;
      pawn := arr->_pawn_idx;
      new_k := (pawn->>'k')::INT;
      new_state := pawn->>'s';
        
      IF new_state = 'track' AND new_k <= 50 THEN
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
                IF v_step <= 50 THEN
                  v_target_path_idx := (public._ludo_start_idx(v_target_slot) + v_step - 1) % 52;
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
  
  IF v_dice = 6 OR captured OR new_state = 'finished' OR v_got_double_roll THEN
    IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::INT = v_slot THEN
      st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
    END IF;
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := jsonb_set(st,'{turn_seq}', to_jsonb(COALESCE((st->>'turn_seq')::int, 0) + 1));
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
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
    st := jsonb_set(st,'{turn_seq}', to_jsonb(COALESCE((st->>'turn_seq')::int, 0) + 1));
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('move'::text));
  END IF;
  
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  PERFORM public._ludo_check_game_over(_game_id);
  RETURN st;
END;
$function$;

-- ludo_pass: increment turn_seq
CREATE OR REPLACE FUNCTION public.ludo_pass(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  g public.ludo_games%ROWTYPE;
  st jsonb;
  v_slot INT;
  v_dice INT;
  v_uid UUID := auth.uid();
  v_user UUID;
  v_isbot BOOLEAN;
  arr jsonb;
  pawn jsonb;
  i INT;
  pstate TEXT;
  pstep INT;
  has_move BOOLEAN := FALSE;
  v_new_slot INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := g.state;
  v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot INTO v_user, v_isbot
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF NOT (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Lancez le de d''abord'; END IF;
  v_dice := (st->>'dice')::INT;
  arr := st->'pawns'->v_slot::text;
  FOR i IN 0..3 LOOP
    pawn := arr->i;
    pstate := pawn->>'s';
    pstep := COALESCE((pawn->>'k')::INT, -1);
    IF pstate='finished' THEN CONTINUE; END IF;
    IF pstate='yard' THEN
      IF v_dice = 6 THEN has_move := TRUE; EXIT; END IF;
    ELSIF pstate='track' THEN
      IF pstep + v_dice <= 56 THEN has_move := TRUE; EXIT; END IF;
    END IF;
  END LOOP;
  IF has_move THEN RAISE EXCEPTION 'Vous avez un coup possible'; END IF;

  UPDATE public.ludo_participants SET consecutive_sixes = 0
    WHERE game_id = _game_id AND slot = v_slot;

  IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
    st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
  END IF;

  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := jsonb_set(st,'{dice}','null'::jsonb);
  v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
  st := public._ludo_clear_shield(st, v_new_slot);
  st := jsonb_set(st,'{turn_slot}', to_jsonb(v_new_slot));
  st := jsonb_set(st,'{turn_seq}', to_jsonb(COALESCE((st->>'turn_seq')::int, 0) + 1));
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('pass'::text));
  st := st - 'no_move_display' - 'power_event' - 'movable_pawns';
  st := jsonb_set(st, '{no_move_streak}', to_jsonb(COALESCE((st->>'no_move_streak')::int, 0) + 1));
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  PERFORM public._ludo_check_game_over(_game_id);
  RETURN st;
END;
$function$;

-- ludo_bot_play: increment turn_seq on pass + use milliseconds in timestamps
CREATE OR REPLACE FUNCTION public.ludo_bot_play(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_slot INT; v_isbot BOOLEAN;
  v_intel INT; v_dice INT; arr jsonb; pawn jsonb;
  i INT; k INT; best INT := -1; best_score INT := -1; sc INT;
  pstate TEXT; pstep INT; abs_cell INT; start_idx INT;
  other_slot INT; op jsonb; op_step INT; op_start INT; would_capture BOOLEAN;
  candidates INT[] := ARRAY[]::INT[];
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;
  SELECT is_bot, bot_intelligence INTO v_isbot, v_intel
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot THEN RETURN st; END IF;

  IF NOT (st->>'must_move')::BOOLEAN THEN
    v_dice := 1 + (floor(random()*6))::INT;
    st := jsonb_set(st,'{dice}', to_jsonb(v_dice));
    st := jsonb_set(st,'{must_move}','true'::jsonb);
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('bot_roll:'||v_dice));
    UPDATE public.ludo_games SET state=st WHERE id=_game_id;
  ELSE
    v_dice := (st->>'dice')::INT;
  END IF;

  arr := st->'pawns'->v_slot::text;
  start_idx := public._ludo_start_idx(v_slot);
  FOR i IN 0..3 LOOP
    pawn := arr->i; pstate := pawn->>'s'; pstep := (pawn->>'k')::INT;
    IF pstate='finished' THEN CONTINUE; END IF;
    IF pstate='yard' THEN
      IF v_dice = 6 THEN candidates := candidates || i; END IF;
    ELSE
      IF pstep + v_dice <= 56 THEN candidates := candidates || i; END IF;
    END IF;
  END LOOP;

  IF array_length(candidates,1) IS NULL THEN
    UPDATE public.ludo_participants SET consecutive_sixes = 0
      WHERE game_id = _game_id AND slot = v_slot;
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st,'{turn_seq}', to_jsonb(COALESCE((st->>'turn_seq')::int, 0) + 1));
    st := jsonb_set(st,'{last_event}', to_jsonb('bot:pass'));
    st := st - 'movable_pawns' - 'no_move_display';
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
    PERFORM public._ludo_check_game_over(_game_id);
    RETURN st;
  END IF;

  IF (random()*100) < COALESCE(v_intel,70) THEN
    FOREACH i IN ARRAY candidates LOOP
      pawn := arr->i; pstate := pawn->>'s'; pstep := (pawn->>'k')::INT;
      IF pstate='yard' THEN sc := 60;
      ELSIF pstep + v_dice = 56 THEN sc := 80;
      ELSE
        would_capture := FALSE;
        IF pstep + v_dice <= 50 THEN
          abs_cell := (start_idx + pstep + v_dice) % 52;
          IF NOT public._ludo_is_safe(abs_cell) THEN
            FOR other_slot IN 0..g.max_players-1 LOOP
              IF other_slot <> v_slot THEN
                op_start := public._ludo_start_idx(other_slot);
                FOR k IN 0..3 LOOP
                  op := st->'pawns'->other_slot::text->k;
                  IF op->>'s' = 'track' THEN
                    op_step := (op->>'k')::INT;
                    IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
                      would_capture := TRUE;
                    END IF;
                  END IF;
                END LOOP;
              END IF;
            END LOOP;
          END IF;
        END IF;
        sc := pstep + v_dice + CASE WHEN would_capture THEN 100 ELSE 0 END;
      END IF;
      IF sc > best_score THEN best_score := sc; best := i; END IF;
    END LOOP;
  ELSE
    best := candidates[1 + (floor(random()*array_length(candidates,1)))::INT];
  END IF;

  RETURN public.ludo_move(_game_id, best);
END $function$;
