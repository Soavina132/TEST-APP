-- Fix: security_lockdown (20260814230000) revoked EXECUTE on internal functions
-- from authenticated, but these functions are used in RLS policies.
-- Without EXECUTE privilege, RLS policy evaluation fails with permission error,
-- making ludo_games, ludo_participants, and all chat tables unreadable.
-- Symptom: "le plateau ne s'affiche pas" + chat cassé sur tous les jeux.

-- Restore EXECUTE on functions used by RLS policies
GRANT EXECUTE ON FUNCTION public._game_visible(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public._is_game_participant(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public._domino_visible(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public._fanorona_visible(uuid) TO authenticated;
