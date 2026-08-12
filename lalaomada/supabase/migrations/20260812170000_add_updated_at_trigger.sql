-- Migration: 20260812170000_add_updated_at_trigger
-- Fix: La colonne updated_at n'existait pas sur domino_games.
-- Le guard realtime du frontend (newUpdated < prevUpdated) ne pouvait pas
-- filtrer les events stale → les tuiles clignotaient (retour dans la main).
--
-- Solution: ajouter updated_at + trigger BEFORE UPDATE qui set now().
-- Comme ça, chaque UPDATE (domino_play, domino_tick, etc.) a updated_at = now(),
-- et le guard realtime peut comparer les timestamps correctement.

ALTER TABLE public.domino_games
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE OR REPLACE FUNCTION public.set_domino_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_domino_set_updated_at ON public.domino_games;
CREATE TRIGGER trg_domino_set_updated_at
  BEFORE UPDATE ON public.domino_games
  FOR EACH ROW
  EXECUTE FUNCTION public.set_domino_updated_at();
