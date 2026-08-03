
-- 1) chess_tick: quand c'est au bot de jouer, ne PAS lui coller un skip
--    (le bot est piloté côté client par l'humain). On repousse la deadline
--    de 10 s pour laisser le client déclencher chess_bot_move.
CREATE OR REPLACE FUNCTION public.chess_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_g public.chess_games%ROWTYPE;
  cur_uid uuid; opp_uid uuid;
  _cfg record; _skips int;
  BOT_UUID CONSTANT uuid := '00000000-0000-0000-0000-000000000001';
BEGIN
  SELECT * INTO v_g FROM public.chess_games WHERE id=_game_id FOR UPDATE;
  IF v_g.status <> 'playing' OR v_g.turn_deadline IS NULL OR v_g.turn_deadline > now() THEN RETURN; END IF;
  SELECT * INTO _cfg FROM public._game_cfg('chess');

  IF v_g.turn = 'w' THEN cur_uid := v_g.white_id; opp_uid := v_g.black_id;
  ELSE cur_uid := v_g.black_id; opp_uid := v_g.white_id; END IF;

  -- Si c'est au bot de jouer : ne rien skipper, simplement repousser la deadline.
  IF cur_uid = BOT_UUID THEN
    UPDATE public.chess_games
       SET turn_deadline = now() + interval '10 seconds'
     WHERE id = _game_id;
    RETURN;
  END IF;

  _skips := COALESCE((v_g.turn_skips->>cur_uid::text)::int, 0) + 1;
  IF _skips >= _cfg.max_turn_skips THEN
    PERFORM public._chess_payout(_game_id, opp_uid, false);
    RETURN;
  END IF;

  UPDATE public.chess_games SET
    turn = CASE WHEN turn='w' THEN 'b' ELSE 'w' END,
    turn_skips = jsonb_set(v_g.turn_skips, ARRAY[cur_uid::text], to_jsonb(_skips)),
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
  WHERE id=_game_id;
END $function$;

-- 2) Cron server-authoritative : passe le tour même si aucun client n'est actif.
CREATE OR REPLACE FUNCTION public.chess_tick_all()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE g_id uuid;
BEGIN
  FOR g_id IN
    SELECT id FROM public.chess_games
    WHERE status = 'playing'
      AND turn_deadline IS NOT NULL
      AND turn_deadline <= now()
  LOOP
    BEGIN
      PERFORM public.chess_tick(g_id);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
END $$;
GRANT EXECUTE ON FUNCTION public.chess_tick_all() TO service_role;

DO $$
DECLARE j bigint;
BEGIN
  SELECT jobid INTO j FROM cron.job WHERE jobname='chess_tick_all';
  IF j IS NOT NULL THEN PERFORM cron.unschedule(j); END IF;
END $$;
SELECT cron.schedule('chess_tick_all', '5 seconds', $$SELECT public.chess_tick_all();$$);
