
DROP FUNCTION IF EXISTS public.admin_advance_tournament_round(uuid) CASCADE;

CREATE OR REPLACE FUNCTION public.admin_advance_tournament_round(_tid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_before int;
  v_after int;
  v_result jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT current_round INTO v_before FROM public.tournaments WHERE id = _tid;
  v_result := public._tournament_advance_round_core(_tid);
  SELECT current_round INTO v_after FROM public.tournaments WHERE id = _tid;

  PERFORM public._tournament_audit_log(
    _tid, NULL, NULL, v_uid,
    CASE WHEN COALESCE(v_after,0) > COALESCE(v_before,0) THEN 'round_advanced' ELSE 'round_advance_noop' END,
    NULL, v_after,
    jsonb_build_object('previous_round', v_before, 'new_round', v_after, 'result', v_result)
  );

  RETURN v_result;
END $function$;

GRANT EXECUTE ON FUNCTION public.admin_advance_tournament_round(uuid) TO authenticated;
