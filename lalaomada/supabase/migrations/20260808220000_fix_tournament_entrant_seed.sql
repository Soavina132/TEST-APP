-- ═══════════════════════════════════════════════════════════════════════
-- FIX: tournament_state() RPC references tournament_entrants.seed which
-- never existed → every call fails with "column e.seed does not exist"
-- → tournament detail page hangs forever loading, looks like a dead click.
-- ═══════════════════════════════════════════════════════════════════════

ALTER TABLE public.tournament_entrants ADD COLUMN IF NOT EXISTS seed INTEGER;

-- Backfill: seed players by registration order within each tournament
WITH ranked AS (
  SELECT id, ROW_NUMBER() OVER (PARTITION BY tournament_id ORDER BY created_at) AS rn
  FROM public.tournament_entrants
)
UPDATE public.tournament_entrants e
SET seed = ranked.rn
FROM ranked
WHERE e.id = ranked.id AND e.seed IS NULL;

-- Auto-assign seed for future registrations (next available number per tournament)
CREATE OR REPLACE FUNCTION public.set_tournament_entrant_seed()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.seed IS NULL THEN
    SELECT COALESCE(MAX(seed), 0) + 1 INTO NEW.seed
    FROM public.tournament_entrants WHERE tournament_id = NEW.tournament_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_tournament_entrant_seed ON public.tournament_entrants;
CREATE TRIGGER trg_set_tournament_entrant_seed
BEFORE INSERT ON public.tournament_entrants
FOR EACH ROW EXECUTE FUNCTION public.set_tournament_entrant_seed();
