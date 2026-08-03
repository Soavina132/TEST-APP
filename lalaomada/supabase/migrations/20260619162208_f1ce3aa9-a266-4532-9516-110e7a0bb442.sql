
-- ============= 1) Admin-disable games =============
ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS games_disabled jsonb NOT NULL DEFAULT '[]'::jsonb;

CREATE OR REPLACE FUNCTION public.is_game_disabled(_slug text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(
    (SELECT (games_disabled) ? _slug FROM public.app_settings WHERE id = 1),
    false);
$$;
GRANT EXECUTE ON FUNCTION public.is_game_disabled(text) TO authenticated, anon;

-- ============= 2) Chess: shrink the draw delay =============
CREATE OR REPLACE FUNCTION public.chess_draw_finalize(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_g public.chess_games%ROWTYPE; v_starter uuid; v_other uuid; _cfg record;
BEGIN
  SELECT * INTO v_g FROM public.chess_games WHERE id=_game_id FOR UPDATE;
  IF v_g.id IS NULL OR v_g.status <> 'drawing' OR v_g.draw_result_color IS NULL THEN RETURN; END IF;
  IF now() < v_g.draw_revealed_at + interval '1 second' THEN RETURN; END IF;

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

-- ============= 3) Fanorona: add draw phase =============
ALTER TABLE public.fanorona_games
  ADD COLUMN IF NOT EXISTS draw_white_by uuid,
  ADD COLUMN IF NOT EXISTS draw_black_by uuid,
  ADD COLUMN IF NOT EXISTS draw_result_color text,
  ADD COLUMN IF NOT EXISTS draw_revealed_at timestamptz,
  ADD COLUMN IF NOT EXISTS draw_spun_by uuid;

-- When both players ready, switch to 'drawing' instead of 'playing' directly
CREATE OR REPLACE FUNCTION public.fanorona_set_ready(_game_id uuid, _ready boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_total int; v_ready int; v_status text;
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
    UPDATE public.fanorona_games
       SET status = 'drawing',
           draw_white_by = NULL, draw_black_by = NULL,
           draw_result_color = NULL, draw_revealed_at = NULL, draw_spun_by = NULL
     WHERE id = _game_id AND status = 'open';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.fanorona_draw_pick_color(_game_id uuid, _color text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_g public.fanorona_games%ROWTYPE;
        v_other uuid; v_is_player boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _color NOT IN ('w','b') THEN RAISE EXCEPTION 'invalid color'; END IF;
  SELECT * INTO v_g FROM public.fanorona_games WHERE id=_game_id FOR UPDATE;
  IF v_g.id IS NULL OR v_g.status <> 'drawing' THEN RAISE EXCEPTION 'not drawing'; END IF;
  SELECT EXISTS(SELECT 1 FROM public.fanorona_participants WHERE game_id=_game_id AND user_id=v_uid) INTO v_is_player;
  IF NOT v_is_player THEN RAISE EXCEPTION 'not a player'; END IF;
  IF v_g.draw_result_color IS NOT NULL THEN RETURN; END IF;
  IF v_g.draw_white_by = v_uid OR v_g.draw_black_by = v_uid THEN RETURN; END IF;

  SELECT user_id INTO v_other FROM public.fanorona_participants
    WHERE game_id=_game_id AND user_id <> v_uid LIMIT 1;

  IF _color = 'w' THEN
    IF v_g.draw_white_by IS NOT NULL THEN RAISE EXCEPTION 'color taken'; END IF;
    UPDATE public.fanorona_games
       SET draw_white_by = v_uid,
           draw_black_by = COALESCE(draw_black_by, v_other)
     WHERE id=_game_id;
  ELSE
    IF v_g.draw_black_by IS NOT NULL THEN RAISE EXCEPTION 'color taken'; END IF;
    UPDATE public.fanorona_games
       SET draw_black_by = v_uid,
           draw_white_by = COALESCE(draw_white_by, v_other)
     WHERE id=_game_id;
  END IF;
END; $$;
GRANT EXECUTE ON FUNCTION public.fanorona_draw_pick_color(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.fanorona_draw_spin(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_g public.fanorona_games%ROWTYPE; v_color text; v_is_player boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM public.fanorona_games WHERE id=_game_id FOR UPDATE;
  IF v_g.id IS NULL OR v_g.status <> 'drawing' THEN RETURN; END IF;
  SELECT EXISTS(SELECT 1 FROM public.fanorona_participants WHERE game_id=_game_id AND user_id=v_uid) INTO v_is_player;
  IF NOT v_is_player THEN RAISE EXCEPTION 'not a player'; END IF;
  IF v_g.draw_white_by IS NULL OR v_g.draw_black_by IS NULL THEN RAISE EXCEPTION 'colors not chosen yet'; END IF;
  IF v_g.draw_result_color IS NOT NULL THEN RETURN; END IF;
  v_color := CASE WHEN random() < 0.5 THEN 'w' ELSE 'b' END;
  UPDATE public.fanorona_games
     SET draw_result_color = v_color,
         draw_revealed_at = now(),
         draw_spun_by = v_uid
   WHERE id=_game_id AND draw_result_color IS NULL;
END; $$;
GRANT EXECUTE ON FUNCTION public.fanorona_draw_spin(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.fanorona_draw_finalize(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_g public.fanorona_games%ROWTYPE; v_starter uuid; v_other uuid;
BEGIN
  SELECT * INTO v_g FROM public.fanorona_games WHERE id=_game_id FOR UPDATE;
  IF v_g.id IS NULL OR v_g.status <> 'drawing' OR v_g.draw_result_color IS NULL THEN RETURN; END IF;
  IF now() < v_g.draw_revealed_at + interval '1 second' THEN RETURN; END IF;

  v_starter := CASE WHEN v_g.draw_result_color = 'w' THEN v_g.draw_white_by ELSE v_g.draw_black_by END;
  SELECT user_id INTO v_other FROM public.fanorona_participants
    WHERE game_id=_game_id AND user_id <> v_starter LIMIT 1;

  -- Assign colors and slots: starter -> slot 0 / white
  UPDATE public.fanorona_participants SET slot = 0, color = 'white'
    WHERE game_id=_game_id AND user_id = v_starter;
  UPDATE public.fanorona_participants SET slot = 1, color = 'black'
    WHERE game_id=_game_id AND user_id = v_other;

  UPDATE public.fanorona_games
     SET status = 'playing',
         started_at = now(),
         current_turn = 0,
         state = jsonb_set(state, '{phase}', '"playing"'::jsonb)
   WHERE id=_game_id AND status='drawing';
END; $$;
GRANT EXECUTE ON FUNCTION public.fanorona_draw_finalize(uuid) TO authenticated;
