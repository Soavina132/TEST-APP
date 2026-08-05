-- ═══════════════════════════════════════════════════════════════════════════
-- REFERRAL SYSTEM V3 — Fixed reward per active referral
-- 100 Ar per active referral (phone verified + deposit ≥ 500 Ar + 10 matches ≥ 200 Ar)
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Extend referral_settings ──────────────────────────────────────────
ALTER TABLE public.referral_settings
  ADD COLUMN IF NOT EXISTS reward_per_active_ar numeric NOT NULL DEFAULT 100,
  ADD COLUMN IF NOT EXISTS min_matches int NOT NULL DEFAULT 10,
  ADD COLUMN IF NOT EXISTS min_stake_ar numeric NOT NULL DEFAULT 200;

-- Update tier thresholds to match new spec: 5/10/20/50
UPDATE public.referral_settings SET
  tier_silver_min  = 5,
  tier_gold_min    = 10,
  tier_diamond_min = 20
WHERE id = 1;

-- Add a 4th tier level (50 = platinum) via a new column
ALTER TABLE public.referral_settings
  ADD COLUMN IF NOT EXISTS tier_platinum_min int NOT NULL DEFAULT 50;

-- ── 2. Referrals tracking table ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.referrals (
  id                uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_id       uuid         NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  referred_user_id  uuid         NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status            text         NOT NULL DEFAULT 'pending',  -- pending → active → rewarded
  deposit_validated boolean      NOT NULL DEFAULT false,
  matches_completed int          NOT NULL DEFAULT 0,
  reward_amount     numeric      NOT NULL DEFAULT 0,
  created_at        timestamptz  NOT NULL DEFAULT now(),
  activated_at      timestamptz,
  UNIQUE(referred_user_id)       -- one referral record per user
);

CREATE INDEX IF NOT EXISTS ref_tracking_referrer ON public.referrals(referrer_id);
CREATE INDEX IF NOT EXISTS ref_tracking_status   ON public.referrals(status);

ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "referrals_own" ON public.referrals;
CREATE POLICY "referrals_own" ON public.referrals
  FOR SELECT USING (referrer_id = auth.uid() OR referred_user_id = auth.uid());

