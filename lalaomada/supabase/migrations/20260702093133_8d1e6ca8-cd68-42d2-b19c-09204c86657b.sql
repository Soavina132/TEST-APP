-- STEP 0 : colonnes prérequis
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_banned          boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS last_daily_claim   date,
  ADD COLUMN IF NOT EXISTS daily_streak       int  NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_wins         int  NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_games        int  NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS player_level       int  NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS suspended_until    timestamptz,
  ADD COLUMN IF NOT EXISTS suspension_reason  text,
  ADD COLUMN IF NOT EXISTS warning_count      int  NOT NULL DEFAULT 0;

-- Si "banned" existe déjà, alignons les valeurs actuelles
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='profiles' AND column_name='banned') THEN
    EXECUTE 'UPDATE public.profiles SET is_banned = COALESCE(banned, false) WHERE is_banned IS DISTINCT FROM COALESCE(banned, false)';
  END IF;
END; $$;

-- Trigger de synchro bidirectionnelle banned <-> is_banned
CREATE OR REPLACE FUNCTION public._sync_banned_flags()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF TG_OP IN ('INSERT','UPDATE') THEN
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema='public' AND table_name='profiles' AND column_name='banned') THEN
      IF NEW.is_banned IS DISTINCT FROM COALESCE(NEW.banned, false) THEN
        IF TG_OP='INSERT' OR NEW.is_banned IS DISTINCT FROM OLD.is_banned THEN
          NEW.banned := NEW.is_banned;
        ELSIF NEW.banned IS DISTINCT FROM OLD.banned THEN
          NEW.is_banned := COALESCE(NEW.banned, false);
        END IF;
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_sync_banned_flags ON public.profiles;
CREATE TRIGGER trg_sync_banned_flags BEFORE INSERT OR UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public._sync_banned_flags();

ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS daily_bonus_enabled      boolean  NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS daily_bonus_amount_ar    integer  NOT NULL DEFAULT 500,
  ADD COLUMN IF NOT EXISTS daily_bonus_streak_bonus boolean  NOT NULL DEFAULT true;

-- ═══════════════════════════════════════════════════════════════════════
-- Bug Reports
-- ═══════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.bug_reports (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  category    TEXT        NOT NULL DEFAULT 'general',
  message     TEXT        NOT NULL CHECK (length(trim(message)) >= 5),
  status      TEXT        NOT NULL DEFAULT 'open'
                          CHECK (status IN ('open','in_progress','resolved','closed')),
  admin_note  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at TIMESTAMPTZ
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.bug_reports TO authenticated;
GRANT ALL ON public.bug_reports TO service_role;
ALTER TABLE public.bug_reports ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "bug_reports_select" ON public.bug_reports;
CREATE POLICY "bug_reports_select" ON public.bug_reports FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());
DROP POLICY IF EXISTS "bug_reports_insert" ON public.bug_reports;
CREATE POLICY "bug_reports_insert" ON public.bug_reports FOR INSERT
  WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "bug_reports_admin_update" ON public.bug_reports;
CREATE POLICY "bug_reports_admin_update" ON public.bug_reports FOR UPDATE
  USING (public.is_admin());

