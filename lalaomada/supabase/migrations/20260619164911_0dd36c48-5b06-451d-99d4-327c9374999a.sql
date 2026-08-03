-- Remove time guard on draw finalize so auto-start fires reliably,
-- and strengthen the random color draw using gen_random_bytes.

-- ===== CHESS =====
CREATE OR REPLACE FUNCTION public.chess_draw_spin(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_g public.chess_games%ROWTYPE; v_color text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM public.chess_games WHERE id=_game_id FOR UPDATE;
  IF v_g.id IS NULL OR v_g.status <> 'drawing' THEN RETURN; END IF;
  IF v_uid <> v_g.white_id AND v_uid <> v_g.black_id THEN RAISE EXCEPTION 'not a player'; END IF;
  IF v_g.draw_white_by IS NULL OR v_g.draw_black_by IS NULL THEN RAISE EXCEPTION 'colors not chosen yet'; END IF;
  IF v_g.draw_result_color IS NOT NULL THEN RETURN; END IF;
  -- Cryptographically random 50/50
  v_color := CASE WHEN (get_byte(gen_random_bytes(1),0) % 2) = 0 THEN 'w' ELSE 'b' END;
  UPDATE public.chess_games
     SET draw_result_color = v_color,
         draw_revealed_at = now(),
         draw_spun_by = v_uid
   WHERE id=_game_id AND draw_result_color IS NULL;
END; $$;

CREATE OR REPLACE FUNCTION public.chess_draw_finalize(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_g public.chess_games%ROWTYPE; v_starter uuid; v_other uuid; _cfg record;
BEGIN
  SELECT * INTO v_g FROM public.chess_games WHERE id=_game_id FOR UPDATE;
  IF v_g.id IS NULL OR v_g.status <> 'drawing' OR v_g.draw_result_color IS NULL THEN RETURN; END IF;
  -- NO time guard: client controls the visual delay; server fires immediately.

  v_starter := CASE WHEN v_g.draw_result_color = 'w' THEN v_g.draw_white_by ELSE v_g.draw_black_by END;
  v_other   := CASE WHEN v_starter = v_g.white_id THEN v_g.black_id ELSE v_g.white_id END;

  SELECT * INTO _cfg FROM public._game_cfg('chess');
  UPDATE public.chess_games
     SET status='playing',
         white_id = v_starter,
         black_id = v_other,
         started_at = now(),
         turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval
   WHERE id=_game_id AND status='drawing';
END; $$;

-- ===== FANORONA =====
CREATE OR REPLACE FUNCTION public.fanorona_draw_spin(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_g public.fanorona_games%ROWTYPE; v_color text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM public.fanorona_games WHERE id=_game_id FOR UPDATE;
  IF v_g.id IS NULL OR v_g.status <> 'drawing' THEN RETURN; END IF;
  IF v_g.draw_white_by IS NULL OR v_g.draw_black_by IS NULL THEN RAISE EXCEPTION 'colors not chosen yet'; END IF;
  IF v_g.draw_result_color IS NOT NULL THEN RETURN; END IF;
  v_color := CASE WHEN (get_byte(gen_random_bytes(1),0) % 2) = 0 THEN 'w' ELSE 'b' END;
  UPDATE public.fanorona_games
     SET draw_result_color = v_color,
         draw_revealed_at = now(),
         draw_spun_by = v_uid
   WHERE id=_game_id AND draw_result_color IS NULL;
END; $$;

CREATE OR REPLACE FUNCTION public.fanorona_draw_finalize(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_g public.fanorona_games%ROWTYPE; v_starter uuid; v_other uuid; _cfg record;
        v_p0 uuid; v_p1 uuid;
BEGIN
  SELECT * INTO v_g FROM public.fanorona_games WHERE id=_game_id FOR UPDATE;
  IF v_g.id IS NULL OR v_g.status <> 'drawing' OR v_g.draw_result_color IS NULL THEN RETURN; END IF;
  -- NO time guard

  v_starter := CASE WHEN v_g.draw_result_color = 'w' THEN v_g.draw_white_by ELSE v_g.draw_black_by END;

  -- Assign slots: starter -> slot 0 (white), other -> slot 1 (black)
  SELECT user_id INTO v_p0 FROM public.fanorona_participants WHERE game_id=_game_id AND user_id = v_starter LIMIT 1;
  SELECT user_id INTO v_p1 FROM public.fanorona_participants WHERE game_id=_game_id AND user_id <> v_starter LIMIT 1;

  UPDATE public.fanorona_participants SET slot = 0, color = 'w' WHERE game_id=_game_id AND user_id = v_p0;
  UPDATE public.fanorona_participants SET slot = 1, color = 'b' WHERE game_id=_game_id AND user_id = v_p1;

  SELECT * INTO _cfg FROM public._game_cfg('fanorona');
  UPDATE public.fanorona_games
     SET status='playing',
         turn = 0,
         started_at = now(),
         turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval
   WHERE id=_game_id AND status='drawing';
END; $$;