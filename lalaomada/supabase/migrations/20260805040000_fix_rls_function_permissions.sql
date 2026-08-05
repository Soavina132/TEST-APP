-- Fix: Grant EXECUTE on RLS helper functions to authenticated and anon roles
-- These functions are used in RLS policies but were missing EXECUTE permissions,
-- causing "permission denied for function" errors on ALL queries to ludo_games,
-- fanorona_games, ludo_participants, fanorona_participants, and game_spectators.
-- This resulted in the game pages being stuck in infinite loading.

GRANT EXECUTE ON FUNCTION public._is_game_participant(uuid, uuid) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public._game_visible(uuid) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public._fanorona_is_player(uuid) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public._game_cfg(text) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public._apply_game_commission() TO authenticated, anon;

-- Also grant on other internal functions used by triggers or RLS that
-- authenticated/anon might need to call indirectly
GRANT EXECUTE ON FUNCTION public._auto_cancel_open_games() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public._auto_resume_paused_games() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public._end_bot_only_games() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public._game_resume_internal(uuid) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public._mark_first_game(uuid) TO authenticated, anon;
