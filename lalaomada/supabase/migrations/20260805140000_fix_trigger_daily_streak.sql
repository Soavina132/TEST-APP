-- ═══════════════════════════════════════════════════════════════════
-- Fix: trigger _trg_check_achievements_on_win references NEW.daily_streak
-- which was dropped from profiles by 20260805090000_security_audit_fixes.sql
--
-- Error: record "new" has no field "daily_streak"
-- Happens on ANY profile update (e.g. winning a domino game)
-- ═══════════════════════════════════════════════════════════════════

-- 1. Fix check_and_award_achievements: remove daily_streak from SELECT
CREATE OR REPLACE FUNCTION public.check_and_award_achievements(_uid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_wins int; v_games int; v_streak int := 0;
  v_ludo_wins int:=0; v_chess_wins int:=0; v_domino_wins int:=0; v_fanorona_wins int:=0; v_rami_wins int:=0;
  v_has_deposit boolean := false;
BEGIN
  SELECT COALESCE(total_wins,0), COALESCE(total_games,0)
  INTO v_wins, v_games FROM public.profiles WHERE id = _uid;
  BEGIN SELECT COUNT(*) INTO v_ludo_wins     FROM public.ludo_games     WHERE winner_id = _uid; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN SELECT COUNT(*) INTO v_chess_wins    FROM public.chess_games    WHERE winner_id = _uid; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN SELECT COUNT(*) INTO v_domino_wins   FROM public.domino_games   WHERE winner_id = _uid; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN SELECT COUNT(*) INTO v_fanorona_wins FROM public.fanorona_games WHERE winner_id = _uid; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN SELECT COUNT(*) INTO v_rami_wins     FROM public.rami_games     WHERE winner_id = _uid; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN SELECT EXISTS(SELECT 1 FROM public.deposits WHERE user_id = _uid AND status = 'approved') INTO v_has_deposit; EXCEPTION WHEN OTHERS THEN NULL; END;
  IF v_wins   >= 1   THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'first_win')   ON CONFLICT DO NOTHING; END IF;
  IF v_wins   >= 10  THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'wins_10')     ON CONFLICT DO NOTHING; END IF;
  IF v_wins   >= 50  THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'wins_50')     ON CONFLICT DO NOTHING; END IF;
  IF v_wins   >= 100 THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'wins_100')    ON CONFLICT DO NOTHING; END IF;
  IF v_wins   >= 200 THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'wins_200')    ON CONFLICT DO NOTHING; END IF;
  IF v_games  >= 50  THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'games_50')    ON CONFLICT DO NOTHING; END IF;
  IF v_games  >= 100 THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'games_100')   ON CONFLICT DO NOTHING; END IF;
  -- Streak achievements: daily_streak column was removed, skip these
  -- IF v_streak >= 7   THEN ... streak_7 ... END IF;
  -- IF v_streak >= 30  THEN ... streak_30 ... END IF;
  IF v_ludo_wins    >= 10 THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'ludo_10')     ON CONFLICT DO NOTHING; END IF;
  IF v_chess_wins   >= 10 THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'chess_10')    ON CONFLICT DO NOTHING; END IF;
  IF v_domino_wins  >= 10 THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'domino_10')   ON CONFLICT DO NOTHING; END IF;
  IF v_fanorona_wins>= 10 THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'fanorona_10') ON CONFLICT DO NOTHING; END IF;
  IF v_rami_wins    >= 10 THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'rami_10')     ON CONFLICT DO NOTHING; END IF;
  IF v_has_deposit  THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'first_deposit') ON CONFLICT DO NOTHING; END IF;
END;
$$;

-- 2. Fix trigger function: remove NEW.daily_streak reference
CREATE OR REPLACE FUNCTION public._trg_check_achievements_on_win()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.total_wins IS DISTINCT FROM OLD.total_wins THEN
    PERFORM public.check_and_award_achievements(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

-- Recreate trigger to pick up new function body
DROP TRIGGER IF EXISTS trg_check_achievements ON public.profiles;
CREATE TRIGGER trg_check_achievements AFTER UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public._trg_check_achievements_on_win();
