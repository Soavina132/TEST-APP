-- ============================================================
-- Migration Priorité 1 : Bonus quotidien · Historique · Niveaux
-- ============================================================

-- ── 1. app_settings : colonnes bonus quotidien ─────────────────────────────
ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS daily_bonus_enabled      boolean  NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS daily_bonus_amount_ar    integer  NOT NULL DEFAULT 500,
  ADD COLUMN IF NOT EXISTS daily_bonus_streak_bonus boolean  NOT NULL DEFAULT true;
  -- streak_bonus : jour 7 = 2×, jour 14 = 3×

-- ── 2. profiles : colonnes suivi bonus quotidien ───────────────────────────
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS last_daily_claim   date,
  ADD COLUMN IF NOT EXISTS daily_streak       int  NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_wins         int  NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_games        int  NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS player_level       int  NOT NULL DEFAULT 1;

-- ── 3. Vue matérialisée (rafraîchissable) pour les stats par joueur ────────
-- On utilise une vue simple (pas matérialisée pour compatibilité)
CREATE OR REPLACE VIEW public.v_player_stats AS
SELECT
  p.id,
  p.pseudo,
  p.avatar_url,
  COALESCE(p.total_wins,  0) AS total_wins,
  COALESCE(p.total_games, 0) AS total_games,
  COALESCE(p.player_level, 1) AS player_level,
  COALESCE(p.daily_streak, 0) AS daily_streak
FROM public.profiles p
WHERE p.is_banned = false OR p.is_banned IS NULL;