-- ── 3. Auto-create referral record on signup ─────────────────────────────
-- When a new profile is created with referred_by, create a tracking row
CREATE OR REPLACE FUNCTION public._referral_on_profile_create()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.referred_by IS NOT NULL AND NEW.referred_by != NEW.id THEN
    INSERT INTO public.referrals(referrer_id, referred_user_id, status, deposit_validated, matches_completed)
    VALUES(NEW.referred_by, NEW.id, 'pending', false, 0)
    ON CONFLICT (referred_user_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_referral_profile_create ON public.profiles;
CREATE TRIGGER trg_referral_profile_create
  AFTER INSERT ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public._referral_on_profile_create();

-- ── 4. Update _referral_on_deposit to set deposit_validated ──────────────
CREATE OR REPLACE FUNCTION public._referral_on_deposit()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_parent     uuid;
  v_verified   boolean;
  v_cfg        public.referral_settings%ROWTYPE;
  v_daily_cnt  int;
BEGIN
  -- Only on first approved deposit
  IF NEW.status <> 'approved' OR OLD.status = 'approved' THEN RETURN NEW; END IF;

  SELECT referred_by, phone_verified
  INTO v_parent, v_verified
  FROM public.profiles WHERE id = NEW.user_id;

  IF v_parent IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_cfg FROM public.referral_settings WHERE id = 1;
  IF NOT v_cfg.enabled THEN RETURN NEW; END IF;
  IF NEW.amount < v_cfg.deposit_min_ar THEN RETURN NEW; END IF;

  -- Anti-fraud: self-referral
  IF NEW.user_id = v_parent THEN
    INSERT INTO public.referral_fraud_flags(referrer_id, referee_id, reason, details)
    VALUES(v_parent, NEW.user_id, 'self_referral',
           jsonb_build_object('deposit_id', NEW.id, 'amount', NEW.amount))
    ON CONFLICT DO NOTHING;
    RETURN NEW;
  END IF;

  -- Anti-fraud: velocity check
  SELECT COUNT(*) INTO v_daily_cnt
  FROM public.referrals r
  JOIN public.profiles p ON p.id = r.referred_user_id
  WHERE r.referrer_id = v_parent
    AND p.created_at > now() - interval '24 hours';
  IF v_daily_cnt > v_cfg.max_daily_new_referrals THEN
    INSERT INTO public.referral_fraud_flags(referrer_id, referee_id, reason, details)
    VALUES(v_parent, NEW.user_id, 'velocity_exceeded',
           jsonb_build_object('daily_count', v_daily_cnt, 'limit', v_cfg.max_daily_new_referrals))
    ON CONFLICT DO NOTHING;
  END IF;

  -- Mark deposit as validated in referrals table
  UPDATE public.referrals
  SET deposit_validated = true
  WHERE referred_user_id = NEW.user_id AND referrer_id = v_parent;

  -- Log the deposit event (no reward yet — matches still needed)
  INSERT INTO public.referral_events(referrer_id, referee_id, event_type, reward_amount, note)
  VALUES(v_parent, NEW.user_id, 'first_deposit', 0, 'Dépôt validé — en attente des matchs')
  ON CONFLICT(referee_id, event_type) DO NOTHING;

  RETURN NEW;
END;
$$;

-- ── 5. Game finish trigger — track matches and auto-reward ─────────────────
CREATE OR REPLACE FUNCTION public._referral_on_game_finish()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cfg        public.referral_settings%ROWTYPE;
  v_part_table text;
  v_player     record;
  v_ref        public.referrals%ROWTYPE;
  v_reward     numeric;
  v_should_activate boolean;
BEGIN
  -- Only when status changes to finished or drawing (completed game)
  IF NEW.status NOT IN ('finished', 'drawing') THEN RETURN NEW; END IF;
  IF OLD.status = NEW.status THEN RETURN NEW; END IF;

  SELECT * INTO v_cfg FROM public.referral_settings WHERE id = 1;
  IF NOT v_cfg.enabled THEN RETURN NEW; END IF;

  -- Skip if stake below minimum
  IF NEW.stake < v_cfg.min_stake_ar THEN RETURN NEW; END IF;

  -- Determine participant table and query
  v_part_table := CASE TG_TABLE_NAME
    WHEN 'ludo_games'     THEN 'ludo_participants'
    WHEN 'domino_games'    THEN 'domino_participants'
    WHEN 'fanorona_games'  THEN 'fanorona_participants'
    WHEN 'rami_games'      THEN 'rami_participants'
    WHEN 'poker_games'     THEN 'poker_players'
    ELSE NULL
  END;

  -- For chess: players are white_id and black_id directly
  IF TG_TABLE_NAME = 'chess_games' THEN
    -- Process white player
    IF NEW.white_id IS NOT NULL THEN
      PERFORM public._referral_process_match(NEW.white_id, v_cfg);
    END IF;
    -- Process black player
    IF NEW.black_id IS NOT NULL THEN
      PERFORM public._referral_process_match(NEW.black_id, v_cfg);
    END IF;
    RETURN NEW;
  END IF;

  -- For other games: query the participants table
  IF v_part_table IS NOT NULL THEN
    FOR v_player IN
      EXECUTE format(
        'SELECT DISTINCT part.user_id FROM %I part
         WHERE part.game_id = $1 AND part.user_id IS NOT NULL',
        v_part_table
      ) USING NEW.id
    LOOP
      PERFORM public._referral_process_match(v_player.user_id, v_cfg);
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

-- ── 6. Helper: process a single player's match for referral tracking ──────
CREATE OR REPLACE FUNCTION public._referral_process_match(
  p_user_id uuid,
  p_cfg public.referral_settings
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_ref       public.referrals%ROWTYPE;
  v_reward    numeric;
  v_verified  boolean;
  v_referred_by uuid;
  v_should_activate boolean;
BEGIN
  -- Get the user's referrer
  SELECT referred_by, phone_verified INTO v_referred_by, v_verified
  FROM public.profiles WHERE id = p_user_id;

  IF v_referred_by IS NULL THEN RETURN; END IF;

  -- Get the referral tracking record
  SELECT * INTO v_ref FROM public.referrals
  WHERE referred_user_id = p_user_id AND referrer_id = v_referred_by;

  IF NOT FOUND THEN RETURN; END IF;

  -- Already rewarded? Skip
  IF v_ref.status = 'rewarded' THEN RETURN; END IF;

  -- Increment matches
  UPDATE public.referrals
  SET matches_completed = matches_completed + 1
  WHERE id = v_ref.id
  RETURNING * INTO v_ref;

  -- Check activation conditions
  v_should_activate := (
    v_ref.deposit_validated = true
    AND v_ref.matches_completed >= p_cfg.min_matches
    AND v_verified = true
  );

  IF v_should_activate AND v_ref.status != 'rewarded' THEN
    v_reward := p_cfg.reward_per_active_ar;

    -- Credit referrer's balance
    UPDATE public.profiles
    SET balance_ar = balance_ar + v_reward
    WHERE id = v_ref.referrer_id;

    -- Mark referral as rewarded
    UPDATE public.referrals
    SET status = 'rewarded', reward_amount = v_reward, activated_at = now()
    WHERE id = v_ref.id;

    -- Log in referral_events
    INSERT INTO public.referral_events(referrer_id, referee_id, event_type, reward_amount, note)
    VALUES(
      v_ref.referrer_id, p_user_id, 'active_reward', v_reward,
      'Filleul actif — ' || v_ref.matches_completed || ' matchs joués'
    )
    ON CONFLICT(referee_id, event_type) DO NOTHING;

    -- Log in transactions
    INSERT INTO public.transactions(user_id, type, amount, note)
    VALUES(v_ref.referrer_id, 'referral', v_reward, 'Récompense parrainage — filleul actif');

    -- Set referral_unlocked on the referee
    UPDATE public.profiles SET referral_unlocked = true WHERE id = p_user_id;
  END IF;
END;
$$;

-- Attach trigger to all game tables
DROP TRIGGER IF EXISTS trg_referral_ludo_finish    ON public.ludo_games;
CREATE TRIGGER trg_referral_ludo_finish
  AFTER UPDATE ON public.ludo_games
  FOR EACH ROW EXECUTE FUNCTION public._referral_on_game_finish();

DROP TRIGGER IF EXISTS trg_referral_domino_finish   ON public.domino_games;
CREATE TRIGGER trg_referral_domino_finish
  AFTER UPDATE ON public.domino_games
  FOR EACH ROW EXECUTE FUNCTION public._referral_on_game_finish();

DROP TRIGGER IF EXISTS trg_referral_chess_finish    ON public.chess_games;
CREATE TRIGGER trg_referral_chess_finish
  AFTER UPDATE ON public.chess_games
  FOR EACH ROW EXECUTE FUNCTION public._referral_on_game_finish();

DROP TRIGGER IF EXISTS trg_referral_fanorona_finish ON public.fanorona_games;
CREATE TRIGGER trg_referral_fanorona_finish
  AFTER UPDATE ON public.fanorona_games
  FOR EACH ROW EXECUTE FUNCTION public._referral_on_game_finish();

DROP TRIGGER IF EXISTS trg_referral_rami_finish     ON public.rami_games;
CREATE TRIGGER trg_referral_rami_finish
  AFTER UPDATE ON public.rami_games
  FOR EACH ROW EXECUTE FUNCTION public._referral_on_game_finish();

DROP TRIGGER IF EXISTS trg_referral_poker_finish    ON public.poker_games;
CREATE TRIGGER trg_referral_poker_finish
  AFTER UPDATE ON public.poker_games
  FOR EACH ROW EXECUTE FUNCTION public._referral_on_game_finish();

-- ── 7. Update v_referral_stats view ──────────────────────────────────────
CREATE OR REPLACE VIEW public.v_referral_stats AS
SELECT
  p.id AS referrer_id,
  p.referral_code,
  COUNT(DISTINCT r.referred_user_id)                                    AS total_referrals,
  COUNT(DISTINCT r.referred_user_id) FILTER (WHERE r.status = 'rewarded') AS active_referrals,
  COALESCE(SUM(r.reward_amount) FILTER (WHERE r.status = 'rewarded'), 0)  AS total_earned_ar,
  COUNT(DISTINCT re.id)                                                  AS paid_events,
  CASE
    WHEN COUNT(DISTINCT r.referred_user_id) FILTER (WHERE r.status = 'rewarded') >=
         (SELECT tier_platinum_min FROM public.referral_settings WHERE id=1) THEN 'platinum'
    WHEN COUNT(DISTINCT r.referred_user_id) FILTER (WHERE r.status = 'rewarded') >=
         (SELECT tier_diamond_min FROM public.referral_settings WHERE id=1) THEN 'diamond'
    WHEN COUNT(DISTINCT r.referred_user_id) FILTER (WHERE r.status = 'rewarded') >=
         (SELECT tier_gold_min FROM public.referral_settings WHERE id=1) THEN 'gold'
    WHEN COUNT(DISTINCT r.referred_user_id) FILTER (WHERE r.status = 'rewarded') >=
         (SELECT tier_silver_min FROM public.referral_settings WHERE id=1) THEN 'silver'
    ELSE 'bronze'
  END AS tier
FROM public.profiles p
LEFT JOIN public.referrals r ON r.referrer_id = p.id
LEFT JOIN public.referral_events re ON re.referrer_id = p.id
GROUP BY p.id, p.referral_code;

-- ── 8. Update get_referral_dashboard RPC ─────────────────────────────────
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
  v_total_earned numeric;
  v_active_count int;
BEGIN
  SELECT * INTO v_stats FROM public.v_referral_stats WHERE referrer_id = v_uid;

  -- Referrals with detailed status
  SELECT jsonb_agg(jsonb_build_object(
    'id', r.id,
    'referred_user_id', r.referred_user_id,
    'pseudo', p.pseudo,
    'avatar_url', p.avatar_url,
    'created_at', r.created_at,
    'status', r.status,
    'deposit_validated', r.deposit_validated,
    'matches_completed', r.matches_completed,
    'reward_amount', r.reward_amount,
    'phone_verified', p.phone_verified,
    'total_earned', r.reward_amount
  ) ORDER BY r.created_at DESC)
  INTO v_refs
  FROM public.referrals r
  JOIN public.profiles p ON p.id = r.referred_user_id
  WHERE r.referrer_id = v_uid;

  -- Reward events
  SELECT jsonb_agg(jsonb_build_object(
    'id', re.id,
    'event_type', re.event_type,
    'reward_amount', re.reward_amount,
    'note', re.note,
    'created_at', re.created_at,
    'referee_pseudo', p.pseudo
  ) ORDER BY re.created_at DESC)
  INTO v_events
  FROM public.referral_events re
  JOIN public.profiles p ON p.id = re.referee_id
  WHERE re.referrer_id = v_uid AND re.reward_amount > 0;

  -- Settings
  SELECT jsonb_build_object(
    'reward_per_active_ar', reward_per_active_ar,
    'min_matches', min_matches,
    'min_stake_ar', min_stake_ar,
    'deposit_min_ar', deposit_min_ar,
    'tier_silver_min', tier_silver_min,
    'tier_gold_min', tier_gold_min,
    'tier_diamond_min', tier_diamond_min,
    'tier_platinum_min', tier_platinum_min,
    'enabled', enabled,
    'require_phone_verification', require_phone_verification,
    'require_first_deposit', require_first_deposit
  ) INTO v_settings FROM public.referral_settings WHERE id = 1;

  SELECT rank INTO v_rank FROM public.get_referral_leaderboard(200) WHERE referrer_id = v_uid;
  SELECT COUNT(*) INTO v_flags FROM public.referral_fraud_flags WHERE referrer_id = v_uid AND status = 'pending';

  SELECT COALESCE(SUM(reward_amount), 0) INTO v_total_earned
  FROM public.referrals WHERE referrer_id = v_uid AND status = 'rewarded';

  SELECT COUNT(*) INTO v_active_count
  FROM public.referrals WHERE referrer_id = v_uid AND status = 'rewarded';

  RETURN jsonb_build_object(
    'referral_code',   (SELECT referral_code FROM public.profiles WHERE id = v_uid),
    'stats',           to_jsonb(v_stats),
    'referrals',       COALESCE(v_refs,   '[]'::jsonb),
    'events',          COALESCE(v_events, '[]'::jsonb),
    'settings',        v_settings,
    'rank',            v_rank,
    'pending_flags',   v_flags,
    'total_earned',    v_total_earned,
    'active_count',    v_active_count
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_referral_dashboard() TO authenticated;

-- ── 9. Update leaderboard to use new active_referrals ────────────────────
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
  WHERE vr.total_referrals > 0
    AND (p.is_banned = false OR p.is_banned IS NULL)
  ORDER BY vr.active_referrals DESC, vr.total_earned_ar DESC
  LIMIT _limit;
$$;
GRANT EXECUTE ON FUNCTION public.get_referral_leaderboard(int) TO authenticated;

-- ── 10. Backfill: create referral records for existing referred users ────
INSERT INTO public.referrals(referrer_id, referred_user_id, status, deposit_validated, matches_completed, reward_amount)
SELECT
  p.referred_by,
  p.id,
  CASE
    WHEN p.referral_unlocked = true THEN 'rewarded'
    WHEN p.first_deposit_at IS NOT NULL THEN 'pending'
    ELSE 'pending'
  END,
  COALESCE(p.first_deposit_at IS NOT NULL, false),
  COALESCE(p.total_games, 0),
  CASE WHEN p.referral_unlocked = true THEN 100 ELSE 0 END
FROM public.profiles p
WHERE p.referred_by IS NOT NULL
  AND p.referred_by != p.id
ON CONFLICT (referred_user_id) DO NOTHING;

-- ── 11. Grant permissions ─────────────────────────────────────────────────
GRANT SELECT ON public.referrals TO authenticated;
GRANT SELECT ON public.referral_settings TO authenticated;
GRANT SELECT ON public.referral_fraud_flags TO authenticated;
GRANT SELECT ON public.v_referral_stats TO authenticated;
