
CREATE OR REPLACE FUNCTION public._trg_third_place_set_deadline()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF COALESCE(NEW.is_third_place, false) = true
     AND NEW.status = 'pending'
     AND NEW.join_deadline IS NULL THEN
    NEW.join_deadline := now() + interval '15 minutes';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_third_place_set_deadline ON public.tournament_matches;
CREATE TRIGGER trg_third_place_set_deadline
  BEFORE INSERT ON public.tournament_matches
  FOR EACH ROW EXECUTE FUNCTION public._trg_third_place_set_deadline();

UPDATE public.tournament_matches
SET join_deadline = now() + interval '15 minutes'
WHERE is_third_place = true
  AND status = 'pending'
  AND join_deadline IS NULL;
