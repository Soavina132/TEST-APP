
CREATE OR REPLACE FUNCTION public.admin_tournament_update_schedule(
  _id uuid,
  _max_concurrent_matches integer,
  _wave_gap_min integer
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE r record;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;
  IF _max_concurrent_matches IS NULL OR _max_concurrent_matches < 1 OR _max_concurrent_matches > 64 THEN
    RAISE EXCEPTION 'max_concurrent_matches invalide (1..64)';
  END IF;
  IF _wave_gap_min IS NULL OR _wave_gap_min < 1 OR _wave_gap_min > 240 THEN
    RAISE EXCEPTION 'wave_gap_min invalide (1..240)';
  END IF;
  UPDATE public.tournaments
     SET max_concurrent_matches = _max_concurrent_matches,
         wave_gap_min = _wave_gap_min,
         updated_at = now()
   WHERE id = _id;

  FOR r IN
    SELECT DISTINCT round
      FROM public.tournament_matches
     WHERE tournament_id = _id
       AND status = 'pending'
       AND NOT is_bye
  LOOP
    PERFORM public._tournament_assign_waves(_id, r.round);
  END LOOP;

  RETURN jsonb_build_object('ok', true);
END $fn$;

GRANT EXECUTE ON FUNCTION public.admin_tournament_update_schedule(uuid, integer, integer) TO authenticated;
