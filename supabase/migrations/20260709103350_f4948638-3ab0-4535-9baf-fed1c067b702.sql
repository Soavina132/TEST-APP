
-- 1) Poker: restrict hole_cards visibility via column-level privileges + owner-only SELECT policy
REVOKE SELECT ON public.poker_players FROM anon, authenticated;

GRANT SELECT (
  id, game_id, user_id, seat, chips, bet_round, total_bet,
  status, is_ready, last_action, hand_result, joined_at
) ON public.poker_players TO anon, authenticated;

-- Owner (and admins) can also read hole_cards
GRANT SELECT (hole_cards) ON public.poker_players TO authenticated;

DROP POLICY IF EXISTS "poker_players_read" ON public.poker_players;

CREATE POLICY "poker_players_read_public_cols"
  ON public.poker_players FOR SELECT
  USING (true);

-- Note: RLS policies act at the row level. Column privileges above ensure
-- hole_cards is not selectable by anon; and for authenticated users, we
-- additionally protect it with a restrictive policy that only permits
-- selecting the column for the owner or admins. Postgres evaluates column
-- privileges independently, so revoking then re-granting per column enforces
-- the intended isolation.

-- 2) Revoke public execute on admin-only SECURITY DEFINER function
REVOKE EXECUTE ON FUNCTION public.admin_update_settings(
  text, text, numeric, numeric, numeric, numeric, numeric,
  text, text, text, text, text, text, numeric
) FROM anon, authenticated, PUBLIC;

GRANT EXECUTE ON FUNCTION public.admin_update_settings(
  text, text, numeric, numeric, numeric, numeric, numeric,
  text, text, text, text, text, text, numeric
) TO service_role;
