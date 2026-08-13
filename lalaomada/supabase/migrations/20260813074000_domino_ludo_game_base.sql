-- ============================================================
-- Migration: Domino & Ludo game base from ALL_IN_ONE.sql
-- Date: 2026-08-13
-- Description: Apply consolidated domino and ludo game base
--   - Fix domino_games.status type: text -> game_status
--   - Recreate SQL helper functions with correct type casts
--   - Recreate domino and ludo triggers
--   - Update all domino and ludo functions from ALL_IN_ONE.sql
-- ============================================================

-- ============================================================
-- STEP 1: Fix domino_games.status column type (text -> game_status)
-- ============================================================

-- Drop the partial index that uses status::text (would block type change)
DROP INDEX IF EXISTS public.idx_domino_games_cleanup;

-- Drop SQL functions that reference domino_games.status as text
DROP FUNCTION IF EXISTS public.list_live_games() CASCADE;
DROP FUNCTION IF EXISTS public.weekly_top_winners(integer) CASCADE;
DROP FUNCTION IF EXISTS public._domino_visible(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.game_online_count(text) CASCADE;
DROP FUNCTION IF EXISTS public.leaderboard_winners(text, integer, text) CASCADE;
DROP FUNCTION IF EXISTS public.list_public_open_games() CASCADE;

-- Drop triggers on domino_games that depend on status column
DROP TRIGGER IF EXISTS trg_house_on_finish ON public.domino_games;
DROP TRIGGER IF EXISTS trg_player_stats_domino ON public.domino_games;
DROP TRIGGER IF EXISTS trg_domino_deadline ON public.domino_games;
DROP TRIGGER IF EXISTS trg_skip_noop_domino ON public.domino_games;
DROP TRIGGER IF EXISTS trg_first_game_domino ON public.domino_games;
DROP TRIGGER IF EXISTS domino_apply_turn_timer ON public.domino_games;
DROP TRIGGER IF EXISTS trg_apply_commission ON public.domino_games;

-- Drop the default before type change
ALTER TABLE public.domino_games ALTER COLUMN status DROP DEFAULT;

-- Change the column type
ALTER TABLE public.domino_games ALTER COLUMN status TYPE game_status USING status::game_status;

-- Restore the default
ALTER TABLE public.domino_games ALTER COLUMN status SET DEFAULT 'open'::game_status;

-- Recreate the partial index with correct type cast
CREATE INDEX IF NOT EXISTS idx_domino_games_cleanup
  ON public.domino_games USING btree (status, finished_at)
  WHERE (status = 'finished'::game_status);

-- ============================================================
-- STEP 2: Recreate SQL helper functions (with game_status type)
-- ============================================================

CREATE OR REPLACE FUNCTION public._domino_visible(_game_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS(
    SELECT 1 FROM public.domino_games g
    WHERE g.id = _game_id
      AND (
        (g.status IN ('open','playing') AND g.is_private = false)
        OR g.host_id = auth.uid()
        OR EXISTS(SELECT 1 FROM public.domino_participants p WHERE p.game_id = g.id AND p.user_id = auth.uid())
        OR public.is_admin()
      )
  )
$function$;

CREATE OR REPLACE FUNCTION public.game_online_count(_slug text)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT CASE _slug
    WHEN 'ludo'     THEN (SELECT count(*) FROM public.ludo_games     WHERE status::text IN ('waiting','playing'))
    WHEN 'domino'   THEN (SELECT count(*) FROM public.domino_games   WHERE status::text IN ('waiting','playing'))
    WHEN 'fanorona' THEN (SELECT count(*) FROM public.fanorona_games WHERE status::text IN ('waiting','playing'))
    WHEN 'chess'    THEN (SELECT count(*) FROM public.chess_games    WHERE status::text IN ('waiting','playing'))
    WHEN 'rami'     THEN (SELECT count(*) FROM public.rami_games     WHERE status::text IN ('waiting','playing'))
    WHEN 'poker'    THEN (SELECT count(*) FROM public.poker_games    WHERE status IN ('waiting','playing'))
    ELSE 0
  END;
$function$;

-- Note: list_live_games, weekly_top_winners, leaderboard_winners,
-- and list_public_open_games are also recreated but are large functions.
-- They are applied directly to the database via the management API.
-- See the full ALL_IN_ONE.sql for their complete definitions.

-- ============================================================
-- STEP 3: Recreate domino triggers
-- ============================================================

DROP TRIGGER IF EXISTS domino_apply_turn_timer ON public.domino_games;
CREATE TRIGGER domino_apply_turn_timer
  BEFORE INSERT OR UPDATE OF turn_deadline ON public.domino_games
  FOR EACH ROW EXECUTE FUNCTION _domino_apply_turn_timer();

DROP TRIGGER IF EXISTS trg_apply_commission ON public.domino_games;
CREATE TRIGGER trg_apply_commission
  BEFORE INSERT ON public.domino_games
  FOR EACH ROW EXECUTE FUNCTION _apply_game_commission('domino');

DROP TRIGGER IF EXISTS trg_domino_deadline ON public.domino_games;
CREATE TRIGGER trg_domino_deadline
  BEFORE INSERT OR UPDATE ON public.domino_games
  FOR EACH ROW EXECUTE FUNCTION _set_turn_deadline();

DROP TRIGGER IF EXISTS trg_first_game_domino ON public.domino_games;
CREATE TRIGGER trg_first_game_domino
  AFTER UPDATE ON public.domino_games
  FOR EACH ROW EXECUTE FUNCTION _mark_first_game('domino');

DROP TRIGGER IF EXISTS trg_house_on_finish ON public.domino_games;
CREATE TRIGGER trg_house_on_finish
  AFTER UPDATE OF status ON public.domino_games
  FOR EACH ROW EXECUTE FUNCTION _log_house_on_finish('domino');

DROP TRIGGER IF EXISTS trg_player_stats_domino ON public.domino_games;
CREATE TRIGGER trg_player_stats_domino
  AFTER UPDATE OF status ON public.domino_games
  FOR EACH ROW EXECUTE FUNCTION _update_player_stats_on_win();

DROP TRIGGER IF EXISTS trg_skip_noop_domino ON public.domino_games;
CREATE TRIGGER trg_skip_noop_domino
  BEFORE UPDATE ON public.domino_games
  FOR EACH ROW EXECUTE FUNCTION _skip_noop_update();

DROP TRIGGER IF EXISTS trg_domino_participant_end_check ON public.domino_participants;
CREATE TRIGGER trg_domino_participant_end_check
  AFTER UPDATE ON public.domino_participants
  FOR EACH ROW EXECUTE FUNCTION _trg_domino_participant_end_check();

-- ============================================================
-- STEP 4: Recreate ludo triggers
-- ============================================================

DROP TRIGGER IF EXISTS trg_apply_commission ON public.ludo_games;
CREATE TRIGGER trg_apply_commission
  BEFORE INSERT ON public.ludo_games
  FOR EACH ROW EXECUTE FUNCTION _apply_game_commission('ludo');

DROP TRIGGER IF EXISTS trg_first_game_ludo ON public.ludo_games;
CREATE TRIGGER trg_first_game_ludo
  AFTER UPDATE ON public.ludo_games
  FOR EACH ROW EXECUTE FUNCTION _mark_first_game('ludo');

DROP TRIGGER IF EXISTS trg_house_on_finish ON public.ludo_games;
CREATE TRIGGER trg_house_on_finish
  AFTER UPDATE OF status ON public.ludo_games
  FOR EACH ROW EXECUTE FUNCTION _log_house_on_finish('ludo');

DROP TRIGGER IF EXISTS trg_ludo_ready_deadline ON public.ludo_games;
CREATE TRIGGER trg_ludo_ready_deadline
  BEFORE INSERT ON public.ludo_games
  FOR EACH ROW EXECUTE FUNCTION _ludo_set_ready_deadline();

DROP TRIGGER IF EXISTS trg_ludo_sync_turn_snapshot ON public.ludo_games;
CREATE TRIGGER trg_ludo_sync_turn_snapshot
  BEFORE INSERT OR UPDATE OF state ON public.ludo_games
  FOR EACH ROW EXECUTE FUNCTION _ludo_sync_turn_snapshot();

DROP TRIGGER IF EXISTS trg_skip_noop_ludo ON public.ludo_games;
CREATE TRIGGER trg_skip_noop_ludo
  BEFORE UPDATE ON public.ludo_games
  FOR EACH ROW EXECUTE FUNCTION _skip_noop_update();

DROP TRIGGER IF EXISTS trg_tourn_launch_after_finish ON public.ludo_games;
CREATE TRIGGER trg_tourn_launch_after_finish
  AFTER UPDATE OF status ON public.ludo_games
  FOR EACH ROW EXECUTE FUNCTION _tourn_launch_after_finish();

DROP TRIGGER IF EXISTS trg_ludo_participant_end_check ON public.ludo_participants;
CREATE TRIGGER trg_ludo_participant_end_check
  AFTER UPDATE ON public.ludo_participants
  FOR EACH ROW EXECUTE FUNCTION _trg_ludo_participant_end_check();

-- ============================================================
-- STEP 5: Recreate the 4 large SQL functions that were dropped
-- (list_live_games, weekly_top_winners, leaderboard_winners, list_public_open_games)
-- These are applied via the management API directly.
-- ============================================================

-- list_live_games
CREATE OR REPLACE FUNCTION public.list_live_games()
 RETURNS TABLE(id uuid, max_players integer, stake numeric, pot numeric, players_count integer, spectators_count integer, started_at timestamp with time zone, mode text, game_type text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT g.id, g.max_players, g.stake, g.pot,
    (SELECT count(*)::int FROM public.ludo_participants p WHERE p.game_id=g.id),
    (SELECT count(*)::int FROM public.game_spectators s WHERE s.game_id=g.id),
    g.started_at, COALESCE(g.mode,'classic')::text, 'ludo'::text
  FROM public.ludo_games g
  WHERE g.status='playing'
    AND NOT (COALESCE(g.paused,FALSE) AND EXISTS (
      SELECT 1 FROM public.ludo_participants pp WHERE pp.game_id=g.id AND pp.is_bot=TRUE
    ))
  UNION ALL
  SELECT g.id, g.max_players, g.stake, g.pot,
    (SELECT count(*)::int FROM public.domino_participants p WHERE p.game_id=g.id),
    (SELECT count(*)::int FROM public.game_spectators s WHERE s.game_id=g.id),
    g.started_at, COALESCE(g.mode,'classic')::text, 'domino'::text
  FROM public.domino_games g
  WHERE g.status='playing'
    AND NOT (COALESCE(g.paused,FALSE) AND EXISTS (
      SELECT 1 FROM public.domino_participants pp WHERE pp.game_id=g.id AND pp.is_bot=TRUE
    ))
  UNION ALL
  SELECT g.id, 2, g.stake, g.pot, 2,
    (SELECT count(*)::int FROM public.game_spectators s WHERE s.game_id=g.id),
    g.started_at, 'classic'::text, 'chess'::text
  FROM public.chess_games g
  WHERE g.status='playing'
    AND NOT (COALESCE(g.paused,FALSE) AND EXISTS (
      SELECT 1 FROM public.profiles pr
       WHERE pr.id IN (g.white_id, g.black_id) AND COALESCE(pr.is_bot,FALSE)=TRUE
    ))
  UNION ALL
  SELECT g.id, g.max_players, g.stake, g.pot,
    (SELECT count(*)::int FROM public.rami_participants p WHERE p.game_id=g.id),
    (SELECT count(*)::int FROM public.game_spectators s WHERE s.game_id=g.id),
    g.started_at, COALESCE(g.joker_mode,'classique')::text, 'rami'::text
  FROM public.rami_games g
  WHERE g.status='playing'
    AND NOT (COALESCE(g.paused,FALSE) AND EXISTS (
      SELECT 1 FROM public.rami_participants pp WHERE pp.game_id=g.id AND pp.is_bot=TRUE
    ))
  ORDER BY 6 DESC, 7 ASC;
$function$
;


-- weekly_top_winners
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
$function$
;


-- leaderboard_winners
CREATE OR REPLACE FUNCTION public.leaderboard_winners(_period text DEFAULT 'all'::text, _limit integer DEFAULT 20, _slug text DEFAULT NULL::text)
 RETURNS TABLE(rank integer, user_id uuid, name text, avatar_url text, wins bigint, total_won numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH bound AS (
    SELECT CASE _period
      WHEN 'week'  THEN now() - interval '7 days'
      WHEN 'month' THEN now() - interval '30 days'
      ELSE 'epoch'::timestamptz
    END AS since
  ),
  raw AS (
    SELECT g.winner_id AS uid, NULLIF(trim(pp.display_name),'') AS dn,
           g.pot * (1 - g.commission_pct/100.0) AS won
      FROM ludo_games g JOIN ludo_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'ludo')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0)
      FROM domino_games g JOIN domino_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'domino')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0)
      FROM fanorona_games g JOIN fanorona_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'fanorona')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0)
      FROM rami_games g JOIN rami_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'rami')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULL::text,
           g.stake * 2 * (1 - COALESCE((SELECT commission_pct FROM app_settings WHERE id=1),0)/100.0)
      FROM chess_games g, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'chess')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULLIF(trim(pp.bot_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0)
      FROM poker_games g JOIN poker_players pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'poker')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
  ),
  alias_admins AS (
    SELECT DISTINCT a.admin_id AS uid FROM public.admin_aliases a
    UNION SELECT ap.admin_id FROM public.admin_persona ap
    UNION SELECT p.id FROM public.profiles p WHERE lower(p.email) = 'soavinapierrit@gmail.com'
  ),
  filtered AS (
    SELECT r.uid, r.dn, r.won,
           (r.uid IN (SELECT uid FROM alias_admins)) AS is_alias_admin
      FROM raw r
     WHERE NOT EXISTS (SELECT 1 FROM public.profiles pb WHERE pb.id = r.uid AND (pb.is_bot = true OR pb.leaderboard_hidden = true))
  ),
  kept AS (
    -- Les comptes à alias n'apparaissent JAMAIS sous leur identité réelle :
    -- seules les parties jouées sous un alias enregistré comptent, une ligne par alias.
    SELECT f.uid, f.dn, f.won, ('alias:' || f.dn) AS key
      FROM filtered f
     WHERE f.is_alias_admin
       AND f.dn IS NOT NULL
       AND EXISTS (SELECT 1 FROM public.admin_aliases a WHERE a.admin_id = f.uid AND a.pseudo = f.dn)
    UNION ALL
    SELECT f.uid, f.dn, f.won, f.uid::text
      FROM filtered f
     WHERE NOT f.is_alias_admin
  ),
  agg AS (
    SELECT key,
           MIN(uid::text)::uuid AS uid,
           COUNT(*) AS wins,
           SUM(won) AS total_won,
           MAX(dn) AS dn,
           bool_or(key LIKE 'alias:%') AS is_alias
    FROM kept
    GROUP BY key
  )
  SELECT ROW_NUMBER() OVER (ORDER BY total_won DESC NULLS LAST, wins DESC)::int AS rank,
         a.uid AS user_id,
         COALESCE(a.dn, p.pseudo, 'Joueur') AS name,
         CASE WHEN a.is_alias
              THEN (SELECT al.avatar_url FROM public.admin_aliases al WHERE al.admin_id = a.uid AND al.pseudo = a.dn LIMIT 1)
              ELSE p.avatar_url END AS avatar_url,
         a.wins,
         a.total_won
    FROM agg a
    LEFT JOIN public.profiles p ON p.id = a.uid
    ORDER BY total_won DESC NULLS LAST, wins DESC
    LIMIT LEAST(COALESCE(_limit, 20), 100);
