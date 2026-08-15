-- ============================================================
-- Fix Ludo bugs:
--   16) ludo_check_timeout: filter forfeited players in turn check
--   17) ludo_check_timeout: skip bots (they're auto-played by tick_all)
-- ============================================================

CREATE OR REPLACE FUNCTION public.ludo_check_timeout(_game_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
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
  v_turn_seconds INT;
  v_max_skips INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := g.state;

  SELECT turn_seconds INTO v_turn_seconds FROM public.app_settings WHERE id = 1;
  v_turn_seconds := COALESCE(v_turn_seconds, 30);

  SELECT COALESCE(
    (SELECT gc.max_turn_skips FROM public.game_configs gc WHERE gc.slug = 'ludo'),
    3
  ) INTO v_max_skips;

  v_started := (st->>'turn_started_at')::TIMESTAMPTZ;
  IF now() - v_started < (v_turn_seconds || ' seconds')::interval THEN RETURN st; END IF;

  v_slot := (st->>'turn_slot')::INT;

  -- Bug 16: filter forfeited players
  SELECT user_id, is_bot, missed_turns INTO v_uid, v_isbot, v_missed
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot AND NOT forfeited;

  -- If current player forfeited or not found, advance turn
  IF NOT FOUND THEN
    st := jsonb_set(st, '{must_move}', 'false'::jsonb);
    st := jsonb_set(st, '{dice}', 'null'::jsonb);
    st := jsonb_set(st, '{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := public._ludo_clear_shield(st, (st->>'turn_slot')::INT);
    st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st, '{last_event}', to_jsonb('skip_forfeit'::text));
    st := st - 'no_move_display' - 'movable_pawns' - 'power_event';
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
    RETURN st;
  END IF;

  -- Bug 17: skip bots — they're auto-played by ludo_tick_all, not timed out
  IF v_isbot THEN
    RETURN st;
  END IF;

  v_missed := COALESCE(v_missed,0) + 1;
  UPDATE public.ludo_participants SET missed_turns=v_missed WHERE game_id=_game_id AND slot=v_slot;

  UPDATE public.ludo_participants SET consecutive_sixes=0
    WHERE game_id=_game_id AND slot=v_slot;

  st := jsonb_set(st, '{no_move_streak}', to_jsonb(COALESCE((st->>'no_move_streak')::int, 0) + 1));

  IF v_missed >= v_max_skips THEN
    UPDATE public.ludo_participants SET forfeited=TRUE WHERE game_id=_game_id AND slot=v_slot;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_uid,'forfeit',0,_game_id,CONCAT('Forfait (', v_max_skips, ' timeouts)'));
    v_winner := public._ludo_check_last_standing(_game_id);
    IF v_winner IS NOT NULL THEN
      PERFORM public.finish_game(_game_id, v_winner);
    ELSE
      UPDATE public.ludo_games SET status='finished', finished_at=now() WHERE id=_game_id;
      PERFORM public._ludo_purge(_game_id);
    END IF;
    RETURN st;
  END IF;

  IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
    st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
  END IF;
  st := jsonb_set(st, '{must_move}', 'false'::jsonb);
  st := jsonb_set(st, '{dice}', 'null'::jsonb);
  st := public._ludo_clear_shield(st, public._ludo_next_slot(_game_id, v_slot, g.max_players));
  st := jsonb_set(st, '{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
  st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  st := jsonb_set(st, '{last_event}', to_jsonb('timeout'::text));
  st := st - 'no_move_display' - 'movable_pawns' - 'power_event';
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  PERFORM public._ludo_check_game_over(_game_id);
  RETURN st;
END $function$;
