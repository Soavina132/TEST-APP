
-- 1) Fix duplicate-key in fanorona_set_ready by reassigning slots atomically
CREATE OR REPLACE FUNCTION public.fanorona_set_ready(_game_id uuid, _ready boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_total int; v_ready int; v_status text;
        v_starter uuid; v_p1 uuid; v_p2 uuid; v_swap boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  UPDATE public.fanorona_participants SET ready = COALESCE(_ready, false)
    WHERE game_id = _game_id AND user_id = v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'not a participant'; END IF;
  SELECT status INTO v_status FROM public.fanorona_games WHERE id = _game_id;
  IF v_status <> 'open' THEN RETURN; END IF;
  SELECT count(*), count(*) FILTER (WHERE ready) INTO v_total, v_ready
    FROM public.fanorona_participants WHERE game_id = _game_id;
  IF v_total = 2 AND v_ready = 2 THEN
    SELECT user_id INTO v_p1 FROM public.fanorona_participants WHERE game_id=_game_id ORDER BY joined_at LIMIT 1;
    SELECT user_id INTO v_p2 FROM public.fanorona_participants WHERE game_id=_game_id AND user_id <> v_p1 LIMIT 1;
    v_swap := (get_byte(gen_random_bytes(1),0) % 2) = 1;
    v_starter := CASE WHEN v_swap THEN v_p2 ELSE v_p1 END;
    -- Single atomic UPDATE: unique (game_id, slot) is checked at statement end,
    -- so swapping slots in one statement avoids the duplicate-key error.
    UPDATE public.fanorona_participants
       SET slot  = CASE WHEN user_id = v_starter THEN 0 ELSE 1 END,
           color = CASE WHEN user_id = v_starter THEN 'white' ELSE 'black' END
     WHERE game_id = _game_id;

    UPDATE public.fanorona_games
       SET status = 'playing', started_at = now(), current_turn = 0,
           state = jsonb_set(state, '{phase}', '"playing"'::jsonb),
           turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')),60) || ' seconds')::interval
     WHERE id = _game_id AND status = 'open';
  END IF;
END $$;

-- 2) Online count = members of the global "Groupe X" discussion room
CREATE OR REPLACE FUNCTION public.game_online_count(_slug text)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COUNT(DISTINCT cm.user_id)::int
  FROM public.chat_members cm
  JOIN public.chat_rooms cr ON cr.id = cm.room_id
  WHERE cr.type = 'global' AND cr.name = CASE _slug
    WHEN 'ludo' THEN 'Groupe Ludo'
    WHEN 'domino' THEN 'Groupe Domino'
    WHEN 'fanorona' THEN 'Groupe Fanorona'
    WHEN 'chess' THEN 'Groupe Échec'
    WHEN 'rami' THEN 'Groupe Rami'
    ELSE '' END;
$$;
GRANT EXECUTE ON FUNCTION public.game_online_count(text) TO authenticated, anon;

-- 3) Auto-cancel open games older than 3 minutes (refund stakes) — for every game type
CREATE OR REPLACE FUNCTION public._auto_cancel_open_games()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record;
BEGIN
  -- Fanorona
  FOR r IN SELECT id, stake FROM public.fanorona_games
           WHERE status='open' AND created_at < now() - interval '3 minutes'
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      FROM public.fanorona_participants pp
      WHERE pp.game_id = r.id AND pp.user_id = p.id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT user_id, 'fanorona_refund', r.stake, r.id, 'Auto-cancelled (3 min)'
      FROM public.fanorona_participants WHERE game_id = r.id;
    UPDATE public.fanorona_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;

  -- Chess
  FOR r IN SELECT id, stake FROM public.chess_games
           WHERE status='open' AND created_at < now() - interval '3 minutes'
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      WHERE p.id IN (SELECT host_id FROM public.chess_games WHERE id=r.id);
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT host_id, 'chess_refund', r.stake, r.id, 'Auto-cancelled (3 min)'
      FROM public.chess_games WHERE id=r.id;
    UPDATE public.chess_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;

  -- Domino
  FOR r IN SELECT id, stake FROM public.domino_games
           WHERE status='open' AND created_at < now() - interval '3 minutes'
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      FROM public.domino_participants pp
      WHERE pp.game_id = r.id AND pp.user_id = p.id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT user_id, 'domino_refund', r.stake, r.id, 'Auto-cancelled (3 min)'
      FROM public.domino_participants WHERE game_id = r.id;
    UPDATE public.domino_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;

  -- Rami
  FOR r IN SELECT id, stake FROM public.rami_games
           WHERE status='waiting' AND created_at < now() - interval '3 minutes'
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      FROM public.rami_participants pp
      WHERE pp.game_id = r.id AND pp.user_id = p.id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT user_id, 'rami_refund', r.stake, r.id, 'Auto-cancelled (3 min)'
      FROM public.rami_participants WHERE game_id = r.id;
    UPDATE public.rami_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;

  -- Ludo
  FOR r IN SELECT id, stake FROM public.ludo_games
           WHERE status='open' AND created_at < now() - interval '3 minutes'
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      FROM public.ludo_participants pp
      WHERE pp.game_id = r.id AND pp.user_id = p.id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT user_id, 'ludo_refund', r.stake, r.id, 'Auto-cancelled (3 min)'
      FROM public.ludo_participants WHERE game_id = r.id;
    UPDATE public.ludo_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;
END $$;

-- 4) Server-side turn ticker: advances overdue turns automatically
CREATE OR REPLACE FUNCTION public._auto_advance_overdue_turns()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record;
BEGIN
  FOR r IN SELECT id FROM public.fanorona_games
           WHERE status='playing' AND turn_deadline IS NOT NULL AND turn_deadline < now()
  LOOP PERFORM public.fanorona_tick(r.id); END LOOP;

  FOR r IN SELECT id FROM public.chess_games
           WHERE status='playing' AND turn_deadline IS NOT NULL AND turn_deadline < now()
  LOOP PERFORM public.chess_tick(r.id); END LOOP;

  FOR r IN SELECT id FROM public.domino_games
           WHERE status='playing' AND turn_deadline IS NOT NULL AND turn_deadline < now()
  LOOP PERFORM public.domino_tick(r.id); END LOOP;

  FOR r IN SELECT id FROM public.rami_games
           WHERE status='playing' AND turn_deadline IS NOT NULL AND turn_deadline < now()
  LOOP PERFORM public.rami_tick(r.id); END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.tick_all_games()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public._auto_cancel_open_games();
  PERFORM public._auto_advance_overdue_turns();
END $$;

-- 5) Schedule via pg_cron every 20 seconds (cron min granularity is 1 min;
--    use 3 jobs offset by 20s for ~20s cadence)
DO $$
BEGIN
  PERFORM cron.unschedule('tick-all-games') WHERE EXISTS(SELECT 1 FROM cron.job WHERE jobname='tick-all-games');
EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$
DECLARE j int;
BEGIN
  FOR j IN SELECT jobid FROM cron.job WHERE jobname IN ('tick-all-games','tick-all-games-20s','tick-all-games-40s') LOOP
    PERFORM cron.unschedule(j);
  END LOOP;
END $$;

SELECT cron.schedule('tick-all-games',     '* * * * *', $$SELECT public.tick_all_games();$$);
SELECT cron.schedule('tick-all-games-20s', '* * * * *', $$SELECT pg_sleep(20); SELECT public.tick_all_games();$$);
SELECT cron.schedule('tick-all-games-40s', '* * * * *', $$SELECT pg_sleep(40); SELECT public.tick_all_games();$$);