-- ── 4. RPC : claim_daily_bonus ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.claim_daily_bonus()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid          uuid := auth.uid();
  v_profile      record;
  v_settings     record;
  v_today        date := CURRENT_DATE;
  v_streak       int;
  v_base_amount  int;
  v_multiplier   int := 1;
  v_amount       int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;

  -- Check settings
  SELECT daily_bonus_enabled, daily_bonus_amount_ar, daily_bonus_streak_bonus
    INTO v_settings FROM public.app_settings WHERE id = 1;

  IF NOT COALESCE(v_settings.daily_bonus_enabled, true) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'bonus_disabled');
  END IF;

  -- Check if already claimed today
  SELECT last_daily_claim, daily_streak INTO v_profile
    FROM public.profiles WHERE id = v_uid;

  IF v_profile.last_daily_claim = v_today THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_claimed', 'next_claim', (v_today + 1)::text);
  END IF;

  -- Compute streak
  v_streak := CASE
    WHEN v_profile.last_daily_claim = v_today - 1 THEN COALESCE(v_profile.daily_streak, 0) + 1
    ELSE 1
  END;

  -- Multiplier (streak bonus)
  v_base_amount := COALESCE(v_settings.daily_bonus_amount_ar, 500);
  IF COALESCE(v_settings.daily_bonus_streak_bonus, true) THEN
    IF v_streak >= 14 THEN v_multiplier := 3;
    ELSIF v_streak >= 7 THEN v_multiplier := 2;
    ELSIF v_streak >= 3 THEN v_multiplier := 1;
    END IF;
  END IF;
  v_amount := v_base_amount * v_multiplier;

  -- Credit balance + update streak
  UPDATE public.profiles
     SET last_daily_claim = v_today,
         daily_streak     = v_streak,
         balance_ar       = COALESCE(balance_ar, 0) + v_amount
   WHERE id = v_uid;

  -- Transaction record
  INSERT INTO public.transactions(user_id, kind, amount, meta)
    VALUES (v_uid, 'daily_bonus', v_amount,
      jsonb_build_object('streak', v_streak, 'multiplier', v_multiplier, 'base', v_base_amount));

  -- Notification
  INSERT INTO public.notifications(user_id, kind, title, body)
    VALUES (v_uid, 'reward',
      '🎁 Bonus quotidien reçu !',
      v_amount || ' Ar crédités' ||
      CASE WHEN v_multiplier > 1 THEN ' (×' || v_multiplier || ' — série de ' || v_streak || ' jours !)' ELSE ' — revenez demain pour continuer votre série !' END);

  RETURN jsonb_build_object(
    'ok', true,
    'amount', v_amount,
    'streak', v_streak,
    'multiplier', v_multiplier,
    'next_claim', (v_today + 1)::text
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_daily_bonus() TO authenticated;

-- ── 5. RPC : get_daily_bonus_status ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_daily_bonus_status()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_profile  record;
  v_settings record;
  v_today    date := CURRENT_DATE;
BEGIN
  SELECT last_daily_claim, daily_streak INTO v_profile FROM public.profiles WHERE id = v_uid;
  SELECT daily_bonus_enabled, daily_bonus_amount_ar, daily_bonus_streak_bonus INTO v_settings FROM public.app_settings WHERE id = 1;
  RETURN jsonb_build_object(
    'enabled',          COALESCE(v_settings.daily_bonus_enabled, true),
    'base_amount',      COALESCE(v_settings.daily_bonus_amount_ar, 500),
    'streak',           COALESCE(v_profile.daily_streak, 0),
    'last_claim',       v_profile.last_daily_claim,
    'can_claim',        COALESCE(v_settings.daily_bonus_enabled, true) AND (v_profile.last_daily_claim IS NULL OR v_profile.last_daily_claim < v_today),
    'next_claim',       CASE WHEN v_profile.last_daily_claim = v_today THEN (v_today + 1)::text ELSE v_today::text END,
    'streak_bonus',     COALESCE(v_settings.daily_bonus_streak_bonus, true)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_daily_bonus_status() TO authenticated;

-- ── 6. RPC admin : admin_set_daily_bonus ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_set_daily_bonus(
  _enabled      boolean,
  _amount_ar    integer,
  _streak_bonus boolean DEFAULT true
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_admin boolean;
BEGIN
  SELECT is_admin INTO v_admin FROM public.profiles WHERE id = auth.uid();
  IF NOT COALESCE(v_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  UPDATE public.app_settings SET
    daily_bonus_enabled   = _enabled,
    daily_bonus_amount_ar = _amount_ar,
    daily_bonus_streak_bonus = _streak_bonus
  WHERE id = 1;

  INSERT INTO public.admin_logs(admin_id, action, new_value)
    VALUES (auth.uid(), 'set_daily_bonus',
      jsonb_build_object('enabled', _enabled, 'amount_ar', _amount_ar, 'streak_bonus', _streak_bonus));
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_set_daily_bonus(boolean, integer, boolean) TO authenticated;

-- ── 7. RPC : get_full_history (parties + transactions filtrées) ───────────
CREATE OR REPLACE FUNCTION public.get_full_history(_uid uuid, _limit int DEFAULT 50)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_admin  boolean;
BEGIN
  SELECT is_admin INTO v_admin FROM public.profiles WHERE id = v_caller;
  IF _uid <> v_caller AND NOT COALESCE(v_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  RETURN jsonb_build_object(
    'transactions', (
      SELECT jsonb_agg(row_to_json(t) ORDER BY t.created_at DESC)
      FROM (SELECT * FROM public.transactions WHERE user_id = _uid ORDER BY created_at DESC LIMIT _limit) t
    ),
    'deposits', (
      SELECT jsonb_agg(row_to_json(d) ORDER BY d.created_at DESC)
      FROM (SELECT * FROM public.deposits WHERE user_id = _uid ORDER BY created_at DESC LIMIT _limit) d
    ),
    'withdrawals', (
      SELECT jsonb_agg(row_to_json(w) ORDER BY w.created_at DESC)
      FROM (SELECT * FROM public.withdrawals WHERE user_id = _uid ORDER BY created_at DESC LIMIT _limit) w
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_full_history(uuid, int) TO authenticated;

-- ── 8. Mise à jour automatique total_wins / total_games via trigger ───────
CREATE OR REPLACE FUNCTION public._update_player_stats_on_win()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE uid_t uuid;
BEGIN
  -- On UPDATE : game just finished with a winner
  IF TG_OP = 'UPDATE' AND OLD.status <> 'finished' AND NEW.status = 'finished' THEN
    -- Increment total_games for all participants
    -- winner
    IF NEW.winner_id IS NOT NULL THEN
      UPDATE public.profiles SET
        total_wins  = COALESCE(total_wins, 0) + 1,
        total_games = COALESCE(total_games, 0) + 1,
        player_level = CASE
          WHEN COALESCE(total_wins,0)+1 >= 200 THEN 10
          WHEN COALESCE(total_wins,0)+1 >= 100 THEN 9
          WHEN COALESCE(total_wins,0)+1 >= 60  THEN 8
          WHEN COALESCE(total_wins,0)+1 >= 35  THEN 7
          WHEN COALESCE(total_wins,0)+1 >= 20  THEN 6
          WHEN COALESCE(total_wins,0)+1 >= 12  THEN 5
          WHEN COALESCE(total_wins,0)+1 >= 7   THEN 4
          WHEN COALESCE(total_wins,0)+1 >= 3   THEN 3
          WHEN COALESCE(total_wins,0)+1 >= 1   THEN 2
          ELSE 1 END
      WHERE id = NEW.winner_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- Attach to domino_games, chess_games, fanorona_games
DO $$
BEGIN
  -- domino_games
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='domino_games' AND table_schema='public') THEN
    DROP TRIGGER IF EXISTS trg_player_stats_domino ON public.domino_games;
    CREATE TRIGGER trg_player_stats_domino
      AFTER UPDATE OF status ON public.domino_games FOR EACH ROW
      EXECUTE FUNCTION public._update_player_stats_on_win();
  END IF;
  -- chess_games
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='chess_games' AND table_schema='public') THEN
    DROP TRIGGER IF EXISTS trg_player_stats_chess ON public.chess_games;
    CREATE TRIGGER trg_player_stats_chess
      AFTER UPDATE OF status ON public.chess_games FOR EACH ROW
      EXECUTE FUNCTION public._update_player_stats_on_win();
  END IF;
  -- fanorona_games
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='fanorona_games' AND table_schema='public') THEN
    DROP TRIGGER IF EXISTS trg_player_stats_fanorona ON public.fanorona_games;
    CREATE TRIGGER trg_player_stats_fanorona
      AFTER UPDATE OF status ON public.fanorona_games FOR EACH ROW
      EXECUTE FUNCTION public._update_player_stats_on_win();
  END IF;
END;
$$;
