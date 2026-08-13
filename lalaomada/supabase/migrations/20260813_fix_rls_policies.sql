-- Migration: Fix RLS policies — tables with RLS enabled but no SELECT policies
-- Date: 2026-08-13
-- Problem: RLS was enabled on ludo_games, ludo_participants, and 22 other tables
--          but NO policies existed. With RLS enabled and no policies, ALL access
--          is denied by default. The frontend couldn't read game data even though
--          RPC functions (SECURITY DEFINER) could create games.
--          Symptom: "Le ludo apparaît sur le live mais on ne voit pas sur le frontend"
-- Fix: Add SELECT policies for authenticated users on all game/chat tables.

-- ── Ludo (critical — main bug) ──
CREATE POLICY IF NOT EXISTS "ludo_games_select" ON public.ludo_games
  FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY IF NOT EXISTS "ludo_participants_select" ON public.ludo_participants
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- ── Fanorona (same issue) ──
CREATE POLICY IF NOT EXISTS "fanorona_games_select" ON public.fanorona_games
  FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY IF NOT EXISTS "fanorona_participants_select" ON public.fanorona_participants
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- ── Chat (used by GameSocialFab in game pages) ──
CREATE POLICY IF NOT EXISTS "chat_rooms_select" ON public.chat_rooms
  FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY IF NOT EXISTS "messages_select" ON public.messages
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- ── Tournament tables ──
CREATE POLICY IF NOT EXISTS "poker_tournament_tables_select" ON public.poker_tournament_tables
  FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY IF NOT EXISTS "poker_tournament_blind_levels_select" ON public.poker_tournament_blind_levels
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- ── User-facing tables ──
CREATE POLICY IF NOT EXISTS "achievements_select" ON public.achievements
  FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY IF NOT EXISTS "referral_settings_select" ON public.referral_settings
  FOR SELECT USING (auth.uid() IS NOT NULL);
