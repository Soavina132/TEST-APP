-- ─────────────────────────────────────────────────────────────────────────────
-- Revert: Domino égalité de pips → match nul (aucun gagnant désigné)
--
-- Annule la migration 20260706000000_domino_tiebreaker_on_equal_pips.sql.
-- On revient au comportement de 20260705100000_fix_domino_draw.sql :
-- quand plusieurs joueurs ont le même total de pips, _domino_lowest_pip_slot
-- retourne NULL → match nul, remboursement du pot à parts égales.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public._domino_lowest_pip_slot(_game_id uuid, _state jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  p         record;
  cur_sum   integer;
  best_sum  integer := 2147483647;
  best_slot integer := NULL;
  tie_count integer := 0;
BEGIN
  FOR p IN
    SELECT slot FROM public.domino_participants
    WHERE game_id = _game_id AND forfeited = false
    ORDER BY slot
  LOOP
    cur_sum := public._domino_hand_pips(
      COALESCE(_state -> 'hands' -> p.slot::text, '[]'::jsonb)
    );
    IF cur_sum < best_sum THEN
      best_sum  := cur_sum;
      best_slot := p.slot;
      tie_count := 1;
    ELSIF cur_sum = best_sum THEN
      tie_count := tie_count + 1;   -- égalité détectée
    END IF;
  END LOOP;

  -- Si plusieurs joueurs partagent le minimum → match nul → retourner NULL
  IF tie_count > 1 THEN
    RETURN NULL;
  END IF;
  RETURN best_slot;
END;
$$;
