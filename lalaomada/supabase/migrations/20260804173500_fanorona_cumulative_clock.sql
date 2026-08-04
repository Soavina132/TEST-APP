-- ============================================================
-- Migration: Fanorona — Pendule cumulée comme les échecs
--
-- Chaque joueur dispose d'un temps de réflexion total (10 min par défaut)
-- qui ne descend que pendant son tour. Quand l'horloge atteint 0,
-- le joueur perd par flag fall (temps écoulé).
--
-- Colonnes ajoutées:
--   white_time_ms   — temps restant joueur blanc (ms), défaut 600000 (10 min)
--   black_time_ms   — temps restant joueur noir  (ms), défaut 600000 (10 min)
--   time_control_min — durée initiale en minutes, défaut 10
--   last_move_at    — timestamp du dernier coup (pour calculer le temps écoulé)
-- ============================================================

-- 1) Add clock columns to fanorona_games
ALTER TABLE public.fanorona_games
  ADD COLUMN IF NOT EXISTS white_time_ms    integer NOT NULL DEFAULT 600000,
  ADD COLUMN IF NOT EXISTS black_time_ms    integer NOT NULL DEFAULT 600000,
  ADD COLUMN IF NOT EXISTS time_control_min integer NOT NULL DEFAULT 10,
  ADD COLUMN IF NOT EXISTS last_move_at     timestamptz;

