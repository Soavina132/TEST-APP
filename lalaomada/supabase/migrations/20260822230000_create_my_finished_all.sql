-- Migration: Create my_finished_all() RPC function
-- Returns all finished/cancelled games for the current user across all game types

CREATE OR REPLACE FUNCTION public.my_finished_all()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid := auth.uid(); v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.finished_at DESC NULLS LAST), '[]'::jsonb) INTO v_result FROM (
    SELECT g.id, 'ludo'::text AS game_type, g.status::text AS status,
           g.stake, g.pot, g.room_code, g.is_private, g.created_at,
           g.finished_at, g.winner_id,
           COALESCE(p.forfeited, false) AS forfeited
    FROM ludo_games g
    JOIN ludo_participants p ON p.game_id = g.id
    WHERE p.user_id = v_uid AND g.status::text IN ('finished', 'cancelled')

    UNION ALL

    SELECT g.id, 'domino'::text, g.status::text,
           g.stake, g.pot, g.room_code, g.is_private, g.created_at,
           g.finished_at, g.winner_id,
           COALESCE(p.forfeited, false)
    FROM domino_games g
    JOIN domino_participants p ON p.game_id = g.id
    WHERE p.user_id = v_uid AND g.status::text IN ('finished', 'cancelled')

    UNION ALL

    SELECT g.id, 'fanorona'::text, g.status::text,
           g.stake, g.pot, g.room_code, g.is_private, g.created_at,
           g.finished_at, g.winner_id,
           COALESCE(p.forfeited, false)
    FROM fanorona_games g
    JOIN fanorona_participants p ON p.game_id = g.id
    WHERE p.user_id = v_uid AND g.status::text IN ('finished', 'cancelled')

    UNION ALL

    SELECT g.id, 'rami'::text, g.status::text,
           g.stake, g.pot, g.room_code, g.is_private, g.created_at,
           g.finished_at, g.winner_id,
           COALESCE(p.forfeited, false)
    FROM rami_games g
    JOIN rami_participants p ON p.game_id = g.id
    WHERE p.user_id = v_uid AND g.status::text IN ('finished', 'cancelled')

    UNION ALL

    SELECT g.id, 'chess'::text, g.status::text,
           g.stake, g.pot, g.room_code, g.is_private, g.created_at,
           g.finished_at, g.winner_id,
           false
    FROM chess_games g
    WHERE (g.white_id = v_uid OR g.black_id = v_uid)
      AND g.status::text IN ('finished', 'cancelled')
  ) t;

  RETURN v_result;
END;
$function$;
