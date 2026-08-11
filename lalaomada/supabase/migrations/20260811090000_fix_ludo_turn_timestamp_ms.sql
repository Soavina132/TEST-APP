-- Fix: harmonize turn_started_at timestamp format to include milliseconds everywhere
-- Previously _ludo_init_state, ludo_check_timeout, and _ludo_advance_turn used
-- SS"Z" (no ms) while ludo_roll used SS.MS"Z". This inconsistency could cause
-- timing issues on the first turn.

CREATE OR REPLACE FUNCTION public._ludo_init_state(_max_players INT, _mode TEXT DEFAULT 'classic')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE p jsonb := '{}'::jsonb; i INT; v_st jsonb;
BEGIN
  FOR i IN 0.._max_players-1 LOOP
    p := p || jsonb_build_object(i::text,
      jsonb_build_array(
        jsonb_build_object('s','yard','k',-1),
        jsonb_build_object('s','yard','k',-1),
        jsonb_build_object('s','yard','k',-1),
        jsonb_build_object('s','yard','k',-1)
      ));
  END LOOP;
  v_st := jsonb_build_object(
    'pawns', p, 'turn_slot', 0, 'dice', NULL, 'must_move', false,
    'turn_started_at', to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'turn_seq', 0, 'phase', 'spinning',
    'phase_started_at', to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'spin_ms', 0, 'last_event', 'start');
  IF _mode = 'fast' THEN
    v_st := v_st || jsonb_build_object(
      'power_tiles', public._ludo_place_power_tiles(),
      'shields', '{}'::jsonb,
      'double_roll_pending', 'null'::jsonb
    );
  END IF;
  RETURN v_st;
END
$function$;

-- ludo_check_timeout: fix timestamp format
CREATE OR REPLACE FUNCTION public.ludo_check_timeout(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_slot int; v_started timestamptz;
  v_uid uuid; v_isbot boolean; v_secs int; v_choice text;
  v_new_slot INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := g.state; v_slot := (st->>'turn_slot')::INT;

  IF st ? 'power_pending' THEN
    IF (st->'power_pending'->>'tile_type') = 'boost' THEN
      v_choice := 'skip';
    ELSE
      v_choice := (st->'power_pending'->'options'->>0);
    END IF;
    PERFORM public.ludo_choose_power(_game_id, v_choice);
    SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
    RETURN st;
  END IF;

  SELECT user_id, is_bot INTO v_uid, v_isbot
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  SELECT COALESCE(turn_seconds,30) INTO v_secs FROM public.app_settings WHERE id=1;
  v_started := (st->>'turn_started_at')::timestamptz;
  IF now() - v_started < (v_secs || ' seconds')::interval THEN RETURN st; END IF;
  IF NOT COALESCE(v_isbot,false) AND COALESCE((st->>'must_move')::boolean, false) AND COALESCE(g.auto_move, false) THEN
    IF public._ludo_auto_move(_game_id, v_slot) THEN
      SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
      RETURN st;
    END IF;
  END IF;
  IF NOT v_isbot AND NOT (st->>'must_move')::BOOLEAN THEN
    UPDATE public.ludo_participants SET afk_t1 = afk_t1 + 1 WHERE game_id=_game_id AND slot=v_slot;
  END IF;
  IF NOT v_isbot AND (st->>'must_move')::BOOLEAN THEN
    UPDATE public.ludo_participants SET afk_t2 = afk_t2 + 1 WHERE game_id=_game_id AND slot=v_slot;
  END IF;
  IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
    st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
  END IF;
  v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
  st := public._ludo_clear_shield(st, v_new_slot);
  st := jsonb_set(st,'{turn_slot}', to_jsonb(v_new_slot));
  st := jsonb_set(st,'{dice}','null'::jsonb);
  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := public._ludo_decrement_cooldowns(st);
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('timeout'::text));
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  IF NOT v_isbot THEN PERFORM public._ludo_check_afk(_game_id, v_slot); END IF;
  RETURN st;
END
$function$;

-- _ludo_advance_turn: fix timestamp format
CREATE OR REPLACE FUNCTION public._ludo_advance_turn(_game_id uuid, _new_slot integer, _last_event text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_isbot boolean;
  v_spin_ms int; v_seq int; v_now text; v_shields jsonb;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id;
  st := g.state;
  v_now := to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
  SELECT is_bot INTO v_isbot FROM public.ludo_participants WHERE game_id=_game_id AND slot=_new_slot;
  v_spin_ms := CASE WHEN COALESCE(v_isbot, FALSE) THEN 2500 ELSE 0 END;
  v_seq := COALESCE((st->>'turn_seq')::int, 0) + 1;
  st := jsonb_set(st, '{turn_slot}', to_jsonb(_new_slot));
  st := jsonb_set(st, '{turn_started_at}', to_jsonb(v_now));
  st := jsonb_set(st, '{turn_seq}', to_jsonb(v_seq));
  st := jsonb_set(st, '{phase}', to_jsonb('spinning'::text));
  st := jsonb_set(st, '{phase_started_at}', to_jsonb(v_now));
  st := jsonb_set(st, '{spin_ms}', to_jsonb(v_spin_ms));
  st := jsonb_set(st, '{dice}', 'null'::jsonb);
  st := jsonb_set(st, '{must_move}', 'false'::jsonb);
  st := jsonb_set(st, '{last_event}', to_jsonb(_last_event));
  IF st ? 'shields' THEN
    v_shields := st->'shields';
    IF v_shields ? _new_slot::text THEN
      v_shields := v_shields - _new_slot::text;
      st := jsonb_set(st, '{shields}', v_shields, true);
    END IF;
  END IF;
  st := public._ludo_decrement_cooldowns(st);
  st := st - 'power_event';
  UPDATE public.ludo_games SET state=st, current_turn=_new_slot WHERE id=_game_id;
  RETURN st;
END
$function$;
