-- ============================================================
-- FIX: Récursion infinie RLS + permissions manquantes + trigger
-- ============================================================

-- ============================================================
-- 1. FONCTIONS HELPER SECURITY DEFINER (brisent la récursion)
-- ============================================================

-- Domino
CREATE OR REPLACE FUNCTION public._domino_game_visible(_game uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.domino_games g
    WHERE g.id = _game
      AND (g.is_private = false OR g.host_id = auth.uid() OR public.is_admin())
  )
$$;

CREATE OR REPLACE FUNCTION public._is_domino_participant(_game uuid, _uid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.domino_participants p
    WHERE p.game_id = _game AND p.user_id = _uid
  )
$$;

-- Poker
CREATE OR REPLACE FUNCTION public._poker_game_visible(_game uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.poker_games g
    WHERE g.id = _game
      AND (g.is_private = false OR g.created_by = auth.uid() OR public.is_admin())
  )
$$;

CREATE OR REPLACE FUNCTION public._is_poker_participant(_game uuid, _uid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.poker_players p
    WHERE p.game_id = _game AND p.user_id = _uid
  )
$$;

-- Rami
CREATE OR REPLACE FUNCTION public._rami_game_visible(_game uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.rami_games g
    WHERE g.id = _game
      AND (g.is_private = false OR g.created_by = auth.uid() OR public.is_admin())
  )
$$;

CREATE OR REPLACE FUNCTION public._is_rami_participant(_game uuid, _uid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.rami_participants p
    WHERE p.game_id = _game AND p.user_id = _uid
  )
$$;

-- Fanorona
CREATE OR REPLACE FUNCTION public._fanorona_game_visible(_game uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.fanorona_games g
    WHERE g.id = _game
      AND (g.is_private = false OR g.host_id = auth.uid() OR public.is_admin())
  )
$$;

CREATE OR REPLACE FUNCTION public._is_fanorona_participant(_game uuid, _uid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.fanorona_participants p
    WHERE p.game_id = _game AND p.user_id = _uid
  )
$$;

-- Chess
CREATE OR REPLACE FUNCTION public._chess_game_visible(_game uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.chess_games g
    WHERE g.id = _game
      AND (g.is_private = false OR g.host_id = auth.uid()
           OR g.white_id = auth.uid() OR g.black_id = auth.uid()
           OR public.is_admin())
  )
$$;

-- ============================================================
-- 2. REMPLACER LES POLITIQUES RÉCURSIVES
-- ============================================================

-- Domino games
DROP POLICY IF EXISTS domino_games_select ON public.domino_games;
CREATE POLICY domino_games_select ON public.domino_games
  FOR SELECT USING (
    (is_private = false AND status IN ('open','playing'))
    OR host_id = auth.uid()
    OR public._is_domino_participant(id, auth.uid())
    OR public.is_admin()
  );

-- Domino participants
DROP POLICY IF EXISTS domino_participants_select ON public.domino_participants;
CREATE POLICY domino_participants_select ON public.domino_participants
  FOR SELECT USING (
    user_id = auth.uid()
    OR public._domino_game_visible(game_id)
  );

-- Poker games
DROP POLICY IF EXISTS poker_games_read ON public.poker_games;
CREATE POLICY poker_games_read ON public.poker_games
  FOR SELECT USING (
    is_private = false
    OR created_by = auth.uid()
    OR public._is_poker_participant(id, auth.uid())
    OR public.is_admin()
  );

-- Poker players
DROP POLICY IF EXISTS poker_players_read ON public.poker_players;
CREATE POLICY poker_players_read ON public.poker_players
  FOR SELECT USING (
    user_id = auth.uid()
    OR public._poker_game_visible(game_id)
  );

-- Rami games
DROP POLICY IF EXISTS rami_games_select ON public.rami_games;
CREATE POLICY rami_games_select ON public.rami_games
  FOR SELECT USING (
    is_private = false
    OR created_by = auth.uid()
    OR public._is_rami_participant(id, auth.uid())
    OR public.is_admin()
  );

-- Rami participants
DROP POLICY IF EXISTS rami_participants_select ON public.rami_participants;
CREATE POLICY rami_participants_select ON public.rami_participants
  FOR SELECT USING (
    user_id = auth.uid()
    OR public._rami_game_visible(game_id)
  );

