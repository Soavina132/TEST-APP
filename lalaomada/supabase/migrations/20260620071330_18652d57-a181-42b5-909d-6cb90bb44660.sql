
-- 1) Chat: opponents in chess/fanorona/domino/rami couldn't receive in-game messages
--    because _is_game_participant only checked ludo_participants.
CREATE OR REPLACE FUNCTION public._is_game_participant(_game_id uuid, _user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT
    EXISTS (SELECT 1 FROM public.ludo_participants     WHERE game_id = _game_id AND user_id = _user_id)
 OR EXISTS (SELECT 1 FROM public.domino_participants   WHERE game_id = _game_id AND user_id = _user_id)
 OR EXISTS (SELECT 1 FROM public.fanorona_participants WHERE game_id = _game_id AND user_id = _user_id)
 OR EXISTS (SELECT 1 FROM public.rami_participants     WHERE game_id = _game_id AND user_id = _user_id)
 OR EXISTS (SELECT 1 FROM public.chess_games
              WHERE id = _game_id AND (white_id = _user_id OR black_id = _user_id))
$$;

-- 2) Fanorona variants + mandatory_capture toggle
ALTER TABLE public.fanorona_games
  ADD COLUMN IF NOT EXISTS cols int NOT NULL DEFAULT 9,
  ADD COLUMN IF NOT EXISTS rows int NOT NULL DEFAULT 5,
  ADD COLUMN IF NOT EXISTS variant text NOT NULL DEFAULT 'tsivy',
  ADD COLUMN IF NOT EXISTS mandatory_capture boolean NOT NULL DEFAULT true;

-- 3) Init board parametrised by variant. Pattern: own pieces on lower half, opponent on upper half,
--    middle row alternates with an empty centre.
CREATE OR REPLACE FUNCTION public._fanorona_init_board(_cols int, _rows int)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  r int; c int; mid int; v int;
  arr jsonb := '[]'::jsonb;
BEGIN
  mid := _rows / 2;
  FOR r IN 0.._rows - 1 LOOP
    FOR c IN 0.._cols - 1 LOOP
      IF r < mid THEN v := 2;
      ELSIF r > mid THEN v := 1;
      ELSE
        -- middle row: alternate, with centre empty
        IF c = _cols / 2 THEN v := 0;
        ELSIF ((c < _cols / 2) = (c % 2 = 0)) THEN v := 1; ELSE v := 2;
        END IF;
      END IF;
      arr := arr || to_jsonb(v);
    END LOOP;
  END LOOP;
  RETURN arr;
END $$;

-- Keep the legacy no-arg version for any callers; default to 9x5.
CREATE OR REPLACE FUNCTION public._fanorona_init_board()
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT public._fanorona_init_board(9, 5);
$$;

-- 4) Helpers parametrised by board dimensions
CREATE OR REPLACE FUNCTION public._fanorona_capture_lists(_board jsonb, _my integer, _from integer, _to integer, _cols int, _rows int)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  opp int := CASE WHEN _my = 1 THEN 2 ELSE 1 END;
  fr int := _from / _cols; fc int := _from % _cols;
  tr int := _to / _cols;   tc int := _to % _cols;
  dr int := tr - fr;       dc int := tc - fc;
  ap jsonb := '[]'::jsonb; wd jsonb := '[]'::jsonb;
  r int; c int; idx int;
BEGIN
  r := tr + dr; c := tc + dc;
  WHILE r >= 0 AND r < _rows AND c >= 0 AND c < _cols LOOP
    idx := r * _cols + c;
    EXIT WHEN (_board->idx)::int <> opp;
    ap := ap || to_jsonb(idx);
    r := r + dr; c := c + dc;
  END LOOP;
  r := fr - dr; c := fc - dc;
  WHILE r >= 0 AND r < _rows AND c >= 0 AND c < _cols LOOP
    idx := r * _cols + c;
    EXIT WHEN (_board->idx)::int <> opp;
    wd := wd || to_jsonb(idx);
    r := r - dr; c := c - dc;
  END LOOP;
  RETURN jsonb_build_object('approach', ap, 'withdrawal', wd);
END $$;

