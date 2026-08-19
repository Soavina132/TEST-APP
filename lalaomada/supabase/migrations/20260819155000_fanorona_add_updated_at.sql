-- Migration: 20260819155000_fanorona_add_updated_at
-- Fix: La table fanorona_games n'avait pas de colonne updated_at.
-- Le guard realtime du frontend (newUpdated < prevUpdated) ne pouvait pas
-- filtrer les events stale → le heartbeat (10s) écrasait l'état optimiste
-- avec l'ancien board → pion capturé réapparaissait, bot se bloquait.
--
-- Solution: ajouter updated_at + trigger BEFORE UPDATE qui set now().
-- Identique à ce qui a été fait pour domino_games.

ALTER TABLE public.fanorona_games
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE OR REPLACE FUNCTION public.set_fanorona_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fanorona_set_updated_at ON public.fanorona_games;
CREATE TRIGGER trg_fanorona_set_updated_at
  BEFORE UPDATE ON public.fanorona_games
  FOR EACH ROW
  EXECUTE FUNCTION public.set_fanorona_updated_at();
