
-- Helper: normalise un axe rectiligne (les vecteurs opposés donnent la même clé)
CREATE OR REPLACE FUNCTION public._fanorona_axis(_dr int, _dc int)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN _dr < 0 OR (_dr = 0 AND _dc < 0)
              THEN (-_dr)::text || ',' || (-_dc)::text
              ELSE _dr::text || ',' || _dc::text END
$$;

-- Helper: calcule les listes de capture approche/éloignement pour un coup donné
CREATE OR REPLACE FUNCTION public._fanorona_capture_lists(_board jsonb, _my int, _from int, _to int)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  opp int := CASE WHEN _my = 1 THEN 2 ELSE 1 END;
  fr int := _from / 9; fc int := _from % 9;
  tr int := _to / 9;   tc int := _to % 9;
  dr int := tr - fr;   dc int := tc - fc;
  ap jsonb := '[]'::jsonb; wd jsonb := '[]'::jsonb;
  r int; c int; idx int;
BEGIN
  r := tr + dr; c := tc + dc;
  WHILE r >= 0 AND r < 5 AND c >= 0 AND c < 9 LOOP
    idx := r * 9 + c;
    EXIT WHEN (_board->idx)::int <> opp;
    ap := ap || to_jsonb(idx);
    r := r + dr; c := c + dc;
  END LOOP;
  r := fr - dr; c := fc - dc;
  WHILE r >= 0 AND r < 5 AND c >= 0 AND c < 9 LOOP
    idx := r * 9 + c;
    EXIT WHEN (_board->idx)::int <> opp;
    wd := wd || to_jsonb(idx);
    r := r - dr; c := c - dc;
  END LOOP;
  RETURN jsonb_build_object('approach', ap, 'withdrawal', wd);
END $$;

-- Helper: un pion peut-il capturer (en respectant visited+last_axis) ?
CREATE OR REPLACE FUNCTION public._fanorona_piece_can_capture(
  _board jsonb, _my int, _idx int, _visited jsonb, _last_axis text
) RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  r int := _idx / 9; c int := _idx % 9;
  is_strong boolean := ((r + c) % 2 = 0);
  dr int; dc int; nr int; nc int; nidx int;
  axis text; lists jsonb;
BEGIN
  FOR dr, dc IN
    SELECT a, b FROM (VALUES (-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)) v(a,b)
  LOOP
    IF NOT is_strong AND (dr <> 0 AND dc <> 0) THEN CONTINUE; END IF;
    nr := r + dr; nc := c + dc;
    IF nr < 0 OR nr >= 5 OR nc < 0 OR nc >= 9 THEN CONTINUE; END IF;
    nidx := nr * 9 + nc;
    IF (_board->nidx)::int <> 0 THEN CONTINUE; END IF;
    IF _visited @> to_jsonb(nidx) THEN CONTINUE; END IF;
    axis := public._fanorona_axis(dr, dc);
    IF _last_axis IS NOT NULL AND axis = _last_axis THEN CONTINUE; END IF;
    lists := public._fanorona_capture_lists(_board, _my, _idx, nidx);
    IF jsonb_array_length(lists->'approach') > 0
       OR jsonb_array_length(lists->'withdrawal') > 0 THEN
      RETURN true;
    END IF;
  END LOOP;
  RETURN false;
END $$;

-- Helper: le joueur a-t-il au moins une capture sur tout le plateau ?
CREATE OR REPLACE FUNCTION public._fanorona_player_can_capture(_board jsonb, _my int)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE i int;
BEGIN
  FOR i IN 0..44 LOOP
    IF (_board->i)::int = _my
       AND public._fanorona_piece_can_capture(_board, _my, i, '[]'::jsonb, NULL) THEN
      RETURN true;
    END IF;
  END LOOP;
  RETURN false;
END $$;

-- Helper: le joueur a-t-il au moins un coup légal (capture ou mouvement sec) ?
CREATE OR REPLACE FUNCTION public._fanorona_player_has_move(_board jsonb, _my int)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE i int; r int; c int; dr int; dc int; nr int; nc int;
BEGIN
  FOR i IN 0..44 LOOP
    IF (_board->i)::int <> _my THEN CONTINUE; END IF;
    r := i / 9; c := i % 9;
    FOR dr, dc IN
      SELECT a, b FROM (VALUES (-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)) v(a,b)
    LOOP
      IF (r + c) % 2 <> 0 AND (dr <> 0 AND dc <> 0) THEN CONTINUE; END IF;
      nr := r + dr; nc := c + dc;
      IF nr < 0 OR nr >= 5 OR nc < 0 OR nc >= 9 THEN CONTINUE; END IF;
      IF (_board->(nr * 9 + nc))::int = 0 THEN RETURN true; END IF;
    END LOOP;
  END LOOP;
  RETURN false;
END $$;

