-- ═══════════════════════════════════════════════════════════════════════════
-- 1. ACHIEVEMENTS
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.achievements (
  key         text PRIMARY KEY,
  label       text NOT NULL,
  description text NOT NULL,
  icon        text NOT NULL DEFAULT '🏅',
  xp_reward   int  NOT NULL DEFAULT 0,
  sort_order  int  NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS public.player_achievements (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  achievement_key text NOT NULL REFERENCES public.achievements(key) ON DELETE CASCADE,
  earned_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, achievement_key)
);

CREATE INDEX IF NOT EXISTS player_achievements_user_idx ON public.player_achievements(user_id);

ALTER TABLE public.player_achievements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "player_achievements_own" ON public.player_achievements;
CREATE POLICY "player_achievements_own" ON public.player_achievements FOR SELECT USING (true);

-- Seed achievement definitions
INSERT INTO public.achievements (key, label, description, icon, xp_reward, sort_order) VALUES
  ('first_win',     'Premier sang',        'Remporter votre toute première victoire',        '🏆', 10, 1),
  ('wins_10',       'En forme',            'Accumuler 10 victoires',                         '🥈', 20, 2),
  ('wins_50',       'Joueur confirmé',     'Accumuler 50 victoires',                         '🥇', 50, 3),
  ('wins_100',      'Centurion',           'Accumuler 100 victoires',                        '💎', 100, 4),
  ('wins_200',      'Légende vivante',     'Accumuler 200 victoires',                        '👑', 200, 5),
  ('games_50',      'Assidu',             'Jouer 50 parties',                               '🎮', 15, 6),
  ('games_100',     'Vétéran',            'Jouer 100 parties',                              '🎖️', 30, 7),
  ('streak_7',      'Habitué',            'Se connecter 7 jours consécutifs',               '🔥', 25, 8),
  ('streak_30',     'Dévot',             'Se connecter 30 jours consécutifs',              '⚡', 75, 9),
  ('ludo_10',       'Maître du Ludo',     'Gagner 10 parties de Ludo',                     '🎲', 20, 10),
  ('chess_10',      'Stratège',           'Gagner 10 parties d''Échecs',                   '♟️', 20, 11),
  ('domino_10',     'Domino Pro',         'Gagner 10 parties de Domino',                   '🁣', 20, 12),
  ('fanorona_10',   'Maître Fanorona',    'Gagner 10 parties de Fanorona',                 '🎯', 20, 13),
  ('rami_10',       'Roi du Rami',        'Gagner 10 parties de Rami',                     '🃏', 20, 14),
  ('first_deposit', 'Bienvenue !',        'Effectuer votre premier dépôt',                  '💰', 5,  15),
  ('big_win',       'Gros lot',           'Remporter un gain d''au moins 500 Ar en une partie', '🤑', 30, 16)
ON CONFLICT (key) DO NOTHING;

-- Function: check and award achievements for a user
CREATE OR REPLACE FUNCTION public.check_and_award_achievements(_uid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_wins        int;
  v_games       int;
  v_streak      int;
  v_ludo_wins   int;
  v_chess_wins  int;
  v_domino_wins int;
  v_fanorona_wins int;
  v_rami_wins   int;
  v_has_deposit boolean;
  v_big_win     boolean;
BEGIN
  SELECT COALESCE(total_wins,0), COALESCE(total_games,0), COALESCE(daily_streak,0)
  INTO v_wins, v_games, v_streak
  FROM public.profiles WHERE id = _uid;

  SELECT COUNT(*) INTO v_ludo_wins    FROM public.ludo_games    WHERE winner_id = _uid;
  SELECT COUNT(*) INTO v_chess_wins   FROM public.chess_games   WHERE winner_id = _uid;
  SELECT COUNT(*) INTO v_domino_wins  FROM public.domino_games  WHERE winner_id = _uid;
  SELECT COUNT(*) INTO v_fanorona_wins FROM public.fanorona_games WHERE winner_id = _uid;
  SELECT COUNT(*) INTO v_rami_wins    FROM public.rami_games    WHERE winner_id = _uid;
  SELECT EXISTS(SELECT 1 FROM public.deposits WHERE user_id = _uid AND status = 'approved') INTO v_has_deposit;
  SELECT EXISTS(SELECT 1 FROM public.transactions WHERE user_id = _uid AND type = 'win' AND amount >= 500) INTO v_big_win;

  -- Win milestones
  IF v_wins >= 1   THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'first_win')   ON CONFLICT DO NOTHING; END IF;
  IF v_wins >= 10  THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'wins_10')     ON CONFLICT DO NOTHING; END IF;
  IF v_wins >= 50  THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'wins_50')     ON CONFLICT DO NOTHING; END IF;
  IF v_wins >= 100 THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'wins_100')    ON CONFLICT DO NOTHING; END IF;
  IF v_wins >= 200 THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'wins_200')    ON CONFLICT DO NOTHING; END IF;
  -- Game milestones
  IF v_games >= 50  THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'games_50')  ON CONFLICT DO NOTHING; END IF;
  IF v_games >= 100 THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'games_100') ON CONFLICT DO NOTHING; END IF;
  -- Streak
  IF v_streak >= 7  THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'streak_7')  ON CONFLICT DO NOTHING; END IF;
  IF v_streak >= 30 THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'streak_30') ON CONFLICT DO NOTHING; END IF;
  -- Per-game
  IF v_ludo_wins    >= 10 THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'ludo_10')     ON CONFLICT DO NOTHING; END IF;
  IF v_chess_wins   >= 10 THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'chess_10')    ON CONFLICT DO NOTHING; END IF;
  IF v_domino_wins  >= 10 THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'domino_10')   ON CONFLICT DO NOTHING; END IF;
  IF v_fanorona_wins >= 10 THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'fanorona_10') ON CONFLICT DO NOTHING; END IF;
  IF v_rami_wins    >= 10 THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'rami_10')     ON CONFLICT DO NOTHING; END IF;
  -- Other
  IF v_has_deposit THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'first_deposit') ON CONFLICT DO NOTHING; END IF;
  IF v_big_win     THEN INSERT INTO public.player_achievements(user_id, achievement_key) VALUES(_uid,'big_win')       ON CONFLICT DO NOTHING; END IF;
