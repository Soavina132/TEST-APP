-- ============================================================
-- FIX: Fanorona cumulative timer — turn_deadline must be NULL
-- when time_control_min > 0 (like chess).
--
-- Bug: fanorona_play sets turn_deadline = now()+60s on every
-- move. The fanorona_tick function forfeits the player when
-- turn_deadline expires. So a player loses after just 60s of
-- thinking on a single turn, even with a 10-min cumulative clock.
--
-- Fix:
-- 1. fanorona_play: set turn_deadline = NULL when time_control_min > 0
--    (only use per-turn deadline when no cumulative clock)
-- 2. _auto_advance_overdue_turns: add Fanorona clock check loop
--    (like chess) to catch timeout even when turn_deadline is NULL
-- 3. fanorona_tick: already handles cumulative clock (section B)
--    but also restore turn-skip behavior for time_control_min = 0
--
-- Key: During chain captures (next_turn = my_slot), last_move_at
-- is NOT updated → clock keeps running for the same player.
-- Only at end of turn (next_turn = 1 - my_slot) does last_move_at
-- reset and clock switches to opponent. This is correct and stays.
-- ============================================================

-- ═══ 1. Re-create fanorona_play with turn_deadline = NULL for clock games ═══
CREATE OR REPLACE FUNCTION public.fanorona_play(_game_id uuid, _move jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  g record;
  my_slot int; my_color int; opp_color int;
  st jsonb; board jsonb;
  from_idx int; to_idx int;
  fr int; fc int; tr int; tc int; dr int; dc int;
  is_strong boolean;
  cap jsonb; lists jsonb;
  opp_left int; next_turn int;
  is_pass boolean;
  move_count int;
  visited jsonb;
  last_axis text;
  axis text;
  chain_from_v int;
  i int;
  v_cols int; v_rows int;
  no_cap int;
  -- Timer variables
  v_elapsed_ms int;
  v_remaining_ms int;
  v_time_ms int;
  v_turn_deadline timestamptz;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  SELECT slot INTO my_slot FROM public.fanorona_participants
    WHERE game_id = _game_id AND user_id = v_uid;
  IF my_slot IS NULL OR my_slot <> g.current_turn THEN RAISE EXCEPTION 'not your turn'; END IF;

  -- ── TIMEOUT CHECK : refuser le coup si le temps est écoulé ──
  IF g.time_control_min > 0 THEN
    v_elapsed_ms := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (now() - COALESCE(g.last_move_at, g.started_at, now()))) * 1000)::int);
    IF g.current_turn = 0 THEN
      v_remaining_ms := g.white_time_ms - v_elapsed_ms;
    ELSE
      v_remaining_ms := g.black_time_ms - v_elapsed_ms;
    END IF;
    IF v_remaining_ms <= 0 THEN
      PERFORM public._fanorona_finalize(_game_id, 1 - g.current_turn, 'timeout');
      RAISE EXCEPTION 'temps écoulé';
    END IF;
  END IF;

  -- Clear expired draw offer
  IF g.draw_offered_by IS NOT NULL AND g.draw_offered_at IS NOT NULL
     AND g.draw_offered_at < now() - interval '30 seconds' THEN
    UPDATE public.fanorona_games SET draw_offered_by = NULL, draw_offered_at = NULL WHERE id = _game_id;
  ELSIF g.draw_offered_by IS NOT NULL AND g.draw_offered_by <> v_uid THEN
    UPDATE public.fanorona_games SET draw_offered_by = NULL, draw_offered_at = NULL WHERE id = _game_id;
  END IF;

  v_cols := COALESCE(g.cols, 9); v_rows := COALESCE(g.rows, 5);
  my_color  := CASE WHEN my_slot = 0 THEN 1 ELSE 2 END;
  opp_color := CASE WHEN my_slot = 0 THEN 2 ELSE 1 END;
  st        := g.state;
  board     := st -> 'board';
  move_count := COALESCE((st->>'move_count')::int, 0);
  visited    := COALESCE(st->'visited', '[]'::jsonb);
  last_axis  := NULLIF(st->>'last_axis', '');
  chain_from_v := CASE WHEN st->'chain_from' IS NULL OR st->'chain_from' = 'null'::jsonb
                       THEN NULL ELSE (st->>'chain_from')::int END;
  no_cap := COALESCE((st->>'no_capture_moves')::int, 0);
  is_pass := COALESCE((_move->>'pass')::boolean, false);

  -- Compute turn_deadline: NULL when using cumulative clock, per-turn timer otherwise
  v_turn_deadline := CASE
    WHEN g.time_control_min > 0 THEN NULL
    ELSE now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')), 60) || ' seconds')::interval
  END;

  -- ═══ PASS : terminer le tour ═══
  IF is_pass THEN
    IF chain_from_v IS NULL
       AND public._fanorona_player_has_move(board, my_color, v_cols, v_rows) THEN
      RAISE EXCEPTION 'cannot pass when you have legal moves';
    END IF;
    next_turn := 1 - my_slot;
    st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
    st := jsonb_set(st, '{visited}',    '[]'::jsonb);
    st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
    st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
    st := jsonb_set(st, '{no_capture_moves}', to_jsonb(no_cap + 1), true);

    -- ── Timer : soustraire le temps écoulé et switcher ──
    IF g.time_control_min > 0 THEN
      v_elapsed_ms := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (now() - COALESCE(g.last_move_at, g.started_at, now()))) * 1000)::int);
      IF my_slot = 0 THEN
        v_time_ms := GREATEST(0, g.white_time_ms - v_elapsed_ms);
        UPDATE public.fanorona_games SET state = st, current_turn = next_turn,
          white_time_ms = v_time_ms,
          last_move_at = now(),
          turn_deadline = v_turn_deadline
          WHERE id = _game_id;
      ELSE
        v_time_ms := GREATEST(0, g.black_time_ms - v_elapsed_ms);
        UPDATE public.fanorona_games SET state = st, current_turn = next_turn,
          black_time_ms = v_time_ms,
          last_move_at = now(),
          turn_deadline = v_turn_deadline
          WHERE id = _game_id;
      END IF;
    ELSE
      UPDATE public.fanorona_games SET state = st, current_turn = next_turn,
        turn_deadline = v_turn_deadline
        WHERE id = _game_id;
    END IF;

    IF NOT public._fanorona_player_has_move(board, opp_color, v_cols, v_rows) THEN
      PERFORM public._fanorona_finalize(_game_id, my_slot);
    END IF;
    IF (no_cap + 1) >= 20
       AND NOT public._fanorona_player_can_capture(board, my_color, v_cols, v_rows)
       AND NOT public._fanorona_player_can_capture(board, opp_color, v_cols, v_rows) THEN
      PERFORM public._fanorona_draw_refund(_game_id);
    END IF;
    RETURN;
  END IF;

  -- ═══ MOVE : traitement normal ═══
  from_idx := (_move->>'from')::int;
  to_idx   := (_move->>'to')::int;
  cap      := COALESCE(_move->'captured', '[]'::jsonb);

  IF chain_from_v IS NOT NULL AND from_idx <> chain_from_v THEN
    RAISE EXCEPTION 'must continue with same piece';
  END IF;
  IF (board->from_idx)::int <> my_color THEN RAISE EXCEPTION 'not your piece'; END IF;
  IF (board->to_idx)::int <> 0 THEN RAISE EXCEPTION 'target not empty'; END IF;

  fr := from_idx / v_cols; fc := from_idx % v_cols;
  tr := to_idx   / v_cols; tc := to_idx   % v_cols;
  dr := tr - fr;           dc := tc - fc;
  IF abs(dr) > 1 OR abs(dc) > 1 OR (dr = 0 AND dc = 0) THEN
    RAISE EXCEPTION 'invalid step';
  END IF;
  is_strong := ((fr + fc) % 2 = 0);
  IF NOT is_strong AND (dr <> 0 AND dc <> 0) THEN
    RAISE EXCEPTION 'diagonal not allowed here';
  END IF;
  axis := public._fanorona_axis(dr, dc);

  IF chain_from_v IS NOT NULL THEN
    IF visited @> to_jsonb(to_idx) THEN RAISE EXCEPTION 'cannot revisit cell'; END IF;
    IF last_axis IS NOT NULL AND axis = last_axis THEN
      RAISE EXCEPTION 'cannot continue on same axis';
    END IF;
  END IF;

  lists := public._fanorona_capture_lists(board, my_color, from_idx, to_idx, v_cols, v_rows);
  IF jsonb_array_length(cap) > 0 THEN
    IF NOT (cap = (lists->'approach') OR cap = (lists->'withdrawal')) THEN
      RAISE EXCEPTION 'invalid capture set';
    END IF;
  END IF;

  IF jsonb_array_length(cap) = 0 THEN
    IF chain_from_v IS NOT NULL THEN
      RAISE EXCEPTION 'must capture during chain';
    END IF;
    IF COALESCE(g.mandatory_capture, true)
       AND public._fanorona_player_can_capture(board, my_color, v_cols, v_rows) THEN
      RAISE EXCEPTION 'capture is mandatory when available';
    END IF;
  END IF;

  -- Apply move
  board := jsonb_set(board, ARRAY[from_idx::text], '0'::jsonb);
  board := jsonb_set(board, ARRAY[to_idx::text],   to_jsonb(my_color));
  IF jsonb_array_length(cap) > 0 THEN
    FOR i IN 0..jsonb_array_length(cap) - 1 LOOP
      board := jsonb_set(board, ARRAY[((cap->i)::int)::text], '0'::jsonb);
    END LOOP;
  END IF;
  st := jsonb_set(st, '{board}', board);
  IF jsonb_array_length(cap) > 0 THEN no_cap := 0; ELSE no_cap := no_cap + 1; END IF;
  st := jsonb_set(st, '{no_capture_moves}', to_jsonb(no_cap), true);

  -- Check if opponent has no pieces left
  SELECT count(*) INTO opp_left FROM jsonb_array_elements(board) v
    WHERE (v::text)::int = opp_color;
  IF opp_left = 0 THEN
    UPDATE public.fanorona_games SET state = st WHERE id = _game_id;
    PERFORM public._fanorona_finalize(_game_id, my_slot, 'capture_all');
    RETURN;
  END IF;

  -- Determine next turn
  IF jsonb_array_length(cap) = 0 THEN
    -- No capture → turn ends
    next_turn := 1 - my_slot;
    st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
    st := jsonb_set(st, '{visited}',    '[]'::jsonb);
    st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
    st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
  ELSE
    IF move_count = 0 THEN
      -- First move capture → turn ends (no chain on first move)
      next_turn := 1 - my_slot;
      st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
      st := jsonb_set(st, '{visited}',    '[]'::jsonb);
      st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
      st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
    ELSE
      -- Check if chain can continue
      visited := visited || to_jsonb(from_idx) || to_jsonb(to_idx);
      IF public._fanorona_piece_can_capture(board, my_color, to_idx, visited, axis, v_cols, v_rows) THEN
        -- Chain continues → SAME player keeps the turn
        next_turn := my_slot;
        st := jsonb_set(st, '{chain_from}', to_jsonb(to_idx));
        st := jsonb_set(st, '{visited}',    visited);
        st := jsonb_set(st, '{last_axis}',  to_jsonb(axis));
      ELSE
        -- Chain ends → turn switches
        next_turn := 1 - my_slot;
        st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
        st := jsonb_set(st, '{visited}',    '[]'::jsonb);
        st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
        st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
      END IF;
    END IF;
  END IF;

  -- ═══ Timer : gérer selon que le tour continue ou switch ═══
  IF next_turn = my_slot AND g.time_control_min > 0 THEN
    -- ── CHAIN CONTINUE : le timer reste actif, NE PAS toucher au clock ──
    -- last_move_at reste inchangé → le temps continue à s'écouler pour le même joueur
    -- turn_deadline reste NULL (cumulative clock mode)
    UPDATE public.fanorona_games SET state = st, current_turn = next_turn
      WHERE id = _game_id;
  ELSE
    -- ── TOUR TERMINE : soustraire le temps écoulé, switcher le timer ──
    IF g.time_control_min > 0 THEN
      v_elapsed_ms := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (now() - COALESCE(g.last_move_at, g.started_at, now()))) * 1000)::int);
      IF my_slot = 0 THEN
        v_time_ms := GREATEST(0, g.white_time_ms - v_elapsed_ms);
        UPDATE public.fanorona_games SET state = st, current_turn = next_turn,
          white_time_ms = v_time_ms,
          last_move_at = now(),
          turn_deadline = v_turn_deadline
          WHERE id = _game_id;
      ELSE
        v_time_ms := GREATEST(0, g.black_time_ms - v_elapsed_ms);
        UPDATE public.fanorona_games SET state = st, current_turn = next_turn,
          black_time_ms = v_time_ms,
          last_move_at = now(),
          turn_deadline = v_turn_deadline
          WHERE id = _game_id;
      END IF;
    ELSE
      UPDATE public.fanorona_games SET state = st, current_turn = next_turn,
        turn_deadline = v_turn_deadline
        WHERE id = _game_id;
    END IF;
  END IF;

  -- Check endgame conditions
  IF NOT public._fanorona_player_has_move(board, opp_color, v_cols, v_rows) THEN
    PERFORM public._fanorona_finalize(_game_id, my_slot);
  ELSIF no_cap >= 20
     AND NOT public._fanorona_player_can_capture(board, my_color, v_cols, v_rows)
     AND NOT public._fanorona_player_can_capture(board, opp_color, v_cols, v_rows) THEN
    PERFORM public._fanorona_draw_refund(_game_id);
  END IF;
