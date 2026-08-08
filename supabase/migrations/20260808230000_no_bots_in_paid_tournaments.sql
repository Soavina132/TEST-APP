-- ═══════════════════════════════════════════════════════════════════════
-- RULE: Tournaments with entry_fee_ar > 0 (real money) must NEVER have bots.
-- This applies to both admin_tournament_add_bots (manual bot insertion)
-- and admin_tournament_start (auto-fill with bots if too few players).
-- ═══════════════════════════════════════════════════════════════════════

-- 1) Block bot insertion on paid tournaments
CREATE OR REPLACE FUNCTION public.admin_tournament_add_bots(_tid uuid, _count integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  t public.tournaments%ROWTYPE;
  i int; v_n int;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin uniquement'; END IF;
  SELECT * INTO t FROM public.tournaments WHERE id = _tid;
  IF t.entry_fee_ar > 0 THEN
    RAISE EXCEPTION 'Impossible d''ajouter des bots à un tournoi payant (frais: % Ar)', t.entry_fee_ar;
  END IF;

  SELECT count(*) INTO v_n FROM public.tournament_entrants WHERE tournament_id = _tid;
  FOR i IN 1.._count LOOP
    INSERT INTO public.tournament_entrants(tournament_id, display_name, is_bot)
      VALUES (_tid, 'Bot ' || (v_n + i), true);
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_tournament_add_bots(uuid, integer) TO authenticated;

-- 2) Safety net: a trigger that rejects any INSERT of a bot entrant
--    when the tournament has entry_fee_ar > 0 (catches any code path)
CREATE OR REPLACE FUNCTION public._trg_no_bots_in_paid_tournament()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_fee numeric;
BEGIN
  IF NEW.is_bot = true THEN
    SELECT entry_fee_ar INTO v_fee FROM public.tournaments WHERE id = NEW.tournament_id;
    IF v_fee > 0 THEN
      RAISE EXCEPTION 'Bots interdits dans les tournois payants';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_no_bots_in_paid_tournament ON public.tournament_entrants;
CREATE TRIGGER trg_no_bots_in_paid_tournament
BEFORE INSERT ON public.tournament_entrants
FOR EACH ROW EXECUTE FUNCTION public._trg_no_bots_in_paid_tournament();

-- 3) Clean up any existing bots in paid tournaments
DELETE FROM public.tournament_entrants
WHERE is_bot = true
  AND tournament_id IN (SELECT id FROM public.tournaments WHERE entry_fee_ar > 0);
