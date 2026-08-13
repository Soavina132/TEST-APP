-- ============================================================
-- FIRST_TILE_IDX: Track center tile index across ALL board-modifying functions
-- Previous migration (20260813100000) only patched domino_play with an OLD version.
-- This migration replaces the CURRENT versions of ALL functions that modify the board.
-- ============================================================

-- ════════════════════════════════════════════════════════════════════════
-- 1. domino_play (human player) — latest version + first_tile_idx tracking
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.domino_play(_game_id uuid, _move jsonb)
RETURNS void AS $$
DECLARE
  _g record; _state jsonb; _action text; _tile jsonb; _side text;
  _part record; _hand jsonb; _idx int; _ta int; _tb int; _le int; _re int;
  _board jsonb; _stock jsonb; _nt jsonb; _slot int; _ts jsonb; _count int; _key text; _draw text;
  _fti int;
BEGIN
  SELECT * INTO _g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND OR _g.status != 'playing' THEN RETURN; END IF;
  _state := _g.state;
  IF _state->>'phase' != 'playing' THEN RETURN; END IF;
  SELECT * INTO _part FROM public.domino_participants WHERE game_id = _game_id AND user_id = auth.uid() AND forfeited = false;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vous ne participez pas'; END IF;
  IF _part.slot != _g.current_turn THEN RAISE EXCEPTION 'Ce n''est pas votre tour'; END IF;

  _action := _move->>'action';
  _hand := _state->('hands')->(_part.slot::text);
  _board := _state->'board';
  _le := NULLIF(_state->>'left_end','')::int;
  _re := NULLIF(_state->>'right_end','')::int;
  _stock := _state->'stock';
  _slot := _part.slot;
  _key := COALESCE(_part.user_id::text, 'bot_'||_slot);
  _draw := COALESCE(_state->>'draw_mode','with');
  _fti := COALESCE((_state->>'first_tile_idx')::int, 0);

  IF _action = 'play' THEN
    _tile := _move->'tile'; _ta := (_tile->>0)::int; _tb := (_tile->>1)::int; _side := COALESCE(_move->>'side','auto');
    _idx := -1;
    FOR _i IN 0..jsonb_array_length(_hand)-1 LOOP
      IF (_hand->>(_i))->>0 = _ta::text AND (_hand->>(_i))->>1 = _tb::text THEN _idx := _i; EXIT; END IF;
      IF (_hand->>(_i))->>0 = _tb::text AND (_hand->>(_i))->>1 = _ta::text THEN
        _tile := jsonb_build_array(_tb, _ta); _ta := (_tile->>0)::int; _tb := (_tile->>1)::int; _idx := _i; EXIT;
      END IF;
    END LOOP;
    IF _idx < 0 THEN RAISE EXCEPTION 'Tuile non valide'; END IF;

    IF jsonb_array_length(_board) = 0 THEN
      _board := jsonb_build_array(_tile); _le := _ta; _re := _tb;
      _fti := 0;
    ELSE
      IF _side = 'auto' THEN
        IF _ta = _re OR _tb = _re THEN _side := 'right';
        ELSIF _ta = _le OR _tb = _le THEN _side := 'left';
        ELSE RAISE EXCEPTION 'Tuile non jouable'; END IF;
      END IF;
      IF _side = 'left' THEN
        IF _tb = _le THEN _nt := jsonb_build_array(_ta, _tb); _le := _ta;
        ELSIF _ta = _le THEN _nt := jsonb_build_array(_tb, _ta); _le := _tb;
        ELSE RAISE EXCEPTION 'Tuile non jouable à gauche'; END IF;
        _board := jsonb_build_array(_nt) || _board;
        _fti := _fti + 1;
      ELSE
        IF _ta = _re THEN _nt := jsonb_build_array(_ta, _tb); _re := _tb;
        ELSIF _tb = _re THEN _nt := jsonb_build_array(_tb, _ta); _re := _ta;
        ELSE RAISE EXCEPTION 'Tuile non jouable à droite'; END IF;
        _board := _board || jsonb_build_array(_nt);
      END IF;
    END IF;

    _hand := public.domino_remove_at(_hand, _idx);
    _state := _state || jsonb_build_object('board',_board,'left_end',_le,'right_end',_re,'passes',0,'last_pass_by',null,'first_move_double',null,'first_tile_idx',_fti);
    _state := jsonb_set(_state, ARRAY['hands', _slot::text], _hand);
    _ts := jsonb_set(_g.turn_skips, ARRAY[_key], '0'::jsonb);

    IF jsonb_array_length(_hand) = 0 THEN PERFORM public.domino_end_round(_game_id, _slot); RETURN; END IF;
    PERFORM public.domino_advance_turn(_game_id, _state, _ts);

  ELSIF _action = 'draw' THEN
    IF jsonb_array_length(_stock) = 0 THEN RAISE EXCEPTION 'Pioche vide'; END IF;
    _nt := _stock->0;
    _stock := public.domino_pop_first(_stock);
    _hand := _hand || jsonb_build_array(_nt);
    _state := _state || jsonb_build_object('stock',_stock);
    _state := jsonb_set(_state, ARRAY['hands', _slot::text], _hand);
    _ta := (_nt->>0)::int; _tb := (_nt->>1)::int;
    IF _ta = _le OR _tb = _le OR _ta = _re OR _tb = _re THEN
      UPDATE public.domino_games SET state=_state, turn_deadline=now()+interval '30 seconds', updated_at=now() WHERE id=_game_id;
    ELSIF jsonb_array_length(_stock) > 0 THEN
      UPDATE public.domino_games SET state=_state, turn_deadline=now()+interval '30 seconds', updated_at=now() WHERE id=_game_id;
    ELSE
      _state := _state || jsonb_build_object('passes',(_state->>'passes')::int+1,'last_pass_by',_slot);
      _ts := jsonb_set(_g.turn_skips, ARRAY[_key], to_jsonb((_g.turn_skips->>_key)::int + 1));
      SELECT count(*) INTO _count FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
      IF (_state->>'passes')::int >= _count THEN PERFORM public.domino_end_round(_game_id, null, true);
      ELSE PERFORM public.domino_advance_turn(_game_id, _state, _ts); END IF;
    END IF;

  ELSIF _action = 'pass' THEN
    IF jsonb_array_length(_stock) > 0 AND _draw = 'with' THEN RAISE EXCEPTION 'Vous pouvez encore piocher'; END IF;
    _state := _state || jsonb_build_object('passes',(_state->>'passes')::int+1,'last_pass_by',_slot);
    _ts := jsonb_set(_g.turn_skips, ARRAY[_key], to_jsonb((_g.turn_skips->>_key)::int + 1));
    SELECT count(*) INTO _count FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
    IF (_state->>'passes')::int >= _count THEN PERFORM public.domino_end_round(_game_id, null, true);
    ELSE PERFORM public.domino_advance_turn(_game_id, _state, _ts); END IF;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ════════════════════════════════════════════════════════════════════════
