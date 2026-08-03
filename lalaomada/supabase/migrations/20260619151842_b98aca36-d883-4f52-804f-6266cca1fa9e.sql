
-- Add per-color picker columns + result color
ALTER TABLE public.chess_games
  ADD COLUMN IF NOT EXISTS draw_white_by uuid,
  ADD COLUMN IF NOT EXISTS draw_black_by uuid,
  ADD COLUMN IF NOT EXISTS draw_result_color text,
  ADD COLUMN IF NOT EXISTS draw_spun_by uuid;

-- Reset draw fields when entering 'drawing'
CREATE OR REPLACE FUNCTION public.chess_set_ready(_game_id uuid, _ready boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_g public.chess_games%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM public.chess_games WHERE id = _game_id FOR UPDATE;
  IF v_g.id IS NULL THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status <> 'open' THEN RETURN; END IF;
  IF v_uid = v_g.white_id THEN
    UPDATE public.chess_games SET ready_white = COALESCE(_ready,false) WHERE id=_game_id;
  ELSIF v_uid = v_g.black_id THEN
    UPDATE public.chess_games SET ready_black = COALESCE(_ready,false) WHERE id=_game_id;
  ELSE RAISE EXCEPTION 'not a player'; END IF;

  SELECT * INTO v_g FROM public.chess_games WHERE id=_game_id;
  IF v_g.white_id IS NOT NULL AND v_g.black_id IS NOT NULL AND v_g.ready_white AND v_g.ready_black THEN
    UPDATE public.chess_games
       SET status='drawing',
           draw_white_by=NULL, draw_black_by=NULL,
           draw_result_color=NULL, draw_revealed_at=NULL, draw_spun_by=NULL,
           draw_pick_value=NULL, draw_result=NULL, draw_picker_id=NULL
     WHERE id=_game_id AND status='open';
  END IF;
END; $$;
GRANT EXECUTE ON FUNCTION public.chess_set_ready(uuid,boolean) TO authenticated;

-- Each player picks a color ('w' or 'b'). First pick auto-assigns the opposite to the other player.
CREATE OR REPLACE FUNCTION public.chess_draw_pick_color(_game_id uuid, _color text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_g public.chess_games%ROWTYPE; v_other uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _color NOT IN ('w','b') THEN RAISE EXCEPTION 'invalid color'; END IF;
  SELECT * INTO v_g FROM public.chess_games WHERE id=_game_id FOR UPDATE;
  IF v_g.id IS NULL OR v_g.status <> 'drawing' THEN RAISE EXCEPTION 'not drawing'; END IF;
  IF v_uid <> v_g.white_id AND v_uid <> v_g.black_id THEN RAISE EXCEPTION 'not a player'; END IF;
  IF v_g.draw_result_color IS NOT NULL THEN RETURN; END IF;
  -- already picked
  IF v_g.draw_white_by = v_uid OR v_g.draw_black_by = v_uid THEN RETURN; END IF;

  v_other := CASE WHEN v_uid = v_g.white_id THEN v_g.black_id ELSE v_g.white_id END;

  IF _color = 'w' THEN
    IF v_g.draw_white_by IS NOT NULL THEN RAISE EXCEPTION 'color taken'; END IF;
    UPDATE public.chess_games
       SET draw_white_by = v_uid,
           draw_black_by = COALESCE(draw_black_by, v_other)
     WHERE id=_game_id;
  ELSE
    IF v_g.draw_black_by IS NOT NULL THEN RAISE EXCEPTION 'color taken'; END IF;
    UPDATE public.chess_games
       SET draw_black_by = v_uid,
           draw_white_by = COALESCE(draw_white_by, v_other)
     WHERE id=_game_id;
  END IF;
END; $$;
GRANT EXECUTE ON FUNCTION public.chess_draw_pick_color(uuid,text) TO authenticated;

-- Spin the box: server rolls the color result. Both colors must be assigned.
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
  v_color := CASE WHEN random() < 0.5 THEN 'w' ELSE 'b' END;
  UPDATE public.chess_games
     SET draw_result_color = v_color,
         draw_revealed_at = now(),
         draw_spun_by = v_uid
   WHERE id=_game_id AND draw_result_color IS NULL;
END; $$;
GRANT EXECUTE ON FUNCTION public.chess_draw_spin(uuid) TO authenticated;

-- Finalize: the player whose chosen color matches the drawn ball plays WHITE (starts).
CREATE OR REPLACE FUNCTION public.chess_draw_finalize(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_g public.chess_games%ROWTYPE; v_starter uuid; v_other uuid; _cfg record;
BEGIN
  SELECT * INTO v_g FROM public.chess_games WHERE id=_game_id FOR UPDATE;
  IF v_g.id IS NULL OR v_g.status <> 'drawing' OR v_g.draw_result_color IS NULL THEN RETURN; END IF;
  IF now() < v_g.draw_revealed_at + interval '3 seconds' THEN RETURN; END IF;

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
GRANT EXECUTE ON FUNCTION public.chess_draw_finalize(uuid) TO authenticated;
