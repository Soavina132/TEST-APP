-- Create a trigger function that protects sensitive fields on profiles
CREATE OR REPLACE FUNCTION public._protect_profile_fields()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Only allow self-update to change non-sensitive fields
  -- If the caller is the user themselves (not service_role), revert sensitive fields
  IF auth.uid() = NEW.id AND NOT public.is_admin() THEN
    -- Revert all sensitive fields to their old values
    NEW.is_admin := OLD.is_admin;
    NEW.is_bot := OLD.is_bot;
    NEW.is_banned := OLD.is_banned;
    NEW.banned := OLD.banned;
    NEW.is_premium := OLD.is_premium;
    NEW.premium_until := OLD.premium_until;
    NEW.premium_tier := OLD.premium_tier;
    NEW.premium_tournament_passes := OLD.premium_tournament_passes;
    NEW.balance_ar := OLD.balance_ar;
    NEW.status := OLD.status;
    NEW.unique_code := OLD.unique_code;
    NEW.referral_code := OLD.referral_code;
    NEW.referral_unlocked := OLD.referral_unlocked;
    NEW.referred_by := OLD.referred_by;
    NEW.phone_verified := OLD.phone_verified;
    NEW.phone_verification_code := OLD.phone_verification_code;
    NEW.phone_verification_code_hash := OLD.phone_verification_code_hash;
    NEW.phone_verification_requested_at := OLD.phone_verification_requested_at;
    NEW.level := OLD.level;
    NEW.xp := OLD.xp;
    NEW.player_level := OLD.player_level;
    NEW.elo_rating := OLD.elo_rating;
    NEW.total_wins := OLD.total_wins;
    NEW.total_games := OLD.total_games;
    NEW.first_deposit_at := OLD.first_deposit_at;
    NEW.first_deposit_amount := OLD.first_deposit_amount;
    NEW.first_game_at := OLD.first_game_at;
    NEW.suspended_until := OLD.suspended_until;
    NEW.suspension_reason := OLD.suspension_reason;
    NEW.warning_count := OLD.warning_count;
    NEW.leaderboard_rank_override := OLD.leaderboard_rank_override;
    NEW.leaderboard_hidden := OLD.leaderboard_hidden;
    NEW.tournament_wins := OLD.tournament_wins;
    NEW.tournament_played := OLD.tournament_played;
    NEW.two_factor_enabled := OLD.two_factor_enabled;
    NEW.free_trial_active_days := OLD.free_trial_active_days;
    NEW.free_trial_completed := OLD.free_trial_completed;
    NEW.last_daily_claim := OLD.last_daily_claim;
    NEW.daily_streak := OLD.daily_streak;
    NEW.bonus_claimed_at := OLD.bonus_claimed_at;
    NEW.referral_stake_count := OLD.referral_stake_count;
    -- phone can only change if not verified
    IF OLD.phone_verified = true THEN
      NEW.phone := OLD.phone;
    END IF;
  END IF;
  RETURN NEW;
END $function$;

DROP TRIGGER IF EXISTS trg_protect_profile_fields ON public.profiles;
CREATE TRIGGER trg_protect_profile_fields
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public._protect_profile_fields();

-- Revoke the trigger function from users
REVOKE EXECUTE ON FUNCTION public._protect_profile_fields() FROM anon, authenticated;
