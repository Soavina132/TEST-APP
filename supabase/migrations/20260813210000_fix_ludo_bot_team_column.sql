-- ============================================================
-- FIX CRITIQUE: ludo_bot_play plante car colonne "team" inexistante
--
-- Bug: ludo_bot_play fait SELECT ... team FROM ludo_participants
-- mais la colonne team n'a jamais ete ajoutee a la table.
-- Resultat: le bot ne joue JAMAIS, ludo_tick_all avale l'erreur.
--
-- Fix: Ajouter la colonne team (nullable, utilisee pour matchs groupe)
-- ============================================================

ALTER TABLE public.ludo_participants 
  ADD COLUMN IF NOT EXISTS team INT;

-- L'equipe est NULL pour les matchs solo/normaux, 
-- un entier pour les matchs groupe (1v1v1v1 -> equipe = slot)
