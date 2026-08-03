
-- Contraintes
ALTER TABLE public.referral_settings
  DROP CONSTRAINT IF EXISTS referral_settings_stake_pct_ck,
  DROP CONSTRAINT IF EXISTS referral_settings_stake_max_ck;
ALTER TABLE public.referral_settings
  ADD CONSTRAINT referral_settings_stake_pct_ck
    CHECK (stake_commission_pct IS NULL OR (stake_commission_pct >= 0 AND stake_commission_pct <= 100)),
  ADD CONSTRAINT referral_settings_stake_max_ck
    CHECK (stake_commission_max_matches IS NULL OR stake_commission_max_matches >= 0);

-- Dépôt : plus de bonus
CREATE OR REPLACE FUNCTION public._referral_on_deposit()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_parent uuid;
  v_cfg    public.referral_settings%ROWTYPE;
BEGIN
  IF NEW.status <> 'approved' THEN RETURN NEW; END IF;
  IF OLD.status = 'approved' THEN RETURN NEW; END IF;
  SELECT referred_by INTO v_parent FROM public.profiles WHERE id = NEW.user_id;
  IF v_parent IS NULL OR v_parent = NEW.user_id THEN RETURN NEW; END IF;
  SELECT * INTO v_cfg FROM public.referral_settings WHERE id = 1;
  IF NOT v_cfg.enabled THEN RETURN NEW; END IF;
  UPDATE public.profiles
     SET first_deposit_at = COALESCE(first_deposit_at, now()),
         first_deposit_amount = COALESCE(first_deposit_amount, NEW.amount)
   WHERE id = NEW.user_id;
  INSERT INTO public.referral_events(referrer_id, referee_id, event_type, reward_amount, note)
  VALUES(v_parent, NEW.user_id, 'first_deposit', 0,
         format('1er dépôt %.0f Ar — aucun bonus (règle: commission sur mise uniquement)', NEW.amount))
  ON CONFLICT (referee_id, event_type) DO NOTHING;
  RETURN NEW;
END;
$$;

-- Mise : commission % × N premières parties
CREATE OR REPLACE FUNCTION public._referral_on_stake()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_stake       numeric;
  v_parent      uuid;
  v_count       integer;
  v_cfg         public.referral_settings%ROWTYPE;
  v_reward      numeric;
  v_pseudo      text;
  v_referee_bot boolean;
  v_referee_ban boolean;
  v_parent_bot  boolean;
  v_parent_ban  boolean;
  v_admin_ref   boolean;
BEGIN
  IF NEW.type NOT IN (
    'chess_stake','ludo_stake','domino_stake','fanorona_stake',
    'rami_stake','petanque_stake','poker_stake','billiard_stake'
  ) THEN RETURN NEW; END IF;

  v_stake := ABS(COALESCE(NEW.amount, 0));
  IF v_stake <= 0 THEN RETURN NEW; END IF;

  SELECT * INTO v_cfg FROM public.referral_settings WHERE id = 1;
  IF NOT v_cfg.enabled THEN RETURN NEW; END IF;
  IF COALESCE(v_cfg.stake_commission_pct, 0) <= 0 THEN RETURN NEW; END IF;
  IF COALESCE(v_cfg.stake_commission_max_matches, 0) <= 0 THEN RETURN NEW; END IF;

  SELECT referred_by, referral_stake_count,
         COALESCE(is_bot,false), COALESCE(is_banned,false)
    INTO v_parent, v_count, v_referee_bot, v_referee_ban
    FROM public.profiles WHERE id = NEW.user_id;

  IF v_parent IS NULL OR v_parent = NEW.user_id THEN RETURN NEW; END IF;
  IF v_referee_bot OR v_referee_ban THEN RETURN NEW; END IF;

  SELECT COALESCE(is_bot,false), COALESCE(is_banned,false)
    INTO v_parent_bot, v_parent_ban
    FROM public.profiles WHERE id = v_parent;
  IF v_parent_bot OR v_parent_ban THEN RETURN NEW; END IF;

  SELECT public.has_role(v_parent, 'admin'::public.app_role) INTO v_admin_ref;
  IF v_admin_ref THEN RETURN NEW; END IF;

  IF COALESCE(v_count,0) >= v_cfg.stake_commission_max_matches THEN RETURN NEW; END IF;

  v_reward := ROUND(v_stake * (v_cfg.stake_commission_pct / 100.0), 0);
  IF v_reward <= 0 THEN RETURN NEW; END IF;

  UPDATE public.profiles
     SET referral_stake_count = COALESCE(referral_stake_count,0) + 1
   WHERE id = NEW.user_id
   RETURNING referral_stake_count INTO v_count;

  UPDATE public.profiles SET balance_ar = balance_ar + v_reward WHERE id = v_parent;

  SELECT pseudo INTO v_pseudo FROM public.profiles WHERE id = NEW.user_id;

  BEGIN
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
    VALUES(v_parent, 'referral', v_reward, NEW.id,
      format('Parrainage %s — %s%% de %.0f Ar (partie %s/%s)',
             COALESCE(v_pseudo,'filleul'), v_cfg.stake_commission_pct,
             v_stake, v_count, v_cfg.stake_commission_max_matches));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  BEGIN
    INSERT INTO public.referral_events(referrer_id, referee_id, event_type, reward_amount, note)
    VALUES(v_parent, NEW.user_id, 'stake_' || v_count::text, v_reward,
      format('%s%% × %.0f Ar (partie %s/%s)',
             v_cfg.stake_commission_pct, v_stake,
             v_count, v_cfg.stake_commission_max_matches));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  BEGIN
    INSERT INTO public.notifications(user_id, kind, title, body, link)
    VALUES(v_parent, 'referral', 'Commission parrainage 💰',
      format('+%s Ar : %s a joué (partie %s/%s).',
        to_char(v_reward,'FM999G999G999'),
        COALESCE(v_pseudo,'filleul'), v_count, v_cfg.stake_commission_max_matches),
      '/parrainage');
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN NEW;
END;
$$;

