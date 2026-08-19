-- ============================================================
-- FIX 1: LUDO — ludo_tick_all() n'est jamais appelée par tick_all_games()
--        → les bots ne jouent pas, les timeouts ne marchent pas
-- ============================================================

-- ═══ FIX 1: Add Ludo to _auto_advance_overdue_turns ═══
CREATE OR REPLACE FUNCTION public._auto_advance_overdue_turns()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r record;
  v_g chess_games%ROWTYPE;
  v_elapsed_ms int;
  v_remaining int;
BEGIN
  -- Fanorona turn deadlines
  FOR r IN SELECT id FROM public.fanorona_games
           WHERE status='playing' AND paused = FALSE AND turn_deadline IS NOT NULL AND turn_deadline < now()
  LOOP PERFORM public.fanorona_tick(r.id); END LOOP;

  -- Fanorona global timeout
  FOR r IN SELECT id FROM public.fanorona_games
           WHERE status='playing' AND game_deadline IS NOT NULL AND game_deadline < now()
  LOOP PERFORM public.fanorona_check_global_timeout(r.id); END LOOP;

  -- Chess turn deadlines (per-move timer)
  FOR r IN SELECT id FROM public.chess_games
           WHERE status='playing' AND paused = FALSE AND turn_deadline IS NOT NULL AND turn_deadline < now()
  LOOP PERFORM public.chess_tick(r.id); END LOOP;

  -- Chess clock timeout
  FOR r IN SELECT id FROM public.chess_games
           WHERE status='playing'
             AND paused = FALSE
             AND time_control_min > 0
  LOOP
    SELECT * INTO v_g FROM public.chess_games WHERE id = r.id FOR UPDATE;
    IF v_g.id IS NULL OR v_g.status <> 'playing' OR COALESCE(v_g.paused, false) THEN CONTINUE; END IF;

    v_elapsed_ms := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (now() - COALESCE(v_g.last_move_at, v_g.started_at, now()))) * 1000)::int);

    IF v_g.turn = 'w' THEN
      v_remaining := v_g.white_time_ms - v_elapsed_ms;
    ELSE
      v_remaining := v_g.black_time_ms - v_elapsed_ms;
    END IF;

    IF v_remaining <= 0 THEN
      PERFORM public.chess_auto_timeout(r.id);
    END IF;
  END LOOP;

  -- Chess global game deadline
  FOR r IN SELECT id FROM public.chess_games
           WHERE status='playing' AND game_deadline IS NOT NULL AND game_deadline < now()
  LOOP PERFORM public.chess_check_global_timeout(r.id); END LOOP;

  -- Domino turn deadlines
  FOR r IN SELECT id FROM public.domino_games
           WHERE status='playing' AND paused = FALSE AND turn_deadline IS NOT NULL AND turn_deadline < now()
  LOOP PERFORM public.domino_tick(r.id); END LOOP;

  -- Rami turn deadlines
  FOR r IN SELECT id FROM public.rami_games
           WHERE status='playing' AND paused = FALSE AND turn_deadline IS NOT NULL AND turn_deadline < now()
  LOOP PERFORM public.rami_tick(r.id); END LOOP;

  -- LUDO: bot play + timeout + auto-move + stalemate detection
  -- This was MISSING — ludo_tick_all() was never called!
  PERFORM public.ludo_tick_all();
END $$;

GRANT EXECUTE ON FUNCTION public._auto_advance_overdue_turns() TO authenticated, anon, service_role;
