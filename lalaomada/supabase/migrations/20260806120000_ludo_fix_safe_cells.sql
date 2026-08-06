-- ═══════════════════════════════════════════════════════════════════
-- Fix CRITIQUE : _ludo_is_safe désynchronisée avec le frontend
--
-- PROBLÈME :
--   Backend _ludo_is_safe : 4 cellules  → (0, 13, 26, 39)
--   Frontend SAFE_PATH_IDX : 8 cellules → (0, 8, 13, 21, 26, 34, 39, 47)
--
--   Conséquence : un pion sur une cellule étoile (8, 21, 34, 47) est
--   considéré "safe" visuellement mais peut être capturé par le backend.
--   Les joueurs voient leur pion "protégé" se faire manger.
--
-- FIX : Aligner le backend sur les 8 cellules safe du frontend.
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._ludo_is_safe(_idx INT)
RETURNS BOOLEAN
LANGUAGE sql IMMUTABLE
AS $$ SELECT _idx IN (0, 8, 13, 21, 26, 34, 39, 47) $$;
