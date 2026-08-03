-- ============================================================
-- Migration: Fix bot timing — split roll/move into separate ticks
--
-- PROBLEM: The bot rolled AND moved in the same tick (same ludo_bot_play call),
-- and ludo_tick_all used a LOOP to play bonus turns instantly.
-- Result: bot plays everything in <1 second, no animation time, no "thinking".
--
-- FIX:
-- 1. ludo_bot_play now does ONE action per call:
--    - must_move=false → roll only, return immediately
--    - must_move=true  → move only
-- 2. ludo_tick_all no longer loops. It does ONE action per tick:
--    - Roll phase: wait ≥1s after turn_started_at (natural startup delay)
--    - Move phase: wait ≥2s after roll (simulates thinking before choosing pawn)
-- 3. With the 5s cron tick, this gives ~5s between roll and move,
--    ~5s between bonus roll and next move — human-like rhythm.
--
-- TIMING FLOW:
--   Tick 0: human moves → turn passes to bot (must_move=false)
--   Tick 1 (≤5s later): bot rolls (must_move=true, turn_started_at=now)
--   Tick 2 (≤5s later): bot moves (≥2s since roll ✓)
--     → If bonus (6/capture/finish): must_move=false, turn_started_at=now
--   Tick 3 (≤5s later): bot rolls again (≥1s ✓)
--   Tick 4 (≤5s later): bot moves again (≥2s ✓)
--     → If no bonus: turn passes to next player
-- ============================================================

