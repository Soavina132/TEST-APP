-- ============================================================
-- Migration: Human-like Ludo bot AI
--
-- PROBLEM: The bot played in a robotic, non-human way:
--   1. Only 3 scoring criteria (yard exit=60, finish=100, capture=+100)
--   2. "Dumb mode" = pure random — humans never play purely randomly
--   3. No danger awareness — bot ignores pawns about to be captured
--   4. No safe-square preference — humans seek star cells
--   5. Always picks the best in smart mode — too predictable
--   6. No block management — humans create/keep pawn pairs for safety
--
-- IMPROVEMENTS:
--   1. Weighted progress scoring (new_step * 3)
--   2. Danger detection: if pawn is currently capturable (opponent within 1-6
--      cells behind on track), prioritize moving it to safety
--   3. Danger penalty: if move would land in a capturable position, apply -30
--   4. Safe landing bonus: +25 for landing on star cells
--   5. Block creation bonus: +15 for joining another own pawn on same cell
--   6. Capture bonus: +80 (slightly less than finish=120 so escaping danger
--      to home can sometimes override a capture)
--   7. Human-like selection: intelligence now controls consistency, not a
--      binary smart/dumb switch. Low intel = more variance but still
--      prefers better moves (weighted top-3, not pure random).
--   8. Small random noise (±3) on every score for human inconsistency
--   9. 15% "human error" even in smart mode (picks 2nd best)
-- ============================================================

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
  best_score INT := -999;
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
  v_consec INT;
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

  SELECT is_bot, bot_intelligence, bot_win_bias, consecutive_sixes
    INTO v_isbot, v_intel, v_bias, v_consec
    FROM public.ludo_participants
    WHERE game_id=_game_id AND slot=v_slot;

  IF NOT v_isbot THEN RETURN st; END IF;

  -- ── ROLL PHASE: use ludo_roll ────────────────────────────────────────
  IF NOT (st->>'must_move')::BOOLEAN THEN
    st := public.ludo_roll(_game_id);
    IF NOT (st->>'must_move')::BOOLEAN THEN
      RETURN st;
    END IF;
    SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
    v_dice := (st->>'dice')::INT;
  ELSE
    v_dice := (st->>'dice')::INT;
  END IF;

  -- ── MOVE PHASE: find candidates ─────────────────────────────────────
  arr := st->'pawns'->v_slot::text;
  start_idx := public._ludo_start_for(_game_id, v_slot);

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
      -- Getting a pawn out is decent but not always the best move
      sc := 50;
    ELSIF pstep + v_dice = 56 THEN
      -- Finishing a pawn — highest priority
      sc := 120;
    ELSE
      new_step := pstep + v_dice;
      -- Base score: weighted progress (further along = more important to advance)
      sc := new_step * 3;

      IF new_step <= 50 THEN
        new_abs_cell := (start_idx + new_step) % 52;

        -- ── Capture detection ──
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

        -- ── Safe landing bonus (star cells) ──
        IF public._ludo_is_safe(new_abs_cell) THEN
          sc := sc + 25;
        END IF;

        -- ── Block creation: joining another own pawn = safe from capture ──
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

        -- ── New danger check: will pawn be capturable at new position? ──
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
                  -- Opponent can capture if distance is 1-6 AND they stay on track
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

      -- ── Danger escape: is current pawn in danger right now? ──
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
            -- Pawn is threatened! Escaping is a high priority.
            IF new_step > 50 THEN
              sc := sc + 60;  -- entering home stretch = fully safe escape
            ELSIF public._ludo_is_safe((start_idx + new_step) % 52) THEN
              sc := sc + 50;  -- landing on safe cell = good escape
            ELSE
              sc := sc + 15;  -- at least moving away (may still be in danger)
            END IF;
          END IF;
        END IF;
      END IF;
    END IF;

    -- Small random noise for human inconsistency (±3)
    sc := sc + (floor(random() * 7)::INT - 3);

    scores := scores || sc;
  END LOOP;

  -- ── SELECTION: human-like, intelligence controls consistency ────────
  v_n := array_length(candidates, 1);

  -- Sort candidates by score descending (simple bubble sort, max 4 items)
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
    -- Smart play: pick best, but 15% chance to pick 2nd best (human error)
    IF v_n > 1 AND (random() * 100)::INT < 15 THEN
      best := candidates[2];
    ELSE
      best := candidates[1];
    END IF;
  ELSE
    -- Imperfect play: weighted top-3 (not pure random — still prefers better)
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
      IF v_roll < 50 THEN
        best := candidates[1];
      ELSIF v_roll < 83 THEN
        best := candidates[2];
      ELSE
        best := candidates[3];
      END IF;
    END IF;
  END IF;

  -- ── EXECUTE MOVE ─────────────────────────────────────────────────────
  RETURN public.ludo_move(_game_id, best);
END $function$;

-- Revoke from anon, grant to authenticated
REVOKE EXECUTE ON FUNCTION public.ludo_bot_play(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.ludo_bot_play(uuid) TO authenticated;
