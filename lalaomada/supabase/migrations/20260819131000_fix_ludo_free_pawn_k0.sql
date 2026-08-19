-- Fix: free_pawn lucky_star reward used k=0 (should be k=1)
-- This would crash the frontend for red player (PATH[-1] = undefined)
-- Same bug as the yard exit, but for the free_pawn power-up.

-- The fix is already applied to the function definition in the previous
-- migration (20260819120000), but we also need to fix existing games
-- that may have pawns with k=0 from the free_pawn reward.

DO $$
DECLARE g RECORD; st jsonb; slot text; arr jsonb; i int; changed boolean;
BEGIN
  FOR g IN SELECT id, state FROM public.ludo_games WHERE status = 'playing' LOOP
    st := g.state;
    IF st IS NULL OR NOT (st ? 'pawns') THEN CONTINUE; END IF;
    changed := false;
    FOR slot IN SELECT * FROM jsonb_object_keys(st->'pawns') LOOP
      arr := st->'pawns'->slot;
      IF arr IS NULL THEN CONTINUE; END IF;
      FOR i IN 0..3 LOOP
        IF arr->i->>'s' = 'track' AND (arr->i->>'k')::int = 0 THEN
          arr := jsonb_set(arr, ARRAY[i::text, 'k'], '1'::jsonb);
          changed := true;
        END IF;
      END LOOP;
      IF changed THEN
        st := jsonb_set(st, ARRAY['pawns', slot], arr);
      END IF;
    END LOOP;
    IF changed THEN
      UPDATE public.ludo_games SET state = st WHERE id = g.id;
    END IF;
  END LOOP;
END $$;