-- ═══════════════════════════════════════════════════════════
-- ludo_bot_play: ONE action per call (roll OR move, not both)
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ludo_bot_play(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
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
  j INT;
  k INT;
  best INT := -1;
  sc INT;
  pstate TEXT;
  pstep INT;
  new_step INT;
  abs_cell INT;
  new_abs_cell INT;
  start_idx INT;
  rec RECORD;
  op jsonb;
  op_step INT;
  op_start INT;
  op_abs INT;
  dist INT;
  would_capture BOOLEAN;
  op_count INT;
  candidates INT[] := ARRAY[]::INT[];
  scores INT[] := ARRAY[]::INT[];
  v_in_danger BOOLEAN;
  v_will_danger BOOLEAN;
  own_count INT;
  v_n INT;
  v_roll INT;
  v_tmp INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;

  SELECT is_bot, bot_intelligence, bot_win_bias
    INTO v_isbot, v_intel, v_bias
    FROM public.ludo_participants
    WHERE game_id=_game_id AND slot=v_slot;

  IF NOT v_isbot THEN RETURN st; END IF;

  -- ═══ ROLL PHASE: roll the dice and RETURN (don't move yet) ═════════
  IF NOT (st->>'must_move')::BOOLEAN THEN
    RETURN public.ludo_roll(_game_id);
  END IF;

  -- ═══ MOVE PHASE: choose and execute the best pawn move ═════════════
  v_dice := (st->>'dice')::INT;
  arr := st->'pawns'->v_slot::text;
  start_idx := public._ludo_start_for(_game_id, v_slot);

  -- Find candidates
  FOR i IN 0..3 LOOP
    pawn := arr->i;
    pstate := pawn->>'s';
    pstep := (pawn->>'k')::INT;
    IF pstate = 'finished' THEN CONTINUE; END IF;
    IF pstate = 'yard' THEN
      IF v_dice = 6 THEN candidates := candidates || i; END IF;
    ELSE
      IF pstep + v_dice <= 56 THEN candidates := candidates || i; END IF;
    END IF;
  END LOOP;

  -- No candidates → pass
  IF array_length(candidates,1) IS NULL THEN
    UPDATE public.ludo_participants SET consecutive_sixes = 0
      WHERE game_id = _game_id AND slot = v_slot;
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('bot:pass'));
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
    RETURN st;
  END IF;

  -- ── AI: score each candidate with human-like heuristics ──────────────
  FOREACH i IN ARRAY candidates LOOP
    pawn := arr->i;
    pstate := pawn->>'s';
    pstep := (pawn->>'k')::INT;
    sc := 0;

    IF pstate = 'yard' THEN
      sc := 50;
    ELSIF pstep + v_dice = 56 THEN
      sc := 120;
    ELSE
      new_step := pstep + v_dice;
      sc := new_step * 3;

      IF new_step <= 50 THEN
        new_abs_cell := (start_idx + new_step) % 52;

        -- Capture detection
        would_capture := FALSE;
        op_count := 0;
        FOR rec IN SELECT slot FROM public.ludo_participants
                    WHERE game_id=_game_id AND slot <> v_slot LOOP
          op_start := public._ludo_start_for(_game_id, rec.slot);
          FOR k IN 0..3 LOOP
            op := st->'pawns'->rec.slot::text->k;
            IF op->>'s' = 'track' THEN
              op_step := (op->>'k')::INT;
              IF op_step <= 50 AND ((op_start + op_step) % 52) = new_abs_cell THEN
                op_count := op_count + 1;
              END IF;
            END IF;
          END LOOP;
        END LOOP;
        would_capture := (op_count = 1);
        IF would_capture THEN
          sc := sc + 80;
        END IF;

        -- Safe landing bonus
        IF public._ludo_is_safe(new_abs_cell) THEN
          sc := sc + 25;
        END IF;

        -- Block creation bonus
        own_count := 1;
        FOR j IN 0..3 LOOP
          IF j <> i THEN
            op := arr->j;
            IF op->>'s' = 'track' THEN
              op_step := (op->>'k')::INT;
              IF op_step = new_step THEN own_count := own_count + 1; END IF;
            END IF;
          END IF;
        END LOOP;
        IF own_count >= 2 THEN
          sc := sc + 15;
        END IF;

        -- New danger check
        IF NOT public._ludo_is_safe(new_abs_cell) AND NOT would_capture THEN
          v_will_danger := FALSE;
          FOR rec IN SELECT slot FROM public.ludo_participants
                      WHERE game_id=_game_id AND slot <> v_slot LOOP
            op_start := public._ludo_start_for(_game_id, rec.slot);
            FOR k IN 0..3 LOOP
              op := st->'pawns'->rec.slot::text->k;
              IF op->>'s' = 'track' THEN
                op_step := (op->>'k')::INT;
                IF op_step <= 50 THEN
                  op_abs := (op_start + op_step) % 52;
                  dist := (new_abs_cell - op_abs + 52) % 52;
                  IF dist >= 1 AND dist <= 6 AND (op_step + dist) <= 50 THEN
                    v_will_danger := TRUE;
                  END IF;
                END IF;
              END IF;
            END LOOP;
          END LOOP;
          IF v_will_danger THEN
            sc := sc - 30;
          END IF;
        END IF;
      END IF;

      -- Danger escape: is current pawn in danger?
      IF pstep <= 50 THEN
        abs_cell := (start_idx + pstep) % 52;
        IF NOT public._ludo_is_safe(abs_cell) THEN
          v_in_danger := FALSE;
          FOR rec IN SELECT slot FROM public.ludo_participants
                      WHERE game_id=_game_id AND slot <> v_slot LOOP
            op_start := public._ludo_start_for(_game_id, rec.slot);
            FOR k IN 0..3 LOOP
              op := st->'pawns'->rec.slot::text->k;
              IF op->>'s' = 'track' THEN
                op_step := (op->>'k')::INT;
                IF op_step <= 50 THEN
                  op_abs := (op_start + op_step) % 52;
                  dist := (abs_cell - op_abs + 52) % 52;
                  IF dist >= 1 AND dist <= 6 AND (op_step + dist) <= 50 THEN
                    v_in_danger := TRUE;
                  END IF;
                END IF;
              END IF;
            END LOOP;
          END LOOP;
          IF v_in_danger THEN
            IF new_step > 50 THEN
              sc := sc + 60;
            ELSIF public._ludo_is_safe((start_idx + new_step) % 52) THEN
              sc := sc + 50;
            ELSE
              sc := sc + 15;
            END IF;
          END IF;
        END IF;
      END IF;
    END IF;

    -- Random noise for human inconsistency (±3)
    sc := sc + (floor(random() * 7)::INT - 3);
    scores := scores || sc;
  END LOOP;

  -- ── SELECTION: sort by score, pick based on intelligence ─────────────
  v_n := array_length(candidates, 1);

  -- Bubble sort by score descending (max 4 items)
  FOR i IN 1..v_n-1 LOOP
    FOR j IN 1..v_n-i LOOP
      IF scores[j] < scores[j+1] THEN
        v_tmp := candidates[j]; candidates[j] := candidates[j+1]; candidates[j+1] := v_tmp;
        v_tmp := scores[j]; scores[j] := scores[j+1]; scores[j+1] := v_tmp;
      END IF;
    END LOOP;
  END LOOP;

  v_roll := (random() * 100)::INT;
  IF v_roll < COALESCE(v_intel, 70) THEN
    -- Smart: best move, 15% chance 2nd best (human error)
    IF v_n > 1 AND (random() * 100)::INT < 15 THEN
      best := candidates[2];
    ELSE
      best := candidates[1];
    END IF;
  ELSE
    -- Imperfect: weighted top-3
    IF v_n = 1 THEN
      best := candidates[1];
    ELSIF v_n = 2 THEN
      IF (random() * 100)::INT < 60 THEN
        best := candidates[1];
      ELSE
        best := candidates[2];
      END IF;
    ELSE
      v_roll := (random() * 100)::INT;
      IF v_roll < 50 THEN best := candidates[1];
      ELSIF v_roll < 83 THEN best := candidates[2];
      ELSE best := candidates[3];
      END IF;
    END IF;
  END IF;

  -- ── EXECUTE MOVE ─────────────────────────────────────────────────────
  RETURN public.ludo_move(_game_id, best);
END $function$;

-- ═══════════════════════════════════════════════════════════
-- ludo_tick_all: ONE action per tick, with delays
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ludo_tick_all()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  g_id UUID;
  v_slot INT;
  v_isbot BOOLEAN;
  v_started TIMESTAMPTZ;
  st JSONB;
BEGIN
  FOR g_id IN SELECT id FROM public.ludo_games WHERE status='playing' LOOP
    BEGIN
      -- Auto-forfeit / pass on timeout (server-authoritative)
      PERFORM public.ludo_check_timeout(g_id);

      -- After potential timeout, refetch turn
      SELECT state INTO st FROM public.ludo_games WHERE id=g_id;
      IF st IS NULL THEN CONTINUE; END IF;
      v_slot := (st->>'turn_slot')::INT;
      SELECT is_bot INTO v_isbot FROM public.ludo_participants
        WHERE game_id=g_id AND slot=v_slot;

      -- Bot: ONE action per tick, with natural delays
      IF v_isbot THEN
        v_started := (st->>'turn_started_at')::TIMESTAMPTZ;

        IF NOT (st->>'must_move')::BOOLEAN THEN
          -- ROLL phase: wait ≥1s after turn started before rolling
          -- (natural startup delay, lets client show it's bot's turn)
          IF now() - v_started >= interval '1 second' THEN
            PERFORM public.ludo_bot_play(g_id);
          END IF;
        ELSE
          -- MOVE phase: wait ≥2s after roll before moving
          -- (simulates thinking time, lets dice animation play)
          IF now() - v_started >= interval '2 seconds' THEN
            PERFORM public.ludo_bot_play(g_id);
          END IF;
        END IF;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
END $function$;

-- Revoke/grant
REVOKE EXECUTE ON FUNCTION public.ludo_bot_play(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.ludo_bot_play(uuid) TO authenticated;
