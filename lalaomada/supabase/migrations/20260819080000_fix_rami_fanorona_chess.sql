-- ============================================================
-- FIX 3: RAMI — _rami_is_joker permission denied
--        REVOKED in security_lockdown, never re-granted
-- FIX 4: FANORONA — fanorona_create_solo missing _stake param
--        Frontend passes _stake but function doesn't accept it
-- FIX 5: CHESS — _chess_apply_move has 2 overlapping signatures
--        PostgreSQL can't resolve which function to call
-- ============================================================

-- ═══ FIX 3: Grant EXECUTE on _rami_is_joker to authenticated ═══
GRANT EXECUTE ON FUNCTION public._rami_is_joker(_c integer, _mode text, _rj integer) TO authenticated;

-- ═══ FIX 4: Re-create fanorona_create_solo with _stake param ═══
CREATE OR REPLACE FUNCTION public.fanorona_create_solo(
  _stake numeric DEFAULT 0,
  _variant text DEFAULT 'tsivy',
  _mandatory_capture boolean DEFAULT true,
  _bot_intelligence integer DEFAULT 2,
  _time_min integer DEFAULT 10
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_name text; v_id uuid;
  v_bot_name text;
  v_time_ms int;
BEGIN
  PERFORM public._assert_solo_bot_enabled();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _time_min NOT IN (0, 1, 3, 5, 7, 10, 15) THEN
    _time_min := 10;
  END IF;
  v_time_ms := _time_min * 60 * 1000;

  v_bot_name := CASE _bot_intelligence WHEN 1 THEN 'Bot Facile'
                                        WHEN 3 THEN 'Bot Difficile'
                                        ELSE 'Bot Moyen' END;
  SELECT pseudo INTO v_name FROM public.profiles WHERE id = v_uid;

  INSERT INTO public.fanorona_games(
    host_id, stake, pot, commission_pct, is_private, room_code, state,
    time_control_min, white_time_ms, black_time_ms,
    status, current_turn, started_at, last_move_at, turn_deadline
  ) VALUES (
    v_uid, _stake, _stake, 0, false, NULL,
    jsonb_build_object('phase','playing','board', public._fanorona_init_board(),
                       'chain_from', null, 'visited', '[]'::jsonb,
                       'last_axis', null, 'move_count', 0),
    _time_min, v_time_ms, v_time_ms,
    'playing', 0, now(), now(),
    now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')), 60) || ' seconds')::interval
  ) RETURNING id INTO v_id;

  INSERT INTO public.fanorona_participants(game_id, user_id, slot, color, display_name, ready)
    VALUES (v_id, v_uid, 0, 'white', COALESCE(v_name,'Vous'), true);
  INSERT INTO public.fanorona_participants(
    game_id, user_id, slot, color, display_name, ready, is_bot, bot_intelligence, bot_name
  ) VALUES (
    v_id, NULL, 1, 'black', v_bot_name, true, true, _bot_intelligence, v_bot_name
  );

  RETURN v_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.fanorona_create_solo(numeric, text, boolean, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fanorona_create_solo(numeric, text, boolean, integer, integer) TO authenticated;

-- Also drop the old 4-param version if it still exists
DROP FUNCTION IF EXISTS public.fanorona_create_solo(text, boolean, integer, integer) CASCADE;

-- ═══ FIX 5: Drop old _chess_apply_move signature ═══
-- Old v1: (_game_id uuid, _fen_after text, _turn text, _san text, _uci text, _by_user uuid, _elapsed_ms int, _mover_color text, _clear_draw_offer uuid)
-- New v2: (_game_id uuid, _san text, _uci text, _fen_after text, _turn text, _by_user uuid, _mover_color text, _elapsed_ms integer, _clear_draw_offer uuid)
-- Both have same param names but different type order at positions 7-8 → ambiguous
DROP FUNCTION IF EXISTS public._chess_apply_move(uuid, text, text, text, text, uuid, int, text, uuid) CASCADE;