-- Supprimer les surcharges de admin_update_referral_settings
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid AS foid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname='admin_update_referral_settings'
  LOOP
    EXECUTE format('DROP FUNCTION public.admin_update_referral_settings(%s)',
      pg_get_function_identity_arguments(r.foid));
  END LOOP;
END $$;

CREATE FUNCTION public.admin_update_referral_settings(
  _enabled                       boolean  DEFAULT NULL,
  _stake_commission_pct          numeric  DEFAULT NULL,
  _stake_commission_max_matches  integer  DEFAULT NULL,
  _require_phone                 boolean  DEFAULT NULL,
  _max_daily                     integer  DEFAULT NULL,
  _auto_flag_velocity            integer  DEFAULT NULL,
  _campaign_label                text     DEFAULT NULL,
  _campaign_expires              timestamptz DEFAULT NULL,
  _campaign_bonus_pct            numeric  DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Accès refusé'; END IF;
  IF _stake_commission_pct IS NOT NULL
     AND (_stake_commission_pct < 0 OR _stake_commission_pct > 100) THEN
    RAISE EXCEPTION 'Commission invalide (0-100)';
  END IF;
  IF _stake_commission_max_matches IS NOT NULL
     AND _stake_commission_max_matches < 0 THEN
    RAISE EXCEPTION 'Nombre de parties invalide';
  END IF;
  UPDATE public.referral_settings SET
    enabled                      = COALESCE(_enabled, enabled),
    stake_commission_pct         = COALESCE(_stake_commission_pct, stake_commission_pct),
    stake_commission_max_matches = COALESCE(_stake_commission_max_matches, stake_commission_max_matches),
    require_phone_verification   = COALESCE(_require_phone, require_phone_verification),
    max_daily_new_referrals      = COALESCE(_max_daily, max_daily_new_referrals),
    auto_flag_velocity           = COALESCE(_auto_flag_velocity, auto_flag_velocity),
    campaign_label               = COALESCE(_campaign_label, campaign_label),
    campaign_expires_at          = COALESCE(_campaign_expires, campaign_expires_at),
    campaign_bonus_pct           = COALESCE(_campaign_bonus_pct, campaign_bonus_pct),
    updated_at                   = now()
  WHERE id = 1;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_update_referral_settings(
  boolean,numeric,integer,boolean,integer,integer,text,timestamptz,numeric
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_referral_settings(
  boolean,numeric,integer,boolean,integer,integer,text,timestamptz,numeric
) TO authenticated;

-- Réactivation + reset compteurs faussés
UPDATE public.referral_settings
SET enabled = true,
    stake_commission_pct = COALESCE(NULLIF(stake_commission_pct,0), 5),
    stake_commission_max_matches = COALESCE(NULLIF(stake_commission_max_matches,0), 10),
    updated_at = now()
WHERE id = 1;

UPDATE public.profiles
SET referral_unlocked = false
WHERE referred_by IS NOT NULL AND referral_unlocked = true;
