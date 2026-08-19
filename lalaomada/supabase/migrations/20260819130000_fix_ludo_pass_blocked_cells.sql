CREATE OR REPLACE FUNCTION public.ludo_pass(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_slot INT; v_dice INT;
  v_uid UUID := auth.uid(); v_user UUID; v_isbot BOOLEAN; arr jsonb;
  pawn jsonb; i INT; pstate TEXT; pstep INT; has_move BOOLEAN := FALSE;
  v_new_slot INT;
  v_movable jsonb;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := g.state; v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot INTO v_user, v_isbot
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF NOT (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Lancez le dé d''abord'; END IF;
  v_dice := (st->>'dice')::INT;

  -- Use _ludo_movable_pawns (the SAME function ludo_roll uses) instead of
  -- a simplified check that doesn't account for blocked cells.
  v_movable := public._ludo_movable_pawns(st, v_slot, v_dice);
  IF jsonb_array_length(v_movable) > 0 THEN RAISE EXCEPTION 'Vous avez un coup possible'; END IF;

  UPDATE public.ludo_participants SET consecutive_sixes = 0
    WHERE game_id = _game_id AND slot = v_slot;

  -- Clean up power mode state
  IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
    st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
  END IF;

  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := jsonb_set(st,'{dice}','null'::jsonb);
  v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
  st := public._ludo_clear_shield(st, v_new_slot);
  st := jsonb_set(st,'{turn_slot}', to_jsonb(v_new_slot));
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('pass'));
  st := st - 'no_move_display';
  st := st - 'power_event';
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;

  PERFORM public._ludo_check_game_over(_game_id);

  RETURN st;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.ludo_pass(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ludo_pass(uuid) TO authenticated;
