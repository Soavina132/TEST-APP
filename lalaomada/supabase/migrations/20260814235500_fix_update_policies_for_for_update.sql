-- ============================================================
-- FIX: Politiques UPDATE manquantes pour SELECT ... FOR UPDATE
-- Les fonctions non-SECURITY DEFINER utilisant FOR UPDATE
-- nécessitent une politique UPDATE sur la table cible.
-- Sans politique UPDATE → default-deny → "Partie introuvable"
-- ============================================================

-- ============================================================
-- 1. LUDO_GAMES — le plus critique (ludo_roll, ludo_move, etc.)
-- ============================================================
CREATE POLICY ludo_games_update ON public.ludo_games
  FOR UPDATE TO authenticated
  USING (
    host_id = auth.uid()
    OR public._is_game_participant(id, auth.uid())
    OR public.is_admin()
  )
  WITH CHECK (
    host_id = auth.uid()
    OR public._is_game_participant(id, auth.uid())
    OR public.is_admin()
  );

-- ============================================================
-- 2. PETANQUE_GAMES
-- ============================================================
CREATE POLICY petanque_games_update ON public.petanque_games
  FOR UPDATE TO authenticated
  USING (
    creator_id = auth.uid()
    OR public.is_admin()
  )
  WITH CHECK (
    creator_id = auth.uid()
    OR public.is_admin()
  );

-- ============================================================
-- 3. TOURNAMENTS
-- ============================================================
CREATE POLICY tournaments_update ON public.tournaments
  FOR UPDATE TO authenticated
  USING (true)
  WITH CHECK (true);

-- ============================================================
-- 4. AUTRES TABLES DE JEUX (préventif)
--    Au cas où des fonctions non-SECURITY DEFINER utilisent
--    FOR UPDATE sur ces tables
-- ============================================================

-- Domino
CREATE POLICY domino_games_update ON public.domino_games
  FOR UPDATE TO authenticated
  USING (
    host_id = auth.uid()
    OR public._is_domino_participant(id, auth.uid())
    OR public.is_admin()
  )
  WITH CHECK (
    host_id = auth.uid()
    OR public._is_domino_participant(id, auth.uid())
    OR public.is_admin()
  );

-- Fanorona
CREATE POLICY fanorona_games_update ON public.fanorona_games
  FOR UPDATE TO authenticated
  USING (
    host_id = auth.uid()
    OR public._is_fanorona_participant(id, auth.uid())
    OR public.is_admin()
  )
  WITH CHECK (
    host_id = auth.uid()
    OR public._is_fanorona_participant(id, auth.uid())
    OR public.is_admin()
  );

-- Poker
CREATE POLICY poker_games_update ON public.poker_games
  FOR UPDATE TO authenticated
  USING (
    created_by = auth.uid()
    OR public._is_poker_participant(id, auth.uid())
    OR public.is_admin()
  )
  WITH CHECK (
    created_by = auth.uid()
    OR public._is_poker_participant(id, auth.uid())
    OR public.is_admin()
  );

-- Rami
CREATE POLICY rami_games_update ON public.rami_games
  FOR UPDATE TO authenticated
  USING (
    created_by = auth.uid()
    OR public._is_rami_participant(id, auth.uid())
    OR public.is_admin()
  )
  WITH CHECK (
    created_by = auth.uid()
    OR public._is_rami_participant(id, auth.uid())
    OR public.is_admin()
  );

-- Billiard
CREATE POLICY billiard_games_update ON public.billiard_games
  FOR UPDATE TO authenticated
  USING (
    host_id = auth.uid()
    OR public.is_admin()
  )
  WITH CHECK (
    host_id = auth.uid()
    OR public.is_admin()
  );

-- ============================================================
-- 5. TABLES PARTICIPANTS (pour UPDATE aussi)
-- ============================================================

CREATE POLICY ludo_participants_update ON public.ludo_participants
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid() OR public.is_admin())
  WITH CHECK (user_id = auth.uid() OR public.is_admin());

CREATE POLICY domino_participants_update ON public.domino_participants
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid() OR public.is_admin())
  WITH CHECK (user_id = auth.uid() OR public.is_admin());

CREATE POLICY fanorona_participants_update ON public.fanorona_participants
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid() OR public.is_admin())
  WITH CHECK (user_id = auth.uid() OR public.is_admin());

CREATE POLICY poker_players_update ON public.poker_players
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid() OR public.is_admin())
  WITH CHECK (user_id = auth.uid() OR public.is_admin());

CREATE POLICY rami_participants_update ON public.rami_participants
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid() OR public.is_admin())
  WITH CHECK (user_id = auth.uid() OR public.is_admin());

-- Petanque participants
CREATE POLICY petanque_participants_update ON public.petanque_participants
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid() OR public.is_admin())
  WITH CHECK (user_id = auth.uid() OR public.is_admin());
