-- ═══════════════════════════════════════════════════════════════
-- Fix : "Mes parties en cours" affichait de vieilles parties
-- penalty/poker fantômes.
--
-- Contexte : poker et penalty ont été retirés du frontend
-- (commit 225828d "Remove poker and penalty games from app"),
-- mais my_ongoing_all() continuait à les inclure dans son UNION.
-- Comme il restait des lignes penalty_games avec status
-- open/playing jamais nettoyées, elles réapparaissaient dans le
-- bandeau "Mes parties en cours" et le widget "Parties en cours".
--
-- Cette migration retire les clauses poker/penalty de
-- my_ongoing_all(). Ludo, domino, fanorona, rami, chess restent
-- inchangés à l'identique.
-- ═══════════════════════════════════════════════════════════════

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
    SELECT g.id, 'ludo'::text AS game_type, g.status::text AS status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at,
      (SELECT count(*) FROM ludo_participants pp WHERE pp.game_id=g.id) AS players_count
    FROM ludo_games g JOIN ludo_participants p ON p.game_id=g.id
    WHERE p.user_id=v_uid AND g.status::text IN ('open','playing') AND p.forfeited=false
    UNION ALL
    SELECT g.id, 'domino', g.status::text, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at,
      (SELECT count(*) FROM domino_participants pp WHERE pp.game_id=g.id)
    FROM domino_games g JOIN domino_participants p ON p.game_id=g.id
    WHERE p.user_id=v_uid AND g.status::text IN ('open','playing') AND p.forfeited=false
    UNION ALL
    SELECT g.id, 'fanorona', g.status::text, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at,
      (SELECT count(*) FROM fanorona_participants pp WHERE pp.game_id=g.id)
    FROM fanorona_games g JOIN fanorona_participants p ON p.game_id=g.id
    WHERE p.user_id=v_uid AND g.status::text IN ('open','playing') AND p.forfeited=false
    UNION ALL
    SELECT g.id, 'rami', g.status::text, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at,
      (SELECT count(*) FROM rami_participants pp WHERE pp.game_id=g.id)
    FROM rami_games g JOIN rami_participants p ON p.game_id=g.id
    WHERE p.user_id=v_uid AND g.status::text IN ('open','playing') AND p.forfeited=false
    UNION ALL
    SELECT g.id, 'chess', g.status::text, 2 AS max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at,
      (CASE WHEN g.black_id IS NULL THEN 1 ELSE 2 END)::bigint
    FROM chess_games g
    WHERE (g.white_id=v_uid OR g.black_id=v_uid) AND g.status::text IN ('open','playing')
  ) t;
  RETURN v_result;
END;
$function$;
