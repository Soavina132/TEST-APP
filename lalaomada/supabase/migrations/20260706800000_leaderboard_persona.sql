-- Fix: l'alias admin (admin_persona) n'apparaissait jamais dans le classement
-- car leaderboard_winners excluait tous les comptes admin sans exception.
-- Correction: on garde l'exclusion des admins par défaut (pour ne pas polluer
-- le classement avec le vrai compte admin), SAUF si l'admin a un alias actif
-- (admin_persona.is_active = true) — dans ce cas ses victoires comptent et
-- s'affichent sous le pseudo/photo de l'alias (déjà stockés dans profiles
-- par admin_activate_persona, donc aucun autre changement nécessaire).

DROP FUNCTION IF EXISTS public.leaderboard_winners(text, int, text);

CREATE OR REPLACE FUNCTION public.leaderboard_winners(
  _period text DEFAULT 'all',
  _limit  int  DEFAULT 20,
  _slug   text DEFAULT NULL   -- NULL or 'all' = all games
)
RETURNS TABLE(rank int, user_id uuid, name text, avatar_url text, wins bigint, total_won numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  WITH bound AS (
    SELECT CASE _period
      WHEN 'week'  THEN now() - interval '7 days'
      WHEN 'month' THEN now() - interval '30 days'
      ELSE 'epoch'::timestamptz
    END AS since
  ),
  raw AS (
    -- ludo
    SELECT g.winner_id AS uid, NULLIF(trim(pp.display_name),'') AS dn,
           g.pot * (1 - g.commission_pct/100.0) AS won,
           COALESCE(g.finished_at, g.created_at) AS at
      FROM ludo_games g JOIN ludo_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'ludo')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    -- domino
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0),
           COALESCE(g.finished_at, g.created_at)
      FROM domino_games g JOIN domino_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'domino')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    -- fanorona
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0),
           COALESCE(g.finished_at, g.created_at)
      FROM fanorona_games g JOIN fanorona_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'fanorona')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    -- rami
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0),
           COALESCE(g.finished_at, g.created_at)
      FROM rami_games g JOIN rami_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'rami')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    -- chess
    SELECT g.winner_id, NULL::text,
           g.stake * 2 * (1 - COALESCE((SELECT commission_pct FROM app_settings WHERE id=1),0)/100.0),
           COALESCE(g.finished_at, g.created_at)
      FROM chess_games g, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'chess')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    -- poker
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0),
           COALESCE(g.finished_at, g.created_at)
      FROM poker_games g JOIN poker_players pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'poker')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
  ),
  filtered AS (
    -- On exclut les admins du classement, SAUF s'ils jouent actuellement
    -- sous un alias actif (admin_persona.is_active) : dans ce cas leurs
    -- victoires comptent et s'affichent sous le nom/photo de l'alias.
    SELECT r.uid, r.dn, r.won, r.at FROM raw r
    WHERE NOT public.has_role(r.uid, 'admin'::public.app_role)
       OR EXISTS (
            SELECT 1 FROM public.admin_persona ap
            WHERE ap.admin_id = r.uid AND ap.is_active
          )
  ),
  named AS (
    SELECT f.uid, f.won, f.at,
           COALESCE(p.pseudo, f.dn, 'Joueur') AS name,
           p.avatar_url
    FROM filtered f LEFT JOIN public.profiles p ON p.id=f.uid
  ),
  agg AS (
    -- Un seul compte = une seule ligne : on agrège uniquement par user_id.
    SELECT uid,
           count(*)::bigint AS wins,
           COALESCE(sum(won), 0)::numeric AS total_won
    FROM named
    GROUP BY uid
  ),
  latest_name AS (
    -- Nom/avatar les plus récents pour ce compte (stable, ne dépend pas de
    -- l'ordre des unions ni des display_name divergents entre parties).
    SELECT DISTINCT ON (uid) uid, name, avatar_url
    FROM named
    ORDER BY uid, at DESC
  )
  SELECT (row_number() OVER (ORDER BY a.wins DESC, ln.name ASC))::int AS rank,
         a.uid AS user_id, ln.name, ln.avatar_url, a.wins, a.total_won
  FROM agg a
  JOIN latest_name ln ON ln.uid = a.uid
  ORDER BY a.wins DESC, ln.name ASC
  LIMIT _limit;
$$;

REVOKE ALL ON FUNCTION public.leaderboard_winners(text, int, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.leaderboard_winners(text, int, text) TO authenticated, anon;