CREATE OR REPLACE FUNCTION public.submit_bug_report(_category TEXT, _message TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); v_id UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF length(trim(_message)) < 5 THEN RAISE EXCEPTION 'Message trop court'; END IF;
  INSERT INTO public.bug_reports(user_id, category, message)
  VALUES (v_uid, COALESCE(NULLIF(trim(_category),''), 'general'), trim(_message))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.submit_bug_report(TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_bug_report(TEXT,TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_update_bug_report(
  _id UUID, _status TEXT, _admin_note TEXT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  UPDATE public.bug_reports SET
    status     = _status,
    admin_note = COALESCE(_admin_note, admin_note),
    resolved_at = CASE WHEN _status IN ('resolved','closed') THEN now() ELSE resolved_at END
  WHERE id = _id;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_update_bug_report(UUID,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_bug_report(UUID,TEXT,TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_list_bug_reports(
  _status TEXT DEFAULT NULL, _limit INT DEFAULT 100
) RETURNS TABLE(
  id UUID, user_id UUID, pseudo TEXT, category TEXT, message TEXT,
  status TEXT, admin_note TEXT, created_at TIMESTAMPTZ, resolved_at TIMESTAMPTZ
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  RETURN QUERY
    SELECT br.id, br.user_id, COALESCE(p.pseudo, 'Joueur supprimé'),
           br.category, br.message, br.status, br.admin_note,
           br.created_at, br.resolved_at
    FROM public.bug_reports br
    LEFT JOIN public.profiles p ON p.id = br.user_id
    WHERE (_status IS NULL OR br.status = _status)
    ORDER BY br.created_at DESC
    LIMIT _limit;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_list_bug_reports(TEXT,INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_bug_reports(TEXT,INT) TO authenticated;

-- Public profile
CREATE OR REPLACE FUNCTION public.get_public_profile(_id uuid)
RETURNS TABLE(
  id uuid, pseudo text, avatar_url text, unique_code text, created_at timestamptz,
  player_level int, total_wins int, total_games int, daily_streak int
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT
    p.id, p.pseudo, p.avatar_url, p.unique_code, p.created_at,
    COALESCE(p.player_level, 1),
    COALESCE(p.total_wins, 0),
    COALESCE(p.total_games, 0),
    COALESCE(p.daily_streak, 0)
  FROM public.profiles p
  WHERE p.id = _id AND (p.is_banned = false OR p.is_banned IS NULL);
$$;
GRANT EXECUTE ON FUNCTION public.get_public_profile(uuid) TO anon, authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- ACHIEVEMENTS
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.achievements (
  key         text PRIMARY KEY,
  label       text NOT NULL,
  description text NOT NULL,
  icon        text NOT NULL DEFAULT '🏅',
  xp_reward   int  NOT NULL DEFAULT 0,
  sort_order  int  NOT NULL DEFAULT 0
);
GRANT SELECT ON public.achievements TO anon, authenticated;
GRANT ALL ON public.achievements TO service_role;

CREATE TABLE IF NOT EXISTS public.player_achievements (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  achievement_key text NOT NULL REFERENCES public.achievements(key) ON DELETE CASCADE,
  earned_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, achievement_key)
);
GRANT SELECT ON public.player_achievements TO anon, authenticated;
GRANT ALL ON public.player_achievements TO service_role;
CREATE INDEX IF NOT EXISTS player_achievements_user_idx ON public.player_achievements(user_id);
ALTER TABLE public.player_achievements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "player_achievements_read_all" ON public.player_achievements;
CREATE POLICY "player_achievements_read_all" ON public.player_achievements FOR SELECT USING (true);

INSERT INTO public.achievements (key, label, description, icon, xp_reward, sort_order) VALUES
  ('first_win','Premier sang','Remporter votre toute première victoire','🏆',10,1),
  ('wins_10','En forme','Accumuler 10 victoires','🥈',20,2),
  ('wins_50','Joueur confirmé','Accumuler 50 victoires','🥇',50,3),
  ('wins_100','Centurion','Accumuler 100 victoires','💎',100,4),
  ('wins_200','Légende vivante','Accumuler 200 victoires','👑',200,5),
  ('games_50','Assidu','Jouer 50 parties','🎮',15,6),
  ('games_100','Vétéran','Jouer 100 parties','🎖️',30,7),
  ('streak_7','Habitué','Se connecter 7 jours consécutifs','🔥',25,8),
  ('streak_30','Dévot','Se connecter 30 jours consécutifs','⚡',75,9),
  ('ludo_10','Maître du Ludo','Gagner 10 parties de Ludo','🎲',20,10),
  ('chess_10','Stratège','Gagner 10 parties d''Échecs','♟️',20,11),
  ('domino_10','Domino Pro','Gagner 10 parties de Domino','🁣',20,12),
  ('fanorona_10','Maître Fanorona','Gagner 10 parties de Fanorona','🎯',20,13),
  ('rami_10','Roi du Rami','Gagner 10 parties de Rami','🃏',20,14),
  ('first_deposit','Bienvenue !','Effectuer votre premier dépôt','💰',5,15),
  ('big_win','Gros lot','Remporter un gain d''au moins 500 Ar en une partie','🤑',30,16)
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.check_and_award_achievements(_uid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_wins int; v_games int; v_streak int;
  v_ludo_wins int:=0; v_chess_wins int:=0; v_domino_wins int:=0; v_fanorona_wins int:=0; v_rami_wins int:=0;
  v_has_deposit boolean := false;
BEGIN
  SELECT COALESCE(total_wins,0), COALESCE(total_games,0), COALESCE(daily_streak,0)
  INTO v_wins, v_games, v_streak FROM public.profiles WHERE id = _uid;
  BEGIN SELECT COUNT(*) INTO v_ludo_wins     FROM public.ludo_games     WHERE winner_id = _uid; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN SELECT COUNT(*) INTO v_chess_wins    FROM public.chess_games    WHERE winner_id = _uid; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN SELECT COUNT(*) INTO v_domino_wins   FROM public.domino_games   WHERE winner_id = _uid; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN SELECT COUNT(*) INTO v_fanorona_wins FROM public.fanorona_games WHERE winner_id = _uid; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN SELECT COUNT(*) INTO v_rami_wins     FROM public.rami_games     WHERE winner_id = _uid; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN SELECT EXISTS(SELECT 1 FROM public.deposits WHERE user_id = _uid AND status = 'approved') INTO v_has_deposit; EXCEPTION WHEN OTHERS THEN NULL; END;
  IF v_wins   >= 1   THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'first_win')   ON CONFLICT DO NOTHING; END IF;
  IF v_wins   >= 10  THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'wins_10')     ON CONFLICT DO NOTHING; END IF;
  IF v_wins   >= 50  THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'wins_50')     ON CONFLICT DO NOTHING; END IF;
  IF v_wins   >= 100 THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'wins_100')    ON CONFLICT DO NOTHING; END IF;
  IF v_wins   >= 200 THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'wins_200')    ON CONFLICT DO NOTHING; END IF;
  IF v_games  >= 50  THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'games_50')    ON CONFLICT DO NOTHING; END IF;
  IF v_games  >= 100 THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'games_100')   ON CONFLICT DO NOTHING; END IF;
  IF v_streak >= 7   THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'streak_7')    ON CONFLICT DO NOTHING; END IF;
  IF v_streak >= 30  THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'streak_30')   ON CONFLICT DO NOTHING; END IF;
  IF v_ludo_wins    >= 10 THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'ludo_10')     ON CONFLICT DO NOTHING; END IF;
  IF v_chess_wins   >= 10 THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'chess_10')    ON CONFLICT DO NOTHING; END IF;
  IF v_domino_wins  >= 10 THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'domino_10')   ON CONFLICT DO NOTHING; END IF;
  IF v_fanorona_wins>= 10 THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'fanorona_10') ON CONFLICT DO NOTHING; END IF;
  IF v_rami_wins    >= 10 THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'rami_10')     ON CONFLICT DO NOTHING; END IF;
  IF v_has_deposit  THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'first_deposit') ON CONFLICT DO NOTHING; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public._trg_check_achievements_on_win()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.total_wins IS DISTINCT FROM OLD.total_wins OR NEW.daily_streak IS DISTINCT FROM OLD.daily_streak THEN
    PERFORM public.check_and_award_achievements(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_check_achievements ON public.profiles;
CREATE TRIGGER trg_check_achievements AFTER UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public._trg_check_achievements_on_win();

CREATE OR REPLACE FUNCTION public.get_player_achievements(_uid uuid)
RETURNS TABLE(key text, label text, description text, icon text, xp_reward int, earned_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT a.key, a.label, a.description, a.icon, a.xp_reward, pa.earned_at
  FROM public.achievements a
  JOIN public.player_achievements pa ON pa.achievement_key = a.key AND pa.user_id = _uid
  ORDER BY pa.earned_at DESC;
$$;
GRANT EXECUTE ON FUNCTION public.get_player_achievements(uuid) TO authenticated, anon;

-- ═══════════════════════════════════════════════════════════════════════════
-- ADMIN PERM DELETE + SOFT DELETE
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.admin_permanently_delete_user(_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::public.app_role) THEN RAISE EXCEPTION 'Accès refusé'; END IF;
  IF _user_id = auth.uid() THEN RAISE EXCEPTION 'Impossible de supprimer votre propre compte'; END IF;
  BEGIN UPDATE public.ludo_games     SET winner_id = NULL WHERE winner_id = _user_id; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN UPDATE public.domino_games   SET winner_id = NULL WHERE winner_id = _user_id; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN UPDATE public.fanorona_games SET winner_id = NULL WHERE winner_id = _user_id; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN UPDATE public.rami_games     SET winner_id = NULL WHERE winner_id = _user_id; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN UPDATE public.chess_games    SET winner_id = NULL WHERE winner_id = _user_id; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN UPDATE public.chess_games    SET white_id  = NULL WHERE white_id  = _user_id; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN UPDATE public.chess_games    SET black_id  = NULL WHERE black_id  = _user_id; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN UPDATE public.profiles       SET referred_by = NULL WHERE referred_by = _user_id; EXCEPTION WHEN OTHERS THEN NULL; END;
  DELETE FROM auth.users WHERE id = _user_id;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_permanently_delete_user(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_permanently_delete_user(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  BEGIN UPDATE public.profiles SET pseudo='Compte supprimé', avatar_url=NULL, balance_ar=0, is_banned=true WHERE id = v_uid; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN UPDATE public.ludo_games     SET winner_id = NULL WHERE winner_id = v_uid; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN UPDATE public.domino_games   SET winner_id = NULL WHERE winner_id = v_uid; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN UPDATE public.fanorona_games SET winner_id = NULL WHERE winner_id = v_uid; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN UPDATE public.rami_games     SET winner_id = NULL WHERE winner_id = v_uid; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN UPDATE public.chess_games    SET winner_id = NULL WHERE winner_id = v_uid; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN UPDATE public.chess_games    SET white_id  = NULL WHERE white_id  = v_uid; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN UPDATE public.chess_games    SET black_id  = NULL WHERE black_id  = v_uid; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN UPDATE public.profiles       SET referred_by = NULL WHERE referred_by = v_uid; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN DELETE FROM auth.users WHERE id = v_uid; EXCEPTION WHEN OTHERS THEN NULL; END;
END;
$$;
REVOKE ALL ON FUNCTION public.delete_my_account() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_my_account() TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- VIEW + BONUS FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE VIEW public.v_player_stats AS
SELECT
  p.id, p.pseudo, p.avatar_url,
  COALESCE(p.total_wins,  0)  AS total_wins,
  COALESCE(p.total_games, 0)  AS total_games,
  COALESCE(p.player_level, 1) AS player_level,
  COALESCE(p.daily_streak, 0) AS daily_streak
FROM public.profiles p
WHERE p.is_banned = false OR p.is_banned IS NULL;
GRANT SELECT ON public.v_player_stats TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.claim_daily_bonus()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_uid uuid := auth.uid(); v_profile record; v_settings record;
  v_today date := CURRENT_DATE; v_streak int; v_base_amount int;
  v_multiplier int := 1; v_amount int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT daily_bonus_enabled, daily_bonus_amount_ar, daily_bonus_streak_bonus
    INTO v_settings FROM public.app_settings WHERE id = 1;
  IF NOT COALESCE(v_settings.daily_bonus_enabled, true) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'bonus_disabled');
  END IF;
  SELECT last_daily_claim, daily_streak INTO v_profile FROM public.profiles WHERE id = v_uid;
  IF v_profile.last_daily_claim = v_today THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_claimed', 'next_claim', (v_today + 1)::text);
  END IF;
  v_streak := CASE WHEN v_profile.last_daily_claim = v_today - 1 THEN COALESCE(v_profile.daily_streak, 0) + 1 ELSE 1 END;
  v_base_amount := COALESCE(v_settings.daily_bonus_amount_ar, 500);
  IF COALESCE(v_settings.daily_bonus_streak_bonus, true) THEN
    IF v_streak >= 14 THEN v_multiplier := 3;
    ELSIF v_streak >= 7 THEN v_multiplier := 2;
    END IF;
  END IF;
  v_amount := v_base_amount * v_multiplier;
  UPDATE public.profiles
     SET last_daily_claim = v_today, daily_streak = v_streak,
         balance_ar = COALESCE(balance_ar, 0) + v_amount
   WHERE id = v_uid;
  RETURN jsonb_build_object('ok', true, 'amount', v_amount, 'streak', v_streak,
    'multiplier', v_multiplier, 'next_claim', (v_today + 1)::text);
END;
$$;
GRANT EXECUTE ON FUNCTION public.claim_daily_bonus() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_daily_bonus_status()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_profile record; v_settings record; v_today date := CURRENT_DATE;
BEGIN
  SELECT last_daily_claim, daily_streak INTO v_profile FROM public.profiles WHERE id = v_uid;
  SELECT daily_bonus_enabled, daily_bonus_amount_ar, daily_bonus_streak_bonus INTO v_settings FROM public.app_settings WHERE id = 1;
  RETURN jsonb_build_object(
    'enabled',     COALESCE(v_settings.daily_bonus_enabled, true),
    'base_amount', COALESCE(v_settings.daily_bonus_amount_ar, 500),
    'streak',      COALESCE(v_profile.daily_streak, 0),
    'last_claim',  v_profile.last_daily_claim,
    'can_claim',   COALESCE(v_settings.daily_bonus_enabled, true) AND (v_profile.last_daily_claim IS NULL OR v_profile.last_daily_claim < v_today),
    'next_claim',  CASE WHEN v_profile.last_daily_claim = v_today THEN (v_today + 1)::text ELSE v_today::text END,
    'streak_bonus',COALESCE(v_settings.daily_bonus_streak_bonus, true));
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_daily_bonus_status() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_daily_bonus(
  _enabled boolean, _amount_ar integer, _streak_bonus boolean DEFAULT true
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::public.app_role) THEN RAISE EXCEPTION 'Accès refusé'; END IF;
  UPDATE public.app_settings SET
    daily_bonus_enabled       = _enabled,
    daily_bonus_amount_ar     = _amount_ar,
    daily_bonus_streak_bonus  = _streak_bonus
  WHERE id = 1;
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_set_daily_bonus(boolean, integer, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_full_history(_uid uuid, _limit int DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_caller uuid := auth.uid();
BEGIN
  IF _uid <> v_caller AND NOT public.has_role(v_caller, 'admin'::public.app_role) THEN RAISE EXCEPTION 'Accès refusé'; END IF;
  RETURN jsonb_build_object(
    'transactions', (SELECT jsonb_agg(row_to_json(t) ORDER BY t.created_at DESC) FROM (SELECT * FROM public.transactions WHERE user_id = _uid ORDER BY created_at DESC LIMIT _limit) t),
    'deposits',     (SELECT jsonb_agg(row_to_json(d) ORDER BY d.created_at DESC) FROM (SELECT * FROM public.deposits     WHERE user_id = _uid ORDER BY created_at DESC LIMIT _limit) d),
    'withdrawals',  (SELECT jsonb_agg(row_to_json(w) ORDER BY w.created_at DESC) FROM (SELECT * FROM public.withdrawals  WHERE user_id = _uid ORDER BY created_at DESC LIMIT _limit) w));
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_full_history(uuid, int) TO authenticated;

CREATE OR REPLACE FUNCTION public._update_player_stats_on_win()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.status <> 'finished' AND NEW.status = 'finished' AND NEW.winner_id IS NOT NULL THEN
    UPDATE public.profiles SET
      total_wins   = COALESCE(total_wins, 0) + 1,
      total_games  = COALESCE(total_games, 0) + 1,
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
  RETURN NEW;
END;
$$;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='domino_games' AND table_schema='public') THEN
    DROP TRIGGER IF EXISTS trg_player_stats_domino ON public.domino_games;
    CREATE TRIGGER trg_player_stats_domino AFTER UPDATE OF status ON public.domino_games FOR EACH ROW EXECUTE FUNCTION public._update_player_stats_on_win();
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='chess_games' AND table_schema='public') THEN
    DROP TRIGGER IF EXISTS trg_player_stats_chess ON public.chess_games;
    CREATE TRIGGER trg_player_stats_chess AFTER UPDATE OF status ON public.chess_games FOR EACH ROW EXECUTE FUNCTION public._update_player_stats_on_win();
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='fanorona_games' AND table_schema='public') THEN
    DROP TRIGGER IF EXISTS trg_player_stats_fanorona ON public.fanorona_games;
    CREATE TRIGGER trg_player_stats_fanorona AFTER UPDATE OF status ON public.fanorona_games FOR EACH ROW EXECUTE FUNCTION public._update_player_stats_on_win();
  END IF;
END; $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- FIX: leaderboard_winners
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.leaderboard_winners(_period text DEFAULT 'all', _limit int DEFAULT 20)
RETURNS TABLE(rank int, id uuid, name text, avatar_url text, wins bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH bound AS (
    SELECT CASE _period
      WHEN 'week'  THEN now() - interval '7 days'
      WHEN 'month' THEN now() - interval '30 days'
      ELSE 'epoch'::timestamptz
    END AS since
  ),
  raw AS (
    SELECT g.winner_id AS uid FROM public.ludo_games g,     bound WHERE g.status='finished' AND g.winner_id IS NOT NULL AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL SELECT g.winner_id FROM public.domino_games g,   bound WHERE g.status='finished' AND g.winner_id IS NOT NULL AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL SELECT g.winner_id FROM public.fanorona_games g, bound WHERE g.status='finished' AND g.winner_id IS NOT NULL AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL SELECT g.winner_id FROM public.rami_games g,     bound WHERE g.status='finished' AND g.winner_id IS NOT NULL AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL SELECT g.winner_id FROM public.chess_games g,    bound WHERE g.status='finished' AND g.winner_id IS NOT NULL AND COALESCE(g.finished_at,g.created_at) >= bound.since
  ),
  agg AS (
    SELECT r.uid, count(*)::bigint AS wins FROM raw r
    WHERE NOT public.has_role(r.uid, 'admin'::public.app_role)
    GROUP BY r.uid
  ),
  joined AS (
    SELECT p.pseudo AS name, p.avatar_url, a.uid AS id, a.wins
    FROM agg a INNER JOIN public.profiles p ON p.id = a.uid
    WHERE (p.is_banned IS NULL OR p.is_banned = false)
  )
  SELECT (row_number() OVER (ORDER BY j.wins DESC, j.name ASC))::int AS rank,
         j.id, j.name, j.avatar_url, j.wins
  FROM joined j
  ORDER BY j.wins DESC, j.name ASC
  LIMIT _limit;
$$;
REVOKE ALL ON FUNCTION public.leaderboard_winners(text, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.leaderboard_winners(text, int) TO authenticated, anon;