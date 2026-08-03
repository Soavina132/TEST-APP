
-- Public RPC: request password reset (unauthenticated users)
CREATE OR REPLACE FUNCTION public.request_password_reset(_contact text, _type text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid;
  v_code text;
  v_norm text;
BEGIN
  IF _type NOT IN ('email','phone') THEN RAISE EXCEPTION 'Type invalide'; END IF;
  v_norm := trim(_contact);
  IF _type = 'email' THEN v_norm := lower(v_norm); END IF;
  IF length(v_norm) < 3 THEN RAISE EXCEPTION 'Contact invalide'; END IF;

  IF _type = 'email' THEN
    SELECT id INTO v_uid FROM public.profiles WHERE lower(email) = v_norm LIMIT 1;
  ELSE
    SELECT id INTO v_uid FROM public.profiles WHERE phone = v_norm LIMIT 1;
  END IF;

  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Aucun compte trouvé avec ce contact';
  END IF;

  v_code := lpad((floor(random()*1000000))::int::text, 6, '0');

  INSERT INTO public.password_reset_requests(user_id, contact, contact_type, code, status)
  VALUES (v_uid, v_norm, _type, v_code, 'pending');

  RETURN v_code;
END;
$$;

REVOKE ALL ON FUNCTION public.request_password_reset(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_password_reset(text,text) TO anon, authenticated;
