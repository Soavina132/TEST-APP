-- ═══════════════════════════════════════════════════════════════════════
-- NEW: admin_tournament_set_timers — update all timer settings at once
-- + default timing: 30min match, 10min prep, 5min lobby
-- ═══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_tournament_set_timers(
  _tid uuid,
  _match_duration_secs integer DEFAULT NULL,
  _break_secs integer DEFAULT NULL,
  _lobby_mins integer DEFAULT NULL,
  _check_in_mins integer DEFAULT NULL,
  _max_concurrent integer DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin uniquement'; END IF;

  UPDATE public.tournaments SET
    max_match_duration_secs = COALESCE(_match_duration_secs, max_match_duration_secs),
    break_seconds = COALESCE(_break_secs, break_seconds),
    lobby_minutes = COALESCE(_lobby_mins, lobby_minutes),
    check_in_minutes = COALESCE(_check_in_mins, check_in_minutes),
    max_concurrent_matches = COALESCE(_max_concurrent, max_concurrent_matches)
  WHERE id = _tid;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_tournament_set_timers(uuid, integer, integer, integer, integer, integer) TO authenticated;

-- Set sensible defaults for future tournaments
UPDATE public.tournaments
   SET max_match_duration_secs = COALESCE(max_match_duration_secs, 1800),  -- 30 min
       break_seconds = COALESCE(break_seconds, 600),                         -- 10 min
       lobby_minutes = COALESCE(lobby_minutes, 5),                          -- 5 min
       check_in_minutes = COALESCE(check_in_minutes, 15)                    -- 15 min
 WHERE max_match_duration_secs IS NULL OR break_seconds IS NULL OR lobby_minutes IS NULL;
