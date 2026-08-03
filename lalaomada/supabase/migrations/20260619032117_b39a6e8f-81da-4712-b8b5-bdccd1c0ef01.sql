CREATE OR REPLACE FUNCTION public.game_online_count(_slug text)
RETURNS integer
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT COUNT(DISTINCT user_id)::int FROM (
    SELECT lp.user_id FROM ludo_participants lp
      JOIN ludo_games g ON g.id = lp.game_id
      WHERE _slug='ludo' AND g.status IN ('open','playing') AND lp.user_id IS NOT NULL
    UNION ALL
    SELECT dp.user_id FROM domino_participants dp
      JOIN domino_games g ON g.id = dp.game_id
      WHERE _slug='domino' AND g.status IN ('open','playing') AND dp.user_id IS NOT NULL
    UNION ALL
    SELECT fp.user_id FROM fanorona_participants fp
      JOIN fanorona_games g ON g.id = fp.game_id
      WHERE _slug='fanorona' AND g.status IN ('open','playing') AND fp.user_id IS NOT NULL
    UNION ALL
    SELECT rp.user_id FROM rami_participants rp
      JOIN rami_games g ON g.id = rp.game_id
      WHERE _slug='rami' AND g.status IN ('open','playing') AND rp.user_id IS NOT NULL
    UNION ALL
    SELECT g.white_id AS user_id FROM chess_games g WHERE _slug='chess' AND g.status IN ('open','playing') AND g.white_id IS NOT NULL
    UNION ALL
    SELECT g.black_id FROM chess_games g WHERE _slug='chess' AND g.status IN ('open','playing') AND g.black_id IS NOT NULL
    UNION ALL
    SELECT cm.user_id FROM chat_members cm
      JOIN chat_rooms cr ON cr.id = cm.room_id
      WHERE cr.type = 'global' AND cr.name = 'Salon ' || _slug AND cm.user_id IS NOT NULL
  ) u;
$function$;