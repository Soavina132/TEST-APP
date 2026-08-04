-- Global game timer for domino, rami, and poker
-- Follows the same pattern as chess/fanorona (migration 20260621063616)

-- 1) app_settings columns
ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS domino_global_timer_enabled  boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS domino_global_timer_minutes  integer NOT NULL DEFAULT 10,
  ADD COLUMN IF NOT EXISTS rami_global_timer_enabled     boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS rami_global_timer_minutes     integer NOT NULL DEFAULT 10,
  ADD COLUMN IF NOT EXISTS poker_global_timer_enabled    boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS poker_global_timer_minutes    integer NOT NULL DEFAULT 10;

-- 2) game_deadline column on each game table
ALTER TABLE public.domino_games ADD COLUMN IF NOT EXISTS game_deadline timestamptz;
ALTER TABLE public.rami_games   ADD COLUMN IF NOT EXISTS game_deadline timestamptz;
ALTER TABLE public.poker_games  ADD COLUMN IF NOT EXISTS game_deadline timestamptz;

-- 3) Trigger functions
CREATE OR REPLACE FUNCTION public._set_domino_global_deadline()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE enabled boolean; mins integer;
BEGIN
  IF NEW.status = 'playing' AND (OLD.status IS DISTINCT FROM 'playing') AND NEW.game_deadline IS NULL THEN
    SELECT domino_global_timer_enabled, domino_global_timer_minutes INTO enabled, mins FROM public.app_settings WHERE id = 1;
    IF COALESCE(enabled, false) AND COALESCE(mins, 0) > 0 THEN
      NEW.game_deadline := now() + (mins || ' minutes')::interval;
    END IF;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_domino_global_deadline ON public.domino_games;
CREATE TRIGGER trg_domino_global_deadline BEFORE UPDATE ON public.domino_games
  FOR EACH ROW EXECUTE FUNCTION public._set_domino_global_deadline();

CREATE OR REPLACE FUNCTION public._set_rami_global_deadline()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE enabled boolean; mins integer;
BEGIN
  IF NEW.status = 'playing' AND (OLD.status IS DISTINCT FROM 'playing') AND NEW.game_deadline IS NULL THEN
    SELECT rami_global_timer_enabled, rami_global_timer_minutes INTO enabled, mins FROM public.app_settings WHERE id = 1;
    IF COALESCE(enabled, false) AND COALESCE(mins, 0) > 0 THEN
      NEW.game_deadline := now() + (mins || ' minutes')::interval;
    END IF;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_rami_global_deadline ON public.rami_games;
CREATE TRIGGER trg_rami_global_deadline BEFORE UPDATE ON public.rami_games
  FOR EACH ROW EXECUTE FUNCTION public._set_rami_global_deadline();

CREATE OR REPLACE FUNCTION public._set_poker_global_deadline()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE enabled boolean; mins integer;
BEGIN
  IF NEW.status = 'playing' AND (OLD.status IS DISTINCT FROM 'playing') AND NEW.game_deadline IS NULL THEN
    SELECT poker_global_timer_enabled, poker_global_timer_minutes INTO enabled, mins FROM public.app_settings WHERE id = 1;
    IF COALESCE(enabled, false) AND COALESCE(mins, 0) > 0 THEN
      NEW.game_deadline := now() + (mins || ' minutes')::interval;
    END IF;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_poker_global_deadline ON public.poker_games;
CREATE TRIGGER trg_poker_global_deadline BEFORE UPDATE ON public.poker_games
  FOR EACH ROW EXECUTE FUNCTION public._set_poker_global_deadline();

-- 4) check_global_timeout RPCs

CREATE OR REPLACE FUNCTION public.domino_check_global_timeout(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE g public.domino_games%ROWTYPE; loser_user uuid; winner_user uuid;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND OR g.status <> 'playing' OR g.game_deadline IS NULL THEN RETURN; END IF;
  IF now() < g.game_deadline THEN RETURN; END IF;
  SELECT user_id INTO loser_user FROM public.domino_participants WHERE game_id = _game_id AND slot = g.current_turn;
  SELECT user_id INTO winner_user FROM public.domino_participants
   WHERE game_id = _game_id AND slot <> g.current_turn AND COALESCE(forfeited, false) = false
   ORDER BY slot LIMIT 1;
  UPDATE public.domino_games SET status = 'finished', winner_id = winner_user, finished_at = now() WHERE id = _game_id;
  IF winner_user IS NOT NULL AND g.pot > 0 THEN
    UPDATE public.profiles SET balance = COALESCE(balance, 0) + g.pot WHERE user_id = winner_user;
    INSERT INTO public.transactions(user_id, kind, amount, meta)
      VALUES (winner_user, 'game_win', g.pot, jsonb_build_object('game', 'domino', 'game_id', _game_id, 'reason', 'global_timeout'));
  END IF;
END; $$;
GRANT EXECUTE ON FUNCTION public.domino_check_global_timeout(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.rami_check_global_timeout(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE g public.rami_games%ROWTYPE; loser_user uuid; winner_user uuid;
BEGIN
  SELECT * INTO g FROM public.rami_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND OR g.status <> 'playing' OR g.game_deadline IS NULL THEN RETURN; END IF;
  IF now() < g.game_deadline THEN RETURN; END IF;
  SELECT user_id INTO loser_user FROM public.rami_participants WHERE game_id = _game_id AND slot = g.current_turn;
  SELECT user_id INTO winner_user FROM public.rami_participants
   WHERE game_id = _game_id AND slot <> g.current_turn ORDER BY slot LIMIT 1;
  UPDATE public.rami_games SET status = 'finished', winner_id = winner_user, finished_at = now() WHERE id = _game_id;
  IF winner_user IS NOT NULL AND g.pot > 0 THEN
    UPDATE public.profiles SET balance = COALESCE(balance, 0) + g.pot WHERE user_id = winner_user;
    INSERT INTO public.transactions(user_id, kind, amount, meta)
      VALUES (winner_user, 'game_win', g.pot, jsonb_build_object('game', 'rami', 'game_id', _game_id, 'reason', 'global_timeout'));
  END IF;
END; $$;
GRANT EXECUTE ON FUNCTION public.rami_check_global_timeout(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.poker_check_global_timeout(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE g public.poker_games%ROWTYPE; winner_user uuid;
BEGIN
  SELECT * INTO g FROM public.poker_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND OR g.status <> 'playing' OR g.game_deadline IS NULL THEN RETURN; END IF;
  IF now() < g.game_deadline THEN RETURN; END IF;
  SELECT user_id INTO winner_user FROM public.poker_players
   WHERE game_id = _game_id AND user_id <> g.current_player AND status = 'playing'
   ORDER BY seat LIMIT 1;
  UPDATE public.poker_games SET status = 'finished', winner_id = winner_user, finished_at = now() WHERE id = _game_id;
  IF winner_user IS NOT NULL AND g.pot > 0 THEN
    UPDATE public.profiles SET balance = COALESCE(balance, 0) + g.pot WHERE user_id = winner_user;
    INSERT INTO public.transactions(user_id, kind, amount, meta)
      VALUES (winner_user, 'game_win', g.pot, jsonb_build_object('game', 'poker', 'game_id', _game_id, 'reason', 'global_timeout'));
  END IF;
END; $$;
GRANT EXECUTE ON FUNCTION public.poker_check_global_timeout(uuid) TO authenticated, service_role;
