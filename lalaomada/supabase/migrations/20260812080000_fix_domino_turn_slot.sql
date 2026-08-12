-- Fix: domino_play lisait state.turn_slot qui est NULL après _domino_next_round,
-- _domino_place_first ou domino_tick (qui mettent à jour current_turn colonne
-- mais pas state.turn_slot dans le JSON). → "Tuile non trouvée dans la main"
--
-- Solution: COALESCE sur g.current_turn + set turn_slot dans toutes les fonctions.

-- ── 1. Fix domino_play : fallback sur current_turn ──
CREATE OR REPLACE FUNCTION public.domino_play(_game_id uuid, _move jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  g public.domino_games%ROWTYPE;
  st jsonb;
  v_slot INT;
  v_uid UUID := auth.uid();
  v_part record;
  v_action TEXT;
  v_tile_idx INT;
  v_side TEXT;
  v_playable jsonb;
  hand jsonb;
  tile jsonb;
  a INT; b INT;
  left_end INT; right_end INT;
  board jsonb;
  first_move_double INT;
  first_tile_rule TEXT;
  v_new_left INT; v_new_right INT;
  v_board_entry jsonb;
  v_passes INT;
  v_last_pass INT;
  v_next_slot INT;
  v_stock_len INT;
  v_draw_mode TEXT;
  i INT;
  v_active_count INT;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;

  st := g.state;
  -- FIX: fallback sur current_turn si turn_slot manquant dans le state JSON
  v_slot := COALESCE(NULLIF(st->>'turn_slot','')::INT, g.current_turn);
  SELECT * INTO v_part FROM public.domino_participants
    WHERE game_id=_game_id AND slot=v_slot;

  IF v_part.user_id IS NOT NULL AND v_part.user_id <> v_uid THEN
    RAISE EXCEPTION 'Pas votre tour';
  END IF;

  v_action := _move->>'action';

  -- ─── PLAY action ──────────────────────────────────────────────
  IF v_action = 'play' THEN
    v_side := COALESCE(_move->>'side', 'auto');
    hand := st->'hands'->v_slot::text;

    -- Support both formats:
    --   1) { action:"play", tile_idx: 2 }  (index dans la main)
    --   2) { action:"play", tile: [3, 5] }  (valeurs de la tuile — format frontend actuel)
    IF _move ? 'tile_idx' AND (_move->>'tile_idx') IS NOT NULL THEN
      v_tile_idx := (_move->>'tile_idx')::INT;
    ELSIF _move ? 'tile' THEN
      tile := _move->'tile';
      v_tile_idx := -1;
      IF jsonb_array_length(hand) > 0 THEN
        FOR i IN 0..jsonb_array_length(hand)-1 LOOP
          IF ((hand->i->>0)::INT = (tile->>0)::INT AND (hand->i->>1)::INT = (tile->>1)::INT)
             OR ((hand->i->>0)::INT = (tile->>1)::INT AND (hand->i->>1)::INT = (tile->>0)::INT) THEN
            v_tile_idx := i;
            EXIT;
          END IF;
        END LOOP;
      END IF;
      IF v_tile_idx = -1 THEN
        RAISE EXCEPTION 'Tuile non trouvée dans la main: %', tile;
      END IF;
    ELSE
      RAISE EXCEPTION 'Move doit contenir tile ou tile_idx';
    END IF;

    v_playable := public._domino_playable_tiles(st, v_slot);
    IF NOT (v_playable @> to_jsonb(v_tile_idx)) THEN
      RAISE EXCEPTION 'Tuile non jouable';
    END IF;

    tile := hand->v_tile_idx;
    a := (tile->>0)::INT;
    b := (tile->>1)::INT;
    board := st->'board';
    left_end := NULLIF(st->>'left_end','')::INT;
    right_end := NULLIF(st->>'right_end','')::INT;
    first_move_double := NULLIF(st->>'first_move_double','')::INT;
    first_tile_rule := COALESCE(st->>'first_tile_rule', 'libre');

    IF jsonb_array_length(board) = 0 THEN
      IF first_move_double IS NOT NULL THEN
        IF NOT (a = first_move_double AND b = first_move_double) THEN
          RAISE EXCEPTION 'Doit jouer le double %', first_move_double;
        END IF;
      ELSIF first_tile_rule = 'under6' THEN
        IF a + b >= 6 THEN RAISE EXCEPTION 'Somme doit etre < 6'; END IF;
      END IF;
      v_new_left := a;
      v_new_right := b;
      v_board_entry := jsonb_build_array(jsonb_build_object('tile', jsonb_build_array(a,b), 'slot', v_slot));
      st := jsonb_set(st, ARRAY['board'], v_board_entry);
      st := jsonb_set(st, ARRAY['left_end'], to_jsonb(v_new_left));
      st := jsonb_set(st, ARRAY['right_end'], to_jsonb(v_new_right));
      st := st - 'first_move_double';
    ELSE
      IF v_side = 'left' OR (v_side = 'auto' AND (a = left_end OR b = left_end)) THEN
        IF b = left_end THEN
          v_board_entry := jsonb_build_array(jsonb_build_object('tile', jsonb_build_array(b,a), 'slot', v_slot)) || board;
        ELSIF a = left_end THEN
          v_board_entry := jsonb_build_array(jsonb_build_object('tile', jsonb_build_array(a,b), 'slot', v_slot)) || board;
        ELSE
          RAISE EXCEPTION 'Ne match pas le côté gauche';
        END IF;
        v_new_left := CASE WHEN b = left_end THEN a ELSE b END;
        v_new_right := right_end;
        st := jsonb_set(st, ARRAY['board'], v_board_entry);
        st := jsonb_set(st, ARRAY['left_end'], to_jsonb(v_new_left));
      ELSIF v_side = 'right' OR (v_side = 'auto' AND (a = right_end OR b = right_end)) THEN
        IF a = right_end THEN
          v_board_entry := board || jsonb_build_array(jsonb_build_object('tile', jsonb_build_array(a,b), 'slot', v_slot));
        ELSIF b = right_end THEN
          v_board_entry := board || jsonb_build_array(jsonb_build_object('tile', jsonb_build_array(b,a), 'slot', v_slot));
        ELSE
          RAISE EXCEPTION 'Ne match pas le côté droit';
        END IF;
        v_new_left := left_end;
        v_new_right := CASE WHEN a = right_end THEN b ELSE a END;
        st := jsonb_set(st, ARRAY['board'], v_board_entry);
        st := jsonb_set(st, ARRAY['right_end'], to_jsonb(v_new_right));
      ELSE
        RAISE EXCEPTION 'Tuile ne match ni gauche ni droite';
      END IF;
    END IF;

    -- Remove tile from hand
    hand := hand - v_tile_idx;
    st := jsonb_set(st, ARRAY['hands'], jsonb_set(st->'hands', ARRAY[v_slot::text], hand));

    -- Reset passes
    st := jsonb_set(st, ARRAY['passes'], '0'::jsonb);
    st := jsonb_set(st, ARRAY['last_pass_by'], 'null'::jsonb);

    -- Check if hand is empty (round winner)
    IF jsonb_array_length(hand) = 0 THEN
      PERFORM public._domino_end_round(_game_id, v_slot);
      RETURN public._domino_visible(_game_id);
    END IF;

    -- Advance turn
    v_next_slot := public._domino_next_playable_slot(_game_id, v_slot, st);
    st := jsonb_set(st, ARRAY['turn_slot'], to_jsonb(v_next_slot));
    st := jsonb_set(st, ARRAY['turn_started_at'], to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    v_playable := public._domino_playable_tiles(st, v_next_slot);
    st := jsonb_set(st, ARRAY['playable_tiles'], v_playable);
    st := jsonb_set(st, ARRAY['last_event'], to_jsonb('play'));

    UPDATE public.domino_games SET state=st, current_turn=v_next_slot WHERE id=_game_id;
    RETURN public._domino_visible(_game_id);

  -- ─── DRAW action ──────────────────────────────────────────────
  ELSIF v_action = 'draw' THEN
    v_stock_len := COALESCE(jsonb_array_length(st->'stock'), 0);
    IF v_stock_len = 0 THEN RAISE EXCEPTION 'Stock vide'; END IF;
    hand := st->'hands'->v_slot::text;
    tile := st->'stock'->0;
    st := jsonb_set(st, ARRAY['stock'], st->'stock' - 0);
    hand := hand || tile;
    st := jsonb_set(st, ARRAY['hands'], jsonb_set(st->'hands', ARRAY[v_slot::text], hand));
    v_playable := public._domino_playable_tiles(st, v_slot);
    st := jsonb_set(st, ARRAY['playable_tiles'], v_playable);
    st := jsonb_set(st, ARRAY['last_event'], to_jsonb('draw'));
    UPDATE public.domino_games SET state=st WHERE id=_game_id;
    RETURN public._domino_visible(_game_id);

  -- ─── PASS action ───────────────────────────────────────────────
  ELSIF v_action = 'pass' THEN
    v_playable := public._domino_playable_tiles(st, v_slot);
    IF jsonb_array_length(v_playable) > 0 THEN
      RAISE EXCEPTION 'Vous avez un domino jouable';
    END IF;
    v_draw_mode := COALESCE(st->>'draw_mode', 'with');
    v_stock_len := COALESCE(jsonb_array_length(st->'stock'), 0);
    IF v_draw_mode = 'with' AND v_stock_len > 0 THEN
      RAISE EXCEPTION 'Vous devez piocher avant de passer';
    END IF;

    v_passes := COALESCE((st->>'passes')::INT, 0) + 1;
    v_last_pass := v_slot;
    st := jsonb_set(st, ARRAY['passes'], to_jsonb(v_passes));
    st := jsonb_set(st, ARRAY['last_pass_by'], to_jsonb(v_last_pass));

    SELECT count(*) INTO v_active_count FROM public.domino_participants
      WHERE game_id=_game_id AND NOT forfeited;
    IF v_passes >= v_active_count THEN
      PERFORM public._domino_end_round(_game_id, public._domino_lowest_pip_slot(_game_id, st));
      RETURN public._domino_visible(_game_id);
    END IF;

    v_next_slot := public._domino_next_playable_slot(_game_id, v_slot, st);
    st := jsonb_set(st, ARRAY['turn_slot'], to_jsonb(v_next_slot));
    st := jsonb_set(st, ARRAY['turn_started_at'], to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    v_playable := public._domino_playable_tiles(st, v_next_slot);
    st := jsonb_set(st, ARRAY['playable_tiles'], v_playable);
    st := jsonb_set(st, ARRAY['last_event'], to_jsonb('pass'));
    UPDATE public.domino_games SET state=st, current_turn=v_next_slot WHERE id=_game_id;
    RETURN public._domino_visible(_game_id);

  ELSE
    RAISE EXCEPTION 'Action inconnue: %', v_action;
  END IF;
END
$$;

REVOKE EXECUTE ON FUNCTION public.domino_play(uuid, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.domino_play(uuid, jsonb) TO authenticated;

-- ── 2. Fix _domino_next_round : ajouter turn_slot + playable_tiles au state ──
CREATE OR REPLACE FUNCTION public._domino_next_round(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  g record; n int; tiles jsonb; hands jsonb := '{}'::jsonb;
  stock jsonb; per_hand int := 7; p record; idx int := 0; hand jsonb;
  starter int := 0; best int := -1; cur_best int; t jsonb;
  starter_double int := -1;
  _cfg record;
  v_round int;
  v_rule text;
  v_prev_starter int;
  slots int[];
  i int;
  a int; b int; sum2 int;
  v_state jsonb;
  v_playable jsonb;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN; END IF;
  SELECT count(*) INTO n FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  IF n < 2 THEN RETURN; END IF;

  tiles := public._domino_deal(n);

  SELECT array_agg(slot ORDER BY slot) INTO slots
    FROM public.domino_participants WHERE game_id=_game_id AND forfeited=false;

  FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
    SELECT jsonb_agg(value) INTO hand FROM jsonb_array_elements(tiles) WITH ORDINALITY t(value, ord)
      WHERE ord > idx*per_hand AND ord <= (idx+1)*per_hand;
    hands := hands || jsonb_build_object(p.slot::text, COALESCE(hand,'[]'::jsonb));
    idx := idx + 1;
  END LOOP;
  SELECT jsonb_agg(value) INTO stock FROM jsonb_array_elements(tiles) WITH ORDINALITY t(value, ord)
    WHERE ord > n*per_hand;
  stock := COALESCE(stock, '[]'::jsonb);

  v_round := COALESCE((g.state->>'round')::int, 1) + 1;
  v_rule := COALESCE(g.state->>'first_tile_rule', g.first_tile_rule, 'libre');
  v_prev_starter := NULLIF(g.state->>'starter_slot','null')::int;

  IF v_prev_starter IS NOT NULL THEN
    starter := slots[1];
    FOR i IN 1..array_length(slots,1) LOOP
      IF slots[i] = v_prev_starter THEN
        starter := slots[ ((i) % array_length(slots,1)) + 1 ];
        EXIT;
      END IF;
    END LOOP;
    starter_double := -1;
  ELSIF v_rule = 'under6' THEN
    best := -1; starter := slots[1]; starter_double := -1;
    FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
      cur_best := -1;
      FOR t IN SELECT * FROM jsonb_array_elements(hands -> p.slot::text) LOOP
        a := (t->>0)::int; b := (t->>1)::int; sum2 := a + b;
        IF a = b AND sum2 < 6 AND sum2 > cur_best THEN cur_best := sum2; END IF;
      END LOOP;
      IF cur_best > best THEN best := cur_best; starter := p.slot; END IF;
    END LOOP;
    IF best < 0 THEN
      FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
        cur_best := -1;
        FOR t IN SELECT * FROM jsonb_array_elements(hands -> p.slot::text) LOOP
          a := (t->>0)::int; b := (t->>1)::int; sum2 := a + b;
          IF sum2 < 6 AND sum2 > cur_best THEN cur_best := sum2; END IF;
        END LOOP;
        IF cur_best > best THEN best := cur_best; starter := p.slot; END IF;
      END LOOP;
    END IF;
  ELSE
    FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
      cur_best := -1;
      FOR t IN SELECT * FROM jsonb_array_elements(hands -> p.slot::text) LOOP
        IF (t->>0)::int = (t->>1)::int AND (t->>0)::int > cur_best THEN cur_best := (t->>0)::int; END IF;
      END LOOP;
      IF cur_best > best THEN best := cur_best; starter := p.slot; starter_double := cur_best; END IF;
    END LOOP;
  END IF;

  SELECT * INTO _cfg FROM public._game_cfg('domino');

  -- FIX: inclure turn_slot dans le state
  v_state := jsonb_build_object(
      'phase','playing',
      'hands', hands,
      'stock', stock,
      'board', '[]'::jsonb,
      'left_end', 'null'::jsonb,
      'right_end', 'null'::jsonb,
      'passes', 0,
      'scores', COALESCE(g.state->'scores','{}'::jsonb),
      'round', v_round,
      'last_round', g.state->'last_round',
      'draw_mode', COALESCE(g.state->>'draw_mode','with'),
      'first_tile_rule', v_rule,
      'starter_slot', to_jsonb(starter),
      'first_move_double', CASE WHEN starter_double >= 0 THEN to_jsonb(starter_double) ELSE 'null'::jsonb END,
      'turn_slot', to_jsonb(starter)
  );

  -- FIX: calculer playable_tiles
  v_playable := public._domino_playable_tiles(v_state, starter);
  v_state := jsonb_set(v_state, ARRAY['playable_tiles'], v_playable);

  v_state := public._domino_arm_bot_think(_game_id, starter, v_state);

  UPDATE public.domino_games SET
    current_turn = starter,
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
    state = v_state
  WHERE id = _game_id;
END
$$;

-- ── 3. Fix _domino_place_first : ajouter turn_slot au state ──
CREATE OR REPLACE FUNCTION public._domino_place_first(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  g record; st jsonb; starter int; starter_double int;
  hands jsonb; starter_hand jsonb; filtered jsonb;
  board jsonb; next_slot int; _cfg record;
  v_playable jsonb;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;
  st := g.state;
  IF (st->>'phase') <> 'dealing' THEN RETURN; END IF;

  starter := COALESCE((st->>'starter_slot')::int, g.current_turn);
  starter_double := COALESCE((st->>'starter_double')::int, -1);
  hands := st->'hands';

  IF starter_double >= 0 THEN
    starter_hand := hands -> starter::text;
    SELECT COALESCE(jsonb_agg(value), '[]'::jsonb) INTO filtered
      FROM jsonb_array_elements(starter_hand) value
      WHERE NOT ((value->>0)::int = starter_double AND (value->>1)::int = starter_double);
    hands := jsonb_set(hands, ARRAY[starter::text], filtered);
    board := jsonb_build_array(
      jsonb_build_object('tile', jsonb_build_array(starter_double, starter_double), 'flipped', false)
    );
    st := jsonb_set(st, '{hands}', hands);
    st := jsonb_set(st, '{board}', board);
    st := jsonb_set(st, '{left_end}', to_jsonb(starter_double));
    st := jsonb_set(st, '{right_end}', to_jsonb(starter_double));

    SELECT slot INTO next_slot FROM public.domino_participants
      WHERE game_id=_game_id AND forfeited=false AND slot > starter ORDER BY slot LIMIT 1;
    IF next_slot IS NULL THEN
      SELECT slot INTO next_slot FROM public.domino_participants
        WHERE game_id=_game_id AND forfeited=false ORDER BY slot LIMIT 1;
    END IF;
  ELSE
    next_slot := starter;
  END IF;

  st := jsonb_set(st, '{phase}', '"play"'::jsonb);
  st := st - 'deal_until';

  -- FIX: set turn_slot dans le state
  next_slot := COALESCE(next_slot, starter);
  st := jsonb_set(st, ARRAY['turn_slot'], to_jsonb(next_slot));
  v_playable := public._domino_playable_tiles(st, next_slot);
  st := jsonb_set(st, ARRAY['playable_tiles'], v_playable);

  SELECT * INTO _cfg FROM public._game_cfg('domino');

  st := public._domino_arm_bot_think(_game_id, next_slot, st);

  UPDATE public.domino_games
     SET state = st,
         current_turn = next_slot,
         turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
   WHERE id = _game_id;
END
$$;

-- ── 4. Fix domino_tick : set state.turn_slot quand on change current_turn ──
CREATE OR REPLACE FUNCTION public.domino_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  g record;
  cur_uid uuid;
  _cfg record;
  _skips int;
  _next int;
  remaining int;
  last_slot int;
  _break_until timestamptz;
  _deal_until timestamptz;
  required_slot int;
  board_empty boolean;
  v_state jsonb;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

  IF (g.state->>'phase') = 'dealing' THEN
    _deal_until := NULLIF(g.state->>'deal_until','')::timestamptz;
    IF _deal_until IS NOT NULL AND _deal_until <= now() THEN
      PERFORM public._domino_place_first(_game_id);
    END IF;
    RETURN;
  END IF;

  IF (g.state->>'phase') = 'break' THEN
    _break_until := NULLIF(g.state->>'break_until','')::timestamptz;
    IF _break_until IS NOT NULL AND _break_until <= now() THEN
      PERFORM public._domino_next_round(_game_id);
    END IF;
    RETURN;
  END IF;

  SELECT * INTO _cfg FROM public._game_cfg('domino');
  board_empty := jsonb_array_length(COALESCE(g.state->'board', '[]'::jsonb)) = 0;
  required_slot := public._domino_required_starter_slot(_game_id, g.state);

  IF board_empty AND required_slot IS NOT NULL AND required_slot <> g.current_turn THEN
    v_state := jsonb_set(g.state, ARRAY['turn_slot'], to_jsonb(required_slot));
    UPDATE public.domino_games
       SET current_turn = required_slot,
           turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
           state = v_state
     WHERE id = _game_id;
    RETURN;
  END IF;

  IF g.turn_deadline IS NULL OR g.turn_deadline > now() THEN RETURN; END IF;

  SELECT user_id INTO cur_uid
    FROM public.domino_participants
   WHERE game_id = _game_id
     AND slot = g.current_turn
     AND forfeited = false;

  IF cur_uid IS NULL THEN
    _next := public._domino_next_playable_slot(_game_id, g.current_turn, g.state);
    IF _next IS NOT NULL THEN
      v_state := jsonb_set(g.state, ARRAY['turn_slot'], to_jsonb(_next));
      UPDATE public.domino_games
         SET current_turn = _next,
             turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
             state = v_state
       WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;

  _skips := COALESCE((g.turn_skips->>cur_uid::text)::int, 0) + 1;

  IF _skips >= _cfg.max_turn_skips THEN
    UPDATE public.domino_participants
       SET forfeited = true
     WHERE game_id = _game_id
       AND user_id = cur_uid;

    SELECT count(*) INTO remaining
      FROM public.domino_participants
     WHERE game_id = _game_id
       AND forfeited = false;

    IF remaining <= 1 THEN
      SELECT slot INTO last_slot
        FROM public.domino_participants
       WHERE game_id = _game_id
         AND forfeited = false
       LIMIT 1;

      IF last_slot IS NOT NULL THEN
        PERFORM public._domino_finalize(_game_id, last_slot);
      ELSE
        UPDATE public.domino_games SET status='cancelled', finished_at=now() WHERE id = _game_id;
      END IF;
      RETURN;
    END IF;

    g.turn_skips := jsonb_set(COALESCE(g.turn_skips,'{}'::jsonb), ARRAY[cur_uid::text], to_jsonb(_skips), true);
    g.state := jsonb_set(g.state, ARRAY['hands', g.current_turn::text], '[]'::jsonb, true);
    required_slot := public._domino_required_starter_slot(_game_id, g.state);

    IF board_empty AND required_slot IS NOT NULL THEN
      v_state := jsonb_set(g.state, ARRAY['turn_slot'], to_jsonb(required_slot));
      UPDATE public.domino_games
         SET state = v_state,
             turn_skips = g.turn_skips,
             current_turn = required_slot,
             turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
       WHERE id = _game_id;
      RETURN;
    END IF;
  ELSE
    g.turn_skips := jsonb_set(COALESCE(g.turn_skips,'{}'::jsonb), ARRAY[cur_uid::text], to_jsonb(_skips), true);

    IF board_empty AND required_slot IS NOT NULL THEN
      v_state := jsonb_set(g.turn_skips, ARRAY['turn_slot'], to_jsonb(required_slot));
      -- Note: turn_skips is a column, not in state
      UPDATE public.domino_games
         SET turn_skips = g.turn_skips,
             current_turn = required_slot,
             turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
       WHERE id = _game_id;
      RETURN;
    END IF;

    UPDATE public.domino_games
       SET turn_skips = g.turn_skips
     WHERE id = _game_id;
  END IF;

  _next := public._domino_next_playable_slot(_game_id, g.current_turn, g.state);
  IF _next IS NULL THEN
    _next := public._domino_lowest_pip_slot(_game_id, g.state);
    IF _next IS NOT NULL THEN
      PERFORM public._domino_end_round(_game_id, _next);
    END IF;
    RETURN;
  END IF;

  v_state := jsonb_set(g.state, ARRAY['turn_slot'], to_jsonb(_next));
  UPDATE public.domino_games
     SET current_turn = _next,
         turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
         state = v_state
   WHERE id = _game_id;
END
$$;

-- ── 5. Fix la partie en cours : set turn_slot + playable_tiles ──
UPDATE public.domino_games
   SET state = jsonb_set(
         jsonb_set(state, ARRAY['turn_slot'], to_jsonb(current_turn)),
         ARRAY['playable_tiles'],
         public._domino_playable_tiles(state, current_turn)
       )
 WHERE status = 'playing'
   AND (state->>'turn_slot') IS NULL;
