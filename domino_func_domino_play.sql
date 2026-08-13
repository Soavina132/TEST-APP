CREATE OR REPLACE FUNCTION public.domino_play(_game_id uuid, _move jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
$function$