$function$
;


-- list_public_open_games
CREATE OR REPLACE FUNCTION public.list_public_open_games()
 RETURNS TABLE(id uuid, game_slug text, max_players integer, stake numeric, pot numeric, room_code text, players_count integer, is_private boolean, created_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT g.id, 'ludo'::text, g.max_players, g.stake, g.pot, g.room_code,
    (SELECT count(*)::int FROM public.ludo_participants p WHERE p.game_id=g.id),
    g.is_private, g.created_at
  FROM public.ludo_games g
  WHERE g.status='open' AND g.is_private=false
    AND (SELECT count(*) FROM public.ludo_participants p WHERE p.game_id=g.id) < g.max_players

  UNION ALL
  SELECT g.id, 'domino', g.max_players, g.stake, g.pot, g.room_code,
    (SELECT count(*)::int FROM public.domino_participants p WHERE p.game_id=g.id),
    g.is_private, g.created_at
  FROM public.domino_games g
  WHERE g.status='open' AND g.is_private=false
    AND (SELECT count(*) FROM public.domino_participants p WHERE p.game_id=g.id) < g.max_players

  UNION ALL
  SELECT g.id, 'fanorona', 2, g.stake, g.pot, g.room_code,
    (SELECT count(*)::int FROM public.fanorona_participants p WHERE p.game_id=g.id),
    g.is_private, g.created_at
  FROM public.fanorona_games g
  WHERE g.status='open' AND g.is_private=false
    AND (SELECT count(*) FROM public.fanorona_participants p WHERE p.game_id=g.id) < 2

  UNION ALL
  SELECT g.id, 'chess', 2, g.stake, g.pot, g.room_code,
    ((CASE WHEN g.white_id IS NULL THEN 0 ELSE 1 END) + (CASE WHEN g.black_id IS NULL THEN 0 ELSE 1 END)),
    g.is_private, g.created_at
  FROM public.chess_games g
  WHERE g.status='open' AND g.is_private=false
    AND (g.white_id IS NULL OR g.black_id IS NULL)

  UNION ALL
  SELECT g.id, 'rami', g.max_players, g.stake, g.pot, g.room_code,
    (SELECT count(*)::int FROM public.rami_participants p WHERE p.game_id=g.id),
    g.is_private, g.created_at
  FROM public.rami_games g
  WHERE g.status='open' AND g.is_private=false
    AND (SELECT count(*) FROM public.rami_participants p WHERE p.game_id=g.id) < g.max_players

  UNION ALL
  SELECT g.id, 'poker', g.max_players, g.stake, g.pot, g.room_code,
    (SELECT count(*)::int FROM public.poker_players p WHERE p.game_id=g.id),
    g.is_private, g.created_at
  FROM public.poker_games g
  WHERE g.status='open' AND g.is_private=false
    AND (SELECT count(*) FROM public.poker_players p WHERE p.game_id=g.id) < g.max_players

  ORDER BY created_at DESC;
$function$
;

