-- ============================================================
-- ADMIN SECURITY HARDENING: MFA + Session Control + Approval
-- ============================================================

-- ---------- admin_sessions ----------
CREATE TABLE IF NOT EXISTS public.admin_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_fingerprint text NOT NULL,
  ip inet,
  user_agent text,
  mfa_verified boolean NOT NULL DEFAULT false,
  approved_by uuid REFERENCES auth.users(id),
  override_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '8 hours'),
  revoked_at timestamptz,
  revoke_reason text
);
CREATE INDEX IF NOT EXISTS idx_admin_sessions_user ON public.admin_sessions(user_id) WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_admin_sessions_active ON public.admin_sessions(expires_at) WHERE revoked_at IS NULL;

GRANT SELECT ON public.admin_sessions TO authenticated;
GRANT ALL ON public.admin_sessions TO service_role;
ALTER TABLE public.admin_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS admin_sessions_self_read ON public.admin_sessions;
CREATE POLICY admin_sessions_self_read ON public.admin_sessions
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'admin'));

-- ---------- admin_login_attempts ----------
CREATE TABLE IF NOT EXISTS public.admin_login_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  identifier text,
  success boolean NOT NULL,
  reason text,
  ip inet,
  user_agent text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_admin_login_attempts_user_time
  ON public.admin_login_attempts(user_id, created_at DESC);

GRANT SELECT ON public.admin_login_attempts TO authenticated;
GRANT ALL ON public.admin_login_attempts TO service_role;
ALTER TABLE public.admin_login_attempts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS admin_login_attempts_admins_read ON public.admin_login_attempts;
CREATE POLICY admin_login_attempts_admins_read ON public.admin_login_attempts
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

-- ---------- admin_lockouts ----------
CREATE TABLE IF NOT EXISTS public.admin_lockouts (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  locked_until timestamptz NOT NULL,
  reason text,
  fail_count int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.admin_lockouts TO authenticated;
GRANT ALL ON public.admin_lockouts TO service_role;
ALTER TABLE public.admin_lockouts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS admin_lockouts_admins_read ON public.admin_lockouts;
CREATE POLICY admin_lockouts_admins_read ON public.admin_lockouts
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin') OR user_id = auth.uid());

-- ---------- admin_login_approvals ----------
CREATE TABLE IF NOT EXISTS public.admin_login_approvals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  requesting_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  requesting_ip inet,
  requesting_user_agent text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','denied','expired','override')),
  approver_user_id uuid REFERENCES auth.users(id),
  override_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  decided_at timestamptz,
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '2 minutes')
);
CREATE INDEX IF NOT EXISTS idx_admin_login_approvals_pending
  ON public.admin_login_approvals(status, expires_at) WHERE status = 'pending';

GRANT SELECT ON public.admin_login_approvals TO authenticated;
GRANT ALL ON public.admin_login_approvals TO service_role;
ALTER TABLE public.admin_login_approvals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS admin_login_approvals_read ON public.admin_login_approvals;
CREATE POLICY admin_login_approvals_read ON public.admin_login_approvals
  FOR SELECT TO authenticated
  USING (requesting_user_id = auth.uid() OR public.has_role(auth.uid(), 'admin'));

-- ---------- admin_email_otps ----------
CREATE TABLE IF NOT EXISTS public.admin_email_otps (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  code_hash text NOT NULL,
  purpose text NOT NULL DEFAULT 'admin_mfa_backup',
  attempts int NOT NULL DEFAULT 0,
  consumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '10 minutes')
);
CREATE INDEX IF NOT EXISTS idx_admin_email_otps_user ON public.admin_email_otps(user_id, created_at DESC);

GRANT SELECT ON public.admin_email_otps TO authenticated;
GRANT ALL ON public.admin_email_otps TO service_role;
ALTER TABLE public.admin_email_otps ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS admin_email_otps_self ON public.admin_email_otps;
CREATE POLICY admin_email_otps_self ON public.admin_email_otps
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- ============================================================
-- HELPERS
-- ============================================================

