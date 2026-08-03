-- Admin controls for the home-page leaderboard ("Top gagnants"):
-- 1) admin can hide/remove a player from the ranking (leaderboard_hidden)
-- 2) admin can pin a manual display order (leaderboard_rank_override)
-- Both are enforced inside leaderboard_winners() so the public leaderboard
-- respects them automatically, plus a dedicated admin_leaderboard_list()
-- RPC (admin-only) that also returns hidden players + their override so the
-- admin panel can manage them.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS leaderboard_hidden boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS leaderboard_rank_override int;

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
    -- On exclut les admins du classement (sauf alias actif), ET les comptes
    -- que l'admin a explicitement retirés du classement (leaderboard_hidden).
    SELECT r.uid, r.dn, r.won, r.at FROM raw r
    WHERE (NOT public.has_role(r.uid, 'admin'::public.app_role)
           OR EXISTS (
                SELECT 1 FROM public.admin_persona ap
                WHERE ap.admin_id = r.uid AND ap.is_active
              ))
      AND NOT EXISTS (
            SELECT 1 FROM public.profiles pr
            WHERE pr.id = r.uid AND pr.leaderboard_hidden
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
  SELECT (row_number() OVER (
            ORDER BY COALESCE(pr.leaderboard_rank_override, 2147483647) ASC,
                     a.wins DESC, ln.name ASC
          ))::int AS rank,
         a.uid AS user_id, ln.name, ln.avatar_url, a.wins, a.total_won
  FROM agg a
  JOIN latest_name ln ON ln.uid = a.uid
  LEFT JOIN public.profiles pr ON pr.id = a.uid
  ORDER BY COALESCE(pr.leaderboard_rank_override, 2147483647) ASC, a.wins DESC, ln.name ASC
  LIMIT _limit;
$$;

REVOKE ALL ON FUNCTION public.leaderboard_winners(text, int, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.leaderboard_winners(text, int, text) TO authenticated, anon;

-- ── Admin: list leaderboard entries including hidden ones, with mgmt flags ──
CREATE OR REPLACE FUNCTION public.admin_leaderboard_list(
  _period text DEFAULT 'all',
  _limit  int  DEFAULT 50,
  _slug   text DEFAULT NULL
)
RETURNS TABLE(user_id uuid, name text, avatar_url text, wins bigint, total_won numeric, hidden boolean, rank_override int)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  RETURN QUERY
  WITH bound AS (
    SELECT CASE _period
      WHEN 'week'  THEN now() - interval '7 days'
      WHEN 'month' THEN now() - interval '30 days'
      ELSE 'epoch'::timestamptz
    END AS since
  ),
  raw AS (
    SELECT g.winner_id AS uid, NULLIF(trim(pp.display_name),'') AS dn,
           g.pot * (1 - g.commission_pct/100.0) AS won,
           COALESCE(g.finished_at, g.created_at) AS at
      FROM ludo_games g JOIN ludo_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'ludo')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0),
           COALESCE(g.finished_at, g.created_at)
      FROM domino_games g JOIN domino_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'domino')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0),
           COALESCE(g.finished_at, g.created_at)
      FROM fanorona_games g JOIN fanorona_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'fanorona')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0),
           COALESCE(g.finished_at, g.created_at)
      FROM rami_games g JOIN rami_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'rami')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULL::text,
           g.stake * 2 * (1 - COALESCE((SELECT commission_pct FROM app_settings WHERE id=1),0)/100.0),
           COALESCE(g.finished_at, g.created_at)
      FROM chess_games g, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'chess')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0),
           COALESCE(g.finished_at, g.created_at)
      FROM poker_games g JOIN poker_players pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'poker')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
  ),
  filtered AS (
    -- Toujours exclure les vrais comptes admin (sans alias actif), même dans
    -- la vue de gestion : ce ne sont pas des joueurs à administrer.
    SELECT r.uid, r.dn, r.won, r.at FROM raw r
    WHERE (NOT public.has_role(r.uid, 'admin'::public.app_role)
           OR EXISTS (
                SELECT 1 FROM public.admin_persona ap
                WHERE ap.admin_id = r.uid AND ap.is_active
              ))
  ),
  named AS (
    SELECT f.uid, f.won, f.at,
           COALESCE(p.pseudo, f.dn, 'Joueur') AS name,
           p.avatar_url
    FROM filtered f LEFT JOIN public.profiles p ON p.id=f.uid
  ),
  agg AS (
    SELECT uid,
           count(*)::bigint AS wins,
           COALESCE(sum(won), 0)::numeric AS total_won
    FROM named
    GROUP BY uid
  ),
  latest_name AS (
    SELECT DISTINCT ON (uid) uid, name, avatar_url
    FROM named
    ORDER BY uid, at DESC
  )
  SELECT a.uid AS user_id, ln.name, ln.avatar_url, a.wins, a.total_won,
         COALESCE(pr.leaderboard_hidden, false) AS hidden,
         pr.leaderboard_rank_override AS rank_override
  FROM agg a
  JOIN latest_name ln ON ln.uid = a.uid
  LEFT JOIN public.profiles pr ON pr.id = a.uid
  ORDER BY COALESCE(pr.leaderboard_rank_override, 2147483647) ASC, a.wins DESC, ln.name ASC
  LIMIT _limit;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_leaderboard_list(text, int, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_leaderboard_list(text, int, text) TO authenticated;

-- ── Admin: hide/show a player from the leaderboard ──────────────────────────
CREATE OR REPLACE FUNCTION public.admin_set_leaderboard_hidden(_user_id uuid, _hidden boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  UPDATE public.profiles SET leaderboard_hidden = _hidden WHERE id = _user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_leaderboard_hidden(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_leaderboard_hidden(uuid, boolean) TO authenticated;

-- ── Admin: pin a manual display rank (lower = shown first). NULL clears it ──
CREATE OR REPLACE FUNCTION public.admin_set_leaderboard_rank(_user_id uuid, _rank_override int)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  UPDATE public.profiles SET leaderboard_rank_override = _rank_override WHERE id = _user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_leaderboard_rank(uuid, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_leaderboard_rank(uuid, int) TO authenticated;
