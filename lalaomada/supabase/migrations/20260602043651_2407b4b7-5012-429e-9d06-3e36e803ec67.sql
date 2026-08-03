
-- =========================================================================
-- 1. CGU
-- =========================================================================
ALTER TABLE public.app_settings ADD COLUMN IF NOT EXISTS terms_text text DEFAULT '';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS terms_accepted_at timestamptz;

CREATE OR REPLACE FUNCTION public.accept_terms()
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path=public AS $$
  UPDATE public.profiles SET terms_accepted_at = now() WHERE id = auth.uid();
$$;

-- =========================================================================
-- 2. Téléphone + parrainage
-- =========================================================================
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS phone text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS phone_verified boolean NOT NULL DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS phone_verification_code text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS phone_verification_requested_at timestamptz;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS referral_unlocked boolean NOT NULL DEFAULT false;

CREATE UNIQUE INDEX IF NOT EXISTS profiles_phone_verified_uniq
  ON public.profiles(phone) WHERE phone_verified = true;

CREATE OR REPLACE FUNCTION public.request_phone_verification(_phone text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_code text; v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _phone IS NULL OR length(trim(_phone))<8 THEN RAISE EXCEPTION 'Numéro invalide'; END IF;
  IF EXISTS (SELECT 1 FROM public.profiles WHERE phone=_phone AND phone_verified=true AND id<>v_uid) THEN
    RAISE EXCEPTION 'Numéro déjà utilisé';
  END IF;
  v_code := 'LM' || lpad((floor(random()*10000))::int::text, 4, '0');
  UPDATE public.profiles
    SET phone = _phone, phone_verified = false,
        phone_verification_code = v_code,
        phone_verification_requested_at = now()
    WHERE id = v_uid;
  RETURN v_code;
END $$;

CREATE OR REPLACE FUNCTION public.admin_verify_phone(_user_id uuid, _approve boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  IF _approve THEN
    UPDATE public.profiles SET phone_verified = true, phone_verification_code = NULL WHERE id = _user_id;
  ELSE
    UPDATE public.profiles SET phone_verified = false, phone_verification_code = NULL, phone_verification_requested_at = NULL WHERE id = _user_id;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.admin_list_phone_requests()
RETURNS TABLE(id uuid, pseudo text, phone text, code text, requested_at timestamptz)
LANGUAGE sql SECURITY DEFINER SET search_path=public AS $$
  SELECT p.id, p.pseudo, p.phone, p.phone_verification_code, p.phone_verification_requested_at
  FROM public.profiles p
  WHERE p.phone IS NOT NULL AND p.phone_verified = false AND p.phone_verification_code IS NOT NULL
  ORDER BY p.phone_verification_requested_at DESC;
$$;

-- Trigger parrainage: au 1er dépôt approuvé, si filleul a phone_verified, crédite parrain
CREATE OR REPLACE FUNCTION public._referral_on_deposit()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_parent uuid; v_pct numeric; v_reward numeric; v_verified boolean; v_unlocked boolean;
BEGIN
  IF NEW.status='approved' AND (OLD.status IS NULL OR OLD.status<>'approved') THEN
    SELECT referred_by, phone_verified, referral_unlocked INTO v_parent, v_verified, v_unlocked
      FROM public.profiles WHERE id=NEW.user_id;
    IF v_parent IS NOT NULL AND v_verified=true AND v_unlocked=false THEN
      SELECT referral_pct INTO v_pct FROM public.app_settings WHERE id=1;
      v_reward := NEW.amount * COALESCE(v_pct,5)/100.0;
      UPDATE public.profiles SET balance_ar = balance_ar + v_reward WHERE id=v_parent;
      UPDATE public.profiles SET referral_unlocked=true WHERE id=NEW.user_id;
      INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
        VALUES (v_parent,'referral',v_reward,NEW.id,'Parrainage débloqué');
    END IF;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_referral_on_deposit ON public.deposits;
CREATE TRIGGER trg_referral_on_deposit AFTER UPDATE ON public.deposits
  FOR EACH ROW EXECUTE FUNCTION public._referral_on_deposit();

-- =========================================================================
-- 3. Chat: champ joinable + jointure
-- =========================================================================
ALTER TABLE public.chat_rooms ADD COLUMN IF NOT EXISTS joinable boolean NOT NULL DEFAULT true;

CREATE TABLE IF NOT EXISTS public.chat_members (
  room_id uuid NOT NULL,
  user_id uuid NOT NULL,
  joined_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (room_id, user_id)
);
GRANT SELECT, INSERT, DELETE ON public.chat_members TO authenticated;
GRANT ALL ON public.chat_members TO service_role;
ALTER TABLE public.chat_members ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS chat_members_read ON public.chat_members;
CREATE POLICY chat_members_read ON public.chat_members FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS chat_members_insert ON public.chat_members;
CREATE POLICY chat_members_insert ON public.chat_members FOR INSERT TO authenticated WITH CHECK (user_id=auth.uid());
DROP POLICY IF EXISTS chat_members_delete ON public.chat_members;
CREATE POLICY chat_members_delete ON public.chat_members FOR DELETE TO authenticated USING (user_id=auth.uid() OR is_admin());

CREATE OR REPLACE FUNCTION public.chat_join_room(_room_id uuid)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path=public AS $$
  INSERT INTO public.chat_members(room_id,user_id) VALUES (_room_id, auth.uid()) ON CONFLICT DO NOTHING;
$$;
CREATE OR REPLACE FUNCTION public.chat_leave_room(_room_id uuid)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path=public AS $$
  DELETE FROM public.chat_members WHERE room_id=_room_id AND user_id=auth.uid();
$$;

-- =========================================================================
-- 4. Suppression compte (soft)
-- =========================================================================
CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path=public AS $$
  UPDATE public.profiles SET banned=true, status='deleted' WHERE id=auth.uid();
$$;

-- =========================================================================
-- 5. Super-player: forcer le dé
-- =========================================================================
CREATE OR REPLACE FUNCTION public.super_player_set_dice(_game_id uuid, _slot int, _value int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  IF _value NOT BETWEEN 1 AND 6 THEN RAISE EXCEPTION 'valeur invalide'; END IF;
  UPDATE public.ludo_games
    SET dice_override = COALESCE(dice_override,'{}'::jsonb) || jsonb_build_object(_slot::text, _value)
    WHERE id=_game_id;
END $$;

-- =========================================================================
-- 6. Admin liste users triée
-- =========================================================================
CREATE OR REPLACE FUNCTION public.admin_list_users_sorted(_sort text)
RETURNS TABLE(id uuid, pseudo text, email text, balance_ar numeric, created_at timestamptz, is_admin boolean, phone_verified boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  RETURN QUERY
    SELECT p.id, p.pseudo, p.email, p.balance_ar, p.created_at,
      EXISTS(SELECT 1 FROM public.user_roles r WHERE r.user_id=p.id AND r.role='admin'),
      p.phone_verified
    FROM public.profiles p
    ORDER BY
      CASE WHEN _sort='balance' THEN p.balance_ar END DESC NULLS LAST,
      CASE WHEN _sort='pseudo' THEN p.pseudo END ASC,
      CASE WHEN _sort='recent' OR _sort IS NULL OR _sort='' THEN p.created_at END DESC;
END $$;

-- =========================================================================
-- 7. Garde-fou: bloquer ludo_set_ready si non vérifié
-- =========================================================================
CREATE OR REPLACE FUNCTION public.ludo_set_ready(_game_id uuid, _ready boolean)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public
AS $function$
DECLARE v_uid UUID := auth.uid(); v_game public.ludo_games%ROWTYPE;
  v_total int; v_ready int; v_verified boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT phone_verified INTO v_verified FROM public.profiles WHERE id=v_uid;
  IF _ready AND NOT COALESCE(v_verified,false) THEN
    RAISE EXCEPTION 'Vérifiez votre numéro de téléphone dans votre profil';
  END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL OR v_game.status <> 'open' THEN RAISE EXCEPTION 'Partie non ouverte'; END IF;
  UPDATE public.ludo_participants SET ready=_ready, last_seen=now()
    WHERE game_id=_game_id AND user_id=v_uid;
  SELECT count(*), count(*) FILTER (WHERE ready OR is_bot)
    INTO v_total, v_ready
    FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_total = v_game.max_players AND v_ready = v_total THEN
    UPDATE public.ludo_games SET status='playing', started_at=now(),
      state=public._ludo_init_state(v_game.max_players) WHERE id=_game_id;
  END IF;
END $function$;
