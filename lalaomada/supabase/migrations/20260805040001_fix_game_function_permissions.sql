-- Fix: Grant EXECUTE on game functions called directly from the frontend
-- These functions were only executable by postgres/service_role, causing
-- "permission denied for function X" errors when the frontend called them
-- via supabase.rpc(). This blocked bot moves, timeout checks, and stale
-- game cleanup across ALL games (Fanorona, Domino, Ludo, Chess, Rami, Pétanque).

-- Bot play functions (called from frontend after bot's turn)
GRANT EXECUTE ON FUNCTION public.fanorona_bot_play(uuid) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.petanque_bot_step(uuid) TO authenticated, anon;

-- Tick / timeout functions (called from frontend to check game state)
GRANT EXECUTE ON FUNCTION public.fanorona_tick(uuid) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.chess_tick(uuid) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.domino_tick(uuid) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.ludo_check_timeout(uuid) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.rami_tick(uuid) TO authenticated, anon;

-- Cleanup functions (called from frontend lobby pages)
GRANT EXECUTE ON FUNCTION public.cleanup_stale_open_games() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.ludo_purge_unready_rooms() TO authenticated, anon;
