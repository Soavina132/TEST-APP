-- Migration: Admin full control over users
-- Functions to modify email, pseudo, phone, verify phone, disable 2FA, reset password

-- ── 1. Admin: update user email (auth.users + profiles) ──
CREATE OR REPLACE FUNCTION public.admin_update_user_email(_user_id uuid, _email text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
BEGIN
  -- Update auth.users email
  UPDATE auth.users SET email = lower(_email), email_change = now() WHERE id = _user_id;
  -- Update profiles email
  UPDATE public.profiles SET email = lower(_email) WHERE id = _user_id;
  -- Log the action
  INSERT INTO public.admin_logs(action, target_user, note)
    VALUES('email_change', _user_id, 'Email changé par admin: ' || lower(_email));
END $$;
REVOKE ALL ON FUNCTION public.admin_update_user_email(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_user_email(uuid, text) TO authenticated;

-- ── 2. Admin: update user pseudo ──
CREATE OR REPLACE FUNCTION public.admin_update_user_pseudo(_user_id uuid, _pseudo text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _existing int;
BEGIN
  -- Check uniqueness
  SELECT count(*) INTO _existing FROM public.profiles WHERE lower(pseudo) = lower(_pseudo) AND id != _user_id;
  IF _existing > 0 THEN
    RAISE EXCEPTION 'Ce pseudo est déjà utilisé';
  END IF;
  UPDATE public.profiles SET pseudo = _pseudo WHERE id = _user_id;
  INSERT INTO public.admin_logs(action, target_user, note)
    VALUES('pseudo_change', _user_id, 'Pseudo changé par admin: ' || _pseudo);
END $$;
REVOKE ALL ON FUNCTION public.admin_update_user_pseudo(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_user_pseudo(uuid, text) TO authenticated;

-- ── 3. Admin: update user phone ──
CREATE OR REPLACE FUNCTION public.admin_update_user_phone(_user_id uuid, _phone text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.profiles SET phone = _phone, phone_verified = false WHERE id = _user_id;
  INSERT INTO public.admin_logs(action, target_user, note)
    VALUES('phone_change', _user_id, 'Téléphone changé par admin: ' || _phone);
END $$;
REVOKE ALL ON FUNCTION public.admin_update_user_phone(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_user_phone(uuid, text) TO authenticated;

-- ── 4. Admin: verify user phone (manual verification) ──
CREATE OR REPLACE FUNCTION public.admin_verify_user_phone(_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.profiles SET phone_verified = true WHERE id = _user_id;
  INSERT INTO public.admin_logs(action, target_user, note)
    VALUES('phone_verified', _user_id, 'Téléphone vérifié manuellement par admin');
END $$;
REVOKE ALL ON FUNCTION public.admin_verify_user_phone(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_verify_user_phone(uuid) TO authenticated;

-- ── 5. Admin: disable 2FA for a user ──
CREATE OR REPLACE FUNCTION public.admin_disable_user_2fa(_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  DELETE FROM public.user_totp_secrets WHERE user_id = _user_id;
  UPDATE public.profiles SET two_factor_enabled = false WHERE id = _user_id;
  INSERT INTO public.admin_logs(action, target_user, note)
    VALUES('2fa_disabled', _user_id, '2FA désactivée par admin');
END $$;
REVOKE ALL ON FUNCTION public.admin_disable_user_2fa(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_disable_user_2fa(uuid) TO authenticated;

-- ── 6. Admin: reset user password ──
CREATE OR REPLACE FUNCTION public.admin_reset_user_password(_user_id uuid, _new_password text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
BEGIN
  IF length(_new_password) < 8 THEN
    RAISE EXCEPTION 'Le mot de passe doit faire au moins 8 caractères';
  END IF;
  -- Update the encrypted password in auth.users
  UPDATE auth.users 
    SET encrypted_password = crypt(_new_password, gen_salt('bf')), 
        email_change = now(),
        updated_at = now()
    WHERE id = _user_id;
  INSERT INTO public.admin_logs(action, target_user, note)
    VALUES('password_reset', _user_id, 'Mot de passe réinitialisé par admin');
END $$;
REVOKE ALL ON FUNCTION public.admin_reset_user_password(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_reset_user_password(uuid, text) TO authenticated;

-- ── 7. Admin: get user details (full profile + 2FA status) ──
CREATE OR REPLACE FUNCTION public.admin_get_user_details(_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'profile', to_jsonb(p.*),
    'has_2fa', EXISTS(SELECT 1 FROM public.user_totp_secrets WHERE user_id = _user_id AND enabled = true),
    'is_admin', EXISTS(SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = 'admin')
  ) INTO _result
  FROM public.profiles p WHERE p.id = _user_id;
  RETURN _result;
END $$;
REVOKE ALL ON FUNCTION public.admin_get_user_details(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_user_details(uuid) TO authenticated;
