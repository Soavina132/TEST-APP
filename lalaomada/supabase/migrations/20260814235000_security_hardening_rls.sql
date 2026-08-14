-- ═════════════════════════════════════════════════════════════════
-- SECURITY HARDENING — RLS & Function Permissions
-- Date: 2026-08-14
--
-- Corrige les vulnérabilités critiques identifiées dans l'audit RLS:
-- 1. REVOKE FROM PUBLIC sur fonctions financières et internes
-- 2. FORCE ROW LEVEL SECURITY sur toutes les tables
-- 3. Révocation anon sur fonctions publiques non-essentielles
-- 4. Correction des politiques RLS trop permissives
-- 5. Ajout de with_check sur UPDATE manquants
-- 6. Restriction des tournois à authenticated
-- ═════════════════════════════════════════════════════════════════

-- =========================================================
-- PHASE 1: FONCTIONS FINANCIÈRES — Révoquer PUBLIC
-- =========================================================

REVOKE EXECUTE ON FUNCTION public.credit_user_balance(uuid, numeric, text, uuid, text, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.debit_user_balance(uuid, numeric, text, uuid, text, jsonb) FROM PUBLIC;

-- =========================================================
-- PHASE 2: FORCE ROW LEVEL SECURITY sur toutes les tables
-- =========================================================

DO $$
DECLARE t text;
BEGIN
  FOR t IN SELECT tablename FROM pg_tables WHERE schemaname = 'public'
  LOOP
    EXECUTE format('ALTER TABLE public.%I FORCE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;

-- =========================================================
-- PHASE 3: RÉVOQUER PUBLIC DE TOUTES LES FONCTIONS INTERNES
-- (Le lockdown précédent utilisait FROM anon, authenticated — inefficace
--  car anon/authenticated héritent de PUBLIC)
-- =========================================================

REVOKE EXECUTE ON FUNCTION public._game_visible(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._is_game_participant(uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._admin_log(uuid, text, jsonb, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._admin_has_active_session(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._admin_notify_others(text, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._admin_security_housekeeping() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._protect_profile_fields() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._trg_balance_audit() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._guard_balance_non_negative() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._no_bot_money() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._sync_banned_flags() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.is_admin() FROM anon;
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, app_role) FROM anon;

-- =========================================================
-- PHASE 4: CORRECTION DES POLITIQUES RLS TROP PERMISSIVES
-- =========================================================

-- messages — filtrer par appartenance à la salle
DROP POLICY IF EXISTS messages_select ON public.messages;
CREATE POLICY messages_select ON public.messages
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM chat_rooms r
      WHERE r.id = messages.room_id
      AND (
        r.type = 'global'
        OR (r.type = 'dm' AND (r.dm_user_a = auth.uid() OR r.dm_user_b = auth.uid()))
        OR (r.type = 'game' AND (
          _is_game_participant(r.game_id, auth.uid())
          OR EXISTS (SELECT 1 FROM game_spectators s WHERE s.game_id = r.game_id AND s.user_id = auth.uid())
        ))
        OR is_admin()
      )
    )
  );

-- chat_rooms — filtrer par appartenance
DROP POLICY IF EXISTS chat_rooms_select ON public.chat_rooms;
CREATE POLICY chat_rooms_select ON public.chat_rooms
  FOR SELECT TO authenticated
  USING (
    (type = 'global' AND enabled = true)
    OR (type = 'dm' AND (dm_user_a = auth.uid() OR dm_user_b = auth.uid()))
    OR (type = 'game' AND (
      _is_game_participant(game_id, auth.uid())
      OR EXISTS (SELECT 1 FROM game_spectators s WHERE s.game_id = chat_rooms.game_id AND s.user_id = auth.uid())
    ))
    OR is_admin()
  );

-- chat_members — filtrer par appartenance à la salle
DROP POLICY IF EXISTS chat_members_read ON public.chat_members;
CREATE POLICY chat_members_read ON public.chat_members
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM chat_rooms r WHERE r.id = chat_members.room_id
      AND (
        r.type = 'global'
        OR (r.type = 'dm' AND (r.dm_user_a = auth.uid() OR r.dm_user_b = auth.uid()))
        OR (r.type = 'game' AND _is_game_participant(r.game_id, auth.uid()))
        OR is_admin()
      )
    )
  );

-- fanorona_participants — filtrer par visibilité du jeu (comme les autres jeux)
DROP POLICY IF EXISTS fanorona_participants_select ON public.fanorona_participants;
CREATE POLICY fanorona_participants_select ON public.fanorona_participants
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM fanorona_games g
      WHERE g.id = fanorona_participants.game_id
      AND (g.is_private = false OR g.host_id = auth.uid() OR is_admin())
    )
  );

-- =========================================================
-- PHASE 5: RESTREINDRE L'ACCÈS ANON AUX TOURNOIS
-- =========================================================

DROP POLICY IF EXISTS t_read ON public.tournaments;
CREATE POLICY t_read ON public.tournaments FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS te_read ON public.tournament_entrants;
CREATE POLICY te_read ON public.tournament_entrants FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS tm_read ON public.tournament_matches;
CREATE POLICY tm_read ON public.tournament_matches FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS tp_read ON public.tournament_pools;
CREATE POLICY tp_read ON public.tournament_pools FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS tpe_read ON public.tournament_pool_entrants;
CREATE POLICY tpe_read ON public.tournament_pool_entrants FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS tw_read ON public.tournament_waitlist;
CREATE POLICY tw_read ON public.tournament_waitlist FOR SELECT TO authenticated USING (true);

-- =========================================================
-- PHASE 6: AJOUTER with_check AUX POLITIQUES UPDATE
-- =========================================================

-- friendships
DROP POLICY IF EXISTS friendships_update_involved ON public.friendships;
CREATE POLICY friendships_update_involved ON public.friendships
  FOR UPDATE TO authenticated
  USING (auth.uid() = requester_id OR auth.uid() = addressee_id)
  WITH CHECK (auth.uid() = requester_id OR auth.uid() = addressee_id);

-- game_invitations
DROP POLICY IF EXISTS gi_update_involved ON public.game_invitations;
CREATE POLICY gi_update_involved ON public.game_invitations
  FOR UPDATE TO authenticated
  USING (auth.uid() = sender_id OR auth.uid() = receiver_id)
  WITH CHECK (auth.uid() = sender_id OR auth.uid() = receiver_id);

-- push_subscriptions
DROP POLICY IF EXISTS "Users can update own push subs" ON public.push_subscriptions;
CREATE POLICY "Users can update own push subs" ON public.push_subscriptions
  FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- push_tokens
DROP POLICY IF EXISTS "Users can update own push tokens" ON public.push_tokens;
CREATE POLICY "Users can update own push tokens" ON public.push_tokens
  FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
