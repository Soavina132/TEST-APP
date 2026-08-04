-- ============================================================
-- Migration: Split ludo_bot_play into roll+move phases + smarter AI
--
-- CHANGES:
--   1. ludo_bot_play now does ONLY the roll when must_move=false
--      and ONLY the move when must_move=true
--      → Frontend can display the dice before the bot moves
--   2. Improved AI scoring:
--      - Escape danger (if opponent can capture us next turn)
--      - Prefer safe cells (star cells)
--      - Prioritize finishing pawns
--      - Early game: get pawns out of yard
--      - Smart capture decisions
--      - Don't land next to an opponent who has a pawn 1-6 behind
-- ============================================================

CREATE OR REPLACE FUNCTION public.ludo_bot_play(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
  op_count INT;
  candidates INT[] := ARRAY[]::INT[];
  v_consec INT;
  v_team INT;
  v_is_groupe BOOLEAN;
  v_danger_bonus INT;
  v_safe_bonus INT;
  v_yard_count INT;
  v_onboard_count INT;
  v_finished_count INT;
  dist_to_home INT;
  op_dist_behind INT;
  v_rolls_since_start INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;
  v_is_groupe := (g.match_type = 'groupe');

  SELECT is_bot, bot_intelligence, bot_win_bias, consecutive_sixes, team
    INTO v_isbot, v_intel, v_bias, v_consec, v_team
    FROM public.ludo_participants
    WHERE game_id=_game_id AND slot=v_slot;

  IF NOT v_isbot THEN RETURN st; END IF;

  -- ═══════════════════════════════════════════════════════════════════
  -- PHASE 1: ROLL ONLY (if must_move = false)
  -- ═══════════════════════════════════════════════════════════════════
  IF NOT (st->>'must_move')::BOOLEAN THEN
    -- Roll the dice via ludo_roll (handles consecutive sixes, triple-six, etc.)
    st := public.ludo_roll(_game_id);
    -- ludo_roll may auto-skip (no legal moves) or triple-six → just return
    RETURN st;
  END IF;

  -- ═══════════════════════════════════════════════════════════════════
  -- PHASE 2: MOVE ONLY (must_move = true)
  -- ═══════════════════════════════════════════════════════════════════

  -- Refetch state after roll
  SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
  v_dice := (st->>'dice')::INT;
  IF v_dice IS NULL THEN RETURN st; END IF;

  arr := st->'pawns'->v_slot::text;
  start_idx := public._ludo_start_for(_game_id, v_slot);

  -- ── Count pawns in each state ──────────────────────────────────────
  v_yard_count := 0; v_onboard_count := 0; v_finished_count := 0;
  FOR i IN 0..3 LOOP
    pawn := arr->i;
    pstate := pawn->>'s';
    IF pstate = 'yard' THEN v_yard_count := v_yard_count + 1;
    ELSIF pstate = 'finished' THEN v_finished_count := v_finished_count + 1;
    ELSE v_onboard_count := v_onboard_count + 1; END IF;
  END LOOP;

  -- ── Find candidate pawns ───────────────────────────────────────────
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

  -- ── AI: score each candidate ───────────────────────────────────────
  IF (random()*100) < COALESCE(v_intel,70) THEN
    -- ══ SMART SELECTION ══════════════════════════════════════════════
    FOREACH i IN ARRAY candidates LOOP
      pawn := arr->i;
      pstate := pawn->>'s';
      pstep := (pawn->>'k')::INT;
      sc := 0;

      IF pstate = 'yard' AND v_dice = 6 THEN
        -- Getting a pawn out of yard
        sc := 50;
        -- Early game bonus: if we have 3+ in yard, prioritize getting them out
        IF v_yard_count >= 3 THEN sc := sc + 30; END IF;
        IF v_yard_count = 4 THEN sc := sc + 20; END IF; -- all in yard, must get one out
        -- If we have no pawns on board, getting one out is very important
        IF v_onboard_count = 0 THEN sc := sc + 25; END IF;

      ELSIF pstep + v_dice = 56 THEN
        -- Finishing a pawn = highest priority
        sc := 200;

      ELSE
        -- Base score: progress made
        sc := pstep + v_dice;

        -- Check capture
        would_capture := FALSE;
        IF pstep + v_dice <= 50 THEN
          abs_cell := (start_idx + pstep + v_dice) % 52;
          IF NOT public._ludo_is_safe(abs_cell) THEN
            op_count := 0;
            FOR rec IN SELECT slot, team FROM public.ludo_participants
                        WHERE game_id=_game_id AND slot <> v_slot LOOP
              -- Skip teammates in groupe mode
              IF v_is_groupe AND rec.team IS NOT NULL AND rec.team = v_team THEN
                CONTINUE;
              END IF;
              op_start := public._ludo_start_for(_game_id, rec.slot);
              FOR k IN 0..3 LOOP
                op := st->'pawns'->rec.slot::text->k;
                IF op->>'s' = 'track' THEN
                  op_step := (op->>'k')::INT;
                  IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
                    op_count := op_count + 1;
                  END IF;
                END IF;
              END LOOP;
            END LOOP;
            -- Only capture if exactly 1 pawn (not a stack of 2+)
            would_capture := (op_count = 1);
          END IF;
        END IF;

        -- Capture bonus
        IF would_capture THEN
          sc := sc + 80;
          -- Extra bonus if capturing a pawn that's far along (more damaging to opponent)
          -- We already know op_count=1, find which one
          FOR rec IN SELECT slot, team FROM public.ludo_participants
                      WHERE game_id=_game_id AND slot <> v_slot LOOP
            IF v_is_groupe AND rec.team IS NOT NULL AND rec.team = v_team THEN CONTINUE; END IF;
            op_start := public._ludo_start_for(_game_id, rec.slot);
            FOR k IN 0..3 LOOP
              op := st->'pawns'->rec.slot::text->k;
              IF op->>'s' = 'track' THEN
                op_step := (op->>'k')::INT;
                IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
                  -- Bonus for capturing advanced pawns
                  sc := sc + op_step;
                END IF;
              END IF;
            END LOOP;
          END LOOP;
        END IF;

        -- Safe cell bonus: landing on a star cell
        IF pstep + v_dice <= 50 THEN
          abs_cell := (start_idx + pstep + v_dice) % 52;
          IF public._ludo_is_safe(abs_cell) THEN
            sc := sc + 25;
          END IF;
        END IF;

        -- Danger avoidance: if current pawn is on an unsafe cell and an opponent
        -- is 1-6 cells behind, bonus for moving it away
        IF pstate = 'track' AND pstep <= 50 THEN
          abs_cell := (start_idx + pstep) % 52;
          IF NOT public._ludo_is_safe(abs_cell) THEN
            FOR rec IN SELECT slot, team FROM public.ludo_participants
                        WHERE game_id=_game_id AND slot <> v_slot LOOP
              IF v_is_groupe AND rec.team IS NOT NULL AND rec.team = v_team THEN CONTINUE; END IF;
              op_start := public._ludo_start_for(_game_id, rec.slot);
              FOR k IN 0..3 LOOP
                op := st->'pawns'->rec.slot::text->k;
                IF op->>'s' = 'track' THEN
                  op_step := (op->>'k')::INT;
                  op_abs := (op_start + op_step) % 52;
                  -- Check if opponent is 1-6 cells behind us on the track
                  op_dist_behind := (abs_cell - op_abs + 52) % 52;
                  IF op_dist_behind >= 1 AND op_dist_behind <= 6 THEN
                    -- This pawn is in danger! Bonus for moving it
                    sc := sc + 40;
                  END IF;
                END IF;
              END LOOP;
            END LOOP;
          END IF;
        END IF;

        -- Home stretch bonus: pawns in the home stretch (k > 50) are safe, small bonus
        IF pstep > 50 THEN
          sc := sc + 15;
        END IF;

        -- Progress bonus: prefer advancing pawns that are further along
        sc := sc + (pstep * 2);
      END IF;

      IF sc > best_score THEN best_score := sc; best := i; END IF;
    END LOOP;
  ELSE
    -- ══ RANDOM SELECTION (dumber) ═════════════════════════════════════
    best := candidates[1 + floor(random() * array_length(candidates,1))::INT];
  END IF;

  IF best < 0 THEN best := candidates[1]; END IF;

  -- ── EXECUTE MOVE ───────────────────────────────────────────────────
  RETURN public.ludo_move(_game_id, best);
END $$;

REVOKE EXECUTE ON FUNCTION public.ludo_bot_play(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.ludo_bot_play(uuid) TO authenticated;
