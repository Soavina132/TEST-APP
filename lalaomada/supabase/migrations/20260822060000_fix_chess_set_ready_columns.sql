-- Fix: chess_set_ready utilisait white_ready/black_ready au lieu de ready_white/ready_black
-- Erreur: column "white_ready" of relation "chess_games" does not exist
-- Survenait quand le swap de couleurs était déclenché (50% des parties)

CREATE OR REPLACE FUNCTION public.chess_set_ready(_game_id uuid, _ready boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_g public.chess_games%ROWTYPE;
  v_cfg record;
  v_time_ms int;
  v_swap boolean;
  v_w uuid; v_b uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM public.chess_games WHERE id = _game_id FOR UPDATE;
  IF v_g.id IS NULL THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status <> 'open' THEN RETURN; END IF;

  IF v_uid = v_g.white_id THEN
    UPDATE public.chess_games SET ready_white = COALESCE(_ready, false) WHERE id = _game_id;
  ELSIF v_uid = v_g.black_id THEN
    UPDATE public.chess_games SET ready_black = COALESCE(_ready, false) WHERE id = _game_id;
  ELSE
    RAISE EXCEPTION 'not a player';
  END IF;

  SELECT * INTO v_g FROM public.chess_games WHERE id = _game_id;
  IF v_g.white_id IS NOT NULL AND v_g.black_id IS NOT NULL AND v_g.ready_white AND v_g.ready_black THEN
    -- Randomiser les couleurs: 50% de chance de swap
    v_swap := (get_byte(extensions.gen_random_bytes(1),0) % 2) = 1;
    IF v_swap THEN
      v_w := v_g.black_id; v_b := v_g.white_id;
      UPDATE public.chess_games
        SET white_id = v_w, black_id = v_b,
            ready_white = ready_black, ready_black = ready_white
        WHERE id = _game_id;
    END IF;

    SELECT * INTO v_cfg FROM public._game_cfg('chess');
    v_time_ms := COALESCE(v_g.time_control_min, 10) * 60 * 1000;
    UPDATE public.chess_games
       SET status = 'playing',
           started_at = now(),
           last_move_at = now(),
           white_time_ms = v_time_ms,
           black_time_ms = v_time_ms,
           turn_deadline = now() + (COALESCE(v_cfg.turn_timer_seconds, 60) || ' seconds')::interval
     WHERE id = _game_id AND status = 'open';
  END IF;
END $$;
