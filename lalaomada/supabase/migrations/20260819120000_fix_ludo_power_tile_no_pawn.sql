-- ═════════════════════════════════════════════════════════════════════════════
-- FIX: Ludo — ne jamais placer une power tile sur une case qui a déjà un pion
--
-- Problème : _ludo_relocate_power_tile (appelée quand un pion consomme une
--   power tile) choisit une nouvelle case au hasard mais ne vérifie pas
--   s'il y a déjà un pion dessus. La power tile se retrouve sous un pion.
--
-- Fix : calculer les cellules absolues de tous les pions sur le track
--   et les exclure du choix de la nouvelle case.
--
-- Note : _ludo_place_power_tiles() (placement initial) est appelée au
--   démarrage quand tous les pions sont au yard → pas de conflit possible.
-- ═════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._ludo_relocate_power_tile(st jsonb, _old_cell integer)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
  tiles jsonb;
  new_cell INT;
  i INT;
  used_cells INT[] := ARRAY[]::INT[];
  cell INT;
  v_slot INT;
  v_pawns jsonb;
  v_pawn jsonb;
  v_k INT;
  v_start INT;
  v_start_positions INT[] := ARRAY[0, 13, 26, 39]; -- red, green, yellow, blue
  v_abs_cell INT;
BEGIN
  tiles := st->'power_tiles';
  IF tiles IS NULL OR jsonb_array_length(tiles) = 0 THEN RETURN st; END IF;

  -- Collect all current tile cells (excluding the one being relocated)
  FOR i IN 0..jsonb_array_length(tiles) - 1 LOOP
    IF (tiles->i->>'cell')::INT <> _old_cell THEN
      used_cells := used_cells || (tiles->i->>'cell')::INT;
    END IF;
  END LOOP;

  -- Collect all cells occupied by pawns on the track
  FOR v_slot IN 0..3 LOOP
    v_pawns := st->'pawns'->v_slot::text;
    IF v_pawns IS NULL THEN CONTINUE; END IF;
    v_start := v_start_positions[v_slot + 1]; -- arrays are 1-indexed in PG
    FOR i IN 0..3 LOOP
      v_pawn := v_pawns->i;
      IF v_pawn IS NOT NULL AND v_pawn->>'s' = 'track' THEN
        v_k := (v_pawn->>'k')::INT;
        IF v_k >= 1 AND v_k <= 50 THEN
          v_abs_cell := (v_start + v_k - 1) % 52;
          used_cells := used_cells || v_abs_cell;
        END IF;
      END IF;
    END LOOP;
  END LOOP;

  -- Find a new random cell that is:
  -- 1. Not a safe cell (no power tiles on safe cells)
  -- 2. Not a starting cell
  -- 3. Not already occupied by another power tile
  -- 4. Not occupied by a pawn (FIX)
  LOOP
    new_cell := floor(random() * 52)::INT;
    EXIT WHEN NOT public._ludo_is_safe(new_cell)
          AND new_cell NOT IN (0, 13, 26, 39)
          AND NOT (new_cell = ANY(used_cells));
  END LOOP;

  -- Update the tile's cell
  FOR i IN 0..jsonb_array_length(tiles) - 1 LOOP
    IF (tiles->i->>'cell')::INT = _old_cell THEN
      tiles := jsonb_set(tiles, ARRAY[i::text, 'cell'], to_jsonb(new_cell));
      EXIT;
    END IF;
  END LOOP;

  RETURN jsonb_set(st, '{power_tiles}', tiles);
END;
$function$;

REVOKE ALL ON FUNCTION public._ludo_relocate_power_tile(jsonb, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._ludo_relocate_power_tile(jsonb, integer) TO authenticated, service_role;
