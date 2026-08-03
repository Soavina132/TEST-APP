-- Update handle_new_user to support phone-only signups (no email)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_pseudo TEXT;
  v_ref_code TEXT;
  v_referred_by UUID;
  v_input_ref TEXT;
  v_bonus NUMERIC;
  v_phone TEXT;
BEGIN
  v_phone := COALESCE(NEW.phone, NEW.raw_user_meta_data->>'phone');
  v_pseudo := COALESCE(
    NEW.raw_user_meta_data->>'pseudo',
    NULLIF(split_part(COALESCE(NEW.email,''),'@',1),''),
    'user_' || substr(NEW.id::text, 1, 8)
  );
  v_input_ref := NEW.raw_user_meta_data->>'referral_code';
  v_ref_code := public.gen_referral_code();

  IF v_input_ref IS NOT NULL AND v_input_ref <> '' THEN
    SELECT id INTO v_referred_by FROM public.profiles WHERE referral_code = upper(v_input_ref);
  END IF;

  SELECT signup_bonus INTO v_bonus FROM public.app_settings WHERE id = 1;

  INSERT INTO public.profiles(id, pseudo, email, phone, referral_code, referred_by, balance_ar)
  VALUES (NEW.id, v_pseudo, NEW.email, v_phone, v_ref_code, v_referred_by, COALESCE(v_bonus,0))
  ON CONFLICT (id) DO NOTHING;

  IF COALESCE(v_bonus,0) > 0 THEN
    INSERT INTO public.transactions(user_id,type,amount,note) VALUES (NEW.id,'bonus',v_bonus,'Bonus inscription');
  END IF;

  IF lower(COALESCE(NEW.email,'')) = 'soavinapierrit@gmail.com' THEN
    INSERT INTO public.user_roles(user_id, role) VALUES (NEW.id, 'admin') ON CONFLICT DO NOTHING;
  ELSE
    INSERT INTO public.user_roles(user_id, role) VALUES (NEW.id, 'user') ON CONFLICT DO NOTHING;
  END IF;

  RETURN NEW;
END $$;

-- Backfill profiles.phone for existing phone-only users (from synthetic emails)
UPDATE public.profiles p
SET phone = COALESCE(p.phone, '+' || substring(p.email FROM 'phone(\d+)@phone\.lalaomada\.local'))
WHERE p.email LIKE 'phone%@phone.lalaomada.local' AND p.phone IS NULL;