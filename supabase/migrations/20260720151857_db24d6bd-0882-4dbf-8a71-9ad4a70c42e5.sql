
-- Bornes de sécurité (5s min, 30 min max pour éviter les extrêmes)
CREATE OR REPLACE FUNCTION public.admin_update_tournament_timings(
  _tid uuid,
  _join_timeout_secs int,
  _auto_start_mins int DEFAULT NULL,
  _apply_to_pending_matches boolean DEFAULT true
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tournament public.tournaments%ROWTYPE;
  v_updated int := 0;
BEGIN
  IF NOT public.has_role(auth.uid(),'admin') THEN
    RAISE EXCEPTION 'Accès refusé';
  END IF;

  IF _join_timeout_secs IS NULL OR _join_timeout_secs < 30 OR _join_timeout_secs > 3600 THEN
    RAISE EXCEPTION 'join_timeout_secs doit être entre 30 et 3600 secondes';
  END IF;
  IF _auto_start_mins IS NOT NULL AND (_auto_start_mins < 1 OR _auto_start_mins > 240) THEN
    RAISE EXCEPTION 'auto_start_mins doit être entre 1 et 240 minutes';
  END IF;

  SELECT * INTO v_tournament FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF v_tournament.id IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;

  UPDATE public.tournaments
    SET join_timeout_secs = _join_timeout_secs,
        auto_start_mins   = COALESCE(_auto_start_mins, auto_start_mins)
    WHERE id = _tid;

  -- Rétro-appliquer aux matchs en attente
  IF _apply_to_pending_matches THEN
    UPDATE public.tournament_matches
      SET join_deadline = now() + (_join_timeout_secs || ' seconds')::interval
      WHERE tournament_id = _tid
        AND status = 'pending'
        AND is_bye = false;
    GET DIAGNOSTICS v_updated = ROW_COUNT;
  END IF;

  INSERT INTO public.admin_action_logs(admin_id, action, target_id, meta)
    VALUES (auth.uid(), 'update_tournament_timings', _tid,
            jsonb_build_object('join_timeout_secs', _join_timeout_secs,
                               'auto_start_mins', _auto_start_mins,
                               'matches_updated', v_updated));

  RETURN jsonb_build_object('ok', true, 'matches_updated', v_updated);
END $$;

GRANT EXECUTE ON FUNCTION public.admin_update_tournament_timings(uuid, int, int, boolean) TO authenticated;

-- Reconfiguration cron auto-forfeit
CREATE OR REPLACE FUNCTION public.admin_set_forfeit_cron_interval(_seconds int)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_sched text;
BEGIN
  IF NOT public.has_role(auth.uid(),'admin') THEN
    RAISE EXCEPTION 'Accès refusé';
  END IF;
  IF _seconds < 10 OR _seconds > 600 THEN
    RAISE EXCEPTION 'La fréquence doit être entre 10 et 600 secondes';
  END IF;

  v_sched := _seconds || ' seconds';

  -- Recréer le job
  PERFORM cron.unschedule('tournament_auto_forfeit')
    WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'tournament_auto_forfeit');

  PERFORM cron.schedule('tournament_auto_forfeit', v_sched,
    $c$SELECT public.tournament_auto_forfeit_expired();$c$);

  INSERT INTO public.admin_action_logs(admin_id, action, meta)
    VALUES (auth.uid(), 'set_forfeit_cron_interval',
            jsonb_build_object('seconds', _seconds));

  RETURN jsonb_build_object('ok', true, 'schedule', v_sched);
END $$;

GRANT EXECUTE ON FUNCTION public.admin_set_forfeit_cron_interval(int) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_get_forfeit_cron_info()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_row record;
BEGIN
  IF NOT public.has_role(auth.uid(),'admin') THEN
    RAISE EXCEPTION 'Accès refusé';
  END IF;
  SELECT jobid, jobname, schedule, active INTO v_row
    FROM cron.job WHERE jobname = 'tournament_auto_forfeit';
  IF v_row.jobid IS NULL THEN
    RETURN jsonb_build_object('exists', false);
  END IF;
  RETURN jsonb_build_object('exists', true, 'jobid', v_row.jobid,
                            'schedule', v_row.schedule, 'active', v_row.active);
END $$;

GRANT EXECUTE ON FUNCTION public.admin_get_forfeit_cron_info() TO authenticated;
