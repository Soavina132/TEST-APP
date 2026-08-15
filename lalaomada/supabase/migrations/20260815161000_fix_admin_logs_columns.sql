-- Fix admin_* functions to use correct admin_logs column names
-- admin_logs has: admin_id, target_user_id, action, old_value, new_value

-- ── 1. Fix admin_update_user_email ──
CREATE OR REPLACE FUNCTION public.admin_update_user_email(_user_id uuid, _email text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE _old_email text;
BEGIN
  SELECT email INTO _old_email FROM public.profiles WHERE id = _user_id;
  UPDATE auth.users SET email = lower(_email), email_change = now() WHERE id = _user_id;
  UPDATE public.profiles SET email = lower(_email) WHERE id = _user_id;
  INSERT INTO public.admin_logs(admin_id, target_user_id, action, old_value, new_value)
    VALUES(auth.uid(), _user_id, 'email_change', to_jsonb(_old_email), to_jsonb(lower(_email)));
END $$;
REVOKE ALL ON FUNCTION public.admin_update_user_email(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_user_email(uuid, text) TO authenticated;

-- ── 2. Fix admin_update_user_pseudo ──
CREATE OR REPLACE FUNCTION public.admin_update_user_pseudo(_user_id uuid, _pseudo text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _existing int; _old_pseudo text;
BEGIN
  SELECT count(*) INTO _existing FROM public.profiles WHERE lower(pseudo) = lower(_pseudo) AND id != _user_id;
  IF _existing > 0 THEN RAISE EXCEPTION 'Ce pseudo est déjà utilisé'; END IF;
  SELECT pseudo INTO _old_pseudo FROM public.profiles WHERE id = _user_id;
  UPDATE public.profiles SET pseudo = _pseudo WHERE id = _user_id;
  INSERT INTO public.admin_logs(admin_id, target_user_id, action, old_value, new_value)
    VALUES(auth.uid(), _user_id, 'pseudo_change', to_jsonb(_old_pseudo), to_jsonb(_pseudo));
END $$;
REVOKE ALL ON FUNCTION public.admin_update_user_pseudo(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_user_pseudo(uuid, text) TO authenticated;

-- ── 3. Fix admin_update_user_phone ──
CREATE OR REPLACE FUNCTION public.admin_update_user_phone(_user_id uuid, _phone text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _old_phone text;
BEGIN
  SELECT phone INTO _old_phone FROM public.profiles WHERE id = _user_id;
  UPDATE public.profiles SET phone = _phone, phone_verified = false WHERE id = _user_id;
  INSERT INTO public.admin_logs(admin_id, target_user_id, action, old_value, new_value)
    VALUES(auth.uid(), _user_id, 'phone_change', to_jsonb(_old_phone), to_jsonb(_phone));
END $$;
REVOKE ALL ON FUNCTION public.admin_update_user_phone(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_user_phone(uuid, text) TO authenticated;

-- ── 4. Fix admin_verify_user_phone ──
CREATE OR REPLACE FUNCTION public.admin_verify_user_phone(_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.profiles SET phone_verified = true WHERE id = _user_id;
  INSERT INTO public.admin_logs(admin_id, target_user_id, action, old_value, new_value)
    VALUES(auth.uid(), _user_id, 'phone_verified', 'false'::jsonb, 'true'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_verify_user_phone(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_verify_user_phone(uuid) TO authenticated;

-- ── 5. Fix admin_disable_user_2fa ──
CREATE OR REPLACE FUNCTION public.admin_disable_user_2fa(_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  DELETE FROM public.user_totp_secrets WHERE user_id = _user_id;
  UPDATE public.profiles SET two_factor_enabled = false WHERE id = _user_id;
  INSERT INTO public.admin_logs(admin_id, target_user_id, action, old_value, new_value)
    VALUES(auth.uid(), _user_id, '2fa_disabled', 'true'::jsonb, 'false'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_disable_user_2fa(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_disable_user_2fa(uuid) TO authenticated;

-- ── 6. Fix admin_reset_user_password ──
CREATE OR REPLACE FUNCTION public.admin_reset_user_password(_user_id uuid, _new_password text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
BEGIN
  IF length(_new_password) < 8 THEN RAISE EXCEPTION 'Le mot de passe doit faire au moins 8 caractères'; END IF;
  UPDATE auth.users 
    SET encrypted_password = crypt(_new_password, gen_salt('bf')), 
        email_change = now(),
        updated_at = now()
    WHERE id = _user_id;
  INSERT INTO public.admin_logs(admin_id, target_user_id, action, old_value, new_value)
    VALUES(auth.uid(), _user_id, 'password_reset', null, '***'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_reset_user_password(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_reset_user_password(uuid, text) TO authenticated;
