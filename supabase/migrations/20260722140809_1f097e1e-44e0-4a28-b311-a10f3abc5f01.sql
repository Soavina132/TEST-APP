
-- Redefine helper: Ludo humans that finished all their pawns are also considered "out".
CREATE OR REPLACE FUNCTION public._end_bot_only_games()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT g.id FROM public.ludo_games g
    WHERE g.status='playing' AND COALESCE(g.is_solo,false)=false
      AND NOT EXISTS (
        SELECT 1 FROM public.ludo_participants p
        WHERE p.game_id=g.id AND p.is_bot=false
          AND COALESCE(p.forfeited,false)=false
          AND p.finish_rank IS NULL
      )
  LOOP
    UPDATE public.ludo_games SET status='finished', finished_at=now() WHERE id=r.id AND status='playing';
  END LOOP;

  FOR r IN
    SELECT g.id FROM public.domino_games g
    WHERE g.status='playing'
      AND NOT EXISTS (SELECT 1 FROM public.domino_participants p WHERE p.game_id=g.id AND p.is_bot=false AND COALESCE(p.forfeited,false)=false)
  LOOP
    UPDATE public.domino_games SET status='finished', finished_at=now() WHERE id=r.id AND status='playing';
  END LOOP;

  FOR r IN
    SELECT g.id FROM public.fanorona_games g
    WHERE g.status='playing'
      AND NOT EXISTS (SELECT 1 FROM public.fanorona_participants p WHERE p.game_id=g.id AND p.is_bot=false AND COALESCE(p.forfeited,false)=false)
  LOOP
    UPDATE public.fanorona_games SET status='finished', finished_at=now() WHERE id=r.id AND status='playing';
  END LOOP;

  FOR r IN
    SELECT g.id FROM public.rami_games g
    WHERE g.status='playing'
      AND NOT EXISTS (SELECT 1 FROM public.rami_participants p WHERE p.game_id=g.id AND p.is_bot=false AND COALESCE(p.forfeited,false)=false)
  LOOP
    UPDATE public.rami_games SET status='finished', finished_at=now() WHERE id=r.id AND status='playing';
  END LOOP;
END $$;

