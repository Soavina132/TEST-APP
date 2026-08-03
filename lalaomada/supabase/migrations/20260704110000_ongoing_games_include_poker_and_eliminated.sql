-- ================================================================
-- Auto-resume feature: when a user comes back to the app, we need
-- to know about EVERY unfinished game they're tied to, including:
--   - poker (missing from the previous version of this function)
--   - games where they've already been eliminated/forfeited but
--     the game is still running (so we can drop them back in as a
--     spectator, "mode live", instead of just forgetting about it)
-- Adds an `eliminated` boolean so the client can decide whether to
-- resume as an active player or auto-join as a spectator.
-- ================================================================

CREATE OR REPLACE FUNCTION public.my_ongoing_all()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_uid uuid := auth.uid(); v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.eliminated ASC, t.created_at DESC), '[]'::jsonb) INTO v_result FROM (
    -- ── ludo: still active ──
    SELECT g.id, 'ludo'::text AS game_type, g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at, false AS eliminated,
      (SELECT count(*) FROM ludo_participants pp WHERE pp.game_id=g.id) AS players_count
    FROM ludo_games g JOIN ludo_participants p ON p.game_id=g.id
    WHERE p.user_id=v_uid AND g.status IN ('open','playing') AND p.forfeited=false
    UNION ALL
    -- ── ludo: eliminated but game still running → spectate ──
    SELECT g.id, 'ludo', g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at, true,
      (SELECT count(*) FROM ludo_participants pp WHERE pp.game_id=g.id)
    FROM ludo_games g JOIN ludo_participants p ON p.game_id=g.id
    WHERE p.user_id=v_uid AND g.status='playing' AND p.forfeited=true

    UNION ALL
    SELECT g.id, 'domino', g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at, false,
      (SELECT count(*) FROM domino_participants pp WHERE pp.game_id=g.id)
    FROM domino_games g JOIN domino_participants p ON p.game_id=g.id
    WHERE p.user_id=v_uid AND g.status IN ('open','playing') AND p.forfeited=false
    UNION ALL
    SELECT g.id, 'domino', g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at, true,
      (SELECT count(*) FROM domino_participants pp WHERE pp.game_id=g.id)
    FROM domino_games g JOIN domino_participants p ON p.game_id=g.id
    WHERE p.user_id=v_uid AND g.status='playing' AND p.forfeited=true

    UNION ALL
    SELECT g.id, 'fanorona', g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at, false,
      (SELECT count(*) FROM fanorona_participants pp WHERE pp.game_id=g.id)
    FROM fanorona_games g JOIN fanorona_participants p ON p.game_id=g.id
    WHERE p.user_id=v_uid AND g.status IN ('open','playing') AND p.forfeited=false
    UNION ALL
    SELECT g.id, 'fanorona', g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at, true,
      (SELECT count(*) FROM fanorona_participants pp WHERE pp.game_id=g.id)
    FROM fanorona_games g JOIN fanorona_participants p ON p.game_id=g.id
    WHERE p.user_id=v_uid AND g.status='playing' AND p.forfeited=true

    UNION ALL
    SELECT g.id, 'rami', g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at, false,
      (SELECT count(*) FROM rami_participants pp WHERE pp.game_id=g.id)
    FROM rami_games g JOIN rami_participants p ON p.game_id=g.id
    WHERE p.user_id=v_uid AND g.status IN ('open','playing') AND p.forfeited=false
    UNION ALL
    SELECT g.id, 'rami', g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at, true,
      (SELECT count(*) FROM rami_participants pp WHERE pp.game_id=g.id)
    FROM rami_games g JOIN rami_participants p ON p.game_id=g.id
    WHERE p.user_id=v_uid AND g.status='playing' AND p.forfeited=true

    UNION ALL
    -- chess: 1v1, no mid-game elimination concept
    SELECT g.id, 'chess', g.status, 2 AS max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at, false,
      (CASE WHEN g.black_id IS NULL THEN 1 ELSE 2 END)::bigint
    FROM chess_games g
    WHERE (g.white_id=v_uid OR g.black_id=v_uid) AND g.status IN ('open','playing')

    UNION ALL
    -- poker: still active (not busted)
    SELECT g.id, 'poker', g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at, false,
      (SELECT count(*) FROM poker_players pp WHERE pp.game_id=g.id)
    FROM poker_games g JOIN poker_players p ON p.game_id=g.id
    WHERE p.user_id=v_uid AND g.status IN ('open','playing') AND p.status <> 'out'
    UNION ALL
    -- poker: busted (chips <= 0) but the table is still playing → spectate
    SELECT g.id, 'poker', g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at, true,
      (SELECT count(*) FROM poker_players pp WHERE pp.game_id=g.id)
    FROM poker_games g JOIN poker_players p ON p.game_id=g.id
    WHERE p.user_id=v_uid AND g.status='playing' AND p.status='out'
  ) t;
  RETURN v_result;
END $$;

GRANT EXECUTE ON FUNCTION public.my_ongoing_all() TO authenticated;