CREATE OR REPLACE FUNCTION public._fanorona_piece_can_capture(_board jsonb, _my integer, _idx integer, _visited jsonb, _last_axis text, _cols int, _rows int)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  r int := _idx / _cols; c int := _idx % _cols;
  is_strong boolean := ((r + c) % 2 = 0);
  dr int; dc int; nr int; nc int; nidx int;
  axis text; lists jsonb;
BEGIN
  FOR dr, dc IN
    SELECT a, b FROM (VALUES (-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)) v(a,b)
  LOOP
    IF NOT is_strong AND (dr <> 0 AND dc <> 0) THEN CONTINUE; END IF;
    nr := r + dr; nc := c + dc;
    IF nr < 0 OR nr >= _rows OR nc < 0 OR nc >= _cols THEN CONTINUE; END IF;
    nidx := nr * _cols + nc;
    IF (_board->nidx)::int <> 0 THEN CONTINUE; END IF;
    IF _visited @> to_jsonb(nidx) THEN CONTINUE; END IF;
    axis := public._fanorona_axis(dr, dc);
    IF _last_axis IS NOT NULL AND axis = _last_axis THEN CONTINUE; END IF;
    lists := public._fanorona_capture_lists(_board, _my, _idx, nidx, _cols, _rows);
    IF jsonb_array_length(lists->'approach') > 0
       OR jsonb_array_length(lists->'withdrawal') > 0 THEN
      RETURN true;
    END IF;
  END LOOP;
  RETURN false;
END $$;

CREATE OR REPLACE FUNCTION public._fanorona_player_can_capture(_board jsonb, _my integer, _cols int, _rows int)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE i int;
BEGIN
  FOR i IN 0..(_cols * _rows - 1) LOOP
    IF (_board->i)::int = _my
       AND public._fanorona_piece_can_capture(_board, _my, i, '[]'::jsonb, NULL, _cols, _rows) THEN
      RETURN true;
    END IF;
  END LOOP;
  RETURN false;
END $$;

CREATE OR REPLACE FUNCTION public._fanorona_player_has_move(_board jsonb, _my integer, _cols int, _rows int)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE i int; r int; c int; dr int; dc int; nr int; nc int;
BEGIN
  FOR i IN 0..(_cols * _rows - 1) LOOP
    IF (_board->i)::int <> _my THEN CONTINUE; END IF;
    r := i / _cols; c := i % _cols;
    FOR dr, dc IN
      SELECT a, b FROM (VALUES (-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)) v(a,b)
    LOOP
      IF (r + c) % 2 <> 0 AND (dr <> 0 AND dc <> 0) THEN CONTINUE; END IF;
      nr := r + dr; nc := c + dc;
      IF nr < 0 OR nr >= _rows OR nc < 0 OR nc >= _cols THEN CONTINUE; END IF;
      IF (_board->(nr * _cols + nc))::int = 0 THEN RETURN true; END IF;
    END LOOP;
  END LOOP;
  RETURN false;
END $$;

