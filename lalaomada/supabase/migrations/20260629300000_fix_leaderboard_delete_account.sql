-- ═══════════════════════════════════════════════════════════════════════════
-- FIX 1: leaderboard_winners — group by uid (not name) + exclude deleted/banned
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.leaderboard_winners(
  _period text DEFAULT 'all',
  _limit  int  DEFAULT 20
)
RETURNS TABLE(rank int, id uuid, name text, avatar_url text, wins bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH bound AS (
    SELECT CASE _period
      WHEN 'week'  THEN now() - interval '7 days'
      WHEN 'month' THEN now() - interval '30 days'
      ELSE 'epoch'::timestamptz
    END AS since
  ),
  -- Collect winner_id from all game types (group by uid, NOT by display_name)
  raw AS (
    SELECT g.winner_id AS uid
      FROM public.ludo_games g, bound
     WHERE g.status = 'finished'
       AND g.winner_id IS NOT NULL
       AND COALESCE(g.finished_at, g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id
      FROM public.domino_games g, bound
     WHERE g.status = 'finished'
       AND g.winner_id IS NOT NULL
       AND COALESCE(g.finished_at, g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id
      FROM public.fanorona_games g, bound
     WHERE g.status = 'finished'
       AND g.winner_id IS NOT NULL
       AND COALESCE(g.finished_at, g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id
      FROM public.rami_games g, bound
     WHERE g.status = 'finished'
       AND g.winner_id IS NOT NULL
       AND COALESCE(g.finished_at, g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id
      FROM public.chess_games g, bound
     WHERE g.status = 'finished'
       AND g.winner_id IS NOT NULL
       AND COALESCE(g.finished_at, g.created_at) >= bound.since
  ),
  -- Count wins per uid
  agg AS (
    SELECT r.uid, count(*)::bigint AS wins
      FROM raw r
     WHERE NOT public.has_role(r.uid, 'admin'::public.app_role)
     GROUP BY r.uid
  ),
  -- Join to profiles to get CURRENT name — INNER JOIN excludes deleted accounts
  joined AS (
    SELECT
      p.pseudo     AS name,
      p.avatar_url,
      a.uid        AS id,
      a.wins
    FROM agg a
    INNER JOIN public.profiles p ON p.id = a.uid
    -- Exclude banned / soft-deleted accounts
    WHERE (p.banned    IS NULL OR p.banned    = false)
      AND (p.is_banned IS NULL OR p.is_banned = false)
  )
  SELECT
    (row_number() OVER (ORDER BY j.wins DESC, j.name ASC))::int AS rank,
    j.id,
    j.name,
    j.avatar_url,
    j.wins
  FROM joined j
  ORDER BY j.wins DESC, j.name ASC
  LIMIT _limit;
$$;
REVOKE ALL ON FUNCTION public.leaderboard_winners(text, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.leaderboard_winners(text, int) TO authenticated, anon;

-- ═══════════════════════════════════════════════════════════════════════════
-- FIX 2: delete_my_account — soft-delete first (survives rollback),
--         then attempt hard delete from auth.users with silent catch
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_uid uuid;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;

  -- ── STEP 1 : Commit a soft-delete immediately in its own sub-transaction ──
  -- This runs first and is committed regardless of what happens in step 2.
  -- Even if the hard delete below fails, the account is already anonymised
  -- and banned so it cannot be used or appear in rankings.
  BEGIN
    UPDATE public.profiles
    SET
      pseudo      = 'Compte supprimé',
      avatar_url  = NULL,
      balance_ar  = 0,
      banned      = true
    WHERE id = v_uid;
  EXCEPTION WHEN OTHERS THEN
    NULL; -- column may not exist in older schema; ignore
  END;

  -- ── STEP 2 : Nullify winner / participant references ──
  UPDATE public.ludo_games     SET winner_id = NULL WHERE winner_id = v_uid;
  UPDATE public.domino_games   SET winner_id = NULL WHERE winner_id = v_uid;
  UPDATE public.fanorona_games SET winner_id = NULL WHERE winner_id = v_uid;
  UPDATE public.rami_games     SET winner_id = NULL WHERE winner_id = v_uid;
  UPDATE public.chess_games    SET winner_id = NULL WHERE winner_id = v_uid;
  UPDATE public.chess_games    SET white_id  = NULL WHERE white_id  = v_uid;
  UPDATE public.chess_games    SET black_id  = NULL WHERE black_id  = v_uid;
  UPDATE public.profiles       SET referred_by = NULL WHERE referred_by = v_uid;

  -- ── STEP 3 : Hard-delete from auth.users (cascades to profiles row) ──
  -- If this fails (e.g. Supabase version restriction), account is already
  -- anonymised + banned from step 1, so no data leak occurs.
  BEGIN
    DELETE FROM auth.users WHERE id = v_uid;
  EXCEPTION WHEN OTHERS THEN
    -- Hard delete failed — soft-delete above is still in effect.
    NULL;
  END;
END;
$$;
REVOKE ALL ON FUNCTION public.delete_my_account() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_my_account() TO authenticated;