END
$function$;

REVOKE ALL ON FUNCTION public.fanorona_play(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fanorona_play(uuid, jsonb) TO authenticated;

-- ═══ 2. Update fanorona_tick: restore turn-skip for non-clock games ═══
CREATE OR REPLACE FUNCTION public.fanorona_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  g record;
  cur_uid uuid;
  v_elapsed_ms int;
  v_remaining int;
  v_cfg record;
  v_skips int;
  v_next int;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;
  IF coalesce(g.paused, false) THEN RETURN; END IF;

  -- ── A. Cumulative clock timeout (flag fall) — checked FIRST ──
  IF g.time_control_min > 0 THEN
    v_elapsed_ms := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (now() - COALESCE(g.last_move_at, g.started_at, now()))) * 1000)::int);
    IF g.current_turn = 0 THEN
      v_remaining := g.white_time_ms - v_elapsed_ms;
    ELSE
      v_remaining := g.black_time_ms - v_elapsed_ms;
    END IF;
    IF v_remaining <= 0 THEN
      PERFORM public._fanorona_finalize(_game_id, 1 - g.current_turn, 'timeout');
      RETURN;
    END IF;
  END IF;

  -- ── B. Turn deadline (per-turn timer, only for non-clock games) ──
  IF g.turn_deadline IS NOT NULL AND g.turn_deadline <= now() THEN
    SELECT * INTO v_cfg FROM public._game_cfg('fanorona');
    SELECT user_id INTO cur_uid FROM public.fanorona_participants
      WHERE game_id = _game_id AND slot = g.current_turn;
    v_skips := COALESCE((g.turn_skips->>cur_uid::text)::int, 0) + 1;
    IF v_skips >= COALESCE(v_cfg.max_turn_skips, 3) THEN
      -- Trop de tours passés → forfait
      UPDATE public.fanorona_participants SET forfeited = true
        WHERE game_id = _game_id AND user_id = cur_uid;
      PERFORM public._fanorona_finalize(_game_id, 1 - g.current_turn, 'timeout');
      RETURN;
    END IF;
    -- Passer le tour
    v_next := 1 - g.current_turn;
    UPDATE public.fanorona_games SET
      current_turn = v_next,
      turn_skips = jsonb_set(g.turn_skips, ARRAY[cur_uid::text], to_jsonb(v_skips)),
      turn_deadline = now() + (COALESCE(v_cfg.turn_timer_seconds, 60) || ' seconds')::interval
    WHERE id = _game_id;
    RETURN;
  END IF;

  -- ── C. Global game deadline expiré ──
  IF g.game_deadline IS NOT NULL AND g.game_deadline <= now() THEN
    PERFORM public._fanorona_finalize(_game_id, 1 - g.current_turn, 'timeout');
    RETURN;
  END IF;