CREATE OR REPLACE FUNCTION public._admin_notify_others(_action text, _payload jsonb)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE _uid uuid; _me uuid := auth.uid();
BEGIN
  FOR _uid IN SELECT user_id FROM public.user_roles WHERE role = 'admin' AND user_id <> COALESCE(_me, '00000000-0000-0000-0000-000000000000'::uuid)
  LOOP
    INSERT INTO public.notifications(user_id, type, title, body, data)
    VALUES (_uid, 'admin_security',
            '🔐 Alerte sécurité admin',
            _action,
            _payload);
  END LOOP;
  INSERT INTO public.admin_logs(admin_id, action, new_value)
  VALUES (_me, _action, _payload);
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- ============================================================
-- LOCKOUT & ATTEMPTS
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_check_lockout(_user_id uuid)
RETURNS TABLE(locked boolean, locked_until timestamptz, reason text)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT
    (l.locked_until > now()) AS locked,
    l.locked_until,
    l.reason
  FROM public.admin_lockouts l
  WHERE l.user_id = _user_id
  UNION ALL
  SELECT false, NULL::timestamptz, NULL::text
  WHERE NOT EXISTS (SELECT 1 FROM public.admin_lockouts WHERE user_id = _user_id)
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.admin_record_login_attempt(
  _user_id uuid, _success boolean, _reason text, _ip inet, _ua text
)
RETURNS jsonb
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

  -- Only count fails for admin users
  IF NOT public.has_role(_user_id, 'admin') THEN
    RETURN jsonb_build_object('locked', false, 'admin', false);
  END IF;

  SELECT count(*) INTO _recent_fails
  FROM public.admin_login_attempts
  WHERE user_id = _user_id
    AND success = false
    AND created_at > now() - interval '10 minutes';

  IF _recent_fails >= 3 THEN
    _lock_until := now() + interval '1 hour';
    INSERT INTO public.admin_lockouts(user_id, locked_until, reason, fail_count)
    VALUES (_user_id, _lock_until, 'Trop de tentatives échouées', _recent_fails)
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

-- ============================================================
-- APPROVAL FLOW
-- ============================================================

CREATE OR REPLACE FUNCTION public._admin_has_active_session(_exclude_user uuid DEFAULT NULL)
RETURNS boolean
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_sessions s
    WHERE s.revoked_at IS NULL
      AND s.expires_at > now()
      AND s.mfa_verified = true
      AND (_exclude_user IS NULL OR s.user_id <> _exclude_user)
  );
$$;

