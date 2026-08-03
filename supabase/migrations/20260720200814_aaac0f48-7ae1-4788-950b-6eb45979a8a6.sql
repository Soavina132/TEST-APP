
CREATE OR REPLACE FUNCTION public.admin_set_reward_distribution(
  _tid uuid,
  _first_pct numeric,
  _second_pct numeric,
  _third_pct numeric,
  _platform_pct numeric
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _sum numeric;
  _p record;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  _sum := COALESCE(_first_pct,0) + COALESCE(_second_pct,0) + COALESCE(_third_pct,0) + COALESCE(_platform_pct,0);
  IF ROUND(_sum::numeric, 2) <> 100 THEN
    RAISE EXCEPTION 'La somme des pourcentages doit être 100 (actuel: %)', _sum;
  END IF;

  UPDATE public.tournaments
  SET reward_distribution = jsonb_build_object(
        'first', _first_pct,
        'second', _second_pct,
        'third', _third_pct,
        'platform', _platform_pct
      ),
      updated_at = now()
  WHERE id = _tid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tournoi introuvable';
  END IF;

  -- Notifier les joueurs inscrits
  FOR _p IN SELECT user_id FROM public.tournament_registrations WHERE tournament_id = _tid LOOP
    BEGIN
      INSERT INTO public.notifications (user_id, type, title, message, data)
      VALUES (
        _p.user_id,
        'tournament_update',
        'Répartition des gains mise à jour',
        format('1er: %s%% • 2e: %s%% • 3e: %s%% • Plateforme: %s%%',
               _first_pct, _second_pct, _third_pct, _platform_pct),
        jsonb_build_object('tournament_id', _tid)
      );
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;

  BEGIN
    INSERT INTO public.admin_action_logs (admin_id, action, target_type, target_id, details)
    VALUES (auth.uid(), 'set_reward_distribution', 'tournament', _tid,
            jsonb_build_object('first',_first_pct,'second',_second_pct,'third',_third_pct,'platform',_platform_pct));
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_set_reward_distribution(uuid, numeric, numeric, numeric, numeric) TO authenticated, service_role;
