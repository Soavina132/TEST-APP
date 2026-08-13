CREATE OR REPLACE FUNCTION public.domino_bot_execute(_game_id uuid, _bot record, _move jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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
