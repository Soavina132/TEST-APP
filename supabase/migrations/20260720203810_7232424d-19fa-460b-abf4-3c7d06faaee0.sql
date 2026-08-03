
-- 1) admin_start_tournament (alias sur admin_force_start_tournament)
CREATE OR REPLACE FUNCTION public.admin_start_tournament(_tid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  RETURN public.admin_force_start_tournament(_tid);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_start_tournament(uuid) TO authenticated;

-- 2) admin_close_expired_registrations (sans paramètre)
CREATE OR REPLACE FUNCTION public.admin_close_expired_registrations()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _closed int := 0;
  _r record;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  FOR _r IN
    SELECT id FROM public.tournaments
    WHERE status IN ('open','registration','registering')
      AND registration_closes_at IS NOT NULL
      AND registration_closes_at < now()
  LOOP
    UPDATE public.tournaments
       SET status = 'closed', updated_at = now()
     WHERE id = _r.id;
    _closed := _closed + 1;
  END LOOP;

  RETURN jsonb_build_object('closed', _closed);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_close_expired_registrations() TO authenticated;

-- 3) admin_auto_process_expired_matches (traite les forfaits expirés pour un tournoi)
CREATE OR REPLACE FUNCTION public.admin_auto_process_expired_matches(_tid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _res jsonb;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Applique les forfaits automatiques (fonction existante, sans paramètre)
  PERFORM public.tournament_auto_forfeit_expired();

  -- Démarre les matchs dont tout le monde est prêt
  BEGIN
    PERFORM public.admin_auto_start_ready_matches(_tid);
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN jsonb_build_object('ok', true, 'tournament_id', _tid);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_auto_process_expired_matches(uuid) TO authenticated;
