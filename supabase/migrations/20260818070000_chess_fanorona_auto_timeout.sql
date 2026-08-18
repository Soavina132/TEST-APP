-- ════════════════════════════════════════════════════════════════════
-- Chess & Fanorona : Timeout automatique sur l'horloge cumulative
--
-- Bug Fanorona : fanorona_tick ne vérifiait QUE turn_deadline (timer par tour),
--   pas l'horloge cumulative (white_time_ms / black_time_ms).
--   Quand le client détectait wTime/bTime = 0 et appelait fanorona_tick,
--   le serveur ignorait l'appel si turn_deadline n'avait pas encore expiré.
--
-- Fix :
--   1. fanorona_tick : ajouter vérification de l'horloge cumulative
--   2. _auto_advance_overdue_turns : ajouter vérif horloge fanorona (comme chess)
--   3. chess_tick : déjà correct, juste s'assurer que chess_auto_timeout est appelé
-- ════════════════════════════════════════════════════════════════════

-- ── 1. fanorona_tick : vérifier aussi l'horloge cumulative ──────────
CREATE OR REPLACE FUNCTION public.fanorona_tick(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  g record;
  cur_uid uuid;
  v_elapsed_ms int;
  v_remaining int;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;
  IF coalesce(g.paused, false) THEN RETURN; END IF;

  -- ── A. Turn deadline expiré (timer par tour) ──
  IF g.turn_deadline IS NOT NULL AND g.turn_deadline <= now() THEN
    SELECT user_id INTO cur_uid FROM public.fanorona_participants
      WHERE game_id = _game_id AND slot = g.current_turn;
    IF cur_uid IS NOT NULL THEN
      UPDATE public.fanorona_participants SET forfeited = true
        WHERE game_id = _game_id AND user_id = cur_uid;
    END IF;
    PERFORM public._fanorona_finalize(_game_id, 1 - g.current_turn);
    RETURN;
  END IF;

  -- ── B. Horloge cumulative expirée (white_time_ms / black_time_ms) ──
  IF g.time_control_min > 0 THEN
    v_elapsed_ms := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (now() - COALESCE(g.last_move_at, g.started_at, now()))) * 1000)::int);

    IF g.current_turn = 0 THEN
      v_remaining := g.white_time_ms - v_elapsed_ms;
    ELSE
      v_remaining := g.black_time_ms - v_elapsed_ms;
    END IF;

    IF v_remaining <= 0 THEN
      -- Le joueur dont c'est le tour a écoulé son temps → il perd
      PERFORM public._fanorona_finalize(_game_id, 1 - g.current_turn);
      RETURN;
    END IF;
  END IF;

  -- ── C. Global game deadline expiré ──
  IF g.game_deadline IS NOT NULL AND g.game_deadline <= now() THEN
    PERFORM public._fanorona_finalize(_game_id, 1 - g.current_turn);
    RETURN;
  END IF;
END $function$;

-- ── 2. _auto_advance_overdue_turns : ajouter horloge fanorona ─────────
CREATE OR REPLACE FUNCTION public._auto_advance_overdue_turns()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  r record;
  v_g chess_games%ROWTYPE;
  v_fg record;
  v_elapsed_ms int;
  v_remaining int;
BEGIN
  -- Fanorona turn deadlines
  FOR r IN SELECT id FROM public.fanorona_games
           WHERE status='playing' AND paused = FALSE AND turn_deadline IS NOT NULL AND turn_deadline < now()
  LOOP PERFORM public.fanorona_tick(r.id); END LOOP;

  -- Fanorona cumulative clock timeout (white_time_ms / black_time_ms)
  -- This catches the case where a player left the page and nobody calls fanorona_tick
  FOR r IN SELECT id FROM public.fanorona_games
           WHERE status='playing'
             AND paused = FALSE
             AND time_control_min > 0
  LOOP
    SELECT * INTO v_fg FROM public.fanorona_games WHERE id = r.id FOR UPDATE;
    IF v_fg IS NULL OR v_fg.status <> 'playing' OR COALESCE(v_fg.paused, false) THEN CONTINUE; END IF;

    v_elapsed_ms := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (now() - COALESCE(v_fg.last_move_at, v_fg.started_at, now()))) * 1000)::int);

    IF v_fg.current_turn = 0 THEN
      v_remaining := v_fg.white_time_ms - v_elapsed_ms;
    ELSE
      v_remaining := v_fg.black_time_ms - v_elapsed_ms;
    END IF;

    IF v_remaining <= 0 THEN
      PERFORM public.fanorona_tick(r.id);
    END IF;
  END LOOP;

  -- Fanorona global timeout
  FOR r IN SELECT id FROM public.fanorona_games
           WHERE status='playing' AND game_deadline IS NOT NULL AND game_deadline < now()
  LOOP PERFORM public.fanorona_check_global_timeout(r.id); END LOOP;

  -- Chess turn deadlines (per-move timer)
  FOR r IN SELECT id FROM public.chess_games
           WHERE status='playing' AND paused = FALSE AND turn_deadline IS NOT NULL AND turn_deadline < now()
  LOOP PERFORM public.chess_tick(r.id); END LOOP;

  -- Chess clock timeout (white_time_ms / black_time_ms)
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
END $function$;
