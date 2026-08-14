-- SECURITY PHASE 2: RLS policies, table access control, function fixes

-- A. REVOKE dangerous functions from anon+authenticated
REVOKE EXECUTE ON FUNCTION public.create_game_2p(text, text, numeric, numeric, boolean, text) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.join_game_2p(text, text, uuid) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.finish_game_2p(text, uuid, uuid) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.refund_game(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.finish_game(uuid, uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_game(integer, numeric) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_game(integer, numeric, text) FROM anon;

-- B. Drop dangerous UPDATE policies (qual=true = anyone can modify)
DROP POLICY IF EXISTS domino_games_update ON public.domino_games;
DROP POLICY IF EXISTS domino_participants_update ON public.domino_participants;
DROP POLICY IF EXISTS billiard_games_update ON public.billiard_games;
DROP POLICY IF EXISTS billiard_participants_update ON public.billiard_participants;

-- C. Fix deposit_transactions — admin only
DROP POLICY IF EXISTS deposit_tx_service_insert ON public.deposit_transactions;
DROP POLICY IF EXISTS deposit_tx_service_update ON public.deposit_transactions;
CREATE POLICY deposit_tx_admin_insert ON public.deposit_transactions
  FOR INSERT WITH CHECK (public.is_admin());
CREATE POLICY deposit_tx_admin_update ON public.deposit_transactions
  FOR UPDATE USING (public.is_admin()) WITH CHECK (public.is_admin());

-- D. Drop direct INSERT on game tables — force through RPC functions
DROP POLICY IF EXISTS chess_games_insert ON public.chess_games;
DROP POLICY IF EXISTS domino_games_insert ON public.domino_games;
DROP POLICY IF EXISTS billiard_games_insert ON public.billiard_games;
DROP POLICY IF EXISTS domino_participants_insert ON public.domino_participants;
DROP POLICY IF EXISTS billiard_participants_insert ON public.billiard_participants;

-- E. Enable RLS on tables without it
ALTER TABLE public.ludo_participants ENABLE ROW LEVEL SECURITY;
CREATE POLICY ludo_parts_select ON public.ludo_participants
  FOR SELECT USING (public._game_visible(game_id));

ALTER TABLE public.ludo_move_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY ludo_move_history_select ON public.ludo_move_history
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.ludo_participants p
     WHERE p.game_id = ludo_move_history.game_id AND p.user_id = auth.uid())
    OR public.is_admin()
  );

ALTER TABLE public.petanque_games ENABLE ROW LEVEL SECURITY;
CREATE POLICY petanque_games_select ON public.petanque_games
  FOR SELECT USING (
    (status IN ('open', 'playing') AND is_private = false)
    OR creator_id = auth.uid()
    OR public.is_admin()
  );

ALTER TABLE public.petanque_participants ENABLE ROW LEVEL SECURITY;
CREATE POLICY petanque_parts_select ON public.petanque_participants
  FOR SELECT USING (
    user_id = auth.uid() OR public.is_admin()
  );

ALTER TABLE public.petanque_boules ENABLE ROW LEVEL SECURITY;
CREATE POLICY petanque_boules_select ON public.petanque_boules
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.petanque_games pg
     WHERE pg.id = petanque_boules.game_id AND (pg.is_private = false OR pg.creator_id = auth.uid()))
    OR public.is_admin()
  );

-- F. Add missing SELECT policies on financial tables
DROP POLICY IF EXISTS withdrawals_select_own ON public.withdrawals;
CREATE POLICY withdrawals_select_own ON public.withdrawals
  FOR SELECT USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS deposits_select_own ON public.deposits;
CREATE POLICY deposits_select_own ON public.deposits
  FOR SELECT USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS house_ledger_admin_select ON public.house_ledger;
CREATE POLICY house_ledger_admin_select ON public.house_ledger
  FOR SELECT USING (public.is_admin());

DROP POLICY IF EXISTS balance_audit_log_admin_select ON public.balance_audit_log;
CREATE POLICY balance_audit_log_admin_select ON public.balance_audit_log
  FOR SELECT USING (public.is_admin());
