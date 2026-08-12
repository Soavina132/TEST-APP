-- ════════════════════════════════════════════════════════════════════════
-- DOMINO — COMPLETE REWRITE
-- Professional game engine with clean state machine and smart bot AI
-- ════════════════════════════════════════════════════════════════════════

-- ── Drop ALL existing domino functions ───────────────────────────────────
DROP FUNCTION IF EXISTS public.domino_create(numeric,integer,boolean,text,integer,integer,text,text) CASCADE;
DROP FUNCTION IF EXISTS public.domino_play(uuid,jsonb) CASCADE;
DROP FUNCTION IF EXISTS public.domino_tick(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.domino_forfeit(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.domino_set_ready(uuid,boolean) CASCADE;
DROP FUNCTION IF EXISTS public.domino_add_bot(uuid,text) CASCADE;
DROP FUNCTION IF EXISTS public.domino_join(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.domino_join_code(text,numeric) CASCADE;
DROP FUNCTION IF EXISTS public.domino_start_game(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.domino_start_solo_bot(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.domino_play_and_bot(uuid,jsonb) CASCADE;
DROP FUNCTION IF EXISTS public.domino_tick_all() CASCADE;
DROP FUNCTION IF EXISTS public.domino_cleanup_empty_rooms() CASCADE;
DROP FUNCTION IF EXISTS public.domino_maybe_schedule_bot(uuid,integer) CASCADE;
DROP FUNCTION IF EXISTS public.domino_advance_turn(uuid,jsonb,jsonb) CASCADE;
DROP FUNCTION IF EXISTS public.domino_end_round(uuid,integer,boolean) CASCADE;
DROP FUNCTION IF EXISTS public.domino_bot_play(uuid,record) CASCADE;
DROP FUNCTION IF EXISTS public.domino_bot_execute(uuid,record,jsonb) CASCADE;
DROP FUNCTION IF EXISTS public.domino_auto_timeout(uuid,record) CASCADE;
DROP FUNCTION IF EXISTS public.domino_start_new_round(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.domino_forfeit_internal(uuid,record) CASCADE;

-- ════════════════════════════════════════════════════════════════════════
-- HELPER: Schedule bot think
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.domino_maybe_schedule_bot(_game_id uuid, _slot integer)
RETURNS void AS $$
DECLARE _part record; _delay float;
BEGIN
  SELECT * INTO _part FROM public.domino_participants
  WHERE game_id = _game_id AND slot = _slot AND is_bot = true AND forfeited = false;
  IF NOT FOUND THEN RETURN; END IF;
  _delay := 1.5 + random() * 2.5;
  UPDATE public.domino_games SET
    state = state || jsonb_build_object('bot_think_until', to_char(now() + make_interval(secs => _delay), 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
    updated_at = now()
  WHERE id = _game_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ════════════════════════════════════════════════════════════════════════
-- HELPER: Generate shuffled 28 tiles
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.domino_generate_tiles()
RETURNS jsonb AS $$
DECLARE _tiles jsonb := '[]'::jsonb; _i int; _j int;
BEGIN
  FOR _i IN 0..6 LOOP
    FOR _j IN _i..6 LOOP
      _tiles := _tiles || jsonb_build_array(_i, _j);
    END LOOP;
  END LOOP;
  SELECT jsonb_agg(x) INTO _tiles FROM (SELECT x FROM jsonb_array_elements(_tiles) AS x ORDER BY random()) s;
  RETURN _tiles;
END;
$$ LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER;

-- ════════════════════════════════════════════════════════════════════════
-- HELPER: Deal tiles to players
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.domino_deal_tiles(_game_id uuid, _tiles jsonb, _ppp int DEFAULT 7)
RETURNS jsonb AS $$
DECLARE
  _hands jsonb := '{}'::jsonb; _stock jsonb; _p record; _count int; _offset int;
BEGIN
  SELECT count(*) INTO _count FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  FOR _p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
    _offset := _p.slot * _ppp;
    _hands := _hands || jsonb_build_object(_p.slot::text,
      (SELECT jsonb_agg(x) FROM (SELECT x FROM jsonb_array_elements(_tiles) WITH ORDINALITY AS ord(x, rn) WHERE rn > _offset AND rn <= _offset + _ppp ORDER BY rn) s));
  END LOOP;
  _stock := (SELECT jsonb_agg(x) FROM (SELECT x FROM jsonb_array_elements(_tiles) WITH ORDINALITY AS ord(x, rn) WHERE rn > _count * _ppp ORDER BY rn) s);
  RETURN jsonb_build_object('hands', _hands, 'stock', COALESCE(_stock, '[]'::jsonb));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ════════════════════════════════════════════════════════════════════════
-- HELPER: Find first player (highest double, or first player)
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.domino_find_first_player(_game_id uuid, _hands jsonb)
RETURNS jsonb AS $$
DECLARE _p record; _i int; _ta int; _tb int; _best int := -1; _slot int := 0;
BEGIN
  FOR _p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
    FOR _i IN 0..jsonb_array_length(_hands->(_p.slot::text))-1 LOOP
      _ta := (_hands->(_p.slot::text)->(_i)->>0)::int;
      _tb := (_hands->(_p.slot::text)->(_i)->>1)::int;
      IF _ta = _tb AND _ta > _best THEN _best := _ta; _slot := _p.slot; END IF;
    END LOOP;
  END LOOP;
  RETURN jsonb_build_object('slot', _slot, 'double', CASE WHEN _best >= 0 THEN _best ELSE null END);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ════════════════════════════════════════════════════════════════════════
-- HELPER: Calculate pips in a hand
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.domino_hand_pips(_hand jsonb)
RETURNS int AS $$
DECLARE _sum int := 0; _i int;
BEGIN
  IF _hand IS NULL THEN RETURN 0; END IF;
  FOR _i IN 0..jsonb_array_length(_hand)-1 LOOP
    _sum := _sum + (_hand->(_i)->>0)::int + (_hand->(_i)->>1)::int;
  END LOOP;
  RETURN _sum;
END;
$$ LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER;

-- ════════════════════════════════════════════════════════════════════════
-- HELPER: Remove tile at index from jsonb array
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.domino_remove_at(_arr jsonb, _idx int)
RETURNS jsonb AS $$
DECLARE _result jsonb;
BEGIN
  SELECT jsonb_agg(x) INTO _result
  FROM (SELECT x FROM jsonb_array_elements(_arr) WITH ORDINALITY AS ord(x, rn) WHERE rn - 1 != _idx ORDER BY rn) s;
  RETURN COALESCE(_result, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER;

-- ════════════════════════════════════════════════════════════════════════
-- HELPER: Pop first element from jsonb array
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.domino_pop_first(_arr jsonb)
RETURNS jsonb AS $$
DECLARE _result jsonb;
BEGIN
  SELECT jsonb_agg(x) INTO _result
  FROM (SELECT x FROM jsonb_array_elements(_arr) WITH ORDINALITY AS ord(x, rn) WHERE rn > 1 ORDER BY rn) s;
  RETURN COALESCE(_result, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER;

-- ════════════════════════════════════════════════════════════════════════
-- HELPER: Advance turn
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.domino_advance_turn(_game_id uuid, _state jsonb, _turn_skips jsonb DEFAULT '{}'::jsonb)
RETURNS void AS $$
DECLARE _game record; _next int; _part record; _count int;
BEGIN
  SELECT current_turn INTO _next FROM public.domino_games WHERE id = _game_id;
  SELECT count(*) INTO _count FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  LOOP
    _next := (_next + 1) % GREATEST(_count, 1);
    SELECT * INTO _part FROM public.domino_participants WHERE game_id = _game_id AND slot = _next AND forfeited = false;
    EXIT WHEN FOUND;
  END LOOP;
  UPDATE public.domino_games SET
    state = _state, current_turn = _next,
    turn_skips = CASE WHEN _turn_skips != '{}'::jsonb THEN _turn_skips ELSE turn_skips END,
    turn_deadline = now() + interval '30 seconds',
    updated_at = now()
  WHERE id = _game_id;
  PERFORM public.domino_maybe_schedule_bot(_game_id, _next);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ════════════════════════════════════════════════════════════════════════
-- HELPER: End round
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.domino_end_round(_game_id uuid, _winner_slot int DEFAULT null, _blocked boolean DEFAULT false)
RETURNS void AS $$
DECLARE
  _game record; _state jsonb; _p record; _pips int; _total int := 0;
  _hand_pips jsonb := '{}'::jsonb; _final_hands jsonb := '{}'::jsonb;
  _round_score int; _scores jsonb; _winner_uid text := null; _target int;
  _game_over boolean := false; _max int := -1; _ws int; _wu text;
  _now timestamp; _bu timestamp; _key text; _best int := 999; _tie int;
BEGIN
  SELECT * INTO _game FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND OR _game.status != 'playing' THEN RETURN; END IF;
  _state := _game.state; _scores := _game.scores;

  FOR _p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
    _key := COALESCE(_p.user_id::text, 'bot_'||_p.slot);
    _pips := public.domino_hand_pips(_state->('hands')->(_p.slot::text));
    _hand_pips := _hand_pips || jsonb_build_object(_key, _pips);
    _final_hands := _final_hands || jsonb_build_object(_key, _state->('hands')->(_p.slot::text));
    _total := _total + _pips;
  END LOOP;

  IF _blocked THEN
    _best := 999; _winner_slot := null;
    FOR _p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
      _key := COALESCE(_p.user_id::text, 'bot_'||_p.slot);
      _pips := (_hand_pips->>_key)::int;
      IF _pips < _best THEN _best := _pips; _winner_slot := _p.slot; _winner_uid := _key;
      ELSIF _pips = _best THEN _winner_uid := null; END IF;
    END LOOP;
    _round_score := GREATEST(0, _total - _best);
  ELSE
    SELECT COALESCE(user_id::text, 'bot_'||_winner_slot) INTO _winner_uid
    FROM public.domino_participants WHERE game_id = _game_id AND slot = _winner_slot AND forfeited = false;
    _round_score := GREATEST(0, _total - public.domino_hand_pips(_state->('hands')->(_winner_slot::text)));
  END IF;

  IF _winner_uid IS NOT NULL THEN
    _scores := jsonb_set(_scores, ARRAY[_winner_uid], to_jsonb((_scores->>_winner_uid)::int + _round_score));
  END IF;

  _target := _game.target_score;
  IF _target > 0 THEN
    FOR _p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
      _key := COALESCE(_p.user_id::text, 'bot_'||_p.slot);
      IF (_scores->>_key)::int >= _target THEN _game_over := true; END IF;
    END LOOP;
  ELSE
    _game_over := true;
  END IF;

  _now := now(); _bu := _now + interval '7 seconds';
  _state := _state || jsonb_build_object('phase', 'break', 'break_until', to_char(_bu, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'last_round', jsonb_build_object('winner_uid', _winner_uid, 'winner_slot', _winner_slot, 'round_score', _round_score,
    'hand_pips', _hand_pips, 'final_hands', _final_hands, 'blocked', _blocked, 'round', (_state->>'round')::int));

  IF _game_over THEN
    _max := -1; _wu := null; _ws := 0;
    FOR _p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
      _key := COALESCE(_p.user_id::text, 'bot_'||_p.slot);
      IF (_scores->>_key)::int > _max THEN _max := (_scores->>_key)::int; _wu := _p.user_id; _ws := _p.slot; END IF;
    END LOOP;
    _state := _state || jsonb_build_object('phase', 'finished', 'winner_slot', _ws);
    IF _wu IS NOT NULL AND _game.stake > 0 THEN
      UPDATE public.profiles SET balance = balance + (_game.pot * (100 - _game.commission_pct) / 100)::int WHERE id = _wu;
      INSERT INTO public.transactions(user_id, type, amount, description) VALUES (_wu, 'winnings', (_game.pot * (100 - _game.commission_pct) / 100)::int, 'Gain domino');
    END IF;
    UPDATE public.domino_games SET status = 'finished', state = _state, scores = _scores, winner_id = _wu, finished_at = _now, turn_deadline = null, updated_at = _now WHERE id = _game_id;
  ELSE
    UPDATE public.domino_games SET state = _state, scores = _scores, turn_deadline = null, updated_at = _now WHERE id = _game_id;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ════════════════════════════════════════════════════════════════════════
-- HELPER: Start new round
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.domino_start_new_round(_game_id uuid)
RETURNS void AS $$
DECLARE
  _game record; _tiles jsonb; _dealt jsonb; _info jsonb; _state jsonb; _draw text;
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
    'first_move_double', _info->>'double', 'bot_think_until', null,
    'last_round', _game.state->'last_round', 'break_until', null, 'reveal_until', null);
  UPDATE public.domino_games SET state = _state, current_turn = (_info->>'slot')::int, turn_deadline = now() + interval '30 seconds', updated_at = now() WHERE id = _game_id;
  PERFORM public.domino_maybe_schedule_bot(_game_id, (_info->>'slot')::int);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ════════════════════════════════════════════════════════════════════════
-- HELPER: Bot execute (bypass auth)
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.domino_bot_execute(_game_id uuid, _bot record, _move jsonb)
RETURNS void AS $$
DECLARE
  _game record; _state jsonb; _action text; _tile jsonb; _side text;
  _hand jsonb; _idx int; _ta int; _tb int; _le int; _re int;
  _board jsonb; _stock jsonb; _nt jsonb; _slot int; _ts jsonb; _count int;
  _key text; _p record;
BEGIN
  SELECT * INTO _game FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND OR _game.status != 'playing' THEN RETURN; END IF;
  _state := _game.state;
  IF _state->>'phase' != 'playing' THEN RETURN; END IF;
  IF _game.current_turn != _bot.slot THEN RETURN; END IF;

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
      IF (_hand->>(_i))->>0 = _ta::text AND (_hand->>(_i))->>1 = _tb::text THEN _idx := _i; EXIT; END IF;
      IF (_hand->>(_i))->>0 = _tb::text AND (_hand->>(_i))->>1 = _ta::text THEN
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
      -- Playable: play it
      PERFORM public.domino_bot_execute(_game_id, _bot, jsonb_build_object('action','play','tile',_nt,'side','auto'));
    ELSIF jsonb_array_length(_stock) > 0 THEN
      -- Draw again
      UPDATE public.domino_games SET state = _state, turn_deadline = now() + interval '30 seconds', updated_at = now() WHERE id = _game_id;
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ════════════════════════════════════════════════════════════════════════
-- HELPER: Bot AI — evaluates and plays best tile
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.domino_bot_play(_game_id uuid, _bot record)
RETURNS void AS $$
DECLARE
  _game record; _state jsonb; _hand jsonb; _board jsonb;
  _le int; _re int; _stock jsonb; _i int; _tile jsonb; _ta int; _tb int;
  _best_idx int := -1; _best_score float := -1; _best_side text := 'right';
  _ts float; _can_play boolean := false; _draw text; _fmd int;
  _can_l boolean; _can_r boolean;
BEGIN
  SELECT * INTO _game FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND OR _game.status != 'playing' THEN RETURN; END IF;
  _state := _game.state;
  _hand := _state->('hands')->(_bot.slot::text);
  _board := _state->'board';
  _le := NULLIF(_state->>'left_end','')::int;
  _re := NULLIF(_state->>'right_end','')::int;
  _stock := _state->'stock';
  _draw := COALESCE(_state->>'draw_mode','with');
  _fmd := NULLIF(_state->>'first_move_double','')::int;

  FOR _i IN 0..jsonb_array_length(_hand)-1 LOOP
    _tile := _hand->(_i); _ta := (_tile->>0)::int; _tb := (_tile->>1)::int;
    IF jsonb_array_length(_board) = 0 THEN
      IF _fmd IS NOT NULL THEN
        IF _ta = _fmd AND _tb = _fmd THEN _ts := 100; ELSE _ts := -1; END IF;
      ELSE
        _ts := _ta + _tb + CASE WHEN _ta = _tb THEN 5 ELSE 0 END;
      END IF;
      IF _ts > _best_score THEN _best_score := _ts; _best_idx := _i; _best_side := 'auto'; _can_play := true; END IF;
    ELSE
      _can_l := (_ta = _le OR _tb = _le);
      _can_r := (_ta = _re OR _tb = _re);
      IF _can_l OR _can_r THEN
        _can_play := true;
        _ts := _ta + _tb + CASE WHEN _ta = _tb THEN 10 ELSE 0 END;
        _ts := _ts * (_bot.bot_intelligence / 100.0) + random() * (1 - _bot.bot_intelligence / 100.0) * 5;
        IF _ts > _best_score THEN
          _best_score := _ts; _best_idx := _i;
          _best_side := CASE WHEN _can_r THEN 'right' ELSE 'left' END;
        END IF;
      END IF;
    END IF;
  END LOOP;

  IF _can_play AND _best_idx >= 0 THEN
    PERFORM public.domino_bot_execute(_game_id, _bot, jsonb_build_object('action','play','tile',_hand->(_best_idx),'side',_best_side));
  ELSIF _draw = 'with' AND jsonb_array_length(_stock) > 0 THEN
    PERFORM public.domino_bot_execute(_game_id, _bot, jsonb_build_object('action','draw'));
  ELSE
    PERFORM public.domino_bot_execute(_game_id, _bot, jsonb_build_object('action','pass'));
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ════════════════════════════════════════════════════════════════════════
-- HELPER: Auto timeout
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.domino_auto_timeout(_game_id uuid, _part record)
RETURNS void AS $$
DECLARE
  _state jsonb; _ts jsonb; _count int; _key text;
BEGIN
  SELECT state, turn_skips INTO _state, _ts FROM public.domino_games WHERE id = _game_id;
  _key := COALESCE(_part.user_id::text, 'bot_'||_part.slot);
  _ts := jsonb_set(_ts, ARRAY[_key], to_jsonb((_ts->>_key)::int + 1));
  IF (_ts->>_key)::int >= 5 THEN PERFORM public.domino_forfeit_internal(_game_id, _part); RETURN; END IF;
  _state := _state || jsonb_build_object('passes', (_state->>'passes')::int + 1, 'last_pass_by', _part.slot);
  SELECT count(*) INTO _count FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  IF (_state->>'passes')::int >= _count THEN PERFORM public.domino_end_round(_game_id, null, true);
  ELSE PERFORM public.domino_advance_turn(_game_id, _state, _ts); END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ════════════════════════════════════════════════════════════════════════
-- HELPER: Forfeit internal
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.domino_forfeit_internal(_game_id uuid, _part record)
RETURNS void AS $$
DECLARE
  _game record; _remaining int; _winner record; _state jsonb; _now timestamp;
BEGIN
  UPDATE public.domino_participants SET forfeited = true WHERE id = _part.id;
  SELECT count(*) INTO _remaining FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  IF _remaining <= 1 THEN
    SELECT * INTO _winner FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false LIMIT 1;
    _now := now();
    SELECT state INTO _state FROM public.domino_games WHERE id = _game_id;
    _state := _state || jsonb_build_object('phase', 'finished', 'winner_slot', _winner.slot);
    SELECT * INTO _game FROM public.domino_games WHERE id = _game_id;
    IF _winner.user_id IS NOT NULL AND _game.stake > 0 THEN
      UPDATE public.profiles SET balance = balance + (_game.pot * (100 - _game.commission_pct) / 100)::int WHERE id = _winner.user_id;
      INSERT INTO public.transactions(user_id, type, amount, description) VALUES (_winner.user_id, 'winnings', (_game.pot * (100 - _game.commission_pct) / 100)::int, 'Gain domino (forfait)');
    END IF;
    UPDATE public.domino_games SET status = 'finished', state = _state, winner_id = _winner.user_id, finished_at = _now, turn_deadline = null, updated_at = _now WHERE id = _game_id;
  ELSE
    SELECT * INTO _game FROM public.domino_games WHERE id = _game_id;
    IF _game.current_turn = _part.slot THEN PERFORM public.domino_advance_turn(_game_id, _game.state); END IF;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ════════════════════════════════════════════════════════════════════════
-- PUBLIC: CREATE GAME
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.domino_create(
  _stake numeric DEFAULT 0, _max integer DEFAULT 2, _private boolean DEFAULT false,
  _mode text DEFAULT 'classic', _commission integer DEFAULT 10,
  _target_score integer DEFAULT 0, _draw_mode text DEFAULT 'with',
  _first_tile_rule text DEFAULT 'libre'
) RETURNS uuid AS $$
DECLARE
  _id uuid; _host uuid := auth.uid(); _rc text; _pr record; _si int := GREATEST(0, ROUND(_stake));
  _mp int := LEAST(4, GREATEST(2, _max)); _c int := LEAST(30, GREATEST(0, _commission));
  _t int := CASE WHEN _mode = 'points' THEN GREATEST(50, _target_score) ELSE 0 END;
BEGIN
  IF _host IS NULL THEN RAISE EXCEPTION 'Auth required'; END IF;
  IF _si > 0 AND _si < 200 THEN RAISE EXCEPTION 'Mise minimum 200 Ar'; END IF;
  SELECT pseudo INTO _pr FROM public.profiles WHERE id = _host;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profil introuvable'; END IF;
  IF _si > 0 THEN
    UPDATE public.profiles SET balance = balance - _si WHERE id = _host AND balance >= _si;
    IF NOT FOUND THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
    INSERT INTO public.transactions(user_id, type, amount, description) VALUES (_host, 'stake', -_si, 'Mise domino');
  END IF;
  IF _private THEN _rc := lpad(floor(random()*1000000)::text, 6, '0'); END IF;
  INSERT INTO public.domino_games(
    host_id, status, stake, pot, commission_pct, is_private, room_code, state,
    max_players, target_score, scores, turn_skips, paused, pause_used,
    first_tile_rule, mode, current_turn, created_at, updated_at
  ) VALUES (
    _host, 'open', _si, 0, _c, _private, _rc,
    jsonb_build_object('phase','waiting','round',0,'board','[]'::jsonb,'left_end',null,'right_end',null,
      'hands','{}'::jsonb,'stock','[]'::jsonb,'draw_mode',_draw_mode,'first_tile_rule',_first_tile_rule,
      'passes',0,'last_pass_by',null,'bot_think_until',null),
    _mp, _t, '{}'::jsonb, '{}'::jsonb, false, false, _first_tile_rule, _mode, -1, now(), now()
  ) RETURNING id INTO _id;
  INSERT INTO public.domino_participants(game_id, user_id, slot, ready, forfeited, score, display_name, is_bot, joined_at)
  VALUES (_id, _host, 0, false, false, 0, COALESCE(_pr.pseudo, 'Joueur'), false, now());
  RETURN _id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ════════════════════════════════════════════════════════════════════════
-- PUBLIC: ADD BOT
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.domino_add_bot(_game_id uuid, _bot_name text DEFAULT 'Bot')
RETURNS void AS $$
DECLARE _g record; _slot int; _n text; _names text[] := ARRAY['Tahiry','Naina','Rado','Hery','Lova','Fara','Vola','Maitso'];
BEGIN
  SELECT * INTO _g FROM public.domino_games WHERE id = _game_id AND status = 'open';
  IF NOT FOUND THEN RAISE EXCEPTION 'Partie introuvable ou déjà commencée'; END IF;
  SELECT COALESCE(MAX(slot), -1) + 1 INTO _slot FROM public.domino_participants WHERE game_id = _game_id;
  IF _slot >= _g.max_players THEN RAISE EXCEPTION 'Partie complète'; END IF;
  _n := COALESCE(NULLIF(_bot_name, ''), _names[(_slot % array_length(_names,1)) + 1]);
  INSERT INTO public.domino_participants(game_id, slot, ready, forfeited, score, display_name, is_bot,
    bot_name, bot_intelligence, bot_win_bias, joined_at)
  VALUES (_game_id, _slot, true, false, 0, _n, true, _n, 60 + floor(random()*35)::int, floor(random()*15)::int, now());
  UPDATE public.domino_games SET updated_at = now() WHERE id = _game_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ════════════════════════════════════════════════════════════════════════
-- PUBLIC: SET READY (also starts game if all ready)
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.domino_set_ready(_game_id uuid, _ready boolean)
RETURNS void AS $$
DECLARE
  _g record; _all boolean; _count int; _tiles jsonb; _dealt jsonb; _info jsonb;
  _state jsonb; _scores jsonb := '{}'::jsonb; _ts jsonb := '{}'::jsonb; _p record; _key text; _draw text;
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
      'first_move_double',_info->>'double','bot_think_until',null,
      'last_round',null,'break_until',null,'reveal_until',null);
    UPDATE public.domino_games SET
      status='playing', state=_state, current_turn=(_info->>'slot')::int,
      scores=_scores, turn_skips=_ts, started_at=now(), turn_deadline=now()+interval '30 seconds',
      pot=_g.stake*_count, updated_at=now()
    WHERE id=_game_id;
    PERFORM public.domino_maybe_schedule_bot(_game_id, (_info->>'slot')::int);
  END IF;
  UPDATE public.domino_games SET updated_at = now() WHERE id = _game_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ════════════════════════════════════════════════════════════════════════
-- PUBLIC: PLAY (place tile, draw, or pass)
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.domino_play(_game_id uuid, _move jsonb)
RETURNS void AS $$
DECLARE
  _g record; _state jsonb; _action text; _tile jsonb; _side text;
  _part record; _hand jsonb; _idx int; _ta int; _tb int; _le int; _re int;
  _board jsonb; _stock jsonb; _nt jsonb; _slot int; _ts jsonb; _count int; _key text; _draw text;
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
      ELSE
        IF _ta = _re THEN _nt := jsonb_build_array(_ta, _tb); _re := _tb;
        ELSIF _tb = _re THEN _nt := jsonb_build_array(_tb, _ta); _re := _ta;
        ELSE RAISE EXCEPTION 'Tuile non jouable à droite'; END IF;
        _board := _board || jsonb_build_array(_nt);
      END IF;
    END IF;

    _hand := public.domino_remove_at(_hand, _idx);
    _state := _state || jsonb_build_object('board',_board,'left_end',_le,'right_end',_re,'passes',0,'last_pass_by',null,'first_move_double',null);
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
      -- Playable: keep turn
      UPDATE public.domino_games SET state=_state, turn_deadline=now()+interval '30 seconds', updated_at=now() WHERE id=_game_id;
    ELSIF jsonb_array_length(_stock) > 0 THEN
      -- Not playable but stock remains: keep turn
      UPDATE public.domino_games SET state=_state, turn_deadline=now()+interval '30 seconds', updated_at=now() WHERE id=_game_id;
    ELSE
      -- Stock empty: auto-pass
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
-- PUBLIC: TICK (timer + bot)
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.domino_tick(_game_id uuid)
RETURNS void AS $$
DECLARE
  _g record; _state jsonb; _phase text; _part record; _think text; _bu timestamp;
BEGIN
  SELECT * INTO _g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND OR _g.status != 'playing' THEN RETURN; END IF;
  _state := _g.state; _phase := _state->>'phase';

  IF _phase = 'break' THEN
    _bu := to_timestamp(_state->>'break_until', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
    IF now() >= _bu THEN PERFORM public.domino_start_new_round(_game_id); END IF;
    RETURN;
  END IF;
  IF _phase != 'playing' THEN RETURN; END IF;

  _think := _state->>'bot_think_until';
  IF _think IS NOT NULL THEN
    IF now() >= to_timestamp(_think, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') THEN
      SELECT * INTO _part FROM public.domino_participants WHERE game_id = _game_id AND slot = _g.current_turn AND is_bot = true AND forfeited = false;
      IF FOUND THEN PERFORM public.domino_bot_play(_game_id, _part); END IF;
    END IF;
    RETURN;
  END IF;

  IF _g.turn_deadline IS NOT NULL AND now() >= _g.turn_deadline THEN
    SELECT * INTO _part FROM public.domino_participants WHERE game_id = _game_id AND slot = _g.current_turn AND forfeited = false;
    IF FOUND THEN
      IF _part.is_bot THEN PERFORM public.domino_bot_play(_game_id, _part);
      ELSE PERFORM public.domino_auto_timeout(_game_id, _part); END IF;
    END IF;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ════════════════════════════════════════════════════════════════════════
-- PUBLIC: FORFEIT
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.domino_forfeit(_game_id uuid)
RETURNS void AS $$
DECLARE _part record;
BEGIN
  SELECT * INTO _part FROM public.domino_participants WHERE game_id = _game_id AND user_id = auth.uid() AND forfeited = false;
  IF NOT FOUND THEN RETURN; END IF;
  PERFORM public.domino_forfeit_internal(_game_id, _part);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ════════════════════════════════════════════════════════════════════════
GRANT EXECUTE ON FUNCTION public.domino_create(numeric,integer,boolean,text,integer,integer,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.domino_add_bot(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.domino_set_ready(uuid,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.domino_play(uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.domino_tick(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.domino_forfeit(uuid) TO authenticated;
