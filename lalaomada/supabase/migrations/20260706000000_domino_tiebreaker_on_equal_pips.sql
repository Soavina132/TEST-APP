-- ─────────────────────────────────────────────────────────────────────────────
-- Fix: Domino blocked game with equal pip counts → désigner un gagnant
-- au lieu d'un match nul.
--
-- Contexte: la migration 20260705100000_fix_domino_draw.sql avait introduit
-- le comportement "match nul" quand plusieurs joueurs ont le même total de
-- pips. Cette migration revient sur ce choix : on désigne toujours un gagnant
-- via un système de départage.
--
-- Règles de départage (en cas d'égalité de pips) :
--   1. Le joueur avec le moins de tuiles en main gagne.
--   2. Si toujours égal, le joueur avec le slot le plus bas (premier joueur)
--      gagne.
--
-- Seule _domino_lowest_pip_slot est modifiée : elle ne retourne plus jamais
-- NULL pour cause de pips égaux. Les branches NULL dans _domino_finalize et
-- _domino_end_round sont conservées comme filet de sécurité mais ne seront
-- plus déclenchées par l'égalité de pips.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public._domino_lowest_pip_slot(_game_id uuid, _state jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  p          record;
  cur_sum    integer;
  cur_tiles  integer;
  best_sum   integer := 2147483647;
  best_tiles integer := 2147483647;
  best_slot  integer := NULL;
BEGIN
  -- Itération dans l'ordre des slots pour que le départage "slot le plus bas"
  -- soit automatique : on ne remplace best_slot que si c'est strictement
  -- meilleur (pips ou tuiles), jamais à égalité.
  FOR p IN
    SELECT slot FROM public.domino_participants
    WHERE game_id = _game_id AND forfeited = false
    ORDER BY slot
  LOOP
    cur_sum   := public._domino_hand_pips(
                   COALESCE(_state -> 'hands' -> p.slot::text, '[]'::jsonb)
                 );
    cur_tiles := jsonb_array_length(
                   COALESCE(_state -> 'hands' -> p.slot::text, '[]'::jsonb)
                 );

    IF cur_sum < best_sum THEN
      -- Meilleur pip : nouveau leader
      best_sum   := cur_sum;
      best_tiles := cur_tiles;
      best_slot  := p.slot;
    ELSIF cur_sum = best_sum AND cur_tiles < best_tiles THEN
      -- Départage 1 : moins de tuiles en main
      best_tiles := cur_tiles;
      best_slot  := p.slot;
    -- Départage 2 (slot le plus bas) : déjà garanti par ORDER BY slot,
    -- on ne remplace pas en cas d'égalité parfaite.
    END IF;
  END LOOP;

  -- Retourne toujours un gagnant (jamais NULL pour égalité de pips).
  RETURN best_slot;
END;
$$;
