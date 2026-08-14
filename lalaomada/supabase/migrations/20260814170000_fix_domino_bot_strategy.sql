-- Migration: Fix Domino bot strategy and tick logic
-- Date: 2026-08-14
-- ═══════════════════════════════════════════════════════════════════
-- Fix: Domino bot plays correctly
-- 1. _domino_autoplay_bots: use _domino_bot_pick_move for strategy
-- 2. domino_tick: call _domino_bot_step for bots instead of skipping
-- 3. domino_tick_all: detect bot_think_until expiry
-- ═══════════════════════════════════════════════════════════════════

-- === 1. Rewrite _domino_autoplay_bots to use _domino_bot_pick_move ===
CREATE OR REPLACE FUNCTION public._domino_autoplay_bots(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  g record; st jsonb; v_slot int; hand jsonb; le int; re int;
  draw_mode text; is_first_move boolean; first_dbl int; v_rule text;
  i int; j int; a int; b int; tile jsonb; placed jsonb;
  new_hand jsonb; new_left int; new_right int;
  next_turn int; winner_slot int; stock jsonb; drawn jsonb;
  _cfg record; v_is_bot boolean; phase text;
  v_intel int := 70;
  v_move jsonb; v_action text; v_side text; v_tile jsonb;
  found_i int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;
  st := g.state;
  phase := COALESCE(st->>'phase', 'play');
  IF phase NOT IN ('play','playing') THEN RETURN; END IF;
  v_slot := g.current_turn;
  SELECT COALESCE(dp.is_bot, false), COALESCE(dp.bot_intelligence, 70)
    INTO v_is_bot, v_intel
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id AND dp.slot = v_slot AND dp.forfeited = false;
  IF NOT COALESCE(v_is_bot, false) THEN RETURN; END IF;

  st := st - 'bot_think_until' - 'bot_locked_slot';

  hand := COALESCE(st->'hands'->v_slot::text, '[]'::jsonb);
  le := NULLIF(st->>'left_end', 'null')::int;
  re := NULLIF(st->>'right_end', 'null')::int;
  draw_mode := COALESCE(st->>'draw_mode', 'with');
  v_rule := COALESCE(st->>'first_tile_rule', 'libre');
  is_first_move := jsonb_array_length(COALESCE(st->'board', '[]'::jsonb)) = 0;
  first_dbl := NULLIF(st->>'first_move_double', 'null')::int;
  SELECT * INTO _cfg FROM public._game_cfg('domino');

  -- Use the strategic bot AI to pick the best move
  v_move := public._domino_bot_pick_move(st, v_slot, v_intel);
  v_action := v_move->>'action';

  IF v_action = 'play' THEN
    v_tile := v_move->'tile';
    v_side := COALESCE(v_move->>'side', 'right');
    a := (v_tile->>0)::int;
    b := (v_tile->>1)::int;

    -- Find the tile in the hand to remove it
    found_i := -1;
    FOR j IN 0..jsonb_array_length(hand)-1 LOOP
      IF (hand->j->>0)::int = a AND (hand->j->>1)::int = b THEN
        found_i := j; EXIT;
      END IF;
    END LOOP;
    -- Fallback: try reversed match
    IF found_i < 0 THEN
      FOR j IN 0..jsonb_array_length(hand)-1 LOOP
        IF (hand->j->>0)::int = b AND (hand->j->>1)::int = a THEN
          found_i := j; EXIT;
        END IF;
      END LOOP;
    END IF;
    -- If still not found, something is wrong — pass
    IF found_i < 0 THEN
      st := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1), true);
      st := jsonb_set(st, '{last_pass_by}', to_jsonb(v_slot), true);
      next_turn := public._domino_next_playable_slot(_game_id, v_slot, st);
      IF next_turn IS NULL THEN
        winner_slot := public._domino_lowest_pip_slot(_game_id, st);
        UPDATE public.domino_games SET state = st WHERE id = _game_id;
        PERFORM public._domino_end_round(_game_id, winner_slot);
        RETURN;
      END IF;
      UPDATE public.domino_games SET state = st, current_turn = next_turn,
           turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
       WHERE id = _game_id;
      RETURN;
    END IF;

    -- Remove tile from hand
    new_hand := '[]'::jsonb;
    FOR j IN 0..jsonb_array_length(hand)-1 LOOP
      IF j <> found_i THEN new_hand := new_hand || jsonb_build_array(hand->j); END IF;
    END LOOP;

    -- Place tile on the board
    IF is_first_move THEN
      placed := jsonb_build_array(a, b);
      st := jsonb_set(st, '{board}', jsonb_build_array(jsonb_build_object('tile', placed, 'flipped', false)), true);
      new_left := a; new_right := b;
    ELSIF v_side = 'right' THEN
      -- Match against right end
      IF a = re THEN
        placed := jsonb_build_array(a, b); new_right := b;
      ELSE
        placed := jsonb_build_array(b, a); new_right := a;
      END IF;
      new_left := le;
      st := jsonb_set(st, '{board}', COALESCE(st->'board','[]'::jsonb) || jsonb_build_array(jsonb_build_object('tile', placed, 'flipped', false)), true);
    ELSE
      -- Match against left end (prepend to board)
      IF a = le THEN
        placed := jsonb_build_array(b, a); new_left := b;
      ELSE
        placed := jsonb_build_array(a, b); new_left := a;
      END IF;
      new_right := re;
      st := jsonb_set(st, '{board}', jsonb_build_array(jsonb_build_object('tile', placed, 'flipped', false)) || COALESCE(st->'board','[]'::jsonb), true);
    END IF;

    st := jsonb_set(st, ARRAY['hands', v_slot::text], new_hand, true);
    st := jsonb_set(st, '{left_end}', to_jsonb(new_left), true);
    st := jsonb_set(st, '{right_end}', to_jsonb(new_right), true);
    st := jsonb_set(st, '{passes}', to_jsonb(0), true);
    st := jsonb_set(st, '{first_move_double}', 'null'::jsonb, true);
    st := jsonb_set(st, '{phase}', '"play"'::jsonb, true);
    st := st - 'last_pass_by';

    -- Check win
    IF jsonb_array_length(new_hand) = 0 THEN
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
      PERFORM public._domino_end_round(_game_id, v_slot);
      RETURN;
    END IF;

    next_turn := public._domino_next_playable_slot(_game_id, v_slot, st);
    IF next_turn IS NULL THEN
      winner_slot := public._domino_lowest_pip_slot(_game_id, st);
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
      PERFORM public._domino_end_round(_game_id, winner_slot);
      RETURN;
    END IF;

    UPDATE public.domino_games
       SET state = st, current_turn = next_turn,
           turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
     WHERE id = _game_id;
    RETURN;

  ELSIF v_action = 'draw' THEN
    stock := COALESCE(st->'stock', '[]'::jsonb);
    IF jsonb_array_length(stock) > 0 THEN
      drawn := stock -> 0;
      hand := hand || jsonb_build_array(drawn);
      stock := stock - 0;
      st := jsonb_set(st, ARRAY['hands', v_slot::text], hand, true);
      st := jsonb_set(st, '{stock}', stock, true);
      UPDATE public.domino_games
         SET state = st,
             turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
       WHERE id = _game_id;
      RETURN;
    END IF;
    -- Stock empty, fall through to pass
  END IF;

  -- Action = 'pass' (or draw failed because stock empty)
  st := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1), true);
  st := jsonb_set(st, '{last_pass_by}', to_jsonb(v_slot), true);
  next_turn := public._domino_next_playable_slot(_game_id, v_slot, st);
  IF next_turn IS NULL THEN
    winner_slot := public._domino_lowest_pip_slot(_game_id, st);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_end_round(_game_id, winner_slot);
    RETURN;
  END IF;

  UPDATE public.domino_games
     SET state = st, current_turn = next_turn,
         turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
   WHERE id = _game_id;
