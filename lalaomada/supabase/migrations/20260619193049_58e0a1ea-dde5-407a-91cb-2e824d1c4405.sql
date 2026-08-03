
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS first_deposit_at timestamptz;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS first_deposit_amount numeric;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS first_game_at timestamptz;

UPDATE public.app_settings SET referral_pct = 10 WHERE id = 1 AND COALESCE(referral_pct,0) < 10;

CREATE OR REPLACE FUNCTION public._try_unlock_referral(_uid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_parent uuid; v_pct numeric; v_reward numeric;
  v_verified boolean; v_unlocked boolean;
  v_dep_at timestamptz; v_game_at timestamptz; v_amount numeric;
BEGIN
  SELECT referred_by, phone_verified, referral_unlocked, first_deposit_at, first_game_at, first_deposit_amount
    INTO v_parent, v_verified, v_unlocked, v_dep_at, v_game_at, v_amount
    FROM public.profiles WHERE id = _uid;
  IF v_parent IS NULL OR v_unlocked = true THEN RETURN; END IF;
  IF v_verified = true AND v_dep_at IS NOT NULL AND v_game_at IS NOT NULL AND COALESCE(v_amount,0) > 0 THEN
    SELECT COALESCE(referral_pct, 10) INTO v_pct FROM public.app_settings WHERE id = 1;
    v_reward := v_amount * v_pct / 100.0;
    UPDATE public.profiles SET balance_ar = balance_ar + v_reward WHERE id = v_parent;
    UPDATE public.profiles SET referral_unlocked = true WHERE id = _uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_parent, 'referral', v_reward, NULL, 'Parrainage débloqué (filleul: ' || _uid || ')');
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public._referral_on_deposit()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.status = 'approved' AND (OLD.status IS NULL OR OLD.status <> 'approved') THEN
    UPDATE public.profiles
       SET first_deposit_at = COALESCE(first_deposit_at, now()),
           first_deposit_amount = COALESCE(first_deposit_amount, NEW.amount)
     WHERE id = NEW.user_id;
    PERFORM public._try_unlock_referral(NEW.user_id);
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public._mark_first_game()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record; v_table text := TG_ARGV[0];
BEGIN
  IF NEW.status = 'finished' AND (OLD.status IS NULL OR OLD.status <> 'finished') THEN
    IF v_table = 'chess' THEN
      IF NEW.white_id IS NOT NULL THEN
        UPDATE public.profiles SET first_game_at = COALESCE(first_game_at, now()) WHERE id = NEW.white_id;
        PERFORM public._try_unlock_referral(NEW.white_id);
      END IF;
      IF NEW.black_id IS NOT NULL THEN
        UPDATE public.profiles SET first_game_at = COALESCE(first_game_at, now()) WHERE id = NEW.black_id;
        PERFORM public._try_unlock_referral(NEW.black_id);
      END IF;
    ELSE
      FOR r IN EXECUTE format('SELECT DISTINCT user_id FROM public.%I_participants WHERE game_id = $1 AND user_id IS NOT NULL', v_table) USING NEW.id LOOP
        UPDATE public.profiles SET first_game_at = COALESCE(first_game_at, now()) WHERE id = r.user_id;
        PERFORM public._try_unlock_referral(r.user_id);
      END LOOP;
    END IF;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_first_game_ludo ON public.ludo_games;
CREATE TRIGGER trg_first_game_ludo AFTER UPDATE ON public.ludo_games
  FOR EACH ROW EXECUTE FUNCTION public._mark_first_game('ludo');
DROP TRIGGER IF EXISTS trg_first_game_domino ON public.domino_games;
CREATE TRIGGER trg_first_game_domino AFTER UPDATE ON public.domino_games
  FOR EACH ROW EXECUTE FUNCTION public._mark_first_game('domino');
