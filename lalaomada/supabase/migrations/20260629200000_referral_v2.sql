-- ═══════════════════════════════════════════════════════════════════════════
-- REFERRAL SYSTEM V2 — Lalao MADA
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Referral Settings (one-row config table) ──────────────────────────
CREATE TABLE IF NOT EXISTS public.referral_settings (
  id                        int PRIMARY KEY DEFAULT 1,
  enabled                   boolean        NOT NULL DEFAULT true,
  -- Rewards
  deposit_bonus_pct         numeric        NOT NULL DEFAULT 10,   -- % du 1er dépôt → parrain
  deposit_min_ar            numeric        NOT NULL DEFAULT 500,  -- dépôt min pour déclencher
  win_commission_pct        numeric        NOT NULL DEFAULT 0,    -- % commission plateforme/victoire filleul
  -- Tier thresholds (nb de filleuls actifs)
  tier_silver_min           int            NOT NULL DEFAULT 5,
  tier_gold_min             int            NOT NULL DEFAULT 15,
  tier_diamond_min          int            NOT NULL DEFAULT 30,
  -- Tier multipliers on deposit_bonus_pct
  tier_silver_mult          numeric        NOT NULL DEFAULT 1.25,
  tier_gold_mult            numeric        NOT NULL DEFAULT 1.60,
  tier_diamond_mult         numeric        NOT NULL DEFAULT 2.00,
  -- Anti-fraud
  require_phone_verification boolean       NOT NULL DEFAULT true,
  require_first_deposit      boolean       NOT NULL DEFAULT true,
  max_daily_new_referrals   int            NOT NULL DEFAULT 20,
  auto_flag_velocity        int            NOT NULL DEFAULT 10,   -- nb filleuls/heure → flag auto
  self_referral_block       boolean        NOT NULL DEFAULT true,
  -- Campaign
  campaign_label            text,
  campaign_expires_at       timestamptz,
  campaign_bonus_pct        numeric,                              -- bonus extra pendant campagne
  updated_at                timestamptz    NOT NULL DEFAULT now()
);

INSERT INTO public.referral_settings (id) VALUES (1) ON CONFLICT DO NOTHING;

-- ── 2. Referral Events (milestone tracker) ───────────────────────────────
CREATE TABLE IF NOT EXISTS public.referral_events (
  id              uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_id     uuid         NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  referee_id      uuid         NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  event_type      text         NOT NULL, -- signup|phone_verified|first_deposit|games_played
  reward_amount   numeric      NOT NULL DEFAULT 0,
  note            text,
  created_at      timestamptz  NOT NULL DEFAULT now(),
  UNIQUE(referee_id, event_type)
);
CREATE INDEX IF NOT EXISTS ref_events_referrer ON public.referral_events(referrer_id);
CREATE INDEX IF NOT EXISTS ref_events_referee  ON public.referral_events(referee_id);

ALTER TABLE public.referral_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "ref_events_own" ON public.referral_events;
CREATE POLICY "ref_events_own" ON public.referral_events
  FOR SELECT USING (referrer_id = auth.uid() OR referee_id = auth.uid());

