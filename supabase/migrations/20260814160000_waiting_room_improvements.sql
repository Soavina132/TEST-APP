-- Migration: Waiting room improvements
-- 1. my_ongoing_all: Add poker to the list of game types
-- 2. game_invite_timeout_minutes: Set to 2 (was 6)

CREATE OR REPLACE FUNCTION public.my_ongoing_all()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
    WHERE p.user_id=v_uid AND g.status IN ('open','playing')
  ) t;
  RETURN v_result;
END;
$function$;

UPDATE public.app_settings SET game_invite_timeout_minutes = 2 WHERE id = 1;
