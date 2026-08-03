-- Improve Ludo bot AI: strategic decision-making instead of random play
-- Priority: win > capture > exit yard (on 6) > advance home stretch > avoid danger > furthest pawn

CREATE OR REPLACE FUNCTION public.ludo_bot_play(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
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
  -- Heuristic scores
  SCORE_WIN        INT := 1000;
  SCORE_CAPTURE    INT := 500;
  SCORE_EXIT_YARD  INT := 200;
  SCORE_HOME_STRETCH INT := 150;
  SCORE_DANGER_BONUS INT := 80;  -- bonus for leaving a dangerous spot
  SCORE_ADVANCE    INT := 10;    -- per step forward
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;

  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;

  SELECT is_bot, bot_intelligence, bot_win_bias
    INTO v_isbot, v_intel, v_bias
    FROM public.ludo_participants
    WHERE game_id = _game_id AND slot = v_slot;

  IF NOT v_isbot THEN RETURN st; END IF;

  -- ── Roll if needed ──
  IF NOT (st->>'must_move')::BOOLEAN THEN
    v_dice := 1 + (floor(random() * 6))::INT;
    -- Win bias: chance to force a 6
    IF COALESCE(v_bias, 0) > 0 AND (random() * 100) < v_bias THEN
      v_dice := 6;
    END IF;
    st := jsonb_set(st, '{dice}', to_jsonb(v_dice));
    st := jsonb_set(st, '{must_move}', 'true'::jsonb);
    st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    st := jsonb_set(st, '{last_event}', to_jsonb('bot_roll:' || v_dice));
    UPDATE public.ludo_games SET state = st WHERE id = _game_id;
  ELSE
    v_dice := (st->>'dice')::INT;
  END IF;

  -- ── Find all playable pawns ──
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

  -- No valid move → pass
  IF array_length(candidates, 1) IS NULL THEN
    st := jsonb_set(st, '{must_move}', 'false'::jsonb);
    st := jsonb_set(st, '{dice}', 'null'::jsonb);
    st := jsonb_set(st, '{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    st := jsonb_set(st, '{last_event}', to_jsonb('bot:pass'));
    UPDATE public.ludo_games SET state = st, current_turn = (st->>'turn_slot')::INT WHERE id = _game_id;
    RETURN st;
  END IF;

  -- ── Intelligence check: with probability v_intel%, use smart strategy; else random ──
  IF (random() * 100) < COALESCE(v_intel, 75) THEN
    -- ── SMART STRATEGY ──
    FOREACH i IN ARRAY candidates LOOP
      pawn := arr->i;
      pstate := pawn->>'s';
      pstep := COALESCE((pawn->>'k')::INT, 0);
      sc := 0;

      -- Priority 1: WIN — pawn reaches finish (k=56)
      IF pstate = 'track' AND pstep + v_dice = 56 THEN
        sc := SCORE_WIN;
      -- Priority 2: CAPTURE — pawn lands on opponent's cell (non-safe)
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
        sc := sc + pstep * SCORE_ADVANCE;  -- tie-break: furthest pawn

        -- Priority 5: DANGER AVOIDANCE — if current position is dangerous, bonus for moving
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
                  -- Check if opponent is within 6 cells behind us (can capture next turn)
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
      -- Priority 3: EXIT YARD — on a 6, get a pawn out
      ELSIF pstate = 'yard' THEN
        sc := SCORE_EXIT_YARD;
      -- Priority 4: HOME STRETCH — advance pawns in the home stretch (k >= 51)
      ELSIF pstate = 'track' AND pstep >= 51 THEN
        sc := SCORE_HOME_STRETCH + pstep * SCORE_ADVANCE;
      ELSE
        -- Default: advance furthest pawn
        sc := pstep * SCORE_ADVANCE;
      END IF;

      IF sc > best_score THEN
        best_score := sc;
        best := i;
      END IF;
    END LOOP;
  ELSE
    -- ── RANDOM PLAY (low intelligence) ──
    best := candidates[1 + (floor(random() * array_length(candidates, 1)))::INT];
  END IF;

  -- Safety fallback
  IF best < 0 AND array_length(candidates, 1) >= 1 THEN
    best := candidates[1];
  END IF;

  RETURN public.ludo_move(_game_id, best);
END $function$;
