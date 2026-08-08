-- ═══════════════════════════════════════════════════════════════════════════
-- REFERRAL PROTECTION: Decrement match count when a finished game is cancelled
-- Ensures "Les matchs annulés ou suspects ne sont pas comptabilisés"
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Helper: decrement match count for a player on game cancellation ───
CREATE OR REPLACE FUNCTION public._referral_decrement_match(
  p_user_id uuid
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_ref       public.referrals%ROWTYPE;
  v_referred_by uuid;
BEGIN
  SELECT referred_by INTO v_referred_by
  FROM public.profiles WHERE id = p_user_id;

  IF v_referred_by IS NULL THEN RETURN; END IF;

  SELECT * INTO v_ref FROM public.referrals
  WHERE referred_user_id = p_user_id AND referrer_id = v_referred_by;

  IF NOT FOUND THEN RETURN; END IF;

  -- If already rewarded, can't take back — skip
  IF v_ref.status = 'rewarded' THEN RETURN; END IF;

  -- Decrement match count (never below 0)
  UPDATE public.referrals
  SET matches_completed = GREATEST(matches_completed - 1, 0)
  WHERE id = v_ref.id;
END;
$$;

-- ── 2. Update the game finish trigger to handle cancelled games ──────────
CREATE OR REPLACE FUNCTION public._referral_on_game_finish()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cfg        public.referral_settings%ROWTYPE;
  v_part_table text;
  v_player     record;
BEGIN
  SELECT * INTO v_cfg FROM public.referral_settings WHERE id = 1;
  IF NOT v_cfg.enabled THEN RETURN NEW; END IF;

  -- ── CANCELLED GAME: decrement match counts ──
  IF NEW.status = 'cancelled' AND OLD.status IN ('finished', 'drawing') THEN
    IF NEW.stake >= v_cfg.min_stake_ar THEN
      v_part_table := CASE TG_TABLE_NAME
        WHEN 'ludo_games'     THEN 'ludo_participants'
        WHEN 'domino_games'    THEN 'domino_participants'
        WHEN 'fanorona_games'  THEN 'fanorona_participants'
        WHEN 'rami_games'      THEN 'rami_participants'
        WHEN 'poker_games'     THEN 'poker_players'
        ELSE NULL
      END;

      IF TG_TABLE_NAME = 'chess_games' THEN
        IF NEW.white_id IS NOT NULL THEN PERFORM public._referral_decrement_match(NEW.white_id); END IF;
        IF NEW.black_id IS NOT NULL THEN PERFORM public._referral_decrement_match(NEW.black_id); END IF;
        RETURN NEW;
      END IF;

      IF v_part_table IS NOT NULL THEN
        FOR v_player IN
          EXECUTE format(
            'SELECT DISTINCT part.user_id FROM %I part
             WHERE part.game_id = $1 AND part.user_id IS NOT NULL',
            v_part_table
          ) USING NEW.id
        LOOP
          PERFORM public._referral_decrement_match(v_player.user_id);
        END LOOP;
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  -- ── FINISHED GAME: count matches (existing logic) ──
  IF NEW.status NOT IN ('finished', 'drawing') THEN RETURN NEW; END IF;
  IF OLD.status = NEW.status THEN RETURN NEW; END IF;

  -- Skip if stake below minimum (free games excluded)
  IF NEW.stake < v_cfg.min_stake_ar THEN RETURN NEW; END IF;

  v_part_table := CASE TG_TABLE_NAME
    WHEN 'ludo_games'     THEN 'ludo_participants'
    WHEN 'domino_games'    THEN 'domino_participants'
    WHEN 'fanorona_games'  THEN 'fanorona_participants'
    WHEN 'rami_games'      THEN 'rami_participants'
    WHEN 'poker_games'     THEN 'poker_players'
    ELSE NULL
  END;

  IF TG_TABLE_NAME = 'chess_games' THEN
    IF NEW.white_id IS NOT NULL THEN PERFORM public._referral_process_match(NEW.white_id, v_cfg); END IF;
    IF NEW.black_id IS NOT NULL THEN PERFORM public._referral_process_match(NEW.black_id, v_cfg); END IF;
    RETURN NEW;
  END IF;

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