-- ── 3. Referral Fraud Flags ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.referral_fraud_flags (
  id              uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_id     uuid         REFERENCES public.profiles(id) ON DELETE SET NULL,
  referee_id      uuid         REFERENCES public.profiles(id) ON DELETE SET NULL,
  reason          text         NOT NULL,
  details         jsonb,
  status          text         NOT NULL DEFAULT 'pending', -- pending|cleared|confirmed
  reviewed_by     uuid         REFERENCES public.profiles(id) ON DELETE SET NULL,
  reviewed_at     timestamptz,
  created_at      timestamptz  NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ref_fraud_referrer ON public.referral_fraud_flags(referrer_id);
CREATE INDEX IF NOT EXISTS ref_fraud_status   ON public.referral_fraud_flags(status);

-- ── 4. Referral Tier View ─────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.v_referral_stats AS
SELECT
  p.id AS referrer_id,
  p.referral_code,
  COUNT(DISTINCT ref.id)                                  AS total_referrals,
  COUNT(DISTINCT ref.id) FILTER (WHERE ref.referral_unlocked)  AS active_referrals,
  COALESCE(SUM(re.reward_amount),0)                       AS total_earned_ar,
  COUNT(DISTINCT re.id) FILTER (WHERE re.event_type='first_deposit') AS paid_events,
  CASE
    WHEN COUNT(DISTINCT ref.id) FILTER (WHERE ref.referral_unlocked) >= (SELECT tier_diamond_min FROM public.referral_settings WHERE id=1) THEN 'diamond'
    WHEN COUNT(DISTINCT ref.id) FILTER (WHERE ref.referral_unlocked) >= (SELECT tier_gold_min    FROM public.referral_settings WHERE id=1) THEN 'gold'
    WHEN COUNT(DISTINCT ref.id) FILTER (WHERE ref.referral_unlocked) >= (SELECT tier_silver_min  FROM public.referral_settings WHERE id=1) THEN 'silver'
    ELSE 'bronze'
  END AS tier
FROM public.profiles p
LEFT JOIN public.profiles ref ON ref.referred_by = p.id
LEFT JOIN public.referral_events re ON re.referrer_id = p.id
GROUP BY p.id, p.referral_code;

-- ── 5. Referral Leaderboard RPC ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_referral_leaderboard(_limit int DEFAULT 50)
RETURNS TABLE(rank int, referrer_id uuid, pseudo text, avatar_url text,
              active_referrals bigint, total_earned_ar numeric, tier text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT
    (row_number() OVER (ORDER BY vr.active_referrals DESC, vr.total_earned_ar DESC))::int AS rank,
    vr.referrer_id,
    p.pseudo,
    p.avatar_url,
    vr.active_referrals,
    vr.total_earned_ar,
    vr.tier
  FROM public.v_referral_stats vr
  JOIN public.profiles p ON p.id = vr.referrer_id
  WHERE vr.active_referrals > 0
    AND (p.is_banned = false OR p.is_banned IS NULL)
  ORDER BY vr.active_referrals DESC, vr.total_earned_ar DESC
  LIMIT _limit;
$$;
GRANT EXECUTE ON FUNCTION public.get_referral_leaderboard(int) TO authenticated;

-- ── 6. Full Referral Dashboard RPC ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_referral_dashboard()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid     uuid := auth.uid();
  v_stats   public.v_referral_stats%ROWTYPE;
  v_refs    jsonb;
  v_events  jsonb;
  v_settings jsonb;
  v_rank    int;
  v_flags   int;
BEGIN
  SELECT * INTO v_stats FROM public.v_referral_stats WHERE referrer_id = v_uid;

  SELECT jsonb_agg(jsonb_build_object(
    'id', p.id, 'pseudo', p.pseudo, 'avatar_url', p.avatar_url,
    'created_at', p.created_at,
    'phone_verified', p.phone_verified,
    'referral_unlocked', p.referral_unlocked,
    'total_earned', COALESCE((SELECT SUM(re.reward_amount) FROM public.referral_events re WHERE re.referee_id=p.id AND re.referrer_id=v_uid),0)
  ) ORDER BY p.created_at DESC)
  INTO v_refs
  FROM public.profiles p WHERE p.referred_by = v_uid;

  SELECT jsonb_agg(jsonb_build_object(
    'id', re.id, 'event_type', re.event_type,
    'reward_amount', re.reward_amount, 'note', re.note,
    'created_at', re.created_at,
    'referee_pseudo', p.pseudo
  ) ORDER BY re.created_at DESC)
  INTO v_events
  FROM public.referral_events re
  JOIN public.profiles p ON p.id = re.referee_id
  WHERE re.referrer_id = v_uid;

  SELECT jsonb_build_object(
    'deposit_bonus_pct', deposit_bonus_pct,
    'deposit_min_ar', deposit_min_ar,
    'tier_silver_min', tier_silver_min,
    'tier_gold_min', tier_gold_min,
    'tier_diamond_min', tier_diamond_min,
    'tier_silver_mult', tier_silver_mult,
    'tier_gold_mult', tier_gold_mult,
    'tier_diamond_mult', tier_diamond_mult,
    'campaign_label', campaign_label,
    'campaign_expires_at', campaign_expires_at,
    'campaign_bonus_pct', campaign_bonus_pct,
    'enabled', enabled
  ) INTO v_settings FROM public.referral_settings WHERE id=1;

  SELECT rank INTO v_rank FROM public.get_referral_leaderboard(200) WHERE referrer_id = v_uid;
  SELECT COUNT(*) INTO v_flags FROM public.referral_fraud_flags WHERE referrer_id=v_uid AND status='pending';

  RETURN jsonb_build_object(
    'referral_code',    (SELECT referral_code FROM public.profiles WHERE id=v_uid),
    'stats',            to_jsonb(v_stats),
    'referrals',        COALESCE(v_refs,  '[]'::jsonb),
    'events',           COALESCE(v_events,'[]'::jsonb),
    'settings',         v_settings,
    'rank',             v_rank,
    'pending_flags',    v_flags
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_referral_dashboard() TO authenticated;

-- ── 7. Enhanced _referral_on_deposit with fraud detection ─────────────────
CREATE OR REPLACE FUNCTION public._referral_on_deposit()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_parent     uuid;
  v_verified   boolean;
  v_unlocked   boolean;
  v_pct        numeric;
  v_min_ar     numeric;
  v_reward     numeric;
  v_mult       numeric := 1.0;
  v_tier       text;
  v_daily_cnt  int;
  v_max_daily  int;
  v_vel_cnt    int;
  v_vel_max    int;
  v_cfg        public.referral_settings%ROWTYPE;
BEGIN
  -- Only on first approved deposit
  IF NEW.status <> 'approved' OR OLD.status = 'approved' THEN RETURN NEW; END IF;

  SELECT referred_by, phone_verified, referral_unlocked
  INTO v_parent, v_verified, v_unlocked
  FROM public.profiles WHERE id = NEW.user_id;

  IF v_parent IS NULL OR v_unlocked THEN RETURN NEW; END IF;

  SELECT * INTO v_cfg FROM public.referral_settings WHERE id=1;
  IF NOT v_cfg.enabled THEN RETURN NEW; END IF;
  IF v_cfg.require_phone_verification AND NOT v_verified THEN RETURN NEW; END IF;
  IF NEW.amount < v_cfg.deposit_min_ar THEN RETURN NEW; END IF;

  -- ── Anti-fraud checks ──────────────────────────────────────────────────
  -- 1. Self-referral (impossible by design but safety check)
  IF NEW.user_id = v_parent THEN
    INSERT INTO public.referral_fraud_flags(referrer_id,referee_id,reason,details)
    VALUES(v_parent, NEW.user_id,'self_referral',jsonb_build_object('deposit_id',NEW.id));
    RETURN NEW;
  END IF;

  -- 2. Velocity: too many referrals unlocked in last hour
  SELECT COUNT(*) INTO v_vel_cnt
  FROM public.referral_events
  WHERE referrer_id=v_parent AND event_type='first_deposit'
    AND created_at > now() - interval '1 hour';
  IF v_vel_cnt >= v_cfg.auto_flag_velocity THEN
    INSERT INTO public.referral_fraud_flags(referrer_id,referee_id,reason,details)
    VALUES(v_parent,NEW.user_id,'velocity_exceeded',
      jsonb_build_object('per_hour',v_vel_cnt,'deposit_id',NEW.id));
    RETURN NEW;
  END IF;

  -- 3. Daily limit
  SELECT COUNT(*) INTO v_daily_cnt
  FROM public.referral_events
  WHERE referrer_id=v_parent AND event_type='first_deposit'
    AND created_at >= current_date;
  IF v_daily_cnt >= v_cfg.max_daily_new_referrals THEN
    INSERT INTO public.referral_fraud_flags(referrer_id,referee_id,reason,details)
    VALUES(v_parent,NEW.user_id,'daily_limit_exceeded',
      jsonb_build_object('daily_count',v_daily_cnt,'deposit_id',NEW.id));
    RETURN NEW;
  END IF;

  -- ── Compute reward ──────────────────────────────────────────────────────
  -- Campaign bonus
  v_pct := v_cfg.deposit_bonus_pct;
  IF v_cfg.campaign_expires_at IS NOT NULL AND now() < v_cfg.campaign_expires_at
     AND v_cfg.campaign_bonus_pct IS NOT NULL THEN
    v_pct := v_pct + v_cfg.campaign_bonus_pct;
  END IF;

  -- Tier multiplier (count active referrals already paid)
  SELECT COUNT(*) INTO v_daily_cnt
  FROM public.referral_events WHERE referrer_id=v_parent AND event_type='first_deposit';
  IF    v_daily_cnt >= v_cfg.tier_diamond_min THEN v_mult := v_cfg.tier_diamond_mult; v_tier := 'diamond';
  ELSIF v_daily_cnt >= v_cfg.tier_gold_min    THEN v_mult := v_cfg.tier_gold_mult;    v_tier := 'gold';
  ELSIF v_daily_cnt >= v_cfg.tier_silver_min  THEN v_mult := v_cfg.tier_silver_mult;  v_tier := 'silver';
  ELSE  v_tier := 'bronze';
  END IF;

  v_reward := ROUND(NEW.amount * (v_pct / 100.0) * v_mult, 0);
  IF v_reward <= 0 THEN RETURN NEW; END IF;

  -- ── Credit referrer ─────────────────────────────────────────────────────
  UPDATE public.profiles SET balance_ar = balance_ar + v_reward WHERE id = v_parent;
  UPDATE public.profiles SET referral_unlocked = true WHERE id = NEW.user_id;

  INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
  VALUES(v_parent, 'referral', v_reward, NEW.id,
    format('Parrainage %s — %s%% × %.0f Ar (tier %s)', (SELECT pseudo FROM public.profiles WHERE id=NEW.user_id), v_pct, NEW.amount, v_tier));

  INSERT INTO public.referral_events(referrer_id, referee_id, event_type, reward_amount, note)
  VALUES(v_parent, NEW.user_id, 'first_deposit', v_reward,
    format('%s%% × %.0f Ar (tier %s × %.2f)', v_pct, NEW.amount, v_tier, v_mult))
  ON CONFLICT(referee_id, event_type) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_referral_on_deposit ON public.deposits;
CREATE TRIGGER trg_referral_on_deposit
  AFTER UPDATE ON public.deposits
  FOR EACH ROW EXECUTE FUNCTION public._referral_on_deposit();

-- ── 8. Record signup event ────────────────────────────────────────────────
-- Called from user_created trigger (if referral was used at signup)
CREATE OR REPLACE FUNCTION public._referral_on_signup()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.referred_by IS NOT NULL THEN
    INSERT INTO public.referral_events(referrer_id, referee_id, event_type, reward_amount, note)
    VALUES(NEW.referred_by, NEW.id, 'signup', 0, 'Inscription avec code parrain')
    ON CONFLICT(referee_id, event_type) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_referral_signup ON public.profiles;
CREATE TRIGGER trg_referral_signup
  AFTER INSERT ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public._referral_on_signup();

-- ── 9. Admin: review fraud flags ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_get_fraud_flags(_status text DEFAULT 'pending')
RETURNS TABLE(id uuid, referrer_id uuid, referee_id uuid,
              referrer_pseudo text, referee_pseudo text,
              reason text, details jsonb, status text, created_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT f.id, f.referrer_id, f.referee_id,
         p1.pseudo, p2.pseudo,
         f.reason, f.details, f.status, f.created_at
  FROM public.referral_fraud_flags f
  LEFT JOIN public.profiles p1 ON p1.id = f.referrer_id
  LEFT JOIN public.profiles p2 ON p2.id = f.referee_id
  WHERE (_status = 'all' OR f.status = _status)
  ORDER BY f.created_at DESC LIMIT 100;
$$;
REVOKE ALL ON FUNCTION public.admin_get_fraud_flags(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_fraud_flags(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_resolve_fraud_flag(
  _flag_id uuid, _resolution text, _pay_anyway boolean DEFAULT false
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_flag public.referral_fraud_flags%ROWTYPE;
  v_reward numeric;
  v_pct    numeric;
BEGIN
  IF NOT public.has_role(auth.uid(),'admin') THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO v_flag FROM public.referral_fraud_flags WHERE id = _flag_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Flag introuvable'; END IF;

  UPDATE public.referral_fraud_flags
  SET status = _resolution, reviewed_by = auth.uid(), reviewed_at = now()
  WHERE id = _flag_id;

  -- If admin decides to pay anyway (cleared + pay_anyway)
  IF _pay_anyway AND _resolution = 'cleared' AND v_flag.referrer_id IS NOT NULL THEN
    SELECT deposit_bonus_pct INTO v_pct FROM public.referral_settings WHERE id=1;
    SELECT amount INTO v_reward FROM public.deposits WHERE id = (v_flag.details->>'deposit_id')::uuid;
    IF v_reward IS NOT NULL THEN
      v_reward := ROUND(v_reward * v_pct / 100.0, 0);
      UPDATE public.profiles SET balance_ar = balance_ar + v_reward WHERE id = v_flag.referrer_id;
      UPDATE public.profiles SET referral_unlocked = true WHERE id = v_flag.referee_id;
      INSERT INTO public.transactions(user_id, type, amount, note)
      VALUES(v_flag.referrer_id,'referral',v_reward,'Parrainage validé manuellement par admin');
      INSERT INTO public.referral_events(referrer_id,referee_id,event_type,reward_amount,note)
      VALUES(v_flag.referrer_id,v_flag.referee_id,'first_deposit',v_reward,'Validé manuellement')
      ON CONFLICT(referee_id,event_type) DO NOTHING;
    END IF;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_resolve_fraud_flag(uuid,text,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_resolve_fraud_flag(uuid,text,boolean) TO authenticated;

-- ── 10. Admin: update referral settings ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_update_referral_settings(
  _deposit_bonus_pct numeric DEFAULT NULL,
  _deposit_min_ar    numeric DEFAULT NULL,
  _win_commission_pct numeric DEFAULT NULL,
  _tier_silver_min   int DEFAULT NULL,
  _tier_gold_min     int DEFAULT NULL,
  _tier_diamond_min  int DEFAULT NULL,
  _tier_silver_mult  numeric DEFAULT NULL,
  _tier_gold_mult    numeric DEFAULT NULL,
  _tier_diamond_mult numeric DEFAULT NULL,
  _require_phone     boolean DEFAULT NULL,
  _max_daily         int DEFAULT NULL,
  _auto_flag_velocity int DEFAULT NULL,
  _enabled           boolean DEFAULT NULL,
  _campaign_label    text DEFAULT NULL,
  _campaign_expires  timestamptz DEFAULT NULL,
  _campaign_bonus_pct numeric DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.has_role(auth.uid(),'admin') THEN RAISE EXCEPTION 'Accès refusé'; END IF;
  UPDATE public.referral_settings SET
    deposit_bonus_pct   = COALESCE(_deposit_bonus_pct, deposit_bonus_pct),
    deposit_min_ar      = COALESCE(_deposit_min_ar, deposit_min_ar),
    win_commission_pct  = COALESCE(_win_commission_pct, win_commission_pct),
    tier_silver_min     = COALESCE(_tier_silver_min, tier_silver_min),
    tier_gold_min       = COALESCE(_tier_gold_min, tier_gold_min),
    tier_diamond_min    = COALESCE(_tier_diamond_min, tier_diamond_min),
    tier_silver_mult    = COALESCE(_tier_silver_mult, tier_silver_mult),
    tier_gold_mult      = COALESCE(_tier_gold_mult, tier_gold_mult),
    tier_diamond_mult   = COALESCE(_tier_diamond_mult, tier_diamond_mult),
    require_phone_verification = COALESCE(_require_phone, require_phone_verification),
    max_daily_new_referrals = COALESCE(_max_daily, max_daily_new_referrals),
    auto_flag_velocity  = COALESCE(_auto_flag_velocity, auto_flag_velocity),
    enabled             = COALESCE(_enabled, enabled),
    campaign_label      = COALESCE(_campaign_label, campaign_label),
    campaign_expires_at = COALESCE(_campaign_expires, campaign_expires_at),
    campaign_bonus_pct  = COALESCE(_campaign_bonus_pct, campaign_bonus_pct),
    updated_at          = now()
  WHERE id = 1;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_update_referral_settings FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_referral_settings TO authenticated;
