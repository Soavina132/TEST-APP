
DROP FUNCTION IF EXISTS public.fanorona_add_bot(uuid, text);
DROP FUNCTION IF EXISTS public.fanorona_bot_play(uuid);
DROP FUNCTION IF EXISTS public.fanorona_play_as_bot(uuid, jsonb);

-- 1) fanorona_add_bot
CREATE OR REPLACE FUNCTION public.fanorona_add_bot(_game_id uuid, _bot_name text DEFAULT 'Bot')
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  g record;
  v_bot_id uuid := gen_random_uuid();
  v_bot_mail text;
  v_slot int;
  v_is_admin boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL THEN RAISE EXCEPTION 'game not found'; END IF;
  IF g.status <> 'open' THEN RAISE EXCEPTION 'game not open'; END IF;

  v_is_admin := public.has_role(v_uid, 'admin'::app_role);
  IF NOT v_is_admin AND g.host_id <> v_uid THEN
    RAISE EXCEPTION 'only host may add bots';
  END IF;
  IF NOT v_is_admin AND g.stake > 0 THEN
    RAISE EXCEPTION 'bots only allowed in free games';
  END IF;
  IF (SELECT count(*) FROM public.fanorona_participants WHERE game_id = _game_id) >= 2 THEN
    RAISE EXCEPTION 'game full';
  END IF;

  v_bot_mail := 'fanoronabot_' || v_bot_id::text || '@bot.lalaomada.internal';
  INSERT INTO auth.users (
    id, instance_id, aud, role,
    email, encrypted_password, email_confirmed_at,
    raw_user_meta_data,
    created_at, updated_at,
    confirmation_token, recovery_token, email_change, email_change_token_new
  ) VALUES (
    v_bot_id, '00000000-0000-0000-0000-000000000000',
    'authenticated','authenticated',
    v_bot_mail, crypt(gen_random_uuid()::text, gen_salt('bf')), now(),
    jsonb_build_object('pseudo', _bot_name, 'is_bot', true),
    now(), now(), '', '', '', ''
  );
  UPDATE public.profiles
     SET balance_ar = 0, pseudo = _bot_name, avatar_url = NULL, is_bot = true
   WHERE id = v_bot_id;

  SELECT COALESCE(MIN(s.slot),0) INTO v_slot
    FROM (SELECT 0 AS slot UNION SELECT 1) s
   WHERE s.slot NOT IN (SELECT slot FROM public.fanorona_participants WHERE game_id = _game_id);

  INSERT INTO public.fanorona_participants(game_id, user_id, slot, color, display_name, is_bot, ready)
  VALUES (_game_id, v_bot_id, v_slot,
          CASE WHEN v_slot = 0 THEN 'white' ELSE 'black' END,
          _bot_name, true, true);

  IF (SELECT count(*) FROM public.fanorona_participants WHERE game_id = _game_id) = 2 THEN
    UPDATE public.fanorona_games
       SET status = 'playing', started_at = now(), current_turn = 0,
           turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')),60) || ' seconds')::interval
     WHERE id = _game_id;
  END IF;
  RETURN v_bot_id;
END $$;
GRANT EXECUTE ON FUNCTION public.fanorona_add_bot(uuid, text) TO authenticated;

