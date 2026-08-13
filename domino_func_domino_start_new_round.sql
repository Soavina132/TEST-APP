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
$function$
