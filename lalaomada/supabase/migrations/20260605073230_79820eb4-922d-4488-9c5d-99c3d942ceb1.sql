
-- 1) Fix request_phone_verification: qualify digest with extensions schema
CREATE OR REPLACE FUNCTION public.request_phone_verification(_phone text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_uid uuid := auth.uid(); v_code text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth'; END IF;
  v_code := lpad((floor(random()*1000000))::int::text, 6, '0');
  UPDATE public.profiles
    SET phone = _phone,
        phone_verified = false,
        phone_verification_code = v_code,
        phone_verification_code_hash = encode(extensions.digest(v_code || id::text, 'sha256'), 'hex'),
        phone_verification_requested_at = now()
    WHERE id = v_uid;
  RETURN v_code;
END $function$;

-- 2) Fix verify_phone_code too
CREATE OR REPLACE FUNCTION public.verify_phone_code(_code text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_uid uuid := auth.uid(); v_hash text; v_expected text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth'; END IF;
  SELECT phone_verification_code_hash INTO v_hash FROM public.profiles WHERE id = v_uid;
  IF v_hash IS NULL THEN RETURN false; END IF;
  v_expected := encode(extensions.digest(_code || v_uid::text, 'sha256'), 'hex');
  IF v_hash = v_expected THEN
    UPDATE public.profiles
      SET phone_verified = true,
          phone_verification_code = NULL,
          phone_verification_code_hash = NULL
      WHERE id = v_uid;
    RETURN true;
  END IF;
  RETURN false;
END $function$;

-- 3) Storage: avatars SELECT policy (needed for upsert to check existing row)
DROP POLICY IF EXISTS "Avatars are publicly readable" ON storage.objects;
CREATE POLICY "Avatars are publicly readable"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');
