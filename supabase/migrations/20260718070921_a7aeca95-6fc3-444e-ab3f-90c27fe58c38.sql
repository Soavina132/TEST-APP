CREATE OR REPLACE FUNCTION public._chess_sync_fen_turn(_fen text, _turn text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  parts text[];
BEGIN
  IF _fen IS NULL OR btrim(_fen) = '' OR _turn IS NULL OR _turn NOT IN ('w','b') THEN
    RETURN _fen;
  END IF;

  parts := regexp_split_to_array(_fen, '\s+');
  IF array_length(parts, 1) < 2 THEN
    RETURN _fen;
  END IF;

  parts[2] := _turn;
  RETURN array_to_string(parts, ' ');
END;
$$;

CREATE OR REPLACE FUNCTION public.chess_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_g public.chess_games%ROWTYPE;
  cur_uid uuid;
  opp_uid uuid;
  next_turn text;
  _cfg record;
  _skips int;
  BOT_UUID CONSTANT uuid := '00000000-0000-0000-0000-000000000001';
BEGIN
  SELECT * INTO v_g FROM public.chess_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND OR v_g.status <> 'playing' OR v_g.paused = TRUE OR v_g.turn_deadline IS NULL OR v_g.turn_deadline > now() THEN
    RETURN;
  END IF;

  SELECT * INTO _cfg FROM public._game_cfg('chess');

  IF v_g.turn = 'w' THEN
    cur_uid := v_g.white_id;
    opp_uid := v_g.black_id;
    next_turn := 'b';
  ELSE
    cur_uid := v_g.black_id;
    opp_uid := v_g.white_id;
    next_turn := 'w';
  END IF;

  IF cur_uid = BOT_UUID THEN
    UPDATE public.chess_games
       SET turn = next_turn,
           fen = public._chess_sync_fen_turn(v_g.fen, next_turn),
           turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval
     WHERE id = _game_id;
    RETURN;
  END IF;

  _skips := COALESCE((v_g.turn_skips ->> cur_uid::text)::int, 0) + 1;
  IF _skips >= COALESCE(_cfg.max_turn_skips, 5) THEN
    PERFORM public._chess_payout(_game_id, opp_uid, false);
    RETURN;
  END IF;

  UPDATE public.chess_games
     SET turn = next_turn,
         fen = public._chess_sync_fen_turn(v_g.fen, next_turn),
         turn_skips = jsonb_set(v_g.turn_skips, ARRAY[cur_uid::text], to_jsonb(_skips), true),
         turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval
   WHERE id = _game_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.chess_tick(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chess_tick(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.chess_tick_all()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  g_id uuid;
BEGIN
  FOR g_id IN
    SELECT id
      FROM public.chess_games
     WHERE status = 'playing'
       AND paused = FALSE
       AND turn_deadline IS NOT NULL
       AND turn_deadline <= now()
  LOOP
    BEGIN
      PERFORM public.chess_tick(g_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'chess_tick failed for game %: %', g_id, SQLERRM;
    END;
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.chess_tick_all() TO service_role;

DO $$
DECLARE
  j bigint;
BEGIN
  SELECT jobid INTO j FROM cron.job WHERE jobname = 'chess_tick_all';
  IF j IS NOT NULL THEN
    PERFORM cron.unschedule(j);
  END IF;
END $$;

SELECT cron.schedule('chess_tick_all', '5 seconds', $$SELECT public.chess_tick_all();$$);