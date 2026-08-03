-- ============================================================
-- Migration: Fix ALL Ludo bot bugs
-- 
-- BUG 1 (CRITICAL): ludo_bot_play rolls its own dice instead of calling ludo_roll
--   → consecutive_sixes never tracked for bots (triple-six rule broken)
--   → dice_override (admin testing) ignored
--   → no-legal-moves auto-skip not triggered (wastes a full tick)
--   → phase/spin_ms not set (client animation desync)
--   FIX: call ludo_roll() for the roll phase
--
-- BUG 2 (MAJOR): ludo_bot_play doesn't handle must_move=false from ludo_roll
--   When ludo_roll auto-skips (no legal moves), it sets must_move=false and
--   advances the turn. But ludo_bot_play then tries to find candidates with
--   the old dice value. Need to detect this and return early.
--
-- BUG 3 (MAJOR): ludo_tick_all only gives bot ONE bonus replay per tick
--   If a bot rolls 6 → moves → gets another 6 → should play again.
--   The current tick only allows 1 extra call. Use a LOOP instead.
--
-- BUG 4 (MINOR): Bot AI doesn't account for stacks of 2+ opponent pawns
--   ludo_move only captures if same_slot_count = 1 (single pawn on cell).
--   Bot AI thinks it can capture when there are 2+ pawns → wrong decision.
--   FIX: count opponent pawns on target cell, adjust would_capture.
--
-- BUG 5 (MINOR): ludo_bot_play random selection crashes on single candidate
--   floor(random()*1) = 0, candidates[1+0] = candidates[1] — this is actually
--   correct in PG (1-indexed), but the code is fragile. Simplify.
--
-- BUG 6 (MAJOR): player_add_bot auto-starts with wrong state initialization
--   Uses _ludo_init_state(v_game.max_players) which doesn't include turn_seq,
--   phase, spin_ms, phase_started_at. Game state is incomplete.
--   FIX: add missing fields to _ludo_init_state.
-- ============================================================

-- ═══════════════════════════════════════════════════════════
-- FIX BUG 6: _ludo_init_state missing fields
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._ludo_init_state(_max_players INT)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE p jsonb := '{}'::jsonb; i INT;
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
  RETURN jsonb_build_object(
    'pawns', p,
    'turn_slot', 0,
    'dice', NULL,
    'must_move', false,
    'turn_started_at', to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'turn_seq', 0,
    'phase', 'spinning',
    'phase_started_at', to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'spin_ms', 0,
    'last_event', 'start');
END $function$;

