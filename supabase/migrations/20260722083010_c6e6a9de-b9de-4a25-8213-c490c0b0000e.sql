
-- 1) Nouveaux paramètres configurables
ALTER TABLE public.referral_settings
  ADD COLUMN IF NOT EXISTS stake_commission_pct numeric NOT NULL DEFAULT 5,
  ADD COLUMN IF NOT EXISTS stake_commission_max_matches integer NOT NULL DEFAULT 10;

-- Neutraliser les anciennes récompenses (dépôt / classique)
UPDATE public.referral_settings
   SET deposit_bonus_pct = 0,
       win_commission_pct = 0,
       require_first_deposit = false
 WHERE id = 1;

-- 2) Compteur de parties avec mise déjà comptabilisées pour le filleul
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS referral_stake_count integer NOT NULL DEFAULT 0;

-- 3) Neutraliser l'ancienne récompense au dépôt
CREATE OR REPLACE FUNCTION public._referral_on_deposit()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
  -- Plus aucune récompense au dépôt : parrainage payé à la mise (voir _referral_on_stake).
  RETURN NEW;
END;
$function$;

-- Ancien "déblocage" plus utilisé : on le rend inoffensif
CREATE OR REPLACE FUNCTION public._try_unlock_referral(_uid uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
  -- No-op : la commission de parrainage se calcule maintenant à chaque mise.
  RETURN;
END;
$function$;

-- 4) Nouvelle logique : 5 % de la mise du filleul, sur ses N premières parties payantes
CREATE OR REPLACE FUNCTION public._referral_on_stake()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
  v_stake numeric;
  v_parent uuid;
  v_count integer;
  v_cfg public.referral_settings%ROWTYPE;
  v_reward numeric;
  v_pseudo text;
  v_event_type text;
BEGIN
  -- On ne traite que les mises (types finissant par _stake ou 'stake')
  IF NEW.type IS NULL OR (NEW.type <> 'stake' AND NEW.type NOT LIKE '%\_stake' ESCAPE '\') THEN
    RETURN NEW;
  END IF;

  v_stake := ABS(COALESCE(NEW.amount, 0));
  IF v_stake <= 0 THEN RETURN NEW; END IF;

  -- Filleul a-t-il un parrain ?
  SELECT referred_by, referral_stake_count
    INTO v_parent, v_count
    FROM public.profiles WHERE id = NEW.user_id;

  IF v_parent IS NULL OR v_parent = NEW.user_id THEN RETURN NEW; END IF;

  SELECT * INTO v_cfg FROM public.referral_settings WHERE id = 1;
  IF NOT v_cfg.enabled THEN RETURN NEW; END IF;
  IF v_count >= v_cfg.stake_commission_max_matches THEN RETURN NEW; END IF;

  v_reward := ROUND(v_stake * (v_cfg.stake_commission_pct / 100.0), 0);
  IF v_reward <= 0 THEN RETURN NEW; END IF;

  -- Crédit du parrain
  UPDATE public.profiles SET balance_ar = balance_ar + v_reward WHERE id = v_parent;

  -- Incrémente le compteur du filleul
  UPDATE public.profiles
     SET referral_stake_count = referral_stake_count + 1
   WHERE id = NEW.user_id;

  SELECT pseudo INTO v_pseudo FROM public.profiles WHERE id = NEW.user_id;
  v_event_type := 'stake_' || (v_count + 1)::text;

  BEGIN
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
    VALUES (v_parent, 'referral', v_reward, NEW.id,
      format('Parrainage %s — %s%% de sa mise n°%s (%s Ar)',
        COALESCE(v_pseudo,'filleul'), v_cfg.stake_commission_pct, v_count + 1, v_stake));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  BEGIN
    INSERT INTO public.referral_events(referrer_id, referee_id, event_type, reward_amount, note)
    VALUES (v_parent, NEW.user_id, v_event_type, v_reward,
      format('%s%% de la mise n°%s (%s Ar)', v_cfg.stake_commission_pct, v_count + 1, v_stake))
    ON CONFLICT (referee_id, event_type) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  BEGIN
    INSERT INTO public.notifications(user_id, kind, title, body, link)
    VALUES (v_parent, 'referral',
      'Commission parrainage 🎉',
      format('Vous avez gagné %s Ar sur la mise de %s (partie %s/%s).',
        to_char(v_reward,'FM999G999G999'),
        COALESCE(v_pseudo,'votre filleul'),
        v_count + 1, v_cfg.stake_commission_max_matches),
      '/parrainage');
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_referral_on_stake ON public.transactions;
CREATE TRIGGER trg_referral_on_stake
  AFTER INSERT ON public.transactions
  FOR EACH ROW EXECUTE FUNCTION public._referral_on_stake();

-- 5) Étendre admin_update_referral_settings
CREATE OR REPLACE FUNCTION public.admin_update_referral_settings(
  _deposit_bonus_pct numeric DEFAULT NULL,
  _deposit_min_ar numeric DEFAULT NULL,
  _win_commission_pct numeric DEFAULT NULL,
  _tier_silver_min integer DEFAULT NULL,
  _tier_gold_min integer DEFAULT NULL,
  _tier_diamond_min integer DEFAULT NULL,
  _tier_silver_mult numeric DEFAULT NULL,
  _tier_gold_mult numeric DEFAULT NULL,
  _tier_diamond_mult numeric DEFAULT NULL,
  _require_phone boolean DEFAULT NULL,
  _max_daily integer DEFAULT NULL,
  _auto_flag_velocity integer DEFAULT NULL,
  _enabled boolean DEFAULT NULL,
  _campaign_label text DEFAULT NULL,
  _campaign_expires timestamptz DEFAULT NULL,
  _campaign_bonus_pct numeric DEFAULT NULL,
  _stake_commission_pct numeric DEFAULT NULL,
  _stake_commission_max_matches integer DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Accès refusé'; END IF;
  UPDATE public.referral_settings SET
    deposit_bonus_pct = COALESCE(_deposit_bonus_pct, deposit_bonus_pct),
    deposit_min_ar = COALESCE(_deposit_min_ar, deposit_min_ar),
    win_commission_pct = COALESCE(_win_commission_pct, win_commission_pct),
    tier_silver_min = COALESCE(_tier_silver_min, tier_silver_min),
    tier_gold_min = COALESCE(_tier_gold_min, tier_gold_min),
    tier_diamond_min = COALESCE(_tier_diamond_min, tier_diamond_min),
    tier_silver_mult = COALESCE(_tier_silver_mult, tier_silver_mult),
    tier_gold_mult = COALESCE(_tier_gold_mult, tier_gold_mult),
    tier_diamond_mult = COALESCE(_tier_diamond_mult, tier_diamond_mult),
    require_phone_verification = COALESCE(_require_phone, require_phone_verification),
    max_daily_new_referrals = COALESCE(_max_daily, max_daily_new_referrals),
    auto_flag_velocity = COALESCE(_auto_flag_velocity, auto_flag_velocity),
    enabled = COALESCE(_enabled, enabled),
    campaign_label = COALESCE(_campaign_label, campaign_label),
    campaign_expires_at = COALESCE(_campaign_expires, campaign_expires_at),
    campaign_bonus_pct = COALESCE(_campaign_bonus_pct, campaign_bonus_pct),
    stake_commission_pct = COALESCE(_stake_commission_pct, stake_commission_pct),
    stake_commission_max_matches = COALESCE(_stake_commission_max_matches, stake_commission_max_matches),
    updated_at = now()
  WHERE id = 1;
END;
$function$;