END;
$function$;


-- === 2. Fix domino_tick to call _domino_bot_step for bots ===
CREATE OR REPLACE FUNCTION public.domino_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  g record; cur_uid uuid; _cfg record; _skips int; _next int;
  remaining int; last_slot int;
  _break_until timestamptz; _reveal_until timestamptz; _deal_until timestamptz;
  required_slot int; board_empty boolean;
  _bot_think timestamptz;
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

  IF (g.state->>'phase') = 'reveal' THEN
    _reveal_until := NULLIF(g.state->>'reveal_until','')::timestamptz;
    IF _reveal_until IS NOT NULL AND _reveal_until <= now() THEN
      UPDATE public.domino_games SET state = jsonb_set(g.state, '{phase}', '"break"'::jsonb) WHERE id = _game_id;
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
    UPDATE public.domino_games
       SET current_turn = required_slot,
           turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
     WHERE id = _game_id;
    RETURN;
  END IF;

  -- ══ NEW: Check bot think delay ══
  -- If a bot's think delay has expired, trigger the bot to play
  _bot_think := NULLIF(g.state->>'bot_think_until', '')::timestamptz;
  IF _bot_think IS NOT NULL AND _bot_think <= now() THEN
    PERFORM public._domino_bot_step(_game_id);
    RETURN;
  END IF;

  IF g.turn_deadline IS NULL OR g.turn_deadline > now() THEN RETURN; END IF;

  SELECT user_id INTO cur_uid
    FROM public.domino_participants
   WHERE game_id = _game_id AND slot = g.current_turn AND forfeited = false;

  -- ══ FIX: For bots, trigger bot_step instead of skipping ══
  IF cur_uid IS NULL THEN
    -- It's a bot's turn and deadline expired — let the bot play
    PERFORM public._domino_bot_step(_game_id);
    RETURN;
  END IF;

  _skips := COALESCE((g.turn_skips->>cur_uid::text)::int, 0) + 1;

  IF _skips >= _cfg.max_turn_skips THEN
    UPDATE public.domino_participants SET forfeited = true WHERE game_id = _game_id AND user_id = cur_uid;
    SELECT count(*) INTO remaining FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
    IF remaining <= 1 THEN
      SELECT slot INTO last_slot FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false LIMIT 1;
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
      UPDATE public.domino_games SET state = g.state, turn_skips = g.turn_skips,
        current_turn = required_slot,
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
      RETURN;
    END IF;
  ELSE
    g.turn_skips := jsonb_set(COALESCE(g.turn_skips,'{}'::jsonb), ARRAY[cur_uid::text], to_jsonb(_skips), true);
    IF board_empty AND required_slot IS NOT NULL THEN
      UPDATE public.domino_games SET turn_skips = g.turn_skips,
        current_turn = required_slot,
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
      RETURN;
    END IF;
    UPDATE public.domino_games SET turn_skips = g.turn_skips WHERE id = _game_id;
  END IF;

  _next := public._domino_next_playable_slot(_game_id, g.current_turn, g.state);
  IF _next IS NULL THEN
    _next := public._domino_lowest_pip_slot(_game_id, g.state);
    IF _next IS NOT NULL THEN
      PERFORM public._domino_end_round(_game_id, _next);
    END IF;
    RETURN;
  END IF;

  UPDATE public.domino_games SET current_turn = _next,
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
END;
$function$;


-- === 3. Fix domino_tick_all to also detect bot_think_until expiry ===
CREATE OR REPLACE FUNCTION public.domino_tick_all()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  g_id uuid;
BEGIN
  FOR g_id IN
    SELECT id
    FROM public.domino_games
    WHERE status = 'playing'
      AND (
        (turn_deadline IS NOT NULL AND turn_deadline <= now())
        OR (
          state->>'phase' = 'reveal'
          AND NULLIF(state->>'reveal_until', '')::timestamptz <= now()
        )
        OR (
          state->>'phase' = 'break'
          AND NULLIF(state->>'break_until', '')::timestamptz <= now()
        )
        OR (
          state->>'phase' = 'dealing'
          AND NULLIF(state->>'deal_until', '')::timestamptz <= now()
        )
        OR (
          state->>'bot_think_until' IS NOT NULL
          AND NULLIF(state->>'bot_think_until', '')::timestamptz <= now()
        )
      )
  LOOP
    BEGIN
      PERFORM public.domino_tick(g_id);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
END;
$function$;