DROP TRIGGER IF EXISTS trg_first_game_fanorona ON public.fanorona_games;
CREATE TRIGGER trg_first_game_fanorona AFTER UPDATE ON public.fanorona_games
  FOR EACH ROW EXECUTE FUNCTION public._mark_first_game('fanorona');
DROP TRIGGER IF EXISTS trg_first_game_rami ON public.rami_games;
CREATE TRIGGER trg_first_game_rami AFTER UPDATE ON public.rami_games
  FOR EACH ROW EXECUTE FUNCTION public._mark_first_game('rami');
DROP TRIGGER IF EXISTS trg_first_game_chess ON public.chess_games;
CREATE TRIGGER trg_first_game_chess AFTER UPDATE ON public.chess_games
  FOR EACH ROW EXECUTE FUNCTION public._mark_first_game('chess');

CREATE OR REPLACE FUNCTION public._referral_on_phone_verified()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NEW.phone_verified = true AND (OLD.phone_verified IS DISTINCT FROM true) THEN
    PERFORM public._try_unlock_referral(NEW.id);
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_referral_on_phone ON public.profiles;
CREATE TRIGGER trg_referral_on_phone AFTER UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public._referral_on_phone_verified();

CREATE OR REPLACE FUNCTION public.admin_reset_all_terms()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n integer;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN RAISE EXCEPTION 'Forbidden'; END IF;
  UPDATE public.profiles SET terms_accepted_at = NULL WHERE terms_accepted_at IS NOT NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;
REVOKE EXECUTE ON FUNCTION public.admin_reset_all_terms() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_reset_all_terms() TO authenticated;

CREATE OR REPLACE FUNCTION public.weekly_top_winners(_limit int DEFAULT 10)
RETURNS TABLE(user_id uuid, pseudo text, avatar_url text, wins bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH wins AS (
    SELECT g.winner_id AS uid, COALESCE(NULLIF(trim(pp.display_name),''), p.pseudo, 'Joueur') AS name
      FROM ludo_games g
      JOIN ludo_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id
      LEFT JOIN profiles p ON p.id=g.winner_id
      WHERE g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at, g.created_at) >= now() - interval '7 days'
    UNION ALL
    SELECT g.winner_id, COALESCE(NULLIF(trim(pp.display_name),''), p.pseudo, 'Joueur')
      FROM domino_games g
      JOIN domino_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id
      LEFT JOIN profiles p ON p.id=g.winner_id
      WHERE g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at, g.created_at) >= now() - interval '7 days'
    UNION ALL
    SELECT g.winner_id, COALESCE(NULLIF(trim(pp.display_name),''), p.pseudo, 'Joueur')
      FROM fanorona_games g
      JOIN fanorona_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id
      LEFT JOIN profiles p ON p.id=g.winner_id
      WHERE g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at, g.created_at) >= now() - interval '7 days'
    UNION ALL
    SELECT g.winner_id, COALESCE(NULLIF(trim(pp.display_name),''), p.pseudo, 'Joueur')
      FROM rami_games g
      JOIN rami_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id
      LEFT JOIN profiles p ON p.id=g.winner_id
      WHERE g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at, g.created_at) >= now() - interval '7 days'
    UNION ALL
    SELECT g.winner_id, COALESCE(p.pseudo, 'Joueur')
      FROM chess_games g
      LEFT JOIN profiles p ON p.id=g.winner_id
      WHERE g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at, g.created_at) >= now() - interval '7 days'
  ),
  agg AS (
    SELECT name, (array_agg(uid))[1] AS uid, count(*)::bigint AS wins
    FROM wins
    GROUP BY name
  )
  SELECT a.uid, a.name, p.avatar_url, a.wins
  FROM agg a LEFT JOIN profiles p ON p.id = a.uid
  ORDER BY a.wins DESC, a.name ASC
  LIMIT _limit;
$$;
GRANT EXECUTE ON FUNCTION public.weekly_top_winners(int) TO authenticated, anon;
