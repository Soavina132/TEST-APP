-- ============================================================
-- Fix: Toujours autoriser la sortie du yard sur un 6
-- Les cases de départ sont des cases sûres (safe cells)
-- Un blocage ne doit pas empêcher de sortir un pion du yard
-- ============================================================

CREATE OR REPLACE FUNCTION public._ludo_movable_pawns(st jsonb, _slot int, _dice int)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  arr jsonb; pawn jsonb; i INT; pstate TEXT; pstep INT;
  result jsonb := '[]'::jsonb;
  v_new_k INT;
  v_path_idx INT;
  v_max_players INT;
  v_start INT;
BEGIN
  IF _dice IS NULL OR _dice < 1 OR _dice > 6 THEN RETURN '[]'::jsonb; END IF;
  IF _slot IS NULL THEN RETURN '[]'::jsonb; END IF;
  arr := st->'pawns'->_slot::text;
  IF arr IS NULL OR arr = 'null'::jsonb THEN RETURN '[]'::jsonb; END IF;
  v_max_players := COALESCE((st->>'max_players')::int, 4);
  v_start := public._ludo_start_from_state(st, _slot);

  FOR i IN 0..3 LOOP
    pawn := arr->i;
    IF pawn IS NULL THEN CONTINUE; END IF;
    pstate := pawn->>'s';
    pstep := COALESCE((pawn->>'k')::INT, -1);
    IF pstate = 'finished' THEN CONTINUE; END IF;
    IF pstate = 'yard' THEN
      -- Toujours autoriser la sortie sur un 6, même si la case de départ est bloquée
      -- (les cases de départ sont safe, pas de capture possible de toute façon)
      IF _dice = 6 THEN
        result := result || to_jsonb(i);
      END IF;
    ELSIF pstate = 'track' THEN
      v_new_k := pstep + _dice;
      IF v_new_k <= 56 THEN
        IF v_new_k <= 50 THEN
          v_path_idx := (v_start + v_new_k - 1) % 52;
          IF NOT public._ludo_is_blocked(st, _slot, v_path_idx, v_max_players) THEN
            result := result || to_jsonb(i);
          END IF;
        ELSE
          -- Zone d'arrivée (51-56): toujours jouable
          result := result || to_jsonb(i);
        END IF;
      END IF;
    END IF;
  END LOOP;
  RETURN result;
END $$;
