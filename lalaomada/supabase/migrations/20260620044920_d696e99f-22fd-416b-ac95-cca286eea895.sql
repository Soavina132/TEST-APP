CREATE OR REPLACE FUNCTION public.weekly_top_winners(_limit integer DEFAULT 10)
 RETURNS TABLE(user_id uuid, pseudo text, avatar_url text, wins bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH wins AS (
    SELECT g.winner_id AS uid, COALESCE(NULLIF(trim(pp.display_name),''), p.pseudo, 'Joueur') AS name
      FROM ludo_games g
      JOIN ludo_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id
      LEFT JOIN profiles p ON p.id=g.winner_id
      WHERE g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at, g.created_at) >= now() - interval '7 days'
    UNION ALL
    SELECT g.winner_id, COALESCE(NULLIF(trim(pp.display_name),''), p.pseudo, 'Joueur')
      FROM domino_games g
      JOIN domino_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id
      LEFT JOIN profiles p ON p.id=g.winner_id
      WHERE g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at, g.created_at) >= now() - interval '7 days'
    UNION ALL
    SELECT g.winner_id, COALESCE(NULLIF(trim(pp.display_name),''), p.pseudo, 'Joueur')
      FROM fanorona_games g
      JOIN fanorona_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id
      LEFT JOIN profiles p ON p.id=g.winner_id
      WHERE g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at, g.created_at) >= now() - interval '7 days'
    UNION ALL
    SELECT g.winner_id, COALESCE(NULLIF(trim(pp.display_name),''), p.pseudo, 'Joueur')
      FROM rami_games g
      JOIN rami_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id
      LEFT JOIN profiles p ON p.id=g.winner_id
      WHERE g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at, g.created_at) >= now() - interval '7 days'
    UNION ALL
    SELECT g.winner_id, COALESCE(p.pseudo, 'Joueur')
      FROM chess_games g
      LEFT JOIN profiles p ON p.id=g.winner_id
      WHERE g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at, g.created_at) >= now() - interval '7 days'
  ),
  filtered AS (
    SELECT w.uid, w.name FROM wins w
    WHERE NOT public.has_role(w.uid, 'admin'::public.app_role)
  ),
  agg AS (
    SELECT name, (array_agg(uid))[1] AS uid, count(*)::bigint AS wins
    FROM filtered
    GROUP BY name
  )
  SELECT a.uid, a.name, p.avatar_url, a.wins
  FROM agg a LEFT JOIN profiles p ON p.id = a.uid
  ORDER BY a.wins DESC, a.name ASC
  LIMIT _limit;
$function$;