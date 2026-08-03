CREATE OR REPLACE FUNCTION public.get_referral_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_stats public.v_referral_stats%ROWTYPE;
  v_refs jsonb; v_events jsonb; v_settings jsonb;
  v_rank int; v_flags int;
  v_max int;
BEGIN
  SELECT COALESCE(referral_stake_max, 10) INTO v_max FROM public.referral_settings WHERE id=1;
  SELECT * INTO v_stats FROM public.v_referral_stats WHERE referrer_id = v_uid;
  SELECT jsonb_agg(jsonb_build_object(
    'id', p.id, 'pseudo', p.pseudo, 'avatar_url', p.avatar_url,
    'created_at', p.created_at,
    'phone_verified', p.phone_verified,
    'referral_unlocked', p.referral_unlocked,
    'referral_stake_count', COALESCE(p.referral_stake_count, 0),
    'first_deposit_amount', COALESCE(p.first_deposit_amount, 0),
    'total_earned', COALESCE((SELECT SUM(re.reward_amount) FROM public.referral_events re WHERE re.referee_id=p.id AND re.referrer_id=v_uid),0)
  ) ORDER BY p.created_at DESC)
  INTO v_refs FROM public.profiles p WHERE p.referred_by = v_uid;

  WITH ordered AS (
    SELECT re.id, re.event_type, re.reward_amount, re.note, re.created_at,
           re.referee_id,
           ROW_NUMBER() OVER (PARTITION BY re.referee_id, re.event_type ORDER BY re.created_at ASC) AS match_index
    FROM public.referral_events re
    WHERE re.referrer_id = v_uid
  )
  SELECT jsonb_agg(jsonb_build_object(
    'id', o.id, 'event_type', o.event_type,
    'reward_amount', o.reward_amount, 'note', o.note,
    'created_at', o.created_at, 'referee_pseudo', p.pseudo,
    'match_index', CASE WHEN o.event_type = 'stake_commission' THEN o.match_index ELSE NULL END,
    'match_max', v_max
  ) ORDER BY o.created_at DESC)
  INTO v_events FROM ordered o
  JOIN public.profiles p ON p.id = o.referee_id;

  SELECT jsonb_build_object(
    'deposit_bonus_pct', deposit_bonus_pct, 'deposit_min_ar', deposit_min_ar,
    'tier_silver_min', tier_silver_min, 'tier_gold_min', tier_gold_min, 'tier_diamond_min', tier_diamond_min,
    'tier_silver_mult', tier_silver_mult, 'tier_gold_mult', tier_gold_mult, 'tier_diamond_mult', tier_diamond_mult,
    'campaign_label', campaign_label, 'campaign_expires_at', campaign_expires_at,
    'campaign_bonus_pct', campaign_bonus_pct, 'enabled', enabled,
    'stake_commission_pct', stake_commission_pct,
    'referral_stake_max', referral_stake_max,
    'first_deposit_bonus_ar', COALESCE(first_deposit_bonus_ar, 0)
  ) INTO v_settings FROM public.referral_settings WHERE id=1;
  SELECT rank INTO v_rank FROM public.get_referral_leaderboard(200) WHERE referrer_id = v_uid;
  SELECT COUNT(*) INTO v_flags FROM public.referral_fraud_flags WHERE referrer_id=v_uid AND status='pending';
  RETURN jsonb_build_object(
    'referral_code', (SELECT referral_code FROM public.profiles WHERE id=v_uid),
    'stats', to_jsonb(v_stats),
    'referrals', COALESCE(v_refs, '[]'::jsonb),
    'events', COALESCE(v_events,'[]'::jsonb),
    'settings', v_settings, 'rank', v_rank, 'pending_flags', v_flags);
END;
$function$;