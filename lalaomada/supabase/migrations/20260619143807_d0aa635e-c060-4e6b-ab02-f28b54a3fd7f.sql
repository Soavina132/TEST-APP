
-- Add 'drawing' to game_status enum if missing
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON e.enumtypid=t.oid WHERE t.typname='game_status' AND e.enumlabel='drawing') THEN
    ALTER TYPE public.game_status ADD VALUE 'drawing';
  END IF;
END $$;

ALTER TABLE public.chess_games
  ADD COLUMN IF NOT EXISTS draw_pick_value int,
  ADD COLUMN IF NOT EXISTS draw_result int,
  ADD COLUMN IF NOT EXISTS draw_picker_id uuid,
  ADD COLUMN IF NOT EXISTS draw_revealed_at timestamptz;

-- Override chess_set_ready: when both ready, enter 'drawing' phase instead of 'playing'
CREATE OR REPLACE FUNCTION public.chess_set_ready(_game_id uuid, _ready boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_g public.chess_games%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM public.chess_games WHERE id = _game_id FOR UPDATE;
  IF v_g.id IS NULL THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status <> 'open' THEN RETURN; END IF;

  IF v_uid = v_g.white_id THEN
    UPDATE public.chess_games SET ready_white = COALESCE(_ready,false) WHERE id=_game_id;
  ELSIF v_uid = v_g.black_id THEN
    UPDATE public.chess_games SET ready_black = COALESCE(_ready,false) WHERE id=_game_id;
  ELSE
    RAISE EXCEPTION 'not a player';
  END IF;

  SELECT * INTO v_g FROM public.chess_games WHERE id=_game_id;
  IF v_g.white_id IS NOT NULL AND v_g.black_id IS NOT NULL AND v_g.ready_white AND v_g.ready_black THEN
    UPDATE public.chess_games
       SET status = 'drawing',
           draw_pick_value = NULL,
           draw_result = NULL,
           draw_picker_id = NULL,
           draw_revealed_at = NULL
     WHERE id = _game_id AND status='open';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.chess_set_ready(uuid, boolean) TO authenticated;

-- The guest picks 1 or 2; a random result is rolled, colors swapped if needed
CREATE OR REPLACE FUNCTION public.chess_draw_pick(_game_id uuid, _value int)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_g public.chess_games%ROWTYPE;
  v_result int;
  v_tmp uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _value NOT IN (1,2) THEN RAISE EXCEPTION 'invalid value'; END IF;

  SELECT * INTO v_g FROM public.chess_games WHERE id=_game_id FOR UPDATE;
  IF v_g.id IS NULL THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status <> 'drawing' THEN RAISE EXCEPTION 'not drawing phase'; END IF;
  IF v_g.draw_result IS NOT NULL THEN RETURN; END IF;
  IF v_uid <> v_g.white_id AND v_uid <> v_g.black_id THEN RAISE EXCEPTION 'not a player'; END IF;

  v_result := 1 + floor(random()*2)::int;

  -- If picker won: picker becomes white (starts). Otherwise other player is white.
  -- Currently white_id is the host. Swap if needed.
  IF v_result = _value THEN
    -- picker should be white
    IF v_uid <> v_g.white_id THEN
      v_tmp := v_g.white_id;
      UPDATE public.chess_games SET white_id = v_uid, black_id = v_tmp WHERE id=_game_id;
    END IF;
  ELSE
    -- other player should be white
    IF v_uid = v_g.white_id THEN
      v_tmp := v_g.black_id;
      UPDATE public.chess_games SET white_id = v_tmp, black_id = v_uid WHERE id=_game_id;
    END IF;
  END IF;

  UPDATE public.chess_games
     SET draw_pick_value = _value,
         draw_result = v_result,
         draw_picker_id = v_uid,
         draw_revealed_at = now()
   WHERE id=_game_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.chess_draw_pick(uuid, int) TO authenticated;

CREATE OR REPLACE FUNCTION public.chess_draw_finalize(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_g public.chess_games%ROWTYPE;
  _cfg record;
BEGIN
  SELECT * INTO v_g FROM public.chess_games WHERE id=_game_id FOR UPDATE;
  IF v_g.id IS NULL OR v_g.status <> 'drawing' OR v_g.draw_result IS NULL THEN RETURN; END IF;
  IF now() < v_g.draw_revealed_at + interval '2 seconds' THEN RETURN; END IF;
  SELECT * INTO _cfg FROM public._game_cfg('chess');
  UPDATE public.chess_games
     SET status='playing',
         started_at = now(),
         turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval
   WHERE id=_game_id AND status='drawing';
END;
$$;

GRANT EXECUTE ON FUNCTION public.chess_draw_finalize(uuid) TO authenticated;
