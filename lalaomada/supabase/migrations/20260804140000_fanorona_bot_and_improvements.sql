-- Fanorona: Bot AI + solo mode + improvements

-- 0) Make user_id nullable for bot participants
ALTER TABLE public.fanorona_participants ALTER COLUMN user_id DROP NOT NULL;

-- 1) Add is_bot column to fanorona_participants
ALTER TABLE public.fanorona_participants
  ADD COLUMN IF NOT EXISTS is_bot boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS bot_intelligence int NOT NULL DEFAULT 3;

-- 2) Add bot_intelligence to fanorona_games
ALTER TABLE public.fanorona_games
  ADD COLUMN IF NOT EXISTS bot_intelligence int DEFAULT 3;

-- 3) Internal play function: plays by slot, no auth check (for bot use)
CREATE OR REPLACE FUNCTION public._fanorona_play_by_slot(_game_id uuid, _move jsonb, _slot int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
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
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  IF g.current_turn <> _slot THEN RAISE EXCEPTION 'not your turn'; END IF;

  v_cols := COALESCE(g.cols, 9); v_rows := COALESCE(g.rows, 5);
  my_color  := CASE WHEN _slot = 0 THEN 1 ELSE 2 END;
  opp_color := CASE WHEN _slot = 0 THEN 2 ELSE 1 END;
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
    UPDATE public.fanorona_games SET state = st, current_turn = next_turn,
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
  IF abs(dr) > 1 OR abs(dc) > 1 OR (dr = 0 AND dc = 0) THEN RAISE EXCEPTION 'invalid step'; END IF;
  is_strong := ((fr + fc) % 2 = 0);
  IF NOT is_strong AND (dr <> 0 AND dc <> 0) THEN RAISE EXCEPTION 'diagonal not allowed here'; END IF;
  axis := public._fanorona_axis(dr, dc);

  IF chain_from_v IS NOT NULL THEN
    IF visited @> to_jsonb(to_idx) THEN RAISE EXCEPTION 'cannot revisit cell'; END IF;
    IF last_axis IS NOT NULL AND axis = last_axis THEN RAISE EXCEPTION 'cannot continue on same axis'; END IF;
  END IF;

  lists := public._fanorona_capture_lists(board, my_color, from_idx, to_idx, v_cols, v_rows);
  IF jsonb_array_length(cap) > 0 THEN
    IF NOT (cap = (lists->'approach') OR cap = (lists->'withdrawal')) THEN RAISE EXCEPTION 'invalid capture set'; END IF;
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

  SELECT count(*) INTO opp_left FROM jsonb_array_elements(board) v WHERE (v::text)::int = opp_color;
  IF opp_left = 0 THEN
    UPDATE public.fanorona_games SET state = st WHERE id = _game_id;
    PERFORM public._fanorona_finalize(_game_id, _slot);
    RETURN;
  END IF;

  IF jsonb_array_length(cap) = 0 THEN
    next_turn := 1 - _slot;
    st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
    st := jsonb_set(st, '{visited}',    '[]'::jsonb);
    st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
    st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
  ELSE
    IF move_count = 0 THEN
      next_turn := 1 - _slot;
      st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
      st := jsonb_set(st, '{visited}',    '[]'::jsonb);
      st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
      st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
    ELSE
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
  END IF;

  UPDATE public.fanorona_games SET state = st, current_turn = next_turn,
    turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')),60) || ' seconds')::interval
    WHERE id = _game_id;

  IF next_turn = 1 - _slot AND NOT public._fanorona_player_has_move(board, opp_color, v_cols, v_rows) THEN
    PERFORM public._fanorona_finalize(_game_id, _slot);
  END IF;
END $$;

-- 4) fanorona_play: delegates to _fanorona_play_by_slot
CREATE OR REPLACE FUNCTION public.fanorona_play(_game_id uuid, _move jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_uid uuid := auth.uid(); my_slot int;
BEGIN
  SELECT slot INTO my_slot FROM public.fanorona_participants
    WHERE game_id = _game_id AND user_id = v_uid;
  IF my_slot IS NULL THEN RAISE EXCEPTION 'not a participant'; END IF;
  PERFORM public._fanorona_play_by_slot(_game_id, _move, my_slot);
END $$;

-- 5) Fanorona create solo game
CREATE OR REPLACE FUNCTION public.fanorona_create_solo(
  _stake numeric DEFAULT 0,
  _variant text DEFAULT 'tsivy',
  _mandatory_capture boolean DEFAULT true,
  _bot_intelligence int DEFAULT 3
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
  v_name text;
  v_cols int; v_rows int;
  v_bot_name text;
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
  INSERT INTO public.fanorona_games(host_id, max_players, stake, pot, commission_pct, is_private, room_code,
    state, cols, rows, variant, mandatory_capture, bot_intelligence, status, started_at)
  VALUES (v_uid, 2, 0, 0, 0, true, null,
    jsonb_build_object('phase','playing','board', public._fanorona_init_board(v_cols, v_rows),'chain_from',null,'chain_dirs','[]'::jsonb,'move_count',0,'visited','[]'::jsonb,'last_axis',null),
    v_cols, v_rows, _variant, COALESCE(_mandatory_capture, true), COALESCE(_bot_intelligence, 3), 'playing', now())
  RETURNING id INTO v_id;
  INSERT INTO public.fanorona_participants(game_id, user_id, slot, color, display_name, is_bot)
  VALUES (v_id, v_uid, 0, 'white', COALESCE(v_name, 'Joueur'), false);
  INSERT INTO public.fanorona_participants(game_id, user_id, slot, color, display_name, is_bot, bot_intelligence)
  VALUES (v_id, NULL, 1, 'black', 'Bot ' || v_bot_name, true, COALESCE(_bot_intelligence, 3));
  UPDATE public.fanorona_games SET current_turn = 0,
    turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')), 60) || ' seconds')::interval
    WHERE id = v_id;
  RETURN v_id;
END $$;

-- 6) Fanorona bot play
CREATE OR REPLACE FUNCTION public.fanorona_bot_play(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  g record; bot_slot int; bot_color int; opp_color int;
  st jsonb; board jsonb;
  v_cols int; v_rows int; v_intelligence int;
  chain_from_v int; visited jsonb; last_axis text; move_count int;
  best_from int; best_to int; best_cap jsonb; best_score int := -99999;
  i int; r int; c int; dr int; dc int; nr int; nc int; nidx int;
  is_strong boolean; axis text; lists jsonb; cap_count int; score int;
  has_capture boolean := false; tmp_board jsonb; j int;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  SELECT slot, bot_intelligence INTO bot_slot, v_intelligence
    FROM public.fanorona_participants WHERE game_id = _game_id AND is_bot = true;
  IF bot_slot IS NULL THEN RAISE EXCEPTION 'no bot'; END IF;
  IF g.current_turn <> bot_slot THEN RAISE EXCEPTION 'not bot turn'; END IF;

  v_cols := COALESCE(g.cols, 9); v_rows := COALESCE(g.rows, 5);
  bot_color := CASE WHEN bot_slot = 0 THEN 1 ELSE 2 END;
  opp_color := CASE WHEN bot_slot = 0 THEN 2 ELSE 1 END;
  st := g.state; board := st -> 'board';
  move_count := COALESCE((st->>'move_count')::int, 0);
  visited := COALESCE(st->'visited', '[]'::jsonb);
  last_axis := NULLIF(st->>'last_axis', '');
  chain_from_v := CASE WHEN st->'chain_from' IS NULL OR st->'chain_from' = 'null'::jsonb THEN NULL ELSE (st->>'chain_from')::int END;

  IF chain_from_v IS NOT NULL THEN
    r := chain_from_v / v_cols; c := chain_from_v % v_cols;
    is_strong := ((r + c) % 2 = 0);
    FOR dr, dc IN SELECT a,b FROM (VALUES (-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)) v(a,b) LOOP
      IF NOT is_strong AND (dr<>0 AND dc<>0) THEN CONTINUE; END IF;
      nr := r+dr; nc := c+dc;
      IF nr<0 OR nr>=v_rows OR nc<0 OR nc>=v_cols THEN CONTINUE; END IF;
      nidx := nr*v_cols+nc;
      IF (board->nidx)::int <> 0 THEN CONTINUE; END IF;
      IF visited @> to_jsonb(nidx) THEN CONTINUE; END IF;
      axis := public._fanorona_axis(dr, dc);
      IF last_axis IS NOT NULL AND axis = last_axis THEN CONTINUE; END IF;
      lists := public._fanorona_capture_lists(board, bot_color, chain_from_v, nidx, v_cols, v_rows);
      IF jsonb_array_length(lists->'approach') > 0 OR jsonb_array_length(lists->'withdrawal') > 0 THEN
        IF jsonb_array_length(lists->'approach') >= jsonb_array_length(lists->'withdrawal') THEN
          PERFORM public._fanorona_play_by_slot(_game_id, jsonb_build_object('from',chain_from_v,'to',nidx,'captured',lists->'approach','chain',false), bot_slot);
        ELSE
          PERFORM public._fanorona_play_by_slot(_game_id, jsonb_build_object('from',chain_from_v,'to',nidx,'captured',lists->'withdrawal','chain',false), bot_slot);
        END IF;
        RETURN;
      END IF;
    END LOOP;
    PERFORM public._fanorona_play_by_slot(_game_id, jsonb_build_object('pass',true), bot_slot);
    RETURN;
  END IF;

  has_capture := public._fanorona_player_can_capture(board, bot_color, v_cols, v_rows);
  FOR i IN 0..(v_cols*v_rows-1) LOOP
    IF (board->i)::int <> bot_color THEN CONTINUE; END IF;
    r := i/v_cols; c := i%v_cols; is_strong := ((r+c)%2=0);
    FOR dr, dc IN SELECT a,b FROM (VALUES (-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)) v(a,b) LOOP
      IF NOT is_strong AND (dr<>0 AND dc<>0) THEN CONTINUE; END IF;
      nr := r+dr; nc := c+dc;
      IF nr<0 OR nr>=v_rows OR nc<0 OR nc>=v_cols THEN CONTINUE; END IF;
      nidx := nr*v_cols+nc;
      IF (board->nidx)::int <> 0 THEN CONTINUE; END IF;
      lists := public._fanorona_capture_lists(board, bot_color, i, nidx, v_cols, v_rows);
      cap_count := GREATEST(jsonb_array_length(lists->'approach'), jsonb_array_length(lists->'withdrawal'));
      IF has_capture AND COALESCE(g.mandatory_capture, true) AND cap_count = 0 THEN CONTINUE; END IF;
      score := cap_count*100 + (v_cols - abs(c - v_cols/2)) + (v_rows - abs(r - v_rows/2));
      IF v_intelligence <= 2 THEN score := score + (random()*50)::int;
      ELSIF v_intelligence = 3 THEN score := score + (random()*20)::int;
      ELSE
        tmp_board := board;
        tmp_board := jsonb_set(tmp_board, ARRAY[i::text], '0'::jsonb);
        tmp_board := jsonb_set(tmp_board, ARRAY[nidx::text], to_jsonb(bot_color));
        IF cap_count > 0 THEN
          IF jsonb_array_length(lists->'approach') >= jsonb_array_length(lists->'withdrawal') THEN
            FOR j IN 0..jsonb_array_length(lists->'approach')-1 LOOP
              tmp_board := jsonb_set(tmp_board, ARRAY[((lists->'approach'->j)::int)::text], '0'::jsonb);
            END LOOP;
          ELSE
            FOR j IN 0..jsonb_array_length(lists->'withdrawal')-1 LOOP
              tmp_board := jsonb_set(tmp_board, ARRAY[((lists->'withdrawal'->j)::int)::text], '0'::jsonb);
            END LOOP;
          END IF;
        END IF;
        IF public._fanorona_player_can_capture(tmp_board, opp_color, v_cols, v_rows) THEN score := score - 50; END IF;
      END IF;
      IF score > best_score THEN
        best_score := score; best_from := i; best_to := nidx;
        IF cap_count > 0 THEN
          IF jsonb_array_length(lists->'approach') >= jsonb_array_length(lists->'withdrawal') THEN best_cap := lists->'approach';
          ELSE best_cap := lists->'withdrawal'; END IF;
        ELSE best_cap := '[]'::jsonb; END IF;
      END IF;
    END LOOP;
  END LOOP;
  IF best_from IS NULL THEN
    PERFORM public._fanorona_play_by_slot(_game_id, jsonb_build_object('pass',true), bot_slot);
  ELSE
    PERFORM public._fanorona_play_by_slot(_game_id, jsonb_build_object('from',best_from,'to',best_to,'captured',best_cap,'chain',false), bot_slot);
  END IF;
END $$;

GRANT EXECUTE ON FUNCTION public._fanorona_play_by_slot(uuid, jsonb, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fanorona_play(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fanorona_create_solo TO authenticated;
GRANT EXECUTE ON FUNCTION public.fanorona_bot_play(uuid) TO authenticated;
