-- ============================================================
-- CREATE MISSING HELPER FUNCTIONS needed by 20260813110000 migration
-- These functions were defined in migrations that were never applied to the DB.
-- We create them here WITHOUT dropping any existing functions.
-- ============================================================


-- ── domino_generate_tiles ──
CREATE OR REPLACE FUNCTION public.domino_generate_tiles()
RETURNS jsonb AS $$
DECLARE _tiles jsonb := '[]'::jsonb; _i int; _j int;
BEGIN
  FOR _i IN 0..6 LOOP
    FOR _j IN _i..6 LOOP
      _tiles := _tiles || jsonb_build_array(jsonb_build_array(_i, _j));
    END LOOP;
  END LOOP;
  SELECT jsonb_agg(x) INTO _tiles FROM (SELECT x FROM jsonb_array_elements(_tiles) AS x ORDER BY random()) s;
  RETURN _tiles;
END;
$$ LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER;


-- ── domino_hand_pips ──
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


-- ── domino_remove_at ──
CREATE OR REPLACE FUNCTION public.domino_remove_at(_arr jsonb, _idx int)
RETURNS jsonb AS $$
DECLARE _result jsonb;
BEGIN
  SELECT jsonb_agg(x) INTO _result
  FROM (SELECT x FROM jsonb_array_elements(_arr) WITH ORDINALITY AS ord(x, rn) WHERE rn - 1 != _idx ORDER BY rn) s;
  RETURN COALESCE(_result, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER;


-- ── domino_pop_first ──
CREATE OR REPLACE FUNCTION public.domino_pop_first(_arr jsonb)
RETURNS jsonb AS $$
DECLARE _result jsonb;
BEGIN
  SELECT jsonb_agg(x) INTO _result
  FROM (SELECT x FROM jsonb_array_elements(_arr) WITH ORDINALITY AS ord(x, rn) WHERE rn > 1 ORDER BY rn) s;
  RETURN COALESCE(_result, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER;


-- ── domino_deal_tiles ──
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


-- ── domino_find_first_player ──
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


-- ── domino_end_round ──
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


-- ── _domino_playable_tiles ──
CREATE OR REPLACE FUNCTION public._domino_playable_tiles(_state jsonb, _slot INT)
RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
  hand jsonb;
  board jsonb;
  left_end INT;
  right_end INT;
  i INT;
  tile jsonb;
  a INT; b INT;
  result jsonb := '[]'::jsonb;
  first_move_double INT;
  first_tile_rule TEXT;
  board_len INT;
BEGIN
  hand := _state->'hands'->_slot::text;
  board := _state->'board';
  IF hand IS NULL THEN RETURN '[]'::jsonb; END IF;

  board_len := COALESCE(jsonb_array_length(board), 0);
  left_end := NULLIF(_state->>'left_end','')::INT;
  right_end := NULLIF(_state->>'right_end','')::INT;
  first_move_double := NULLIF(_state->>'first_move_double','')::INT;
  first_tile_rule := COALESCE(_state->>'first_tile_rule', 'libre');

  FOR i IN 0..jsonb_array_length(hand)-1 LOOP
    tile := hand->i;
    a := (tile->>0)::INT;
    b := (tile->>1)::INT;

    IF board_len = 0 THEN
      -- First tile rules
      IF first_move_double IS NOT NULL THEN
        IF a = first_move_double AND b = first_move_double THEN
          result := result || to_jsonb(i);
        END IF;
      ELSIF first_tile_rule = 'under6' THEN
        IF a + b < 6 THEN result := result || to_jsonb(i); END IF;
      ELSE
        result := result || to_jsonb(i);
      END IF;
    ELSE
      IF a = left_end OR b = left_end OR a = right_end OR b = right_end THEN
        result := result || to_jsonb(i);
      END IF;
    END IF;
  END LOOP;

  RETURN result;
END $$;


-- ── _domino_turn_delay ──
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


-- ── domino_advance_turn ──
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