END;
$$;

-- Trigger: check after wins update
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
CREATE TRIGGER trg_check_achievements
  AFTER UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public._trg_check_achievements_on_win();

-- RPC: get achievements for a player (public)
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
-- 2. ADMIN PERMANENT DELETE USER
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_permanently_delete_user(_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
BEGIN
  -- Only admins can call this
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'Accès refusé';
  END IF;
  -- Cannot delete self
  IF _user_id = auth.uid() THEN
    RAISE EXCEPTION 'Impossible de supprimer votre propre compte';
  END IF;

  -- Clean game participant tables (non-cascade)
  UPDATE public.ludo_games    SET winner_id = NULL WHERE winner_id = _user_id;
  UPDATE public.domino_games  SET winner_id = NULL WHERE winner_id = _user_id;
  UPDATE public.fanorona_games SET winner_id = NULL WHERE winner_id = _user_id;
  UPDATE public.rami_games    SET winner_id = NULL WHERE winner_id = _user_id;
  UPDATE public.chess_games   SET winner_id = NULL WHERE winner_id = _user_id;
  UPDATE public.chess_games   SET white_id  = NULL WHERE white_id  = _user_id;
  UPDATE public.chess_games   SET black_id  = NULL WHERE black_id  = _user_id;

  -- Nullify referral chain references (don't delete other people's profiles)
  UPDATE public.profiles SET referred_by = NULL WHERE referred_by = _user_id;

  -- Delete the auth user — cascades to profiles, and via FK to other tables
  DELETE FROM auth.users WHERE id = _user_id;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_permanently_delete_user(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_permanently_delete_user(uuid) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. USER SELF-DELETE (verify password on client, then call this)
-- ═══════════════════════════════════════════════════════════════════════════

-- The existing delete_my_account() already works; we just make sure it's clean
CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE v_uid uuid;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  -- Nullify winner references (keep game history intact for other players)
  UPDATE public.ludo_games    SET winner_id = NULL WHERE winner_id = v_uid;
  UPDATE public.domino_games  SET winner_id = NULL WHERE winner_id = v_uid;
  UPDATE public.fanorona_games SET winner_id = NULL WHERE winner_id = v_uid;
  UPDATE public.rami_games    SET winner_id = NULL WHERE winner_id = v_uid;
  UPDATE public.chess_games   SET winner_id = NULL WHERE winner_id = v_uid;
  UPDATE public.chess_games   SET white_id  = NULL WHERE white_id  = v_uid;
  UPDATE public.chess_games   SET black_id  = NULL WHERE black_id  = v_uid;
  UPDATE public.profiles SET referred_by = NULL WHERE referred_by = v_uid;
  -- Delete auth user (cascades to profiles and downstream)
  DELETE FROM auth.users WHERE id = v_uid;
END;
$$;
REVOKE ALL ON FUNCTION public.delete_my_account() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_my_account() TO authenticated;
