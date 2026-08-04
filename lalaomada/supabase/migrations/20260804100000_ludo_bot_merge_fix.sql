-- ============================================================
-- Migration: Merge ludo_bot_play bug fixes with groupe 2v2 support
--
-- PROBLEM: Migration 20260803210000 (groupe 2v2) overwrote ludo_bot_play
-- with the OLD version, reintroducing ALL bugs fixed in 20260803150000:
--   - Bot rolls own dice with random() instead of calling ludo_roll()
--   - No triple-six tracking, no consecutive_sixes reset
--   - No stack detection (tries to capture 2+ pawns)
--   - No dice_override support
--
-- FIX: Merge both: use ludo_roll() from 150000 + team checks from 210000
-- ============================================================

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
  would_capture BOOLEAN;
  op_count INT;
  candidates INT[] := ARRAY[]::INT[];
  v_consec INT;
  v_team INT;
  v_is_groupe BOOLEAN;
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

  -- ── ROLL PHASE: use ludo_roll (handles consecutive_sixes, triple-six, etc.) ──
  IF NOT (st->>'must_move')::BOOLEAN THEN
    st := public.ludo_roll(_game_id);

    -- ludo_roll may have auto-skipped (no legal moves) or triple-sixed
    IF NOT (st->>'must_move')::BOOLEAN THEN
      RETURN st;
    END IF;

    -- Refetch game state after ludo_roll
    SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
    v_dice := (st->>'dice')::INT;
  ELSE
    v_dice := (st->>'dice')::INT;
  END IF;

  -- ── MOVE PHASE: find candidate pawns ─────────────────────────────────
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

  -- ── AI: score each candidate ─────────────────────────────────────────
  IF (random()*100) < COALESCE(v_intel,70) THEN
    -- Smart selection
    FOREACH i IN ARRAY candidates LOOP
      pawn := arr->i;
      pstate := pawn->>'s';
      pstep := (pawn->>'k')::INT;

      IF pstate = 'yard' THEN
        sc := 60;
      ELSIF pstep + v_dice = 56 THEN
        sc := 100;  -- finishing is best
      ELSE
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
        sc := pstep + v_dice + CASE WHEN would_capture THEN 100 ELSE 0 END;
      END IF;

      IF sc > best_score THEN best_score := sc; best := i; END IF;
    END LOOP;
  ELSE
    -- Random selection
    best := candidates[1 + floor(random() * array_length(candidates,1))::INT];
  END IF;

  IF best < 0 THEN best := candidates[1]; END IF;

  -- ── EXECUTE MOVE ─────────────────────────────────────────────────────
  RETURN public.ludo_move(_game_id, best);
END $function$;

REVOKE ALL ON FUNCTION public.ludo_bot_play(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ludo_bot_play(uuid) TO authenticated;
