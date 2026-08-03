CREATE OR REPLACE FUNCTION public.ludo_check_timeout(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $function$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_slot INT; v_started TIMESTAMPTZ;
  v_uid UUID; v_isbot BOOLEAN; v_missed INT; v_winner UUID;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := g.state;
  v_started := (st->>'turn_started_at')::TIMESTAMPTZ;
  IF now() - v_started < interval '30 seconds' THEN RETURN st; END IF;
  v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot, missed_turns INTO v_uid, v_isbot, v_missed
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  v_missed := COALESCE(v_missed,0) + 1;
  UPDATE public.ludo_participants SET missed_turns=v_missed WHERE game_id=_game_id AND slot=v_slot;
  IF v_missed >= 3 AND NOT v_isbot THEN
    UPDATE public.ludo_participants SET forfeited=TRUE WHERE game_id=_game_id AND slot=v_slot;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_uid,'forfeit',0,_game_id,'Forfait (3 timeouts)');
    v_winner := public._ludo_check_last_standing(_game_id);
    IF v_winner IS NOT NULL THEN
      PERFORM public.finish_game(_game_id, v_winner);
      RETURN (SELECT state FROM public.ludo_games WHERE id=_game_id);
    END IF;
  END IF;
  st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
  st := jsonb_set(st,'{dice}','null'::jsonb);
  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('timeout'::text));
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  RETURN st;
END $function$;