-- Fanorona games
DROP POLICY IF EXISTS fanorona_games_select ON public.fanorona_games;
CREATE POLICY fanorona_games_select ON public.fanorona_games
  FOR SELECT USING (
    (is_private = false AND status IN ('open','playing'))
    OR host_id = auth.uid()
    OR public._is_fanorona_participant(id, auth.uid())
    OR public.is_admin()
  );

-- Fanorona participants
DROP POLICY IF EXISTS fanorona_participants_select ON public.fanorona_participants;
CREATE POLICY fanorona_participants_select ON public.fanorona_participants
  FOR SELECT USING (
    user_id = auth.uid()
    OR public._fanorona_game_visible(game_id)
  );

-- Chess games
DROP POLICY IF EXISTS chess_games_select ON public.chess_games;
CREATE POLICY chess_games_select ON public.chess_games
  FOR SELECT USING (
    is_private = false
    OR host_id = auth.uid()
    OR white_id = auth.uid()
    OR black_id = auth.uid()
    OR public.is_admin()
  );

-- ============================================================
-- 3. GRANT EXECUTE sur toutes les fonctions helper
-- ============================================================

GRANT EXECUTE ON FUNCTION public._domino_game_visible(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public._is_domino_participant(uuid, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public._poker_game_visible(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public._is_poker_participant(uuid, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public._rami_game_visible(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public._is_rami_participant(uuid, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public._fanorona_game_visible(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public._is_fanorona_participant(uuid, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public._chess_game_visible(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public._game_visible(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public._is_game_participant(uuid, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin() TO anon, authenticated;

-- ============================================================
-- 4. FIX TRIGGER _protect_profile_fields
-- ============================================================

CREATE OR REPLACE FUNCTION public._protect_profile_fields()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN
  IF current_user = 'postgres' THEN
    RETURN NEW;
  END IF;

  IF auth.uid() = NEW.id AND NOT public.is_admin() THEN
    NEW.balance_ar := OLD.balance_ar;
    NEW.is_admin := OLD.is_admin;
    NEW.is_bot := OLD.is_bot;
    NEW.status := OLD.status;
    NEW.unique_code := OLD.unique_code;
    NEW.referral_code := OLD.referral_code;
    NEW.referral_unlocked := OLD.referral_unlocked;
    NEW.phone_verified := OLD.phone_verified;
    NEW.banned := OLD.banned;
    NEW.referred_by := OLD.referred_by;
    NEW.phone_verification_code := OLD.phone_verification_code;
    NEW.phone_verification_code_hash := OLD.phone_verification_code_hash;
    NEW.phone_verification_requested_at := OLD.phone_verification_requested_at;
    IF OLD.phone_verified = false THEN
      NEW.phone := OLD.phone;
    END IF;
  END IF;
  RETURN NEW;
END $function$;

-- ============================================================
-- 5. POLITIQUES INSERT POUR LES TABLES DE JEUX
-- ============================================================

CREATE POLICY chess_games_self_update ON public.chess_games
  FOR UPDATE TO authenticated
  USING (host_id = auth.uid() OR white_id = auth.uid() OR black_id = auth.uid())
  WITH CHECK (host_id = auth.uid() OR white_id = auth.uid() OR black_id = auth.uid());

CREATE POLICY domino_games_insert ON public.domino_games
  FOR INSERT TO authenticated WITH CHECK (host_id = auth.uid());

CREATE POLICY domino_participants_insert ON public.domino_participants
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

CREATE POLICY fanorona_games_insert ON public.fanorona_games
  FOR INSERT TO authenticated WITH CHECK (host_id = auth.uid());

CREATE POLICY fanorona_participants_insert ON public.fanorona_participants
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

CREATE POLICY chess_games_insert ON public.chess_games
  FOR INSERT TO authenticated WITH CHECK (host_id = auth.uid());

CREATE POLICY poker_games_insert ON public.poker_games
  FOR INSERT TO authenticated WITH CHECK (created_by = auth.uid());

CREATE POLICY poker_players_insert ON public.poker_players
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

CREATE POLICY rami_games_insert ON public.rami_games
  FOR INSERT TO authenticated WITH CHECK (created_by = auth.uid());

CREATE POLICY rami_participants_insert ON public.rami_participants
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

-- ============================================================
-- 6. GRANT EXECUTE sur fonctions RPC révoquées à tort
-- ============================================================

GRANT EXECUTE ON FUNCTION public.cleanup_stale_open_games() TO authenticated;
GRANT EXECUTE ON FUNCTION public.refund_game(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chess_auto_timeout(uuid) TO authenticated;
