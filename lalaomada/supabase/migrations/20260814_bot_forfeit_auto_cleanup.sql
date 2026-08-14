-- ============================================================
-- Migration: Auto-cleanup bot-only games when human forfeits
-- Minimal change — triggers only, no game logic modified
-- ============================================================

-- 1. Add forfeited column to poker_players (if not exists)
ALTER TABLE public.poker_players
  ADD COLUMN IF NOT EXISTS forfeited boolean NOT NULL DEFAULT false;

-- 2. Create _maybe_end_bot_only_ludo (same pattern as domino/fanorona/rami)
CREATE OR REPLACE FUNCTION public._maybe_end_bot_only_ludo(_game_id uuid)
RETURNS void AS $$
BEGIN
  UPDATE public.ludo_games g SET status = 'finished', finished_at = now()
  WHERE g.id = _game_id AND g.status = 'playing'
    AND NOT EXISTS (
      SELECT 1 FROM public.ludo_participants p
      WHERE p.game_id = _game_id
        AND p.is_bot = false
        AND COALESCE(p.forfeited, false) = false
        AND p.finish_rank IS NULL
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Create _maybe_end_bot_only_poker
CREATE OR REPLACE FUNCTION public._maybe_end_bot_only_poker(_game_id uuid)
RETURNS void AS $$
BEGIN
  UPDATE public.poker_games g SET status = 'finished', finished_at = now()
  WHERE g.id = _game_id AND g.status = 'playing'
    AND NOT EXISTS (
      SELECT 1 FROM public.poker_players p
      WHERE p.game_id = _game_id
        AND p.is_bot = false
        AND COALESCE(p.forfeited, false) = false
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Trigger function for ludo
CREATE OR REPLACE FUNCTION public._trg_ludo_participant_end_check()
RETURNS TRIGGER AS $$
BEGIN
  IF COALESCE(NEW.forfeited, false) IS DISTINCT FROM COALESCE(OLD.forfeited, false) THEN
    PERFORM public._maybe_end_bot_only_ludo(NEW.game_id);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 5. Trigger function for domino
CREATE OR REPLACE FUNCTION public._trg_domino_participant_end_check()
RETURNS TRIGGER AS $$
BEGIN
  IF COALESCE(NEW.forfeited, false) IS DISTINCT FROM COALESCE(OLD.forfeited, false) THEN
    PERFORM public._maybe_end_bot_only_domino(NEW.game_id);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 6. Trigger function for poker
CREATE OR REPLACE FUNCTION public._trg_poker_player_end_check()
RETURNS TRIGGER AS $$
BEGIN
  IF COALESCE(NEW.forfeited, false) IS DISTINCT FROM COALESCE(OLD.forfeited, false) THEN
    PERFORM public._maybe_end_bot_only_poker(NEW.game_id);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 7. Attach triggers (drop if exists first for idempotency)
DROP TRIGGER IF EXISTS trg_ludo_participant_end_check ON public.ludo_participants;
CREATE TRIGGER trg_ludo_participant_end_check
  AFTER UPDATE ON public.ludo_participants
  FOR EACH ROW EXECUTE FUNCTION public._trg_ludo_participant_end_check();

DROP TRIGGER IF EXISTS trg_domino_participant_end_check ON public.domino_participants;
CREATE TRIGGER trg_domino_participant_end_check
  AFTER UPDATE ON public.domino_participants
  FOR EACH ROW EXECUTE FUNCTION public._trg_domino_participant_end_check();

DROP TRIGGER IF EXISTS trg_poker_player_end_check ON public.poker_players;
CREATE TRIGGER trg_poker_player_end_check
  AFTER UPDATE ON public.poker_players
  FOR EACH ROW EXECUTE FUNCTION public._trg_poker_player_end_check();

-- 8. Update my_ongoing_all to exclude forfeited poker players
CREATE OR REPLACE FUNCTION public.my_ongoing_all()
RETURNS jsonb AS $$
DECLARE v_uid uuid := auth.uid(); v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.created_at DESC), '[]'::jsonb) INTO v_result FROM (
    SELECT g.id, 'ludo'::text AS game_type, g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at,
      (SELECT count(*) FROM ludo_participants pp WHERE pp.game_id=g.id) AS players_count
    FROM ludo_games g JOIN ludo_participants p ON p.game_id=g.id
    WHERE p.user_id=v_uid AND g.status IN ('open','playing') AND p.forfeited=false
    UNION ALL
    SELECT g.id, 'domino', g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at,
      (SELECT count(*) FROM domino_participants pp WHERE pp.game_id=g.id)
    FROM domino_games g JOIN domino_participants p ON p.game_id=g.id
    WHERE p.user_id=v_uid AND g.status IN ('open','playing') AND p.forfeited=false
    UNION ALL
    SELECT g.id, 'fanorona', g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at,
      (SELECT count(*) FROM fanorona_participants pp WHERE pp.game_id=g.id)
    FROM fanorona_games g JOIN fanorona_participants p ON p.game_id=g.id
    WHERE p.user_id=v_uid AND g.status IN ('open','playing') AND p.forfeited=false
    UNION ALL
    SELECT g.id, 'rami', g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at,
      (SELECT count(*) FROM rami_participants pp WHERE pp.game_id=g.id)
    FROM rami_games g JOIN rami_participants p ON p.game_id=g.id
    WHERE p.user_id=v_uid AND g.status IN ('open','playing') AND p.forfeited=false
    UNION ALL
    SELECT g.id, 'chess', g.status, 2 AS max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at,
      (CASE WHEN g.black_id IS NULL THEN 1 ELSE 2 END)::bigint
    FROM chess_games g
    WHERE (g.white_id=v_uid OR g.black_id=v_uid) AND g.status IN ('open','playing')
    UNION ALL
    SELECT g.id, 'poker', g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at,
      (SELECT count(*) FROM poker_players pp WHERE pp.game_id=g.id)
    FROM poker_games g JOIN poker_players p ON p.game_id=g.id
    WHERE p.user_id=v_uid AND g.status IN ('open','playing') AND COALESCE(p.forfeited, false) = false
  ) t;
  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