-- 2) Update fanorona_set_ready to initialize clocks and last_move_at on game start
CREATE OR REPLACE FUNCTION public.fanorona_set_ready(_game_id uuid, _ready boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $function$
DECLARE v_uid uuid := auth.uid(); v_total int; v_ready int; v_status text;
        v_starter uuid; v_other uuid; v_swap boolean;
        v_p1 uuid; v_p2 uuid;
        v_time_ms int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  UPDATE public.fanorona_participants SET ready = COALESCE(_ready, false)
    WHERE game_id = _game_id AND user_id = v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'not a participant'; END IF;
  SELECT status INTO v_status FROM public.fanorona_games WHERE id = _game_id;
  IF v_status <> 'open' THEN RETURN; END IF;
  SELECT count(*), count(*) FILTER (WHERE ready) INTO v_total, v_ready
    FROM public.fanorona_participants WHERE game_id = _game_id;
  IF v_total = 2 AND v_ready = 2 THEN
    SELECT user_id INTO v_p1 FROM public.fanorona_participants WHERE game_id=_game_id ORDER BY joined_at LIMIT 1;
    SELECT user_id INTO v_p2 FROM public.fanorona_participants WHERE game_id=_game_id AND user_id <> v_p1 LIMIT 1;
    v_swap := (get_byte(gen_random_bytes(1),0) % 2) = 1;
    IF v_swap THEN v_starter := v_p2; v_other := v_p1;
    ELSE v_starter := v_p1; v_other := v_p2; END IF;

    UPDATE public.fanorona_participants SET slot = 0, color = 'white'
      WHERE game_id=_game_id AND user_id = v_starter;
    UPDATE public.fanorona_participants SET slot = 1, color = 'black'
      WHERE game_id=_game_id AND user_id = v_other;

    -- Initialize clocks from time_control_min
    v_time_ms := COALESCE(
      (SELECT time_control_min FROM public.fanorona_games WHERE id = _game_id),
      10
    ) * 60 * 1000;

    UPDATE public.fanorona_games
       SET status = 'playing',
           started_at = now(),
           current_turn = 0,
           last_move_at = now(),
           white_time_ms = v_time_ms,
           black_time_ms = v_time_ms,
           state = jsonb_set(state, '{phase}', '"playing"'::jsonb)
     WHERE id = _game_id AND status = 'open';
  END IF;
END $function$;

-- 3) Update _fanorona_play_by_slot to deduct elapsed time from active player's clock
CREATE OR REPLACE FUNCTION public._fanorona_play_by_slot(_game_id uuid, _move jsonb, _slot integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  g record;
  my_color int; opp_color int;
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
  v_elapsed_ms int;
  v_new_time_ms int;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  IF g.current_turn <> _slot THEN RAISE EXCEPTION 'not your turn'; END IF;

  v_cols := COALESCE(g.cols, 9); v_rows := COALESCE(g.rows, 5);
  my_color  := CASE WHEN _slot = 0 THEN 1 ELSE 2 END;
  opp_color := CASE WHEN _slot = 0 THEN 2 ELSE 1 END;

  -- Compute elapsed time since last move (or game start)
  v_elapsed_ms := GREATEST(0, EXTRACT(EPOCH FROM (now() - COALESCE(g.last_move_at, g.started_at, now())))::int * 1000);

  -- Deduct from active player's clock
  IF _slot = 0 THEN
    v_new_time_ms := GREATEST(0, g.white_time_ms - v_elapsed_ms);
  ELSE
    v_new_time_ms := GREATEST(0, g.black_time_ms - v_elapsed_ms);
  END IF;

  -- If clock ran out, finalize — opponent wins by flag fall
  IF v_new_time_ms <= 0 THEN
    PERFORM public._fanorona_finalize(_game_id, 1 - _slot);
    RETURN;
  END IF;

  st        := g.state;
  board     := st -> 'board';
  move_count := COALESCE((st->>'move_count')::int, 0);
  visited    := COALESCE(st->'visited', '[]'::jsonb);
  last_axis  := NULLIF(st->>'last_axis', '');
  chain_from_v := CASE WHEN st->'chain_from' IS NULL OR st->'chain_from' = 'null'::jsonb
                       THEN NULL ELSE (st->>'chain_from')::int END;

  is_pass := COALESCE((_move->>'pass')::boolean, false);

  IF is_pass THEN
    next_turn := 1 - _slot;
    st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
    st := jsonb_set(st, '{visited}',    '[]'::jsonb);
    st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
    st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
    UPDATE public.fanorona_games SET
      state = st,
      current_turn = next_turn,
      last_move_at = now(),
      white_time_ms = CASE WHEN _slot = 0 THEN v_new_time_ms ELSE white_time_ms END,
      black_time_ms = CASE WHEN _slot = 1 THEN v_new_time_ms ELSE black_time_ms END,
      turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')),60) || ' seconds')::interval
      WHERE id = _game_id;
    IF NOT public._fanorona_player_has_move(board, opp_color, v_cols, v_rows) THEN
      PERFORM public._fanorona_finalize(_game_id, _slot);
    END IF;
    RETURN;
  END IF;

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

  board := jsonb_set(board, ARRAY[from_idx::text], '0'::jsonb);
  board := jsonb_set(board, ARRAY[to_idx::text],   to_jsonb(my_color));
  IF jsonb_array_length(cap) > 0 THEN
    FOR i IN 0..jsonb_array_length(cap) - 1 LOOP
      board := jsonb_set(board, ARRAY[((cap->i)::int)::text], '0'::jsonb);
    END LOOP;
  END IF;
  st := jsonb_set(st, '{board}', board);

  SELECT count(*) INTO opp_left FROM jsonb_array_elements(board) v
    WHERE (v::text)::int = opp_color;
  IF opp_left = 0 THEN
    UPDATE public.fanorona_games SET
      state = st,
      last_move_at = now(),
      white_time_ms = CASE WHEN _slot = 0 THEN v_new_time_ms ELSE white_time_ms END,
      black_time_ms = CASE WHEN _slot = 1 THEN v_new_time_ms ELSE black_time_ms END
      WHERE id = _game_id;
    PERFORM public._fanorona_finalize(_game_id, _slot);
    RETURN;
  END IF;

  IF jsonb_array_length(cap) = 0 THEN
    -- Simple move without capture: turn always passes, no chain possible.
    next_turn := 1 - _slot;
    st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
    st := jsonb_set(st, '{visited}',    '[]'::jsonb);
    st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
    st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
  ELSE
    -- Capture happened: check whether the SAME piece can keep chaining
    visited := visited || to_jsonb(from_idx) || to_jsonb(to_idx);
    IF public._fanorona_piece_can_capture(board, my_color, to_idx, visited, axis, v_cols, v_rows) THEN
      next_turn := _slot;
      st := jsonb_set(st, '{chain_from}', to_jsonb(to_idx));
      st := jsonb_set(st, '{visited}',    visited);
      st := jsonb_set(st, '{last_axis}',  to_jsonb(axis));
    ELSE
      next_turn := 1 - _slot;
      st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
      st := jsonb_set(st, '{visited}',    '[]'::jsonb);
      st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
      st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
    END IF;
  END IF;

  UPDATE public.fanorona_games SET
    state = st,
    current_turn = next_turn,
    last_move_at = now(),
    white_time_ms = CASE WHEN _slot = 0 THEN v_new_time_ms ELSE white_time_ms END,
    black_time_ms = CASE WHEN _slot = 1 THEN v_new_time_ms ELSE black_time_ms END,
    turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')),60) || ' seconds')::interval
    WHERE id = _game_id;

  IF next_turn = 1 - _slot
     AND NOT public._fanorona_player_has_move(board, opp_color, v_cols, v_rows) THEN
    PERFORM public._fanorona_finalize(_game_id, _slot);
  END IF;
END $function$;

-- 4) Update fanorona_tick to check cumulative clock timeout (flag fall)
CREATE OR REPLACE FUNCTION public.fanorona_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $function$
DECLARE
  g record; cur_uid uuid; _cfg record; _skips int; _next int;
  v_elapsed_ms int; v_active_time_ms int;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

  -- Check cumulative clock timeout (flag fall)
  v_elapsed_ms := GREATEST(0, EXTRACT(EPOCH FROM (now() - COALESCE(g.last_move_at, g.started_at, now())))::int * 1000);
  IF g.current_turn = 0 THEN
    v_active_time_ms := GREATEST(0, g.white_time_ms - v_elapsed_ms);
  ELSE
    v_active_time_ms := GREATEST(0, g.black_time_ms - v_elapsed_ms);
  END IF;

  IF v_active_time_ms <= 0 THEN
    -- Flag fall: active player ran out of time
    SELECT user_id INTO cur_uid FROM public.fanorona_participants WHERE game_id = _game_id AND slot = g.current_turn;
    PERFORM public._fanorona_finalize(_game_id, 1 - g.current_turn);
    RETURN;
  END IF;

  -- Also check turn_deadline (per-turn skip)
  IF g.turn_deadline IS NULL OR g.turn_deadline > now() THEN RETURN; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('fanorona');
  SELECT user_id INTO cur_uid FROM public.fanorona_participants WHERE game_id = _game_id AND slot = g.current_turn;
  _skips := COALESCE((g.turn_skips->>cur_uid::text)::int, 0) + 1;
  IF _skips >= _cfg.max_turn_skips THEN
    UPDATE public.fanorona_participants SET forfeited = true WHERE game_id = _game_id AND user_id = cur_uid;
    PERFORM public._fanorona_finalize(_game_id, 1 - g.current_turn);
    RETURN;
  END IF;
  _next := 1 - g.current_turn;
  UPDATE public.fanorona_games SET
    current_turn = _next,
    turn_skips = jsonb_set(g.turn_skips, ARRAY[cur_uid::text], to_jsonb(_skips)),
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
  WHERE id = _game_id;