-- 2. domino_bot_execute — latest version + first_tile_idx tracking
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.domino_bot_execute(_game_id uuid, _bot record, _move jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  _game record; _state jsonb; _action text; _tile jsonb; _side text;
  _hand jsonb; _idx int; _ta int; _tb int; _le int; _re int;
  _board jsonb; _stock jsonb; _nt jsonb; _slot int; _ts jsonb; _count int;
  _key text; _fti int;
BEGIN
  SELECT * INTO _game FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND OR _game.status != 'playing' THEN RETURN; END IF;
  _state := _game.state;
  IF _state->>'phase' NOT IN ('playing', 'play') THEN RETURN; END IF;
  IF _game.current_turn != _bot.slot THEN RETURN; END IF;

  _state := _state - 'bot_think_until' - 'bot_locked_slot';

  _action := _move->>'action';
  _hand := _state->('hands')->(_bot.slot::text);
  _board := _state->'board';
  _le := NULLIF(_state->>'left_end','')::int;
  _re := NULLIF(_state->>'right_end','')::int;
  _stock := _state->'stock';
  _slot := _bot.slot;
  _key := COALESCE(_bot.user_id::text, 'bot_'||_slot);
  _fti := COALESCE((_state->>'first_tile_idx')::int, 0);

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
      _fti := 0;
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
        _fti := _fti + 1;
      ELSE
        IF _ta = _re THEN _nt := jsonb_build_array(_ta, _tb); _re := _tb;
        ELSIF _tb = _re THEN _nt := jsonb_build_array(_tb, _ta); _re := _ta;
        ELSE RETURN; END IF;
        _board := _board || jsonb_build_array(_nt);
      END IF;
    END IF;

    _hand := public.domino_remove_at(_hand, _idx);
    _state := _state || jsonb_build_object('board', _board, 'left_end', _le, 'right_end', _re, 'passes', 0, 'last_pass_by', null, 'first_move_double', null, 'first_tile_idx', _fti);
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
      PERFORM public.domino_bot_execute(_game_id, _bot, jsonb_build_object('action','play','tile',_nt,'side','auto'));
    ELSIF jsonb_array_length(_stock) > 0 THEN
      UPDATE public.domino_games SET state = _state, turn_deadline = now() + make_interval(secs => 2), updated_at = now() WHERE id = _game_id;
    ELSE
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

-- ════════════════════════════════════════════════════════════════════════
-- 3. _domino_place_first — latest version + first_tile_idx = 0
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._domino_place_first(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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
      jsonb_build_array(starter_double, starter_double)
    );
    st := jsonb_set(st, '{hands}', hands);
    st := jsonb_set(st, '{board}', board);
    st := jsonb_set(st, '{left_end}', to_jsonb(starter_double));
    st := jsonb_set(st, '{right_end}', to_jsonb(starter_double));
    st := jsonb_set(st, '{first_tile_idx}', '0'::jsonb);

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

-- ════════════════════════════════════════════════════════════════════════
-- 4. domino_start_new_round — latest version + first_tile_idx: 0
-- ════════════════════════════════════════════════════════════════════════
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
    'first_tile_idx', 0,
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

-- ════════════════════════════════════════════════════════════════════════
-- 5. domino_set_ready — latest version + first_tile_idx: 0
-- ════════════════════════════════════════════════════════════════════════
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
      'first_tile_idx',0,
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

-- ════════════════════════════════════════════════════════════════════════
-- 6. Backfill existing games: set first_tile_idx = 0 if missing
-- ════════════════════════════════════════════════════════════════════════
UPDATE public.domino_games
SET state = state || jsonb_build_object('first_tile_idx', 0),
    updated_at = now()
WHERE status IN ('playing', 'open')
  AND NOT (state ? 'first_tile_idx');
