-- ============================================================
-- FIX: Rend les échecs serveur-autoritaire (sécurité argent réel)
--
-- Les anciennes fonctions RPC (chess_play, chess_bot_play, chess_finish)
-- sont remplacées par des stubs qui forcent l'utilisation de l'Edge Function
-- chess-validate-move qui valide les coups avec chess.js côté serveur.
--
-- RLS policies restrictives:
-- - chess_moves: INSERT supprimé (coups via Edge Function uniquement)
-- - chess_games: UPDATE supprimé (updates via SECURITY DEFINER uniquement)
-- ============================================================

CREATE OR REPLACE FUNCTION public.chess_play(_id uuid, _uci text, _san text, _fen_after text, _elapsed_ms integer DEFAULT 0)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RAISE EXCEPTION 'Use the Edge Function chess-validate-move to play moves';
END $$;

CREATE OR REPLACE FUNCTION public.chess_bot_play(_id uuid, _uci text, _san text, _fen_after text, _elapsed_ms integer DEFAULT 0)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RAISE EXCEPTION 'Use the Edge Function chess-validate-move to play bot moves';
END $$;

CREATE OR REPLACE FUNCTION public.chess_finish(_id uuid, _winner uuid, _draw boolean, _reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RAISE EXCEPTION 'Use the Edge Function chess-validate-move to finish games';
END $$;

DROP POLICY IF EXISTS chess_moves_insert ON public.chess_moves;
DROP POLICY IF EXISTS chess_games_update ON public.chess_games;