-- ═══════════════════════════════════════════════════════════
-- FIX BUG 1, 2, 4, 5: Rewrite ludo_bot_play to use ludo_roll
-- ═══════════════════════════════════════════════════════════
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

  -- ── ROLL PHASE: use ludo_roll instead of manual dice ──────────────────
  IF NOT (st->>'must_move')::BOOLEAN THEN
    -- Call ludo_roll which handles: consecutive_sixes, triple-six,
    -- dice_override, no-legal-moves auto-skip, phase/spin_ms
    st := public.ludo_roll(_game_id);

    -- ludo_roll may have auto-skipped (no legal moves) or triple-sixed
    -- In that case turn has already advanced → nothing more to do
    IF NOT (st->>'must_move')::BOOLEAN THEN
      RETURN st;
    END IF;

    -- Refetch game state after ludo_roll
    SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
    v_dice := (st->>'dice')::INT;
  ELSE
    v_dice := (st->>'dice')::INT;
  END IF;

  -- ── MOVE PHASE: select best pawn ─────────────────────────────────────
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

  -- No candidates → pass (shouldn't happen if ludo_roll worked, but safety)
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
        sc := 60;  -- getting a pawn out is good
      ELSIF pstep + v_dice = 56 THEN
        sc := 100;  -- finishing a pawn is best
      ELSE
        would_capture := FALSE;
        IF pstep + v_dice <= 50 THEN
          abs_cell := (start_idx + pstep + v_dice) % 52;
          IF NOT public._ludo_is_safe(abs_cell) THEN
            -- FIX BUG 4: count actual opponent pawns on target cell
            op_count := 0;
            FOR rec IN SELECT slot FROM public.ludo_participants
                        WHERE game_id=_game_id AND slot <> v_slot LOOP
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
            -- Only count as capture if exactly 1 opponent pawn (not a stack)
            would_capture := (op_count = 1);
          END IF;
        END IF;
        -- Prioritize: capture > progress > everything else
        -- Also prioritize pawns closer to home
        sc := pstep + v_dice + CASE WHEN would_capture THEN 100 ELSE 0 END;
      END IF;

      IF sc > best_score THEN best_score := sc; best := i; END IF;
    END LOOP;
  ELSE
    -- Random selection (dumb mode)
    best := candidates[1 + floor(random() * array_length(candidates,1))::INT];
  END IF;

  -- ── EXECUTE MOVE ─────────────────────────────────────────────────────
  RETURN public.ludo_move(_game_id, best);
END $function$;

-- ═══════════════════════════════════════════════════════════
-- FIX BUG 3: ludo_tick_all — allow unlimited bonus replays for bot
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ludo_tick_all()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $function$
DECLARE
  g_id UUID;
  v_slot INT;
  v_isbot BOOLEAN;
  v_started TIMESTAMPTZ;
  st JSONB;
  v_iter INT;
  v_max_iter INT := 8;  -- safety limit to prevent infinite loops
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

      -- Bot autonomous play (no client required)
      IF v_isbot THEN
        v_iter := 0;
        LOOP
          v_iter := v_iter + 1;
          IF v_iter > v_max_iter THEN EXIT; END IF;

          PERFORM public.ludo_bot_play(g_id);

          -- Refetch state after bot play
          SELECT state INTO st FROM public.ludo_games WHERE id=g_id;
          IF st IS NULL THEN EXIT; END IF;

          -- Check if bot still has the turn and can play again
          v_slot := (st->>'turn_slot')::INT;
          SELECT is_bot INTO v_isbot FROM public.ludo_participants
            WHERE game_id=g_id AND slot=v_slot;

          -- If turn changed to a human, or game ended, stop
          IF NOT v_isbot THEN EXIT; END IF;

          -- If it's still the same bot's turn with must_move=false (bonus),
          -- the loop continues and bot will roll again
          IF (st->>'must_move')::BOOLEAN THEN
            -- Bot has dice and needs to move — next iteration handles it
            CONTINUE;
          ELSE
            -- Bot has bonus (spinning phase) — next iteration will roll
            -- Small safety: only continue if game is still playing
            EXIT WHEN (st->>'last_event')::TEXT IS NULL;
            CONTINUE;
          END IF;
        END LOOP;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
END $function$;

-- ═══════════════════════════════════════════════════════════
-- FIX: player_add_bot — better state init on auto-start
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.player_add_bot(_game_id UUID, _bot_name TEXT DEFAULT 'Bot')
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_game public.ludo_games%ROWTYPE;
  v_count INT;
  v_slot INT;
  v_color TEXT;
  v_colors TEXT[] := ARRAY['red','green','yellow','blue'];
  v_uid UUID := auth.uid();
  v_is_participant BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;

  SELECT * INTO v_game FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF v_game.id IS NULL OR v_game.status <> 'open' THEN
    RAISE EXCEPTION 'Partie non ouverte';
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM public.ludo_participants
    WHERE game_id = _game_id AND user_id = v_uid
  ) INTO v_is_participant;

  IF NOT v_is_participant THEN
    RAISE EXCEPTION 'Seuls les participants peuvent ajouter un bot';
  END IF;

  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = _game_id;
  IF v_count >= v_game.max_players THEN
    RAISE EXCEPTION 'Partie pleine';
  END IF;

  -- Allow bots on free games or private games (including solo)
  IF v_game.stake > 0 AND NOT v_game.is_private THEN
    RAISE EXCEPTION 'Bots réservés aux parties amicales (mise 0) ou privées';
  END IF;

  v_slot := v_count;
  v_color := v_colors[v_slot + 1];

  INSERT INTO public.ludo_participants(
    game_id, user_id, slot, color, is_bot, bot_name, display_name,
    bot_intelligence, bot_win_bias, ready
  ) VALUES (
    _game_id, NULL, v_slot, v_color, TRUE, _bot_name, _bot_name,
    70, 0, TRUE
  );

  -- Auto-start if full
  IF v_count + 1 = v_game.max_players THEN
    UPDATE public.ludo_games
      SET status = 'playing',
          started_at = now(),
          state = public._ludo_init_state(v_game.max_players),
          current_turn = 0
      WHERE id = _game_id;
  END IF;
END $$;

REVOKE EXECUTE ON FUNCTION public.player_add_bot(UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.player_add_bot(UUID, TEXT) TO authenticated;