CREATE OR REPLACE FUNCTION public.admin_request_login_approval(
  _ip inet, _user_agent text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  _me uuid := auth.uid();
  _req_id uuid;
BEGIN
  IF _me IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.has_role(_me, 'admin') THEN
    RAISE EXCEPTION 'Not admin';
  END IF;

  -- If no other admin session is active, auto-approve
  IF NOT public._admin_has_active_session(_me) THEN
    RETURN jsonb_build_object('status', 'auto_approved', 'requires_approval', false);
  END IF;

  -- Otherwise create pending approval
  INSERT INTO public.admin_login_approvals(requesting_user_id, requesting_ip, requesting_user_agent)
  VALUES (_me, _ip, _user_agent)
  RETURNING id INTO _req_id;

  PERFORM public._admin_notify_others(
    'admin_login_approval_requested',
    jsonb_build_object('request_id', _req_id, 'requester', _me, 'ip', _ip::text, 'ua', _user_agent)
  );

  RETURN jsonb_build_object('status', 'pending', 'requires_approval', true, 'request_id', _req_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_respond_login_approval(
  _request_id uuid, _decision text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  _me uuid := auth.uid();
  _rec public.admin_login_approvals;
BEGIN
  IF _me IS NULL OR NOT public.has_role(_me, 'admin') THEN
    RAISE EXCEPTION 'Not admin';
  END IF;
  IF _decision NOT IN ('approved','denied') THEN
    RAISE EXCEPTION 'Invalid decision';
  END IF;

  SELECT * INTO _rec FROM public.admin_login_approvals WHERE id = _request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Not found'; END IF;
  IF _rec.status <> 'pending' THEN
    RETURN jsonb_build_object('status', _rec.status, 'already_decided', true);
  END IF;
  IF _rec.expires_at <= now() THEN
    UPDATE public.admin_login_approvals SET status='expired', decided_at=now() WHERE id=_request_id;
    RETURN jsonb_build_object('status', 'expired');
  END IF;
  IF _rec.requesting_user_id = _me THEN
    RAISE EXCEPTION 'Cannot approve your own request';
  END IF;

  UPDATE public.admin_login_approvals
     SET status = _decision, approver_user_id = _me, decided_at = now()
   WHERE id = _request_id;

  PERFORM public._admin_notify_others(
    'admin_login_' || _decision,
    jsonb_build_object('request_id', _request_id, 'requester', _rec.requesting_user_id, 'approver', _me)
  );

  RETURN jsonb_build_object('status', _decision);
END $$;

CREATE OR REPLACE FUNCTION public.admin_override_login(
  _reason text, _ip inet, _user_agent text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  _me uuid := auth.uid();
  _req_id uuid;
BEGIN
  IF _me IS NULL OR NOT public.has_role(_me, 'admin') THEN
    RAISE EXCEPTION 'Not admin';
  END IF;
  IF _reason IS NULL OR length(trim(_reason)) < 10 THEN
    RAISE EXCEPTION 'Motif obligatoire (10 caractères minimum)';
  END IF;

  INSERT INTO public.admin_login_approvals(
    requesting_user_id, requesting_ip, requesting_user_agent,
    status, override_reason, decided_at
  ) VALUES (_me, _ip, _user_agent, 'override', _reason, now())
  RETURNING id INTO _req_id;

  PERFORM public._admin_notify_others(
    'admin_login_override',
    jsonb_build_object('request_id', _req_id, 'requester', _me, 'reason', _reason,
                       'ip', _ip::text, 'ua', _user_agent)
  );

  RETURN jsonb_build_object('status', 'override', 'request_id', _req_id);
END $$;

-- ============================================================
-- SESSION LIFECYCLE
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_create_session(
  _mfa_verified boolean,
  _approval_id uuid,
  _ip inet,
  _user_agent text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  _me uuid := auth.uid();
  _fp text;
  _sid uuid;
  _approval public.admin_login_approvals;
BEGIN
  IF _me IS NULL OR NOT public.has_role(_me, 'admin') THEN
    RAISE EXCEPTION 'Not admin';
  END IF;

  IF NOT _mfa_verified THEN
    RAISE EXCEPTION 'MFA obligatoire';
  END IF;

  -- If another admin session exists, an approval or override is REQUIRED
  IF public._admin_has_active_session(_me) THEN
    IF _approval_id IS NULL THEN
      RAISE EXCEPTION 'Approbation d''un admin déjà connecté requise';
    END IF;
    SELECT * INTO _approval FROM public.admin_login_approvals
     WHERE id = _approval_id AND requesting_user_id = _me;
    IF NOT FOUND OR _approval.status NOT IN ('approved','override') THEN
      RAISE EXCEPTION 'Approbation invalide ou refusée';
    END IF;
  END IF;

  _fp := encode(extensions.gen_random_bytes(24), 'hex');

  INSERT INTO public.admin_sessions(
    user_id, session_fingerprint, ip, user_agent,
    mfa_verified, approved_by, override_reason
  ) VALUES (
    _me, _fp, _ip, _user_agent, true,
    _approval.approver_user_id,
    CASE WHEN _approval.status = 'override' THEN _approval.override_reason ELSE NULL END
  ) RETURNING id INTO _sid;

  PERFORM public._admin_notify_others(
    'admin_session_created',
    jsonb_build_object('session_id', _sid, 'user_id', _me, 'ip', _ip::text,
                       'override', (_approval.status = 'override'))
  );

  RETURN jsonb_build_object('session_id', _sid, 'fingerprint', _fp,
                            'expires_at', now() + interval '8 hours');
END $$;

CREATE OR REPLACE FUNCTION public.admin_validate_session(_fingerprint text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  _me uuid := auth.uid();
  _rec public.admin_sessions;
BEGIN
  IF _me IS NULL THEN RETURN jsonb_build_object('valid', false, 'reason', 'no_auth'); END IF;

  SELECT * INTO _rec FROM public.admin_sessions
   WHERE user_id = _me AND session_fingerprint = _fingerprint;

  IF NOT FOUND THEN RETURN jsonb_build_object('valid', false, 'reason', 'not_found'); END IF;
  IF _rec.revoked_at IS NOT NULL THEN
    RETURN jsonb_build_object('valid', false, 'reason', 'revoked', 'revoke_reason', _rec.revoke_reason);
  END IF;
  IF _rec.expires_at <= now() THEN
    RETURN jsonb_build_object('valid', false, 'reason', 'expired');
  END IF;

  UPDATE public.admin_sessions SET last_seen_at = now() WHERE id = _rec.id;
  RETURN jsonb_build_object('valid', true, 'expires_at', _rec.expires_at, 'session_id', _rec.id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_revoke_session(_session_id uuid, _reason text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE _me uuid := auth.uid(); _target uuid;
BEGIN
  IF _me IS NULL OR NOT public.has_role(_me, 'admin') THEN
    RAISE EXCEPTION 'Not admin';
  END IF;

  SELECT user_id INTO _target FROM public.admin_sessions WHERE id = _session_id;
  IF _target IS NULL THEN RAISE EXCEPTION 'Not found'; END IF;
  -- self, or any admin can revoke
  UPDATE public.admin_sessions
     SET revoked_at = now(), revoke_reason = COALESCE(_reason, 'manual')
   WHERE id = _session_id AND revoked_at IS NULL;

  IF _target <> _me THEN
    PERFORM public._admin_notify_others(
      'admin_session_revoked_by_peer',
      jsonb_build_object('session_id', _session_id, 'target', _target, 'by', _me, 'reason', _reason)
    );
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.admin_revoke_all_other_sessions()
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE _me uuid := auth.uid(); _n int;
BEGIN
  IF _me IS NULL OR NOT public.has_role(_me, 'admin') THEN
    RAISE EXCEPTION 'Not admin';
  END IF;
  WITH upd AS (
    UPDATE public.admin_sessions
       SET revoked_at = now(), revoke_reason = 'revoked_by_self_all_other'
     WHERE user_id = _me AND revoked_at IS NULL
     RETURNING 1
  ) SELECT count(*) INTO _n FROM upd;
  RETURN COALESCE(_n, 0);
END $$;

CREATE OR REPLACE FUNCTION public.admin_list_my_sessions()
RETURNS TABLE(
  id uuid, ip inet, user_agent text, mfa_verified boolean,
  created_at timestamptz, last_seen_at timestamptz, expires_at timestamptz,
  revoked_at timestamptz, revoke_reason text, override_reason text
)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT id, ip, user_agent, mfa_verified,
         created_at, last_seen_at, expires_at,
         revoked_at, revoke_reason, override_reason
  FROM public.admin_sessions
  WHERE user_id = auth.uid()
  ORDER BY created_at DESC
  LIMIT 50;
$$;

-- ============================================================
-- EMAIL OTP (fallback MFA)
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_send_email_otp()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  _me uuid := auth.uid();
  _code text;
  _hash text;
  _email text;
BEGIN
  IF _me IS NULL OR NOT public.has_role(_me, 'admin') THEN
    RAISE EXCEPTION 'Not admin';
  END IF;

  -- rate limit: max 3 codes / 10 min
  IF (SELECT count(*) FROM public.admin_email_otps
      WHERE user_id = _me AND created_at > now() - interval '10 minutes') >= 3 THEN
    RAISE EXCEPTION 'Trop de codes demandés. Réessayez dans 10 min.';
  END IF;

  SELECT email INTO _email FROM auth.users WHERE id = _me;
  IF _email IS NULL THEN RAISE EXCEPTION 'Aucune e-mail associée au compte'; END IF;

  _code := lpad((floor(random() * 1000000))::int::text, 6, '0');
  _hash := encode(extensions.digest(_code, 'sha256'), 'hex');

  INSERT INTO public.admin_email_otps(user_id, code_hash) VALUES (_me, _hash);

  -- Try enqueue via existing email infra (silent fallback)
  BEGIN
    PERFORM public.enqueue_email(
      _email,
      '🔐 Code de secours admin — Lalao MADA',
      '<p>Votre code de secours admin est :</p><h1 style="font-size:32px;letter-spacing:8px;text-align:center;">' || _code || '</h1><p>Valide 10 minutes. Ne le partagez jamais.</p>'
    );
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object('sent', true);
END $$;

CREATE OR REPLACE FUNCTION public.admin_verify_email_otp(_code text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  _me uuid := auth.uid();
  _rec public.admin_email_otps;
  _hash text;
BEGIN
  IF _me IS NULL OR NOT public.has_role(_me, 'admin') THEN
    RAISE EXCEPTION 'Not admin';
  END IF;
  IF _code IS NULL OR length(_code) <> 6 THEN
    RAISE EXCEPTION 'Code invalide';
  END IF;

  _hash := encode(extensions.digest(_code, 'sha256'), 'hex');

  SELECT * INTO _rec FROM public.admin_email_otps
   WHERE user_id = _me AND consumed_at IS NULL AND expires_at > now()
   ORDER BY created_at DESC LIMIT 1 FOR UPDATE;

  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'no_active_code'); END IF;

  IF _rec.attempts >= 5 THEN
    UPDATE public.admin_email_otps SET consumed_at = now() WHERE id = _rec.id;
    RETURN jsonb_build_object('ok', false, 'reason', 'too_many_attempts');
  END IF;

  IF _rec.code_hash <> _hash THEN
    UPDATE public.admin_email_otps SET attempts = attempts + 1 WHERE id = _rec.id;
    RETURN jsonb_build_object('ok', false, 'reason', 'bad_code');
  END IF;

  UPDATE public.admin_email_otps SET consumed_at = now() WHERE id = _rec.id;
  RETURN jsonb_build_object('ok', true);
END $$;

-- ============================================================
-- CRON: auto-expire sessions and approvals
-- ============================================================

CREATE OR REPLACE FUNCTION public._admin_security_housekeeping()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  UPDATE public.admin_sessions
     SET revoked_at = now(), revoke_reason = 'expired'
   WHERE revoked_at IS NULL AND expires_at <= now();

  UPDATE public.admin_login_approvals
     SET status = 'expired', decided_at = now()
   WHERE status = 'pending' AND expires_at <= now();

  DELETE FROM public.admin_lockouts WHERE locked_until <= now() - interval '1 day';
  DELETE FROM public.admin_login_attempts WHERE created_at < now() - interval '90 days';
  DELETE FROM public.admin_email_otps WHERE expires_at < now() - interval '1 day';
END $$;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('admin_security_housekeeping');
  END IF;
EXCEPTION WHEN OTHERS THEN NULL; END $$;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule('admin_security_housekeeping', '* * * * *',
      $cmd$SELECT public._admin_security_housekeeping();$cmd$);
  END IF;
EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- ============================================================
-- GRANTS on RPCs
-- ============================================================
GRANT EXECUTE ON FUNCTION public.admin_check_lockout(uuid) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.admin_record_login_attempt(uuid, boolean, text, inet, text) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.admin_request_login_approval(inet, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_respond_login_approval(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_override_login(text, inet, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_session(boolean, uuid, inet, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_validate_session(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_revoke_session(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_revoke_all_other_sessions() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_my_sessions() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_send_email_otp() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_verify_email_otp(text) TO authenticated;