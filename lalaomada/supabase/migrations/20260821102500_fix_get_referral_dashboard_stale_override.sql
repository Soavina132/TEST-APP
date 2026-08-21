-- ═══════════════════════════════════════════════════════════════════════════
-- FIX: get_referral_dashboard was overwritten by a stale/older migration
-- (top-level supabase/migrations/*, dated before referral_v3) that referenced
-- a non-existent column "referral_stake_max", causing the RPC to throw an
-- error on every call. The frontend silently swallowed the error, showing
-- 0 filleuls even though pending referrals existed in the `referrals` table.
-- This migration re-applies the correct v3 version (matching referral-rules.ts
-- expectations: top-level `total_earned` / `active_count`, referrals joined
-- from the `referrals` table) with a timestamp newer than the conflicting
-- older migrations so it always wins on any future full re-apply.
-- ═══════════════════════════════════════════════════════════════════════════

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
