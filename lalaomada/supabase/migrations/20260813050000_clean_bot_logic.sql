-- ============================================================
-- CLEAN BOT LOGIC REWRITE
-- ============================================================
-- Problem: Bot logic was spread across 5+ functions with two
-- overlapping timers (bot_think_until + turn_deadline) and
-- incompatible timestamp formats. The bot never reliably played.
--
-- Solution: Use ONLY turn_deadline. Short (3-5s) for bots, long
-- (30s) for humans. domino_tick checks turn_deadline → if bot,
-- play; if human, timeout. No more bot_think_until.
--
-- Functions rewritten:
--   domino_tick          — clean, only uses turn_deadline
--   domino_advance_turn  — sets turn_deadline based on bot/human
--   _domino_place_first  — sets turn_deadline based on bot/human
--   _domino_next_round   — sets turn_deadline based on bot/human
--   domino_start_new_round — sets turn_deadline based on bot/human
--   domino_set_ready     — sets turn_deadline based on bot/human
--   domino_bot_execute   — short deadline for draw-again case
--
-- Functions made no-op (backward compat):
--   _domino_arm_bot_think  — just clears bot_think_until
--   domino_maybe_schedule_bot — just clears bot_think_until
--   _domino_bot_loop       — no-op (bot driven by turn_deadline)
--
-- Dead code dropped:
--   _domino_bot_step, _domino_autoplay_bots, _domino_play_as,
--   _domino_force_pass
-- ============================================================

-- Helper: returns the appropriate turn delay for a player
CREATE OR REPLACE FUNCTION public._domino_turn_delay(_game_id uuid, _slot int)
RETURNS interval
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_is_bot boolean := false;
  v_cfg record;
BEGIN
  SELECT COALESCE(dp.is_bot, false) INTO v_is_bot
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id AND dp.slot = _slot AND dp.forfeited = false;
  IF v_is_bot THEN
    RETURN make_interval(secs => 3 + random() * 2);
  ELSE
    SELECT * INTO v_cfg FROM public._game_cfg('domino');
    RETURN (COALESCE(v_cfg.turn_timer_seconds, 30) || ' seconds')::interval;
  END IF;
END;
$function$;