-- Keep legacy 9x5 wrappers so old call sites stay valid.
CREATE OR REPLACE FUNCTION public._fanorona_capture_lists(_board jsonb, _my integer, _from integer, _to integer)
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT public._fanorona_capture_lists(_board, _my, _from, _to, 9, 5);
$$;
CREATE OR REPLACE FUNCTION public._fanorona_piece_can_capture(_board jsonb, _my integer, _idx integer, _visited jsonb, _last_axis text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT public._fanorona_piece_can_capture(_board, _my, _idx, _visited, _last_axis, 9, 5);
$$;
CREATE OR REPLACE FUNCTION public._fanorona_player_can_capture(_board jsonb, _my integer)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT public._fanorona_player_can_capture(_board, _my, 9, 5);
$$;
CREATE OR REPLACE FUNCTION public._fanorona_player_has_move(_board jsonb, _my integer)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT public._fanorona_player_has_move(_board, _my, 9, 5);
$$;

-- 5) Updated fanorona_create with variant + mandatory_capture
CREATE OR REPLACE FUNCTION public.fanorona_create(_stake numeric, _private boolean, _commission numeric DEFAULT 10, _variant text DEFAULT 'tsivy', _mandatory_capture boolean DEFAULT true)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_balance numeric;
  v_code text;
  v_id uuid;
  v_name text;
  v_cols int; v_rows int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'invalid stake'; END IF;

  CASE _variant
    WHEN 'telo'  THEN v_cols := 3; v_rows := 3;
    WHEN 'dimy'  THEN v_cols := 5; v_rows := 5;
    WHEN 'tsivy' THEN v_cols := 9; v_rows := 5;
    ELSE v_cols := 9; v_rows := 5; _variant := 'tsivy';
  END CASE;

  SELECT balance_ar, pseudo INTO v_balance, v_name FROM public.profiles WHERE id = v_uid;
  IF v_balance < _stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;
  IF _private THEN v_code := upper(substring(md5(random()::text||clock_timestamp()::text) from 1 for 6)); END IF;

  INSERT INTO public.fanorona_games(host_id, stake, pot, commission_pct, is_private, room_code, state, cols, rows, variant, mandatory_capture)
  VALUES (v_uid, _stake, _stake, _commission, _private, v_code,
    jsonb_build_object('phase','waiting','board', public._fanorona_init_board(v_cols, v_rows), 'chain_from', null, 'chain_dirs', '[]'::jsonb),
    v_cols, v_rows, _variant, COALESCE(_mandatory_capture, true))
  RETURNING id INTO v_id;

  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note) VALUES (v_uid, 'fanorona_stake', -_stake, v_id, 'Create fanorona');
  INSERT INTO public.fanorona_participants(game_id, user_id, slot, color, display_name) VALUES (v_id, v_uid, 0, 'white', COALESCE(v_name,'Player'));
  RETURN v_id;
END $$;

-- 6) Updated fanorona_play: dimension-aware, optional mandatory capture, voluntary pass any time
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
  last_axis text;
  axis text;
  chain_from_v int;
  i int;
  v_cols int; v_rows int;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  SELECT slot INTO my_slot FROM public.fanorona_participants
    WHERE game_id = _game_id AND user_id = v_uid;
  IF my_slot IS NULL OR my_slot <> g.current_turn THEN RAISE EXCEPTION 'not your turn'; END IF;

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

  is_pass := COALESCE((_move->>'pass')::boolean, false);

  IF is_pass THEN
    -- Voluntary pass: ending a capture chain OR skipping a turn entirely.
    next_turn := 1 - my_slot;
    st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
    st := jsonb_set(st, '{visited}',    '[]'::jsonb);
    st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
    st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
    UPDATE public.fanorona_games SET state = st, current_turn = next_turn,
      turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')),60) || ' seconds')::interval
      WHERE id = _game_id;
    IF NOT public._fanorona_player_has_move(board, opp_color, v_cols, v_rows) THEN
      PERFORM public._fanorona_finalize(_game_id, my_slot);
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
    -- Only enforce mandatory capture when the game says so.
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
    UPDATE public.fanorona_games SET state = st WHERE id = _game_id;
    PERFORM public._fanorona_finalize(_game_id, my_slot);
    RETURN;
  END IF;

  IF jsonb_array_length(cap) = 0 THEN
    next_turn := 1 - my_slot;
    st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
    st := jsonb_set(st, '{visited}',    '[]'::jsonb);
    st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
    st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
  ELSE
    IF move_count = 0 THEN
      next_turn := 1 - my_slot;
      st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
      st := jsonb_set(st, '{visited}',    '[]'::jsonb);
      st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
      st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
    ELSE
      visited := visited || to_jsonb(from_idx) || to_jsonb(to_idx);
      IF public._fanorona_piece_can_capture(board, my_color, to_idx, visited, axis, v_cols, v_rows) THEN
        next_turn := my_slot;
        st := jsonb_set(st, '{chain_from}', to_jsonb(to_idx));
        st := jsonb_set(st, '{visited}',    visited);
        st := jsonb_set(st, '{last_axis}',  to_jsonb(axis));
      ELSE
        next_turn := 1 - my_slot;
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

  IF next_turn = 1 - my_slot
     AND NOT public._fanorona_player_has_move(board, opp_color, v_cols, v_rows) THEN
    PERFORM public._fanorona_finalize(_game_id, my_slot);
  END IF;
END $$;
