
-- Skip draw phase: when all players ready, start the game immediately with random color assignment.

CREATE OR REPLACE FUNCTION public.chess_set_ready(_game_id uuid, _ready boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_g public.chess_games%ROWTYPE; _cfg record;
        v_w uuid; v_b uuid; v_swap boolean;
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
    SELECT * INTO _cfg FROM public._game_cfg('chess');
    -- random 50/50 swap
    v_swap := (get_byte(gen_random_bytes(1),0) % 2) = 1;
    IF v_swap THEN
      v_w := v_g.black_id; v_b := v_g.white_id;
    ELSE
      v_w := v_g.white_id; v_b := v_g.black_id;
    END IF;
    UPDATE public.chess_games
       SET status='playing',
           white_id = v_w,
           black_id = v_b,
           started_at = now(),
           turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval
     WHERE id=_game_id AND status='open';
  END IF;
END; $$;

CREATE OR REPLACE FUNCTION public.fanorona_set_ready(_game_id uuid, _ready boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_total int; v_ready int; v_status text;
        v_starter uuid; v_other uuid; v_swap boolean;
        v_p1 uuid; v_p2 uuid;
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
    IF v_swap THEN v_starter := v_p2; v_other := v_p1;
    ELSE v_starter := v_p1; v_other := v_p2; END IF;

    UPDATE public.fanorona_participants SET slot = 0, color = 'white'
      WHERE game_id=_game_id AND user_id = v_starter;
    UPDATE public.fanorona_participants SET slot = 1, color = 'black'
      WHERE game_id=_game_id AND user_id = v_other;

    UPDATE public.fanorona_games
       SET status = 'playing',
           started_at = now(),
           current_turn = 0,
           state = jsonb_set(state, '{phase}', '"playing"'::jsonb)
     WHERE id = _game_id AND status = 'open';
  END IF;
END $$;