-- ============================================================
-- 1. domino_tick — CLEAN: only turn_deadline, no bot_think_until
-- ============================================================
CREATE OR REPLACE FUNCTION public.domino_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  _g record; _state jsonb; _phase text; _part record; _bu timestamptz;
BEGIN
  SELECT * INTO _g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND OR _g.status != 'playing' THEN RETURN; END IF;
  _state := _g.state;
  _phase := COALESCE(_state->>'phase', 'playing');

  -- Phase: dealing → transition to playing
  IF _phase = 'dealing' THEN
    _bu := (_state->>'deal_until')::timestamptz;
    IF now() >= _bu THEN
      PERFORM public._domino_place_first(_game_id);
    END IF;
    RETURN;
  END IF;

  -- Phase: break → start new round
  IF _phase = 'break' THEN
    _bu := to_timestamp(_state->>'break_until', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
    IF now() >= _bu THEN PERFORM public.domino_start_new_round(_game_id); END IF;
    RETURN;
  END IF;

  -- Phase: playing → check turn_deadline
  IF _phase NOT IN ('playing', 'play') THEN RETURN; END IF;

  IF _g.turn_deadline IS NOT NULL AND now() >= _g.turn_deadline THEN
    SELECT * INTO _part FROM public.domino_participants
      WHERE game_id = _game_id AND slot = _g.current_turn AND forfeited = false;
    IF FOUND THEN
      IF _part.is_bot THEN
        PERFORM public.domino_bot_play(_game_id, _part);
      ELSE
        PERFORM public.domino_auto_timeout(_game_id, _part);
      END IF;
    END IF;
  END IF;
END;
$function$;

-- ============================================================
-- 2. domino_advance_turn — sets turn_deadline based on bot/human
-- ============================================================
CREATE OR REPLACE FUNCTION public.domino_advance_turn(_game_id uuid, _state jsonb, _turn_skips jsonb DEFAULT '{}'::jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  _next int; _part record; _count int; _delay interval;
BEGIN
  -- Clear stale bot_think state
  _state := _state - 'bot_think_until' - 'bot_locked_slot';

  SELECT current_turn INTO _next FROM public.domino_games WHERE id = _game_id;
  SELECT count(*) INTO _count FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  LOOP
    _next := (_next + 1) % GREATEST(_count, 1);
    SELECT * INTO _part FROM public.domino_participants WHERE game_id = _game_id AND slot = _next AND forfeited = false;
    EXIT WHEN FOUND;
  END LOOP;

  _delay := public._domino_turn_delay(_game_id, _next);

  UPDATE public.domino_games SET
    state = _state,
    current_turn = _next,
    turn_skips = CASE WHEN _turn_skips != '{}'::jsonb THEN _turn_skips ELSE turn_skips END,
    turn_deadline = now() + _delay,
    updated_at = now()
  WHERE id = _game_id;
END;
$function$;

-- ============================================================
-- 3. _domino_arm_bot_think — NO-OP, just clears bot_think_until
-- ============================================================
CREATE OR REPLACE FUNCTION public._domino_arm_bot_think(_game_id uuid, _slot integer, _state jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
BEGIN
  -- bot_think_until is no longer used. Turn deadline is set by the caller.
  _state := _state - 'bot_think_until' - 'bot_locked_slot';
  RETURN _state;
END;
$function$;

-- ============================================================
-- 4. domino_maybe_schedule_bot — NO-OP, just clears bot_think_until
-- ============================================================
CREATE OR REPLACE FUNCTION public.domino_maybe_schedule_bot(_game_id uuid, _slot integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
  -- bot_think_until is no longer used. Turn deadline is set by domino_advance_turn.
  UPDATE public.domino_games SET
    state = state - 'bot_think_until' - 'bot_locked_slot',
    updated_at = now()
  WHERE id = _game_id;
END;
$function$;

-- ============================================================
-- 5. _domino_bot_loop — NO-OP (bot is driven by turn_deadline)
-- ============================================================
CREATE OR REPLACE FUNCTION public._domino_bot_loop(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
BEGIN
  -- No longer needed. Bot auto-play is driven by turn_deadline + domino_tick.
  -- Just clean up any stale bot_think_until.
  UPDATE public.domino_games SET
    state = state - 'bot_think_until' - 'bot_locked_slot'
  WHERE id = _game_id AND state ? 'bot_think_until';
END;
$function$;

-- ============================================================
-- 6. _domino_place_first — sets turn_deadline based on bot/human
-- ============================================================
CREATE OR REPLACE FUNCTION public._domino_place_first(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  g record; st jsonb; starter int; starter_double int;
  hands jsonb; starter_hand jsonb; filtered jsonb;
  board jsonb; next_slot int; v_playable jsonb; _delay interval;
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
  st := st - 'deal_until' - 'bot_think_until' - 'bot_locked_slot';

  next_slot := COALESCE(next_slot, starter);
  st := jsonb_set(st, ARRAY['turn_slot'], to_jsonb(next_slot));
  v_playable := public._domino_playable_tiles(st, next_slot);
  st := jsonb_set(st, ARRAY['playable_tiles'], v_playable);

  _delay := public._domino_turn_delay(_game_id, next_slot);

  UPDATE public.domino_games
     SET state = st,
         current_turn = next_slot,
         turn_deadline = now() + _delay
   WHERE id = _game_id;
END;
$function$;

-- ============================================================
-- 7. _domino_next_round — sets turn_deadline based on bot/human
-- ============================================================
CREATE OR REPLACE FUNCTION public._domino_next_round(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  g record; n int; tiles jsonb; hands jsonb := '{}'::jsonb;
  stock jsonb; per_hand int := 7; p record; idx int := 0; hand jsonb;
  starter int := 0; best int := -1; cur_best int; t jsonb;
  starter_double int := -1;
  v_round int; v_rule text; v_prev_starter int;
  slots int[]; i int; a int; b int; sum2 int;
  v_state jsonb; v_playable jsonb; _delay interval;
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

  v_state := jsonb_build_object(
      'phase','playing',
      'hands', hands,
      'stock', stock,
      'board', '[]'::jsonb,
      'left_end', 'null'::jsonb,
      'right_end', 'null'::jsonb,
      'passes', 0,
      'scores', COALESCE(g.state->'scores','{}'::jsonb),
      'round_scores', COALESCE(g.state->'round_scores','{}'::jsonb),
      'round', v_round,
      'last_round', g.state->'last_round',
      'draw_mode', COALESCE(g.state->>'draw_mode','with'),
      'first_tile_rule', v_rule,
      'starter_slot', to_jsonb(starter),
      'first_move_double', CASE WHEN starter_double >= 0 THEN to_jsonb(starter_double) ELSE 'null'::jsonb END,
      'turn_slot', to_jsonb(starter)
  );

  v_playable := public._domino_playable_tiles(v_state, starter);
  v_state := jsonb_set(v_state, ARRAY['playable_tiles'], v_playable);

  -- Clean up any stale bot state
  v_state := v_state - 'bot_think_until' - 'bot_locked_slot';

  _delay := public._domino_turn_delay(_game_id, starter);

  UPDATE public.domino_games SET
    current_turn = starter,
    turn_deadline = now() + _delay,
    state = v_state
  WHERE id = _game_id;
END;
$function$;

-- ============================================================
-- 8. domino_start_new_round — sets turn_deadline based on bot/human
-- ============================================================
CREATE OR REPLACE FUNCTION public.domino_start_new_round(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  _game record; _tiles jsonb; _dealt jsonb; _info jsonb; _state jsonb; _draw text;
  _delay interval;
BEGIN
  SELECT * INTO _game FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND OR _game.status != 'playing' THEN RETURN; END IF;
  _tiles := public.domino_generate_tiles();
  _dealt := public.domino_deal_tiles(_game_id, _tiles);
  _info := public.domino_find_first_player(_game_id, _dealt->'hands');
  _draw := COALESCE(_game.state->>'draw_mode', 'with');
  _state := jsonb_build_object(
    'phase', 'playing', 'round', (_game.state->>'round')::int + 1,
    'board', '[]'::jsonb, 'left_end', null, 'right_end', null,
    'hands', _dealt->'hands', 'stock', CASE WHEN _draw = 'without' THEN '[]'::jsonb ELSE _dealt->'stock' END,
    'passes', 0, 'last_pass_by', null, 'draw_mode', _draw,
    'first_tile_rule', COALESCE(_game.state->>'first_tile_rule', 'libre'),
    'first_move_double', _info->>'double',
    'last_round', _game.state->'last_round', 'break_until', null, 'reveal_until', null);

  _delay := public._domino_turn_delay(_game_id, (_info->>'slot')::int);

  UPDATE public.domino_games SET
    state = _state, current_turn = (_info->>'slot')::int,
    turn_deadline = now() + _delay, updated_at = now()
  WHERE id = _game_id;
END;
$function$;

-- ============================================================
-- 9. domino_set_ready — sets turn_deadline based on bot/human
-- ============================================================
CREATE OR REPLACE FUNCTION public.domino_set_ready(_game_id uuid, _ready boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  _g record; _all boolean; _count int; _tiles jsonb; _dealt jsonb; _info jsonb;
  _state jsonb; _scores jsonb := '{}'::jsonb; _ts jsonb := '{}'::jsonb; _p record;
  _key text; _draw text; _delay interval;
BEGIN
  SELECT * INTO _g FROM public.domino_games WHERE id = _game_id;
  IF NOT FOUND OR _g.status != 'open' THEN RETURN; END IF;
  UPDATE public.domino_participants SET ready = _ready WHERE game_id = _game_id AND user_id = auth.uid() AND forfeited = false;
  SELECT bool_and(ready), count(*) INTO _all, _count FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  IF _count < 2 THEN _all := false; END IF;

  IF _all THEN
    _tiles := public.domino_generate_tiles();
    _dealt := public.domino_deal_tiles(_game_id, _tiles);
    _info := public.domino_find_first_player(_game_id, _dealt->'hands');
    _draw := COALESCE(_g.state->>'draw_mode', 'with');
    FOR _p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
      _key := COALESCE(_p.user_id::text, 'bot_'||_p.slot);
      _scores := _scores || jsonb_build_object(COALESCE(_p.user_id::text, _key), 0);
      _ts := _ts || jsonb_build_object(_key, 0);
    END LOOP;
    _state := jsonb_build_object(
      'phase','playing','round',1,'board','[]'::jsonb,'left_end',null,'right_end',null,
      'hands',_dealt->'hands','stock',CASE WHEN _draw='without' THEN '[]'::jsonb ELSE _dealt->'stock' END,
      'passes',0,'last_pass_by',null,'draw_mode',_draw,
      'first_tile_rule',COALESCE(_g.state->>'first_tile_rule','libre'),
      'first_move_double',_info->>'double',
      'last_round',null,'break_until',null,'reveal_until',null);

    _delay := public._domino_turn_delay(_game_id, (_info->>'slot')::int);

    UPDATE public.domino_games SET
      status='playing', state=_state, current_turn=(_info->>'slot')::int,
      scores=_scores, turn_skips=_ts, started_at=now(),
      turn_deadline=now() + _delay,
      pot=_g.stake*_count, updated_at=now()
    WHERE id=_game_id;
  END IF;
  UPDATE public.domino_games SET updated_at = now() WHERE id = _game_id;
END;
$function$;

-- ============================================================
-- 10. domino_bot_execute — short deadline for draw-again case
-- ============================================================
CREATE OR REPLACE FUNCTION public.domino_bot_execute(_game_id uuid, _bot record, _move jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  _game record; _state jsonb; _action text; _tile jsonb; _side text;
  _hand jsonb; _idx int; _ta int; _tb int; _le int; _re int;
  _board jsonb; _stock jsonb; _nt jsonb; _slot int; _ts jsonb; _count int;
  _key text;
BEGIN
  SELECT * INTO _game FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND OR _game.status != 'playing' THEN RETURN; END IF;
  _state := _game.state;
  IF _state->>'phase' NOT IN ('playing', 'play') THEN RETURN; END IF;
  IF _game.current_turn != _bot.slot THEN RETURN; END IF;

  -- Clean up stale bot state
  _state := _state - 'bot_think_until' - 'bot_locked_slot';

  _action := _move->>'action';
  _hand := _state->('hands')->(_bot.slot::text);
  _board := _state->'board';
  _le := NULLIF(_state->>'left_end','')::int;
  _re := NULLIF(_state->>'right_end','')::int;
  _stock := _state->'stock';
  _slot := _bot.slot;
  _key := COALESCE(_bot.user_id::text, 'bot_'||_slot);

  IF _action = 'play' THEN
    _tile := _move->'tile'; _ta := (_tile->>0)::int; _tb := (_tile->>1)::int; _side := COALESCE(_move->>'side','auto');
    _idx := -1;
    FOR _i IN 0..jsonb_array_length(_hand)-1 LOOP
      IF (_hand->(_i))->>0 = _ta::text AND (_hand->(_i))->>1 = _tb::text THEN _idx := _i; EXIT; END IF;
      IF (_hand->(_i))->>0 = _tb::text AND (_hand->(_i))->>1 = _ta::text THEN
        _tile := jsonb_build_array(_tb, _ta); _ta := (_tile->>0)::int; _tb := (_tile->>1)::int; _idx := _i; EXIT;
      END IF;
    END LOOP;
    IF _idx < 0 THEN RETURN; END IF;

    IF jsonb_array_length(_board) = 0 THEN
      _board := jsonb_build_array(_tile); _le := _ta; _re := _tb;
    ELSE
      IF _side = 'auto' THEN
        IF _ta = _re OR _tb = _re THEN _side := 'right';
        ELSIF _ta = _le OR _tb = _le THEN _side := 'left';
        ELSE RETURN; END IF;
      END IF;
      IF _side = 'left' THEN
        IF _tb = _le THEN _nt := jsonb_build_array(_ta, _tb); _le := _ta;
        ELSIF _ta = _le THEN _nt := jsonb_build_array(_tb, _ta); _le := _tb;
        ELSE RETURN; END IF;
        _board := jsonb_build_array(_nt) || _board;
      ELSE
        IF _ta = _re THEN _nt := jsonb_build_array(_ta, _tb); _re := _tb;
        ELSIF _tb = _re THEN _nt := jsonb_build_array(_tb, _ta); _re := _ta;
        ELSE RETURN; END IF;
        _board := _board || jsonb_build_array(_nt);
      END IF;
    END IF;

    _hand := public.domino_remove_at(_hand, _idx);
    _state := _state || jsonb_build_object('board', _board, 'left_end', _le, 'right_end', _re, 'passes', 0, 'last_pass_by', null, 'first_move_double', null);
    _state := jsonb_set(_state, ARRAY['hands', _slot::text], _hand);
    _ts := jsonb_set(_game.turn_skips, ARRAY[_key], '0'::jsonb);

    IF jsonb_array_length(_hand) = 0 THEN
      PERFORM public.domino_end_round(_game_id, _slot);
      RETURN;
    END IF;
    PERFORM public.domino_advance_turn(_game_id, _state, _ts);

  ELSIF _action = 'draw' THEN
    IF jsonb_array_length(_stock) = 0 THEN RETURN; END IF;
    _nt := _stock->0;
    _stock := public.domino_pop_first(_stock);
    _hand := _hand || jsonb_build_array(_nt);
    _state := _state || jsonb_build_object('stock', _stock);
    _state := jsonb_set(_state, ARRAY['hands', _slot::text], _hand);
    _ta := (_nt->>0)::int; _tb := (_nt->>1)::int;
    IF _ta = _le OR _tb = _le OR _ta = _re OR _tb = _re THEN
      -- Playable: play it immediately (recursive)
      PERFORM public.domino_bot_execute(_game_id, _bot, jsonb_build_object('action','play','tile',_nt,'side','auto'));
    ELSIF jsonb_array_length(_stock) > 0 THEN
      -- Not playable but stock remains: short bot deadline so tick fires soon
      UPDATE public.domino_games SET state = _state, turn_deadline = now() + make_interval(secs => 2), updated_at = now() WHERE id = _game_id;
    ELSE
      -- Stock empty: pass
      _state := _state || jsonb_build_object('passes', (_state->>'passes')::int + 1, 'last_pass_by', _slot);
      _ts := jsonb_set(_game.turn_skips, ARRAY[_key], to_jsonb((_game.turn_skips->>_key)::int + 1));
      SELECT count(*) INTO _count FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
      IF (_state->>'passes')::int >= _count THEN PERFORM public.domino_end_round(_game_id, null, true);
      ELSE PERFORM public.domino_advance_turn(_game_id, _state, _ts); END IF;
    END IF;

  ELSIF _action = 'pass' THEN
    _state := _state || jsonb_build_object('passes', (_state->>'passes')::int + 1, 'last_pass_by', _slot);
    _ts := jsonb_set(_game.turn_skips, ARRAY[_key], to_jsonb((_game.turn_skips->>_key)::int + 1));
    SELECT count(*) INTO _count FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
    IF (_state->>'passes')::int >= _count THEN PERFORM public.domino_end_round(_game_id, null, true);
    ELSE PERFORM public.domino_advance_turn(_game_id, _state, _ts); END IF;
  END IF;
END;
$function$;

-- ============================================================
-- 11. Clean up stale bot_think_until from all existing games
-- ============================================================
UPDATE public.domino_games
   SET state = state - 'bot_think_until' - 'bot_locked_slot',
       updated_at = now()
 WHERE state ? 'bot_think_until';

-- ============================================================
-- 12. Drop dead code
-- ============================================================
DROP FUNCTION IF EXISTS public._domino_bot_step(uuid);
DROP FUNCTION IF EXISTS public._domino_autoplay_bots(uuid);
DROP FUNCTION IF EXISTS public._domino_play_as(uuid, jsonb);
DROP FUNCTION IF EXISTS public._domino_force_pass(uuid, int);