END
$function$;

REVOKE ALL ON FUNCTION public.fanorona_tick(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fanorona_tick(uuid) TO authenticated, anon, service_role;

-- ═══ 3. Update _auto_advance_overdue_turns: add Fanorona clock check ═══
CREATE OR REPLACE FUNCTION public._auto_advance_overdue_turns()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r record;
  v_g chess_games%ROWTYPE;
  v_fg fanorona_games%ROWTYPE;
  v_elapsed_ms int;
  v_remaining int;
BEGIN
  -- Fanorona cumulative clock timeout (like chess)
  -- Check ALL active fanorona games with a time control, not just
  -- those with an expired turn_deadline. This catches the case where
  -- turn_deadline is NULL (clock mode) and nobody is on the page.
  FOR r IN SELECT id FROM public.fanorona_games
           WHERE status='playing'
             AND paused = FALSE
             AND time_control_min > 0
  LOOP
    SELECT * INTO v_fg FROM public.fanorona_games WHERE id = r.id FOR UPDATE;
    IF v_fg.id IS NULL OR v_fg.status <> 'playing' OR COALESCE(v_fg.paused, false) THEN CONTINUE; END IF;

    v_elapsed_ms := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (now() - COALESCE(v_fg.last_move_at, v_fg.started_at, now()))) * 1000)::int);

    IF v_fg.current_turn = 0 THEN
      v_remaining := v_fg.white_time_ms - v_elapsed_ms;
    ELSE
      v_remaining := v_fg.black_time_ms - v_elapsed_ms;
    END IF;

    IF v_remaining <= 0 THEN
      PERFORM public.fanorona_tick(r.id);
    END IF;
  END LOOP;

  -- Fanorona turn deadlines (per-turn timer for non-clock games)
  FOR r IN SELECT id FROM public.fanorona_games
           WHERE status='playing' AND paused = FALSE AND turn_deadline IS NOT NULL AND turn_deadline < now()
  LOOP PERFORM public.fanorona_tick(r.id); END LOOP;

  -- Fanorona global timeout
  FOR r IN SELECT id FROM public.fanorona_games
           WHERE status='playing' AND game_deadline IS NOT NULL AND game_deadline < now()
  LOOP PERFORM public.fanorona_check_global_timeout(r.id); END LOOP;

  -- Chess turn deadlines (per-move timer)
  FOR r IN SELECT id FROM public.chess_games
           WHERE status='playing' AND paused = FALSE AND turn_deadline IS NOT NULL AND turn_deadline < now()
  LOOP PERFORM public.chess_tick(r.id); END LOOP;

  -- Chess clock timeout
  FOR r IN SELECT id FROM public.chess_games
           WHERE status='playing'
             AND paused = FALSE
             AND time_control_min > 0
  LOOP
    SELECT * INTO v_g FROM public.chess_games WHERE id = r.id FOR UPDATE;
    IF v_g.id IS NULL OR v_g.status <> 'playing' OR COALESCE(v_g.paused, false) THEN CONTINUE; END IF;

    v_elapsed_ms := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (now() - COALESCE(v_g.last_move_at, v_g.started_at, now()))) * 1000)::int);

    IF v_g.turn = 'w' THEN
      v_remaining := v_g.white_time_ms - v_elapsed_ms;
    ELSE
      v_remaining := v_g.black_time_ms - v_elapsed_ms;
    END IF;

    IF v_remaining <= 0 THEN
      PERFORM public.chess_auto_timeout(r.id);
    END IF;
  END LOOP;

  -- Chess global game deadline
  FOR r IN SELECT id FROM public.chess_games
           WHERE status='playing' AND game_deadline IS NOT NULL AND game_deadline < now()
  LOOP PERFORM public.chess_check_global_timeout(r.id); END LOOP;

  -- Domino turn deadlines
  FOR r IN SELECT id FROM public.domino_games
           WHERE status='playing' AND paused = FALSE AND turn_deadline IS NOT NULL AND turn_deadline < now()
  LOOP PERFORM public.domino_tick(r.id); END LOOP;

  -- Rami turn deadlines
  FOR r IN SELECT id FROM public.rami_games
           WHERE status='playing' AND paused = FALSE AND turn_deadline IS NOT NULL AND turn_deadline < now()
  LOOP PERFORM public.rami_tick(r.id); END LOOP;

  -- LUDO: bot play + timeout + auto-move + stalemate detection
  PERFORM public.ludo_tick_all();
END $$;

GRANT EXECUTE ON FUNCTION public._auto_advance_overdue_turns() TO authenticated, anon, service_role;

-- ═══ 4. Clear turn_deadline for existing clock-mode games ═══
UPDATE public.fanorona_games
  SET turn_deadline = NULL
  WHERE status = 'playing'
    AND time_control_min > 0
    AND turn_deadline IS NOT NULL;
