
-- 1) finish_game: only allow participants, host or admin to call it (and only callers themselves)
CREATE OR REPLACE FUNCTION public.finish_game(_game_id uuid, _winner_id uuid)
RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_game public.ludo_games%ROWTYPE;
  v_payout NUMERIC;
  v_referrer UUID;
  v_ref_pct NUMERIC;
  v_ref_amount NUMERIC;
  v_caller uuid := auth.uid();
BEGIN
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_game.status = 'finished' THEN RETURN 0; END IF;

  -- AUTH GUARD: only an internal SECURITY DEFINER caller (auth.uid() NULL inside DB cron etc),
  -- or a participant / host / admin can trigger.
  IF v_caller IS NOT NULL
     AND v_caller <> v_game.host_id
     AND NOT public._is_game_participant(_game_id, v_caller)
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Non autorisé';
  END IF;

  IF _winner_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.ludo_participants WHERE game_id=_game_id AND user_id=_winner_id AND is_bot=FALSE
  ) THEN
    RAISE EXCEPTION 'Gagnant invalide';
  END IF;

  v_payout := v_game.pot * (100 - v_game.commission_pct) / 100.0;
  UPDATE public.ludo_games SET status='finished', winner_id=_winner_id, finished_at=now() WHERE id=_game_id;

  IF _winner_id IS NOT NULL THEN
    UPDATE public.profiles SET balance_ar = balance_ar + v_payout WHERE id=_winner_id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note) VALUES (_winner_id,'win',v_payout,_game_id,'Gain partie');

    SELECT referred_by INTO v_referrer FROM public.profiles WHERE id=_winner_id;
    IF v_referrer IS NOT NULL THEN
      SELECT referral_pct INTO v_ref_pct FROM public.app_settings WHERE id=1;
      v_ref_amount := v_payout * COALESCE(v_ref_pct,0) / 100.0;
      IF v_ref_amount > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + v_ref_amount WHERE id=v_referrer;
        INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
          VALUES (v_referrer,'referral',v_ref_amount,_game_id,'Bonus parrainage');
      END IF;
    END IF;
  END IF;

  RETURN v_payout;
END $function$;

-- Restrict direct execution: caller must be one of the actors above; revoke from broad authenticated
REVOKE EXECUTE ON FUNCTION public.finish_game(uuid,uuid) FROM PUBLIC, anon, authenticated;

-- 2) chat_send: enforce room membership server-side
CREATE OR REPLACE FUNCTION public.chat_send(_room_id uuid, _body text, _reply_to uuid DEFAULT NULL::uuid, _attachment_url text DEFAULT NULL::text, _attachment_type text DEFAULT NULL::text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_me uuid:=auth.uid(); v_id uuid; v_count int; v_mute public.chat_mutes%ROWTYPE;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'auth'; END IF;

  -- ROOM ACCESS GUARD
  IF NOT EXISTS (
    SELECT 1 FROM public.chat_rooms r WHERE r.id = _room_id AND r.enabled = true AND (
      r.type = 'global'
      OR (r.type = 'dm' AND (r.dm_user_a = v_me OR r.dm_user_b = v_me))
      OR (r.type = 'game' AND (
            public._is_game_participant(r.game_id, v_me)
            OR EXISTS (SELECT 1 FROM public.game_spectators s WHERE s.game_id=r.game_id AND s.user_id=v_me)
         ))
      OR public.is_admin()
    )
  ) THEN
    RAISE EXCEPTION 'Accès refusé à ce salon';
  END IF;

  SELECT * INTO v_mute FROM public.chat_mutes WHERE user_id=v_me;
  IF v_mute.user_id IS NOT NULL AND (v_mute.banned OR (v_mute.until IS NOT NULL AND v_mute.until>now())) THEN
    RAISE EXCEPTION 'Vous êtes muté';
  END IF;
  SELECT count(*) INTO v_count FROM public.chat_messages WHERE user_id=v_me AND created_at>now()-interval '5 seconds';
  IF v_count >= 5 THEN RAISE EXCEPTION 'Trop de messages, ralentissez'; END IF;
  INSERT INTO public.chat_messages(room_id,user_id,body,reply_to,attachment_url,attachment_type)
    VALUES (_room_id, v_me, NULLIF(_body,''), _reply_to, _attachment_url, _attachment_type) RETURNING id INTO v_id;
  RETURN v_id;
END $function$;

-- 3) game_spectators: restrict SELECT to games the user can see
DROP POLICY IF EXISTS spectators_select ON public.game_spectators;
CREATE POLICY spectators_select ON public.game_spectators
  FOR SELECT TO authenticated
  USING (public._game_visible(game_id));

-- 4) profiles_self_update_safe: also lock phone-verification fields and phone (after verified)
DROP POLICY IF EXISTS profiles_self_update_safe ON public.profiles;
CREATE POLICY profiles_self_update_safe ON public.profiles
  FOR UPDATE TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (
    auth.uid() = id
    AND balance_ar = (SELECT balance_ar FROM public.profiles WHERE id = auth.uid())
    AND banned = (SELECT banned FROM public.profiles WHERE id = auth.uid())
    AND status = (SELECT status FROM public.profiles WHERE id = auth.uid())
    AND unique_code = (SELECT unique_code FROM public.profiles WHERE id = auth.uid())
    AND referral_code = (SELECT referral_code FROM public.profiles WHERE id = auth.uid())
    AND phone_verified = (SELECT phone_verified FROM public.profiles WHERE id = auth.uid())
    AND referral_unlocked = (SELECT referral_unlocked FROM public.profiles WHERE id = auth.uid())
    AND COALESCE(referred_by::text,'') = COALESCE((SELECT referred_by::text FROM public.profiles WHERE id = auth.uid()),'')
    -- new locks
    AND COALESCE(phone_verification_code,'') = COALESCE((SELECT phone_verification_code FROM public.profiles WHERE id = auth.uid()),'')
    AND COALESCE(phone_verification_requested_at::text,'') = COALESCE((SELECT phone_verification_requested_at::text FROM public.profiles WHERE id = auth.uid()),'')
    -- block changing phone after verified=true
    AND (
      (SELECT phone_verified FROM public.profiles WHERE id = auth.uid()) = false
      OR COALESCE(phone,'') = COALESCE((SELECT phone FROM public.profiles WHERE id = auth.uid()),'')
    )
  );

-- 5) Storage: chat bucket SELECT + DELETE policies (bucket is public; we still scope DELETE to owner)
CREATE POLICY "chat_public_read" ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'chat');

CREATE POLICY "chat_owner_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'chat' AND (auth.uid())::text = (storage.foldername(name))[1]);

-- 6) Function search_path hardening for the remaining helpers
ALTER FUNCTION public._ludo_start_idx(integer) SET search_path = public;
ALTER FUNCTION public._ludo_is_safe(integer) SET search_path = public;
ALTER FUNCTION public._ludo_init_state(integer) SET search_path = public;
ALTER FUNCTION public._ludo_next_slot(uuid, integer, integer) SET search_path = public;
ALTER FUNCTION public._ludo_check_last_standing(uuid) SET search_path = public;
ALTER FUNCTION public._ludo_active_humans(uuid) SET search_path = public;
ALTER FUNCTION public._ludo_ensure_state(uuid) SET search_path = public;
