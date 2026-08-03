
ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS chess_global_timer_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS chess_global_timer_minutes integer NOT NULL DEFAULT 10,
  ADD COLUMN IF NOT EXISTS fanorona_global_timer_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS fanorona_global_timer_minutes integer NOT NULL DEFAULT 10;

ALTER TABLE public.chess_games ADD COLUMN IF NOT EXISTS game_deadline timestamptz;
ALTER TABLE public.fanorona_games ADD COLUMN IF NOT EXISTS game_deadline timestamptz;

CREATE OR REPLACE FUNCTION public.chess_check_global_timeout(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  g public.chess_games%ROWTYPE;
  loser uuid;
  winner uuid;
BEGIN
  SELECT * INTO g FROM public.chess_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND OR g.status <> 'playing' OR g.game_deadline IS NULL THEN RETURN; END IF;
  IF now() < g.game_deadline THEN RETURN; END IF;

  IF g.turn = 'w' THEN
    loser := g.white_id; winner := g.black_id;
  ELSE
    loser := g.black_id; winner := g.white_id;
  END IF;

  UPDATE public.chess_games
     SET status = 'finished', winner_id = winner, finished_at = now()
   WHERE id = _game_id;

  IF winner IS NOT NULL AND g.pot > 0 THEN
    UPDATE public.profiles SET balance = COALESCE(balance,0) + g.pot WHERE user_id = winner;
    INSERT INTO public.transactions(user_id, kind, amount, meta)
      VALUES (winner, 'game_win', g.pot, jsonb_build_object('game','chess','game_id',_game_id,'reason','global_timeout'));
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.chess_check_global_timeout(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fanorona_check_global_timeout(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  g public.fanorona_games%ROWTYPE;
  loser_slot int;
  loser_user uuid;
  winner_user uuid;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND OR g.status <> 'playing' OR g.game_deadline IS NULL THEN RETURN; END IF;
  IF now() < g.game_deadline THEN RETURN; END IF;

  loser_slot := g.current_turn;
  SELECT user_id INTO loser_user FROM public.fanorona_participants WHERE game_id = _game_id AND slot = loser_slot;
  SELECT user_id INTO winner_user FROM public.fanorona_participants WHERE game_id = _game_id AND slot <> loser_slot LIMIT 1;

  UPDATE public.fanorona_games
     SET status = 'finished', winner_id = winner_user, finished_at = now()
   WHERE id = _game_id;

  IF winner_user IS NOT NULL AND g.pot > 0 THEN
    UPDATE public.profiles SET balance = COALESCE(balance,0) + g.pot WHERE user_id = winner_user;
    INSERT INTO public.transactions(user_id, kind, amount, meta)
      VALUES (winner_user, 'game_win', g.pot, jsonb_build_object('game','fanorona','game_id',_game_id,'reason','global_timeout'));
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fanorona_check_global_timeout(uuid) TO authenticated, service_role;