END $function$;

-- 5) Update fanorona_create_solo to initialize clocks and last_move_at
CREATE OR REPLACE FUNCTION public.fanorona_create_solo(_stake numeric DEFAULT 0, _variant text DEFAULT 'tsivy', _mandatory_capture boolean DEFAULT true, _bot_intelligence integer DEFAULT 3)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
  v_name text;
  v_cols int; v_rows int;
  v_bot_name text;
  v_time_ms int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'invalid stake'; END IF;

  CASE _variant
    WHEN 'telo'  THEN v_cols := 3; v_rows := 3;
    WHEN 'dimy'  THEN v_cols := 5; v_rows := 5;
    WHEN 'tsivy' THEN v_cols := 9; v_rows := 5;
    ELSE v_cols := 9; v_rows := 5; _variant := 'tsivy';
  END CASE;

  SELECT pseudo INTO v_name FROM public.profiles WHERE id = v_uid;
  v_bot_name := CASE _bot_intelligence WHEN 1 THEN 'Debutant' WHEN 2 THEN 'Amateur' WHEN 3 THEN 'Confirme' WHEN 4 THEN 'Expert' ELSE 'Maitre' END;
  v_time_ms := 10 * 60 * 1000;

  INSERT INTO public.fanorona_games(
    host_id, max_players, stake, pot, commission_pct, is_private, room_code,
    state, cols, rows, variant, mandatory_capture, bot_intelligence, status, started_at, last_move_at,
    white_time_ms, black_time_ms
  )
  VALUES (
    v_uid, 2, 0, 0, 0, true, null,
    jsonb_build_object('phase','playing', 'board', public._fanorona_init_board(v_cols, v_rows), 'chain_from',null,'chain_dirs','[]'::jsonb,'move_count',0,'visited','[]'::jsonb,'last_axis',null),
    v_cols, v_rows, _variant, COALESCE(_mandatory_capture, true), COALESCE(_bot_intelligence, 3), 'playing', now(), now(),
    v_time_ms, v_time_ms
  ) RETURNING id INTO v_id;

  INSERT INTO public.fanorona_participants(game_id, user_id, slot, color, display_name, is_bot)
  VALUES (v_id, v_uid, 0, 'white', COALESCE(v_name, 'Joueur'), false);

  INSERT INTO public.fanorona_participants(game_id, user_id, slot, color, display_name, is_bot, bot_intelligence)
  VALUES (v_id, NULL, 1, 'black', 'Bot ' || v_bot_name, true, COALESCE(_bot_intelligence, 3));

  UPDATE public.fanorona_games
    SET current_turn = 0,
        turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')), 60) || ' seconds')::interval
    WHERE id = v_id;

  RETURN v_id;
END $function$;

-- 6) Fix existing playing games that have NULL last_move_at
UPDATE public.fanorona_games SET last_move_at = now() WHERE status = 'playing' AND last_move_at IS NULL;