-- 2) Draw refund
CREATE OR REPLACE FUNCTION public._fanorona_draw_refund(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE g record; p record;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN; END IF;
  IF g.stake > 0 THEN
    FOR p IN SELECT user_id FROM public.fanorona_participants WHERE game_id = _game_id LOOP
      UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id = p.user_id;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (p.user_id, 'fanorona_refund', g.stake, _game_id, 'Fanorona draw (Vasa)');
    END LOOP;
  END IF;
  UPDATE public.fanorona_games
     SET status = 'draw', finished_at = now(), winner_id = NULL
   WHERE id = _game_id;
END $$;

-- 3) Internal bot player (bypass auth check)
CREATE OR REPLACE FUNCTION public.fanorona_play_as_bot(_game_id uuid, _move jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  g record; bot_uid uuid;
  my_slot int; my_color int; opp_color int;
  st jsonb; board jsonb;
  from_idx int; to_idx int;
  fr int; fc int; tr int; tc int; dr int; dc int;
  cap jsonb;
  opp_left int; next_turn int;
  is_pass boolean;
  move_count int;
  visited jsonb; last_axis text; axis text;
  chain_from_v int;
  i int;
  v_cols int; v_rows int;
  no_cap int;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN; END IF;
  my_slot := g.current_turn;
  SELECT user_id INTO bot_uid FROM public.fanorona_participants
    WHERE game_id = _game_id AND slot = my_slot AND is_bot = true;
  IF bot_uid IS NULL THEN RETURN; END IF;

  v_cols := COALESCE(g.cols, 9); v_rows := COALESCE(g.rows, 5);
  my_color  := CASE WHEN my_slot = 0 THEN 1 ELSE 2 END;
  opp_color := CASE WHEN my_slot = 0 THEN 2 ELSE 1 END;
  st := g.state; board := st -> 'board';
  move_count := COALESCE((st->>'move_count')::int, 0);
  visited := COALESCE(st->'visited', '[]'::jsonb);
  last_axis := NULLIF(st->>'last_axis', '');
  chain_from_v := CASE WHEN st->'chain_from' IS NULL OR st->'chain_from' = 'null'::jsonb
                       THEN NULL ELSE (st->>'chain_from')::int END;
  no_cap := COALESCE((st->>'no_capture_moves')::int, 0);

  is_pass := COALESCE((_move->>'pass')::boolean, false);
  IF is_pass THEN
    next_turn := 1 - my_slot;
    st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
    st := jsonb_set(st, '{visited}', '[]'::jsonb);
    st := jsonb_set(st, '{last_axis}', 'null'::jsonb);
    st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
    st := jsonb_set(st, '{no_capture_moves}', to_jsonb(no_cap + 1), true);
    UPDATE public.fanorona_games SET state = st, current_turn = next_turn,
      turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')),60) || ' seconds')::interval
      WHERE id = _game_id;
    IF NOT public._fanorona_player_has_move(board, opp_color, v_cols, v_rows) THEN
      PERFORM public._fanorona_finalize(_game_id, my_slot); RETURN;
    END IF;
    IF (no_cap + 1) >= 20
       AND NOT public._fanorona_player_can_capture(board, my_color, v_cols, v_rows)
       AND NOT public._fanorona_player_can_capture(board, opp_color, v_cols, v_rows) THEN
      PERFORM public._fanorona_draw_refund(_game_id);
    END IF;
    RETURN;
  END IF;

  from_idx := (_move->>'from')::int;
  to_idx   := (_move->>'to')::int;
  cap      := COALESCE(_move->'captured', '[]'::jsonb);
  fr := from_idx / v_cols; fc := from_idx % v_cols;
  tr := to_idx   / v_cols; tc := to_idx   % v_cols;
  dr := tr - fr;           dc := tc - fc;
  axis := public._fanorona_axis(dr, dc);

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

  SELECT count(*) INTO opp_left FROM jsonb_array_elements(board) v WHERE (v::text)::int = opp_color;
  IF opp_left = 0 THEN
    UPDATE public.fanorona_games SET state = st WHERE id = _game_id;
    PERFORM public._fanorona_finalize(_game_id, my_slot); RETURN;
  END IF;

  IF jsonb_array_length(cap) = 0 THEN
    next_turn := 1 - my_slot;
    st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
    st := jsonb_set(st, '{visited}', '[]'::jsonb);
    st := jsonb_set(st, '{last_axis}', 'null'::jsonb);
    st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
  ELSE
    IF move_count = 0 THEN
      next_turn := 1 - my_slot;
      st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
      st := jsonb_set(st, '{visited}', '[]'::jsonb);
      st := jsonb_set(st, '{last_axis}', 'null'::jsonb);
      st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
    ELSE
      visited := visited || to_jsonb(from_idx) || to_jsonb(to_idx);
      IF public._fanorona_piece_can_capture(board, my_color, to_idx, visited, axis, v_cols, v_rows) THEN
        next_turn := my_slot;
        st := jsonb_set(st, '{chain_from}', to_jsonb(to_idx));
        st := jsonb_set(st, '{visited}', visited);
        st := jsonb_set(st, '{last_axis}', to_jsonb(axis));
      ELSE
        next_turn := 1 - my_slot;
        st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
        st := jsonb_set(st, '{visited}', '[]'::jsonb);
        st := jsonb_set(st, '{last_axis}', 'null'::jsonb);
        st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
      END IF;
    END IF;
  END IF;

  UPDATE public.fanorona_games SET state = st, current_turn = next_turn,
    turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')),60) || ' seconds')::interval
    WHERE id = _game_id;

  IF next_turn = 1 - my_slot
     AND NOT public._fanorona_player_has_move(board, opp_color, v_cols, v_rows) THEN
    PERFORM public._fanorona_finalize(_game_id, my_slot); RETURN;
  END IF;

  IF no_cap >= 20
     AND NOT public._fanorona_player_can_capture(board, my_color, v_cols, v_rows)
     AND NOT public._fanorona_player_can_capture(board, opp_color, v_cols, v_rows) THEN
    PERFORM public._fanorona_draw_refund(_game_id); RETURN;
  END IF;

  IF next_turn = my_slot THEN
    PERFORM public.fanorona_bot_play(_game_id);
  END IF;
END $$;

-- 4) Bot AI
CREATE OR REPLACE FUNCTION public.fanorona_bot_play(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  g record;
  st jsonb; board jsonb;
  my_slot int; my_color int;
  v_cols int; v_rows int;
  is_bot boolean;
  i int; r int; c int; dr int; dc int; nr int; nc int; nidx int;
  is_strong boolean;
  lists jsonb;
  best_from int := -1; best_to int := -1; best_cap jsonb := '[]'::jsonb;
  best_count int := -1;
  chain_from_v int;
  visited jsonb; last_axis text; axis text;
  move_count int;
  cap_count int;
  first_move boolean;
  choose_cap jsonb;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

  my_slot := g.current_turn;
  SELECT COALESCE(fp.is_bot, false) INTO is_bot FROM public.fanorona_participants fp
    WHERE fp.game_id = _game_id AND fp.slot = my_slot;
  IF NOT COALESCE(is_bot, false) THEN RETURN; END IF;

  st := g.state; board := st -> 'board';
  v_cols := COALESCE(g.cols, 9); v_rows := COALESCE(g.rows, 5);
  my_color := CASE WHEN my_slot = 0 THEN 1 ELSE 2 END;
  move_count := COALESCE((st->>'move_count')::int, 0);
  visited := COALESCE(st->'visited', '[]'::jsonb);
  last_axis := NULLIF(st->>'last_axis', '');
  chain_from_v := CASE WHEN st->'chain_from' IS NULL OR st->'chain_from' = 'null'::jsonb
                       THEN NULL ELSE (st->>'chain_from')::int END;
  first_move := (move_count = 0);

  FOR i IN 0..(v_cols * v_rows - 1) LOOP
    IF chain_from_v IS NOT NULL AND i <> chain_from_v THEN CONTINUE; END IF;
    IF (board->i)::int <> my_color THEN CONTINUE; END IF;
    r := i / v_cols; c := i % v_cols;
    is_strong := ((r + c) % 2 = 0);
    FOR dr, dc IN
      SELECT a, b FROM (VALUES (-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)) v(a,b)
    LOOP
      IF NOT is_strong AND (dr <> 0 AND dc <> 0) THEN CONTINUE; END IF;
      nr := r + dr; nc := c + dc;
      IF nr < 0 OR nr >= v_rows OR nc < 0 OR nc >= v_cols THEN CONTINUE; END IF;
      nidx := nr * v_cols + nc;
      IF (board->nidx)::int <> 0 THEN CONTINUE; END IF;
      IF chain_from_v IS NOT NULL AND visited @> to_jsonb(nidx) THEN CONTINUE; END IF;
      axis := public._fanorona_axis(dr, dc);
      IF chain_from_v IS NOT NULL AND last_axis IS NOT NULL AND axis = last_axis THEN CONTINUE; END IF;

      lists := public._fanorona_capture_lists(board, my_color, i, nidx, v_cols, v_rows);
      choose_cap := NULL;
      IF jsonb_array_length(lists->'approach') > 0 THEN
        choose_cap := lists->'approach';
      END IF;
      IF NOT first_move AND jsonb_array_length(lists->'withdrawal') > COALESCE(jsonb_array_length(choose_cap),0) THEN
        choose_cap := lists->'withdrawal';
      END IF;

      cap_count := COALESCE(jsonb_array_length(choose_cap), 0);
      IF cap_count > best_count THEN
        best_count := cap_count;
        best_from := i; best_to := nidx;
        best_cap := COALESCE(choose_cap, '[]'::jsonb);
      END IF;
    END LOOP;
  END LOOP;

  IF best_from < 0 THEN
    PERFORM public.fanorona_play_as_bot(_game_id, jsonb_build_object('pass', true));
    RETURN;
  END IF;

  -- If we're in a chain and best move has 0 captures, pass instead
  IF chain_from_v IS NOT NULL AND best_count <= 0 THEN
    PERFORM public.fanorona_play_as_bot(_game_id, jsonb_build_object('pass', true));
    RETURN;
  END IF;

  PERFORM public.fanorona_play_as_bot(_game_id,
    jsonb_build_object('from', best_from, 'to', best_to, 'captured', best_cap));
END $$;
GRANT EXECUTE ON FUNCTION public.fanorona_bot_play(uuid) TO authenticated;

-- 5) fanorona_play with first-move rule, no-capture counter, bot trigger
CREATE OR REPLACE FUNCTION public.fanorona_play(_game_id uuid, _move jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
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
  last_axis text; axis text;
  chain_from_v int;
  i int;
  v_cols int; v_rows int;
  no_cap int;
  used_approach boolean;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  SELECT slot INTO my_slot FROM public.fanorona_participants
    WHERE game_id = _game_id AND user_id = v_uid;
  IF my_slot IS NULL OR my_slot <> g.current_turn THEN RAISE EXCEPTION 'not your turn'; END IF;

  v_cols := COALESCE(g.cols, 9); v_rows := COALESCE(g.rows, 5);
  my_color := CASE WHEN my_slot = 0 THEN 1 ELSE 2 END;
  opp_color := CASE WHEN my_slot = 0 THEN 2 ELSE 1 END;
  st := g.state; board := st -> 'board';
  move_count := COALESCE((st->>'move_count')::int, 0);
  visited := COALESCE(st->'visited', '[]'::jsonb);
  last_axis := NULLIF(st->>'last_axis', '');
  chain_from_v := CASE WHEN st->'chain_from' IS NULL OR st->'chain_from' = 'null'::jsonb
                       THEN NULL ELSE (st->>'chain_from')::int END;
  no_cap := COALESCE((st->>'no_capture_moves')::int, 0);
  is_pass := COALESCE((_move->>'pass')::boolean, false);

  IF is_pass THEN
    next_turn := 1 - my_slot;
    st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
    st := jsonb_set(st, '{visited}', '[]'::jsonb);
    st := jsonb_set(st, '{last_axis}', 'null'::jsonb);
    st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
    st := jsonb_set(st, '{no_capture_moves}', to_jsonb(no_cap + 1), true);
    UPDATE public.fanorona_games SET state = st, current_turn = next_turn,
      turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')),60) || ' seconds')::interval
      WHERE id = _game_id;
    IF NOT public._fanorona_player_has_move(board, opp_color, v_cols, v_rows) THEN
      PERFORM public._fanorona_finalize(_game_id, my_slot); RETURN;
    END IF;
    IF (no_cap + 1) >= 20
       AND NOT public._fanorona_player_can_capture(board, my_color, v_cols, v_rows)
       AND NOT public._fanorona_player_can_capture(board, opp_color, v_cols, v_rows) THEN
      PERFORM public._fanorona_draw_refund(_game_id); RETURN;
    END IF;
    PERFORM public.fanorona_bot_play(_game_id);
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
  used_approach := false;
  IF jsonb_array_length(cap) > 0 THEN
    IF cap = (lists->'approach') THEN used_approach := true;
    ELSIF cap = (lists->'withdrawal') THEN used_approach := false;
    ELSE RAISE EXCEPTION 'invalid capture set';
    END IF;
  END IF;

  IF move_count = 0 AND jsonb_array_length(cap) > 0 AND NOT used_approach THEN
    RAISE EXCEPTION 'first move: only approach captures allowed';
  END IF;

  IF jsonb_array_length(cap) = 0 THEN
    IF chain_from_v IS NOT NULL THEN RAISE EXCEPTION 'must capture during chain'; END IF;
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

  IF jsonb_array_length(cap) > 0 THEN no_cap := 0; ELSE no_cap := no_cap + 1; END IF;
  st := jsonb_set(st, '{no_capture_moves}', to_jsonb(no_cap), true);

  SELECT count(*) INTO opp_left FROM jsonb_array_elements(board) v WHERE (v::text)::int = opp_color;
  IF opp_left = 0 THEN
    UPDATE public.fanorona_games SET state = st WHERE id = _game_id;
    PERFORM public._fanorona_finalize(_game_id, my_slot); RETURN;
  END IF;

  IF jsonb_array_length(cap) = 0 THEN
    next_turn := 1 - my_slot;
    st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
    st := jsonb_set(st, '{visited}', '[]'::jsonb);
    st := jsonb_set(st, '{last_axis}', 'null'::jsonb);
    st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
  ELSE
    IF move_count = 0 THEN
      next_turn := 1 - my_slot;
      st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
      st := jsonb_set(st, '{visited}', '[]'::jsonb);
      st := jsonb_set(st, '{last_axis}', 'null'::jsonb);
      st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
    ELSE
      visited := visited || to_jsonb(from_idx) || to_jsonb(to_idx);
      IF public._fanorona_piece_can_capture(board, my_color, to_idx, visited, axis, v_cols, v_rows) THEN
        next_turn := my_slot;
        st := jsonb_set(st, '{chain_from}', to_jsonb(to_idx));
        st := jsonb_set(st, '{visited}', visited);
        st := jsonb_set(st, '{last_axis}', to_jsonb(axis));
      ELSE
        next_turn := 1 - my_slot;
        st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
        st := jsonb_set(st, '{visited}', '[]'::jsonb);
        st := jsonb_set(st, '{last_axis}', 'null'::jsonb);
        st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
      END IF;
    END IF;
  END IF;

  UPDATE public.fanorona_games SET state = st, current_turn = next_turn,
    turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')),60) || ' seconds')::interval
    WHERE id = _game_id;

  IF next_turn = 1 - my_slot
     AND NOT public._fanorona_player_has_move(board, opp_color, v_cols, v_rows) THEN
    PERFORM public._fanorona_finalize(_game_id, my_slot); RETURN;
  END IF;

  IF no_cap >= 20
     AND NOT public._fanorona_player_can_capture(board, my_color, v_cols, v_rows)
     AND NOT public._fanorona_player_can_capture(board, opp_color, v_cols, v_rows) THEN
    PERFORM public._fanorona_draw_refund(_game_id); RETURN;
  END IF;

  PERFORM public.fanorona_bot_play(_game_id);
END $$;

-- 6) fanorona_tick: bot plays if its turn
CREATE OR REPLACE FUNCTION public.fanorona_tick(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  g record; cur_uid uuid; _cfg record; _skips int; _next int; v_is_bot boolean;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

  SELECT COALESCE(is_bot,false), user_id INTO v_is_bot, cur_uid
    FROM public.fanorona_participants WHERE game_id = _game_id AND slot = g.current_turn;

  IF v_is_bot THEN
    PERFORM public.fanorona_bot_play(_game_id); RETURN;
  END IF;

  IF g.turn_deadline IS NULL OR g.turn_deadline > now() THEN RETURN; END IF;
  SELECT * INTO _cfg FROM public._game_cfg('fanorona');
  _skips := COALESCE((g.turn_skips->>cur_uid::text)::int, 0) + 1;
  IF _skips >= _cfg.max_turn_skips THEN
    UPDATE public.fanorona_participants SET forfeited = true WHERE game_id = _game_id AND user_id = cur_uid;
    PERFORM public._fanorona_finalize(_game_id, 1 - g.current_turn); RETURN;
  END IF;
  _next := 1 - g.current_turn;
  UPDATE public.fanorona_games SET
    current_turn = _next,
    turn_skips = jsonb_set(g.turn_skips, ARRAY[cur_uid::text], to_jsonb(_skips)),
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
  WHERE id = _game_id;
  SELECT COALESCE(is_bot,false) INTO v_is_bot FROM public.fanorona_participants
    WHERE game_id = _game_id AND slot = _next;
  IF v_is_bot THEN PERFORM public.fanorona_bot_play(_game_id); END IF;
END $$;
GRANT EXECUTE ON FUNCTION public.fanorona_tick(uuid) TO authenticated;
