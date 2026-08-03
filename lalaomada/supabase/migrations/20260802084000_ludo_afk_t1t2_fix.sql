-- ========================================
-- Restore and fix T1/T2 AFK system
-- T1 = passive AFK (didn't roll the dice) — max 5
-- T2 = active AFK (rolled but didn't move) — max 2
-- ========================================

CREATE OR REPLACE FUNCTION public.ludo_check_timeout(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  g public.ludo_games%ROWTYPE;
  st jsonb;
  v_slot INT;
  v_started TIMESTAMPTZ;
  v_uid UUID;
  v_isbot BOOLEAN;
  v_missed INT;
  v_winner UUID;
  v_status TEXT;
  v_must_move BOOLEAN;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL OR g.status IS NULL OR g.status <> 'playing' THEN RETURN g.state; END IF;
  st := g.state;
  IF st IS NULL THEN RETURN st; END IF;
  v_started := (st->>'turn_started_at')::TIMESTAMPTZ;
  -- Guard against clock skew
  IF v_started > now() + interval '1 minute' THEN
    v_started := now() - interval '60 seconds';
  END IF;
  IF now() - v_started < interval '30 seconds' THEN RETURN st; END IF;

  v_slot := (st->>'turn_slot')::INT;
  v_must_move := (st->>'must_move')::BOOLEAN;

  SELECT user_id, is_bot, missed_turns
    INTO v_uid, v_isbot, v_missed
    FROM public.ludo_participants
    WHERE game_id = _game_id AND slot = v_slot;

  -- Bots never get AFK penalties
  IF v_isbot THEN
    -- Just advance the turn
    st := jsonb_set(st, '{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st, '{dice}', 'null'::jsonb);
    st := jsonb_set(st, '{must_move}', 'false'::jsonb);
    st := jsonb_set(st, '{consecutive_sixes}', '0'::jsonb);
    st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    st := jsonb_set(st, '{last_event}', to_jsonb('bot_timeout'::text));
    UPDATE public.ludo_games SET state = st, current_turn = (st->>'turn_slot')::INT WHERE id = _game_id;
    RETURN st;
  END IF;

  -- Increment the appropriate AFK counter
  -- T1: player didn't even roll (must_move = false)
  -- T2: player rolled but didn't move (must_move = true)
  v_missed := COALESCE(v_missed, 0) + 1;

  IF v_must_move THEN
    -- T2: rolled but didn't move — more severe
    UPDATE public.ludo_participants
      SET missed_turns = v_missed, afk_t2 = COALESCE(afk_t2, 0) + 1
      WHERE game_id = _game_id AND slot = v_slot;
  ELSE
    -- T1: didn't even roll — less severe
    UPDATE public.ludo_participants
      SET missed_turns = v_missed, afk_t1 = COALESCE(afk_t1, 0) + 1
      WHERE game_id = _game_id AND slot = v_slot;
  END IF;

  -- Check if the player should be forfeited (T1 or T2 threshold reached)
  PERFORM public._ludo_check_afk(_game_id, v_slot);

  -- Check if game was finished by the AFK check
  SELECT status INTO v_status FROM public.ludo_games WHERE id = _game_id;
  IF v_status = 'finished' THEN
    RETURN (SELECT state FROM public.ludo_games WHERE id = _game_id);
  END IF;

  -- Also forfeit after 3 total missed turns (fallback safety net)
  IF v_missed >= 3 THEN
    UPDATE public.ludo_participants SET forfeited = TRUE WHERE game_id = _game_id AND slot = v_slot;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'forfeit', 0, _game_id,
        'Forfait (' || v_missed || ' timeouts, T1+T2 total)');
    v_winner := public._ludo_check_last_standing(_game_id);
    IF v_winner IS NOT NULL THEN
      PERFORM public.finish_game(_game_id, v_winner);
      RETURN (SELECT state FROM public.ludo_games WHERE id = _game_id);
    END IF;
  END IF;

  -- Advance the turn
  st := jsonb_set(st, '{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
  st := jsonb_set(st, '{dice}', 'null'::jsonb);
  st := jsonb_set(st, '{must_move}', 'false'::jsonb);
  st := jsonb_set(st, '{consecutive_sixes}', '0'::jsonb);
  st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')));
  st := jsonb_set(st, '{last_event}', to_jsonb(
    CASE WHEN v_must_move THEN 'timeout_t2' ELSE 'timeout_t1' END
  ));
  UPDATE public.ludo_games SET state = st, current_turn = (st->>'turn_slot')::INT WHERE id = _game_id;
  RETURN st;
END $function$;
