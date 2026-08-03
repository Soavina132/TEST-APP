
CREATE OR REPLACE FUNCTION public._set_chess_global_deadline()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  enabled boolean;
  mins integer;
BEGIN
  IF NEW.status = 'playing' AND (OLD.status IS DISTINCT FROM 'playing') AND NEW.game_deadline IS NULL THEN
    SELECT chess_global_timer_enabled, chess_global_timer_minutes INTO enabled, mins FROM public.app_settings WHERE id = 1;
    IF COALESCE(enabled, false) AND COALESCE(mins, 0) > 0 THEN
      NEW.game_deadline := now() + (mins || ' minutes')::interval;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_chess_global_deadline ON public.chess_games;
CREATE TRIGGER trg_chess_global_deadline
  BEFORE UPDATE ON public.chess_games
  FOR EACH ROW EXECUTE FUNCTION public._set_chess_global_deadline();

CREATE OR REPLACE FUNCTION public._set_fanorona_global_deadline()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  enabled boolean;
  mins integer;
BEGIN
  IF NEW.status = 'playing' AND (OLD.status IS DISTINCT FROM 'playing') AND NEW.game_deadline IS NULL THEN
    SELECT fanorona_global_timer_enabled, fanorona_global_timer_minutes INTO enabled, mins FROM public.app_settings WHERE id = 1;
    IF COALESCE(enabled, false) AND COALESCE(mins, 0) > 0 THEN
      NEW.game_deadline := now() + (mins || ' minutes')::interval;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fanorona_global_deadline ON public.fanorona_games;
CREATE TRIGGER trg_fanorona_global_deadline
  BEFORE UPDATE ON public.fanorona_games
  FOR EACH ROW EXECUTE FUNCTION public._set_fanorona_global_deadline();
