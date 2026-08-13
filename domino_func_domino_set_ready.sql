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
$function$