-- fanorona_play réécrit avec toutes les règles
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
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  SELECT slot INTO my_slot FROM public.fanorona_participants
    WHERE game_id = _game_id AND user_id = v_uid;
  IF my_slot IS NULL OR my_slot <> g.current_turn THEN RAISE EXCEPTION 'not your turn'; END IF;

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

  -- Termine volontairement la rafale
  IF is_pass THEN
    IF chain_from_v IS NULL THEN RAISE EXCEPTION 'no chain in progress'; END IF;
    next_turn := 1 - my_slot;
    st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
    st := jsonb_set(st, '{visited}',    '[]'::jsonb);
    st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
    st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
    UPDATE public.fanorona_games SET state = st, current_turn = next_turn WHERE id = _game_id;
    IF NOT public._fanorona_player_has_move(board, opp_color) THEN
      PERFORM public._fanorona_finalize(_game_id, my_slot);
    END IF;
    RETURN;
  END IF;

  from_idx := (_move->>'from')::int;
  to_idx   := (_move->>'to')::int;
  cap      := COALESCE(_move->'captured', '[]'::jsonb);

  -- En rafale: même pion obligatoire
  IF chain_from_v IS NOT NULL AND from_idx <> chain_from_v THEN
    RAISE EXCEPTION 'must continue with same piece';
  END IF;

  IF (board->from_idx)::int <> my_color THEN RAISE EXCEPTION 'not your piece'; END IF;
  IF (board->to_idx)::int <> 0 THEN RAISE EXCEPTION 'target not empty'; END IF;

  fr := from_idx / 9; fc := from_idx % 9;
  tr := to_idx   / 9; tc := to_idx   % 9;
  dr := tr - fr;      dc := tc - fc;
  IF abs(dr) > 1 OR abs(dc) > 1 OR (dr = 0 AND dc = 0) THEN
    RAISE EXCEPTION 'invalid step';
  END IF;
  is_strong := ((fr + fc) % 2 = 0);
  IF NOT is_strong AND (dr <> 0 AND dc <> 0) THEN
    RAISE EXCEPTION 'diagonal not allowed here';
  END IF;
  axis := public._fanorona_axis(dr, dc);

  -- Règles de rafale: pas de retour, pas le même axe que le pas précédent
  IF chain_from_v IS NOT NULL THEN
    IF visited @> to_jsonb(to_idx) THEN RAISE EXCEPTION 'cannot revisit cell'; END IF;
    IF last_axis IS NOT NULL AND axis = last_axis THEN
      RAISE EXCEPTION 'cannot continue on same axis';
    END IF;
  END IF;

  -- Validation de la capture envoyée par le client
  lists := public._fanorona_capture_lists(board, my_color, from_idx, to_idx);
  IF jsonb_array_length(cap) > 0 THEN
    IF NOT (cap = (lists->'approach') OR cap = (lists->'withdrawal')) THEN
      RAISE EXCEPTION 'invalid capture set';
    END IF;
  END IF;

  -- Capture obligatoire si possible (mouvement sec interdit)
  IF jsonb_array_length(cap) = 0 THEN
    IF chain_from_v IS NOT NULL THEN
      RAISE EXCEPTION 'must capture during chain';
    END IF;
    IF public._fanorona_player_can_capture(board, my_color) THEN
      RAISE EXCEPTION 'capture is mandatory when available';
    END IF;
  END IF;

  -- Applique le déplacement
  board := jsonb_set(board, ARRAY[from_idx::text], '0'::jsonb);
  board := jsonb_set(board, ARRAY[to_idx::text],   to_jsonb(my_color));
  IF jsonb_array_length(cap) > 0 THEN
    FOR i IN 0..jsonb_array_length(cap) - 1 LOOP
      board := jsonb_set(board, ARRAY[((cap->i)::int)::text], '0'::jsonb);
    END LOOP;
  END IF;
  st := jsonb_set(st, '{board}', board);

  -- Victoire par élimination
  SELECT count(*) INTO opp_left FROM jsonb_array_elements(board) v
    WHERE (v::text)::int = opp_color;
  IF opp_left = 0 THEN
    UPDATE public.fanorona_games SET state = st WHERE id = _game_id;
    PERFORM public._fanorona_finalize(_game_id, my_slot);
    RETURN;
  END IF;

  -- Décide rafale ou fin de tour
  IF jsonb_array_length(cap) = 0 THEN
    -- Mouvement sec (autorisé seulement parce qu'aucune capture n'est possible)
    next_turn := 1 - my_slot;
    st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
    st := jsonb_set(st, '{visited}',    '[]'::jsonb);
    st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
    st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
  ELSE
    -- Capture effectuée
    -- Premier coup global: une seule capture autorisée
    IF move_count = 0 THEN
      next_turn := 1 - my_slot;
      st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
      st := jsonb_set(st, '{visited}',    '[]'::jsonb);
      st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
      st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
    ELSE
      visited := visited || to_jsonb(from_idx) || to_jsonb(to_idx);
      IF public._fanorona_piece_can_capture(board, my_color, to_idx, visited, axis) THEN
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

  UPDATE public.fanorona_games SET state = st, current_turn = next_turn WHERE id = _game_id;

  -- Blocage de l'adversaire au tour suivant → nul
  IF next_turn = 1 - my_slot
     AND NOT public._fanorona_player_has_move(board, opp_color) THEN
    PERFORM public._fanorona_finalize(_game_id, my_slot);
  END IF;
END
$function$;
