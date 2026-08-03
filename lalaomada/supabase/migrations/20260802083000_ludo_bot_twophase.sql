-- Split ludo_bot_play into two phases:
-- Phase 1 (must_move=false): roll the dice, set must_move=true, RETURN (don't move yet)
-- Phase 2 (must_move=true): find best pawn, call ludo_move
-- This lets the frontend show the dice result between roll and move.

CREATE OR REPLACE FUNCTION public.ludo_bot_play(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  g public.ludo_games%ROWTYPE;
  st jsonb;
  v_slot INT;
  v_isbot BOOLEAN;
  v_intel INT;
  v_bias INT;
  v_dice INT;
  v_consec INT;
  arr jsonb;
  pawn jsonb;
  i INT;
  k INT;
  best INT := -1;
  best_score INT := -1;
  sc INT;
  pstate TEXT;
  pstep INT;
  abs_cell INT;
  start_idx INT;
  rec RECORD;
  op jsonb;
  op_step INT;
  op_start INT;
  op_abs INT;
  would_capture BOOLEAN;
  would_be_danger BOOLEAN;
  danger_dist INT;
  candidates INT[] := ARRAY[]::INT[];
  has_move BOOLEAN := FALSE;
  SCORE_WIN        INT := 1000;
  SCORE_CAPTURE    INT := 500;
  SCORE_EXIT_YARD  INT := 200;
  SCORE_HOME_STRETCH INT := 150;
  SCORE_DANGER_BONUS INT := 80;
  SCORE_ADVANCE    INT := 10;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;

  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;

  SELECT is_bot, bot_intelligence, bot_win_bias, consecutive_sixes
    INTO v_isbot, v_intel, v_bias, v_consec
    FROM public.ludo_participants
    WHERE game_id = _game_id AND slot = v_slot;

  IF NOT v_isbot THEN RETURN st; END IF;

  -- ══════════════════════════════════════
  -- PHASE 1: ROLL THE DICE (must_move = false)
  -- ══════════════════════════════════════
  IF NOT (st->>'must_move')::BOOLEAN THEN
    v_dice := 1 + (floor(random() * 6))::INT;
    IF COALESCE(v_bias, 0) > 0 AND (random() * 100) < v_bias THEN
      v_dice := 6;
    END IF;

    -- Track consecutive sixes
    IF v_dice = 6 THEN
      v_consec := COALESCE(v_consec, 0) + 1;
    ELSE
      v_consec := 0;
    END IF;
    UPDATE public.ludo_participants SET consecutive_sixes = v_consec
      WHERE game_id = _game_id AND slot = v_slot;

    -- Triple six → cancel turn (don't even show the dice)
    IF v_consec >= 3 THEN
      UPDATE public.ludo_participants SET consecutive_sixes = 0
        WHERE game_id = _game_id AND slot = v_slot;
      st := jsonb_set(st, '{consecutive_sixes}', '0'::jsonb);
      st := jsonb_set(st, '{must_move}', 'false'::jsonb);
      st := jsonb_set(st, '{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
      st := jsonb_set(st, '{dice}', 'null'::jsonb);
      st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')));
      st := jsonb_set(st, '{last_event}', to_jsonb('triple_six:cancel'::text));
      UPDATE public.ludo_games SET state = st, current_turn = (st->>'turn_slot')::INT WHERE id = _game_id;
      RETURN st;
    END IF;

    -- Check if any valid move exists
    arr := st->'pawns'->v_slot::text;
    FOR i IN 0..3 LOOP
      pawn := arr->i;
      pstate := pawn->>'s';
      pstep := COALESCE((pawn->>'k')::INT, 0);
      IF pstate = 'finished' THEN CONTINUE; END IF;
      IF pstate = 'yard' THEN
        IF v_dice = 6 THEN has_move := TRUE; EXIT; END IF;
      ELSE
        IF pstep + v_dice <= 56 THEN has_move := TRUE; EXIT; END IF;
      END IF;
    END LOOP;

    -- No valid move → pass immediately (show dice briefly, then skip)
    IF NOT has_move THEN
      st := jsonb_set(st, '{consecutive_sixes}', to_jsonb(v_consec));
      st := jsonb_set(st, '{dice}', to_jsonb(v_dice));
      st := jsonb_set(st, '{must_move}', 'true'::jsonb);
      st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')));
      st := jsonb_set(st, '{last_event}', to_jsonb('bot_roll:' || v_dice || ':no_move'));
      UPDATE public.ludo_games SET state = st WHERE id = _game_id;
      -- Return with dice visible + must_move=true so frontend shows the dice
      -- The next bot_play call will handle the pass
      RETURN st;
    END IF;

    -- Valid move exists → show the dice, wait for phase 2
    st := jsonb_set(st, '{consecutive_sixes}', to_jsonb(v_consec));
    st := jsonb_set(st, '{dice}', to_jsonb(v_dice));
    st := jsonb_set(st, '{must_move}', 'true'::jsonb);
    st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    st := jsonb_set(st, '{last_event}', to_jsonb('bot_roll:' || v_dice));
    UPDATE public.ludo_games SET state = st WHERE id = _game_id;
    RETURN st;  -- STOP HERE — frontend will show the dice, then call again to move
  END IF;

  -- ══════════════════════════════════════
  -- PHASE 2: MOVE A PAWN (must_move = true)
  -- ══════════════════════════════════════
  v_dice := (st->>'dice')::INT;

  -- Check if this was a "no move" roll — pass the turn
  IF st->>'last_event' = 'bot_roll:' || v_dice || ':no_move'
     OR st->>'last_event' LIKE '%no_move' THEN
    st := jsonb_set(st, '{must_move}', 'false'::jsonb);
    st := jsonb_set(st, '{dice}', 'null'::jsonb);
    st := jsonb_set(st, '{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    st := jsonb_set(st, '{last_event}', to_jsonb('bot:pass'));
    -- Reset consecutive_sixes only if dice was NOT 6
    IF v_dice <> 6 THEN
      UPDATE public.ludo_participants SET consecutive_sixes = 0 WHERE game_id = _game_id AND slot = v_slot;
      st := jsonb_set(st, '{consecutive_sixes}', '0'::jsonb);
    END IF;
    UPDATE public.ludo_games SET state = st, current_turn = (st->>'turn_slot')::INT WHERE id = _game_id;
    RETURN st;
  END IF;

  -- Find all playable pawns
  arr := st->'pawns'->v_slot::text;
  start_idx := public._ludo_start_for(_game_id, v_slot);

  FOR i IN 0..3 LOOP
    pawn := arr->i;
    pstate := pawn->>'s';
    pstep := COALESCE((pawn->>'k')::INT, 0);
    IF pstate = 'finished' THEN CONTINUE; END IF;
    IF pstate = 'yard' THEN
      IF v_dice = 6 THEN candidates := candidates || i; END IF;
    ELSE
      IF pstep + v_dice <= 56 THEN candidates := candidates || i; END IF;
    END IF;
  END LOOP;

  -- Safety: no candidates (shouldn't happen, phase 1 checked)
  IF array_length(candidates, 1) IS NULL THEN
    st := jsonb_set(st, '{must_move}', 'false'::jsonb);
    st := jsonb_set(st, '{dice}', 'null'::jsonb);
    st := jsonb_set(st, '{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    st := jsonb_set(st, '{last_event}', to_jsonb('bot:pass'));
    IF v_dice <> 6 THEN
      UPDATE public.ludo_participants SET consecutive_sixes = 0 WHERE game_id = _game_id AND slot = v_slot;
      st := jsonb_set(st, '{consecutive_sixes}', '0'::jsonb);
    END IF;
    UPDATE public.ludo_games SET state = st, current_turn = (st->>'turn_slot')::INT WHERE id = _game_id;
    RETURN st;
  END IF;

  -- ── Intelligence check ──
  IF (random() * 100) < COALESCE(v_intel, 75) THEN
    FOREACH i IN ARRAY candidates LOOP
      pawn := arr->i;
      pstate := pawn->>'s';
      pstep := COALESCE((pawn->>'k')::INT, 0);
      sc := 0;

      IF pstate = 'track' AND pstep + v_dice = 56 THEN
        sc := SCORE_WIN;
      ELSIF pstate = 'track' AND pstep + v_dice <= 50 THEN
        abs_cell := (start_idx + pstep + v_dice) % 52;
        would_capture := FALSE;
        IF NOT public._ludo_is_safe(abs_cell) THEN
          FOR rec IN SELECT slot FROM public.ludo_participants
                      WHERE game_id = _game_id AND slot <> v_slot LOOP
            op_start := public._ludo_start_for(_game_id, rec.slot);
            FOR k IN 0..3 LOOP
              op := st->'pawns'->rec.slot::text->k;
              IF op->>'s' = 'track' THEN
                op_step := COALESCE((op->>'k')::INT, 0);
                IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
                  would_capture := TRUE;
                END IF;
              END IF;
            END LOOP;
          END LOOP;
        END IF;
        sc := SCORE_CAPTURE * CASE WHEN would_capture THEN 1 ELSE 0 END;
        sc := sc + pstep * SCORE_ADVANCE;
        IF pstep <= 50 THEN
          abs_cell := (start_idx + pstep) % 52;
          IF NOT public._ludo_is_safe(abs_cell) THEN
            would_be_danger := FALSE;
            FOR rec IN SELECT slot FROM public.ludo_participants
                        WHERE game_id = _game_id AND slot <> v_slot LOOP
              op_start := public._ludo_start_for(_game_id, rec.slot);
              FOR k IN 0..3 LOOP
                op := st->'pawns'->rec.slot::text->k;
                IF op->>'s' = 'track' THEN
                  op_step := COALESCE((op->>'k')::INT, 0);
                  op_abs := (op_start + op_step) % 52;
                  danger_dist := (abs_cell - op_abs + 52) % 52;
                  IF danger_dist >= 1 AND danger_dist <= 6 THEN
                    would_be_danger := TRUE;
                  END IF;
                END IF;
              END LOOP;
            END LOOP;
            IF would_be_danger THEN
              sc := sc + SCORE_DANGER_BONUS;
            END IF;
          END IF;
        END IF;
      ELSIF pstate = 'yard' THEN
        sc := SCORE_EXIT_YARD;
      ELSIF pstate = 'track' AND pstep >= 51 THEN
        sc := SCORE_HOME_STRETCH + pstep * SCORE_ADVANCE;
      ELSE
        sc := pstep * SCORE_ADVANCE;
      END IF;

      IF sc > best_score THEN
        best_score := sc;
        best := i;
      END IF;
    END LOOP;
  ELSE
    best := candidates[1 + (floor(random() * array_length(candidates, 1)))::INT];
  END IF;

  IF best < 0 AND array_length(candidates, 1) >= 1 THEN
    best := candidates[1];
  END IF;

  RETURN public.ludo_move(_game_id, best);
END $function$;
