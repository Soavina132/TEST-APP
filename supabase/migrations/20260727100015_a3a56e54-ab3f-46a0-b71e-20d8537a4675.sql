-- 1. Assouplir le lockout
CREATE OR REPLACE FUNCTION public.admin_record_login_attempt(
  _user_id uuid, _success boolean, _reason text, _ip inet, _ua text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  _recent_fails int;
  _lock_until timestamptz;
BEGIN
  INSERT INTO public.admin_login_attempts(user_id, success, reason, ip, user_agent)
  VALUES (_user_id, _success, _reason, _ip, _ua);

  IF _success THEN
    DELETE FROM public.admin_lockouts WHERE user_id = _user_id;
    RETURN jsonb_build_object('locked', false);
  END IF;

  IF _user_id IS NULL OR NOT public.has_role(_user_id, 'admin') THEN
    RETURN jsonb_build_object('locked', false, 'admin', false);
  END IF;

  SELECT count(*) INTO _recent_fails
  FROM public.admin_login_attempts
  WHERE user_id = _user_id
    AND success = false
    AND created_at > now() - interval '30 minutes';

  -- Assoupli : 10 échecs / 30min → blocage 10 min
  IF _recent_fails >= 10 THEN
    _lock_until := now() + interval '10 minutes';
    INSERT INTO public.admin_lockouts(user_id, locked_until, reason, fail_count)
    VALUES (_user_id, _lock_until, 'Trop de tentatives échouées (10 en 30 min)', _recent_fails)
    ON CONFLICT (user_id) DO UPDATE
      SET locked_until = EXCLUDED.locked_until,
          reason = EXCLUDED.reason,
          fail_count = EXCLUDED.fail_count,
          updated_at = now();

    PERFORM public._admin_notify_others(
      'admin_locked_out',
      jsonb_build_object('user_id', _user_id, 'until', _lock_until, 'ip', _ip::text, 'ua', _ua)
    );

    RETURN jsonb_build_object('locked', true, 'until', _lock_until);
  END IF;

  RETURN jsonb_build_object('locked', false, 'fails', _recent_fails);
END $$;

-- 2. Débloque tous les admins actuellement verrouillés
DELETE FROM public.admin_lockouts;

-- 3. Vue globale des sessions admin actives (tous les admins)
CREATE OR REPLACE FUNCTION public.admin_list_all_active_sessions()
RETURNS TABLE(
  id uuid,
  user_id uuid,
  admin_name text,
  ip inet,
  user_agent text,
  mfa_verified boolean,
  created_at timestamptz,
  last_seen_at timestamptz,
  expires_at timestamptz,
  override_reason text,
  is_me boolean
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT s.id, s.user_id,
         COALESCE(p.pseudo, p.phone, 'admin') AS admin_name,
         s.ip, s.user_agent, s.mfa_verified,
         s.created_at, s.last_seen_at, s.expires_at, s.override_reason,
         (s.user_id = auth.uid()) AS is_me
  FROM public.admin_sessions s
  LEFT JOIN public.profiles p ON p.id = s.user_id
  WHERE s.revoked_at IS NULL
    AND s.expires_at > now()
    AND public.has_role(auth.uid(), 'admin')
  ORDER BY s.last_seen_at DESC;
$$;

-- 4. Révocation à distance d'une session admin d'un autre admin
CREATE OR REPLACE FUNCTION public.admin_revoke_any_session(_session_id uuid, _reason text)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE _me uuid := auth.uid(); _target_user uuid;
BEGIN
  IF _me IS NULL OR NOT public.has_role(_me, 'admin') THEN
    RAISE EXCEPTION 'Not admin';
  END IF;

  UPDATE public.admin_sessions
     SET revoked_at = now(),
         revoke_reason = COALESCE(_reason, 'révoquée par un autre admin')
   WHERE id = _session_id AND revoked_at IS NULL
   RETURNING user_id INTO _target_user;

  IF _target_user IS NULL THEN RETURN false; END IF;

  PERFORM public._admin_notify_others(
    'admin_session_revoked_by_peer',
    jsonb_build_object('session_id', _session_id, 'target_user', _target_user, 'by', _me, 'reason', _reason)
  );
  RETURN true;
END $$;

GRANT EXECUTE ON FUNCTION public.admin_list_all_active_sessions() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_revoke_any_session(uuid, text) TO authenticated;