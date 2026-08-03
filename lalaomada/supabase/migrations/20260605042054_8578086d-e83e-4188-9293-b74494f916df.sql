-- 1. Hash phone verification codes
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS phone_verification_code_hash text;

CREATE OR REPLACE FUNCTION public.request_phone_verification(_phone text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_uid uuid := auth.uid(); v_code text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth'; END IF;
  v_code := lpad((floor(random()*1000000))::int::text, 6, '0');
  UPDATE public.profiles
    SET phone = _phone,
        phone_verified = false,
        phone_verification_code = NULL,
        phone_verification_code_hash = encode(digest(v_code || id::text, 'sha256'), 'hex'),
        phone_verification_requested_at = now()
    WHERE id = v_uid;
  RETURN v_code;
END $$;

CREATE OR REPLACE FUNCTION public.verify_phone_code(_code text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_uid uuid := auth.uid(); v_hash text; v_expected text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth'; END IF;
  SELECT phone_verification_code_hash INTO v_hash FROM public.profiles WHERE id = v_uid;
  IF v_hash IS NULL THEN RETURN false; END IF;
  v_expected := encode(digest(_code || v_uid::text, 'sha256'), 'hex');
  IF v_hash = v_expected THEN
    UPDATE public.profiles
      SET phone_verified = true,
          phone_verification_code = NULL,
          phone_verification_code_hash = NULL
      WHERE id = v_uid;
    RETURN true;
  END IF;
  RETURN false;
END $$;

REVOKE EXECUTE ON FUNCTION public.request_phone_verification(text) FROM public, anon;
REVOKE EXECUTE ON FUNCTION public.verify_phone_code(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.request_phone_verification(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.verify_phone_code(text) TO authenticated;

-- Clear plaintext codes
UPDATE public.profiles SET phone_verification_code = NULL WHERE phone_verification_code IS NOT NULL;

-- Update profiles_self_update_safe to lock the new hash column too
DROP POLICY IF EXISTS profiles_self_update_safe ON public.profiles;
CREATE POLICY profiles_self_update_safe ON public.profiles
FOR UPDATE TO authenticated
USING (auth.uid() = id)
WITH CHECK (
  auth.uid() = id
  AND balance_ar = (SELECT p.balance_ar FROM public.profiles p WHERE p.id = auth.uid())
  AND banned = (SELECT p.banned FROM public.profiles p WHERE p.id = auth.uid())
  AND status = (SELECT p.status FROM public.profiles p WHERE p.id = auth.uid())
  AND unique_code = (SELECT p.unique_code FROM public.profiles p WHERE p.id = auth.uid())
  AND referral_code = (SELECT p.referral_code FROM public.profiles p WHERE p.id = auth.uid())
  AND phone_verified = (SELECT p.phone_verified FROM public.profiles p WHERE p.id = auth.uid())
  AND referral_unlocked = (SELECT p.referral_unlocked FROM public.profiles p WHERE p.id = auth.uid())
  AND COALESCE(referred_by::text,'') = COALESCE((SELECT p.referred_by::text FROM public.profiles p WHERE p.id = auth.uid()),'')
  AND COALESCE(phone_verification_code,'') = COALESCE((SELECT p.phone_verification_code FROM public.profiles p WHERE p.id = auth.uid()),'')
  AND COALESCE(phone_verification_code_hash,'') = COALESCE((SELECT p.phone_verification_code_hash FROM public.profiles p WHERE p.id = auth.uid()),'')
  AND COALESCE(phone_verification_requested_at::text,'') = COALESCE((SELECT p.phone_verification_requested_at::text FROM public.profiles p WHERE p.id = auth.uid()),'')
  AND ((SELECT p.phone_verified FROM public.profiles p WHERE p.id = auth.uid()) = false
       OR COALESCE(phone,'') = COALESCE((SELECT p.phone FROM public.profiles p WHERE p.id = auth.uid()),''))
);

-- 2. Restrict chat_members insert: only global rooms (or admin), block DM/game self-add
DROP POLICY IF EXISTS chat_members_insert ON public.chat_members;
CREATE POLICY chat_members_insert ON public.chat_members
FOR INSERT TO authenticated
WITH CHECK (
  user_id = auth.uid()
  AND (
    public.is_admin()
    OR EXISTS (SELECT 1 FROM public.chat_rooms r WHERE r.id = room_id AND r.type = 'global' AND r.joinable = true AND r.enabled = true)
  )
);

-- 3. Restrict chat_reactions SELECT to room members
DROP POLICY IF EXISTS chat_reactions_all ON public.chat_reactions;
CREATE POLICY chat_reactions_select ON public.chat_reactions
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.chat_messages m
    JOIN public.chat_rooms r ON r.id = m.room_id
    WHERE m.id = chat_reactions.message_id
      AND (
        r.type = 'global'
        OR (r.type = 'dm' AND (r.dm_user_a = auth.uid() OR r.dm_user_b = auth.uid()))
        OR (r.type = 'game' AND (
          public._is_game_participant(r.game_id, auth.uid())
          OR EXISTS (SELECT 1 FROM public.game_spectators s WHERE s.game_id = r.game_id AND s.user_id = auth.uid())
        ))
        OR public.is_admin()
      )
  )
);

-- 4. Restrict withdrawals INSERT to authenticated role
DROP POLICY IF EXISTS withdrawals_insert ON public.withdrawals;
CREATE POLICY withdrawals_insert ON public.withdrawals
FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id AND status = 'pending'::tx_status);

-- Also tighten deposits_insert to authenticated (same edge-case hygiene)
DROP POLICY IF EXISTS deposits_insert ON public.deposits;
CREATE POLICY deposits_insert ON public.deposits
FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id AND status = 'pending'::tx_status);
