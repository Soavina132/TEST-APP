
-- 1) player_submit_claim (wrapper de tournament_claim_create avec catégorie + description)
CREATE OR REPLACE FUNCTION public.player_submit_claim(
  _tournament_id uuid,
  _match_id uuid,
  _category text,
  _description text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_reason text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _description IS NULL OR length(trim(_description)) < 10 THEN
    RAISE EXCEPTION 'Description trop courte';
  END IF;

  IF _match_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.tournament_matches
    WHERE id = _match_id AND auth.uid() = ANY(player_ids)
  ) THEN
    RAISE EXCEPTION 'Vous n''êtes pas participant à ce match';
  END IF;

  v_reason := '[' || COALESCE(NULLIF(_category,''), 'autre') || '] ' || trim(_description);

  INSERT INTO public.tournament_claims(tournament_id, match_id, claimant_id, reason, status)
    VALUES (_tournament_id, _match_id, auth.uid(), v_reason, 'pending')
    RETURNING id INTO v_id;

  -- Notifier les admins
  BEGIN
    INSERT INTO public.notifications(user_id, kind, title, body, link, ref_id)
    SELECT ur.user_id, 'tournament',
           'Nouvelle réclamation',
           'Catégorie: ' || COALESCE(_category,'autre'),
           '/admin', v_id
    FROM public.user_roles ur WHERE ur.role = 'admin';
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.player_submit_claim(uuid, uuid, text, text) TO authenticated, service_role;

-- 2) admin_auto_start_ready_matches
CREATE OR REPLACE FUNCTION public.admin_auto_start_ready_matches(_tid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_match record;
  v_ready boolean;
  v_pid uuid;
  v_count int := 0;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Accès refusé';
  END IF;

  FOR v_match IN
    SELECT id, player_ids, player_ready
    FROM public.tournament_matches
    WHERE tournament_id = _tid
      AND status = 'pending'
      AND NOT is_bye
  LOOP
    v_ready := true;
    IF v_match.player_ids IS NULL OR array_length(v_match.player_ids,1) IS NULL THEN
      v_ready := false;
    ELSE
      FOREACH v_pid IN ARRAY v_match.player_ids LOOP
        IF NOT (COALESCE(v_match.player_ready, '{}'::jsonb) ? v_pid::text) THEN
          v_ready := false;
          EXIT;
        END IF;
      END LOOP;
    END IF;

    IF v_ready THEN
      UPDATE public.tournament_matches
        SET join_deadline = now() + interval '5 seconds'
        WHERE id = v_match.id;
      v_count := v_count + 1;
    END IF;
  END LOOP;

  BEGIN
    INSERT INTO public.admin_action_logs(admin_id, action, target_type, target_id, details)
    VALUES (auth.uid(), 'auto_start_ready_matches', 'tournament', _tid,
            jsonb_build_object('started_count', v_count));
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object('started', v_count);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_auto_start_ready_matches(uuid) TO authenticated, service_role;