-- Per-game fast checks fired by trigger so we don't wait for the 1-minute cron.
CREATE OR REPLACE FUNCTION public._maybe_end_bot_only_ludo(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  UPDATE public.ludo_games g SET status='finished', finished_at=now()
  WHERE g.id=_game_id AND g.status='playing' AND COALESCE(g.is_solo,false)=false
    AND NOT EXISTS (
      SELECT 1 FROM public.ludo_participants p
      WHERE p.game_id=g.id AND p.is_bot=false
        AND COALESCE(p.forfeited,false)=false
        AND p.finish_rank IS NULL
    );
END $$;

CREATE OR REPLACE FUNCTION public._maybe_end_bot_only_domino(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  UPDATE public.domino_games g SET status='finished', finished_at=now()
  WHERE g.id=_game_id AND g.status='playing'
    AND NOT EXISTS (SELECT 1 FROM public.domino_participants p WHERE p.game_id=g.id AND p.is_bot=false AND COALESCE(p.forfeited,false)=false);
END $$;

CREATE OR REPLACE FUNCTION public._maybe_end_bot_only_fanorona(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  UPDATE public.fanorona_games g SET status='finished', finished_at=now()
  WHERE g.id=_game_id AND g.status='playing'
    AND NOT EXISTS (SELECT 1 FROM public.fanorona_participants p WHERE p.game_id=g.id AND p.is_bot=false AND COALESCE(p.forfeited,false)=false);
END $$;

CREATE OR REPLACE FUNCTION public._maybe_end_bot_only_rami(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  UPDATE public.rami_games g SET status='finished', finished_at=now()
  WHERE g.id=_game_id AND g.status='playing'
    AND NOT EXISTS (SELECT 1 FROM public.rami_participants p WHERE p.game_id=g.id AND p.is_bot=false AND COALESCE(p.forfeited,false)=false);
END $$;

-- Trigger fns
CREATE OR REPLACE FUNCTION public._trg_ludo_participant_end_check()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NEW.is_bot=false AND (
        COALESCE(NEW.forfeited,false) IS DISTINCT FROM COALESCE(OLD.forfeited,false)
     OR NEW.finish_rank IS DISTINCT FROM OLD.finish_rank
  ) THEN
    PERFORM public._maybe_end_bot_only_ludo(NEW.game_id);
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public._trg_domino_participant_end_check()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NEW.is_bot=false AND COALESCE(NEW.forfeited,false) IS DISTINCT FROM COALESCE(OLD.forfeited,false) THEN
    PERFORM public._maybe_end_bot_only_domino(NEW.game_id);
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public._trg_fanorona_participant_end_check()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF COALESCE(NEW.forfeited,false) IS DISTINCT FROM COALESCE(OLD.forfeited,false) THEN
    PERFORM public._maybe_end_bot_only_fanorona(NEW.game_id);
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public._trg_rami_participant_end_check()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF COALESCE(NEW.forfeited,false) IS DISTINCT FROM COALESCE(OLD.forfeited,false) THEN
    PERFORM public._maybe_end_bot_only_rami(NEW.game_id);
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_ludo_participant_end_check ON public.ludo_participants;
CREATE TRIGGER trg_ludo_participant_end_check
AFTER UPDATE ON public.ludo_participants
FOR EACH ROW EXECUTE FUNCTION public._trg_ludo_participant_end_check();

DROP TRIGGER IF EXISTS trg_domino_participant_end_check ON public.domino_participants;
CREATE TRIGGER trg_domino_participant_end_check
AFTER UPDATE ON public.domino_participants
FOR EACH ROW EXECUTE FUNCTION public._trg_domino_participant_end_check();

DROP TRIGGER IF EXISTS trg_fanorona_participant_end_check ON public.fanorona_participants;
CREATE TRIGGER trg_fanorona_participant_end_check
AFTER UPDATE ON public.fanorona_participants
FOR EACH ROW EXECUTE FUNCTION public._trg_fanorona_participant_end_check();

DROP TRIGGER IF EXISTS trg_rami_participant_end_check ON public.rami_participants;
CREATE TRIGGER trg_rami_participant_end_check
AFTER UPDATE ON public.rami_participants
FOR EACH ROW EXECUTE FUNCTION public._trg_rami_participant_end_check();

-- Also update the Ludo predicate in list_live_games to hide games where every human already finished.
CREATE OR REPLACE FUNCTION public.list_live_games()
RETURNS TABLE(id uuid, max_players integer, stake numeric, pot numeric, players_count integer, spectators_count integer, started_at timestamp with time zone, mode text, game_type text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT g.id, g.max_players, g.stake, g.pot,
    (SELECT count(*)::int FROM public.ludo_participants p WHERE p.game_id=g.id),
    (SELECT count(*)::int FROM public.game_spectators s WHERE s.game_id=g.id),
    g.started_at, COALESCE(g.mode,'classic')::text, 'ludo'::text
  FROM public.ludo_games g
  WHERE g.status='playing' AND COALESCE(g.is_solo,false)=false
    AND EXISTS (
      SELECT 1 FROM public.ludo_participants p
      WHERE p.game_id=g.id AND p.is_bot=false
        AND COALESCE(p.forfeited,false)=false
        AND p.finish_rank IS NULL
    )
  UNION ALL
  SELECT g.id, g.max_players, g.stake, g.pot,
    (SELECT count(*)::int FROM public.domino_participants p WHERE p.game_id=g.id),
    (SELECT count(*)::int FROM public.game_spectators s WHERE s.game_id=g.id),
    g.started_at, COALESCE(g.mode,'classic')::text, 'domino'::text
  FROM public.domino_games g
  WHERE g.status='playing'
    AND EXISTS (SELECT 1 FROM public.domino_participants p WHERE p.game_id=g.id AND p.is_bot=false AND COALESCE(p.forfeited,false)=false)
    AND NOT EXISTS (SELECT 1 FROM public.domino_participants pp WHERE pp.game_id=g.id AND pp.is_bot=true AND pp.user_id=g.host_id)
  UNION ALL
  SELECT g.id, 2, g.stake, g.pot, 2,
    (SELECT count(*)::int FROM public.game_spectators s WHERE s.game_id=g.id),
    g.started_at, 'classic'::text, 'chess'::text
  FROM public.chess_games g
  WHERE g.status='playing' AND g.white_id IS DISTINCT FROM g.black_id
  UNION ALL
  SELECT g.id, 2, g.stake, g.pot, 2,
    (SELECT count(*)::int FROM public.game_spectators s WHERE s.game_id=g.id),
    g.started_at, 'classic'::text, 'fanorona'::text
  FROM public.fanorona_games g
  WHERE g.status='playing'
    AND EXISTS (SELECT 1 FROM public.fanorona_participants p WHERE p.game_id=g.id AND p.is_bot=false AND COALESCE(p.forfeited,false)=false)
    AND NOT EXISTS (SELECT 1 FROM public.fanorona_participants pp WHERE pp.game_id=g.id AND pp.is_bot=true AND pp.user_id=g.host_id)
  UNION ALL
  SELECT g.id, g.max_players, g.stake, g.pot,
    (SELECT count(*)::int FROM public.rami_participants p WHERE p.game_id=g.id),
    (SELECT count(*)::int FROM public.game_spectators s WHERE s.game_id=g.id),
    g.started_at, COALESCE(g.joker_mode,'classique')::text, 'rami'::text
  FROM public.rami_games g
  WHERE g.status='playing'
    AND EXISTS (SELECT 1 FROM public.rami_participants p WHERE p.game_id=g.id AND p.is_bot=false AND COALESCE(p.forfeited,false)=false)
    AND NOT EXISTS (SELECT 1 FROM public.rami_participants pp WHERE pp.game_id=g.id AND pp.is_bot=true AND pp.user_id=g.created_by)
  ORDER BY 6 DESC, 7 ASC;
$$;

-- Backfill: nettoyer immédiatement les parties existantes sans humain actif.
SELECT public._end_bot_only_games();
