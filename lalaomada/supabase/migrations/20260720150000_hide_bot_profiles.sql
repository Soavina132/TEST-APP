-- ============================================================
-- Hide bot profiles from every user-facing list
-- Bots (chess solo bot) create a real auth.users row via
-- chess_start_solo_bot, which triggers handle_new_user and adds
-- a profile — causing "Bot" to appear in DM picker, rankings,
-- etc. Flag those profiles with is_bot=true and filter them out
-- of every public listing RPC.
-- ============================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_bot boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_profiles_is_bot ON public.profiles(is_bot);

-- Backfill existing bot profiles (chess solo bot uses this email domain)
UPDATE public.profiles p
   SET is_bot = true
  FROM auth.users u
 WHERE u.id = p.id
   AND (u.email LIKE '%@bot.lalaomada.internal'
        OR (u.raw_user_meta_data ->> 'is_bot')::boolean = true);

-- Update chess bot creator to also mark the profile is_bot=true
CREATE OR REPLACE FUNCTION public.chess_start_solo_bot(
  _difficulty text DEFAULT 'medium',
  _color      text DEFAULT 'white'
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_bot_id   uuid := gen_random_uuid();
  v_bot_mail text;
  v_id       uuid;
  v_code     text;
  v_human_w  boolean := (_color IS NULL OR lower(_color) <> 'black');
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;

  v_bot_mail := 'chessbot_' || v_bot_id::text || '@bot.lalaomada.internal';

  INSERT INTO auth.users (
    id, instance_id, aud, role,
    email, encrypted_password, email_confirmed_at,
    raw_user_meta_data,
    created_at, updated_at,
    confirmation_token, recovery_token, email_change, email_change_token_new
  ) VALUES (
    v_bot_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated',
    v_bot_mail,
    crypt(gen_random_uuid()::text, gen_salt('bf')),
    now(),
    jsonb_build_object('pseudo', 'Bot', 'is_bot', true),
    now(), now(),
    '', '', '', ''
  );

  UPDATE public.profiles
    SET balance_ar = 0, pseudo = 'Bot', avatar_url = NULL, is_bot = true
    WHERE id = v_bot_id;

  DELETE FROM public.transactions WHERE user_id = v_bot_id;

  v_code := upper(substring(md5(random()::text||clock_timestamp()::text) from 1 for 6));

  INSERT INTO public.chess_games(
    host_id, white_id, black_id, status,
    stake, pot, commission_pct, is_private, room_code,
    white_is_bot, black_is_bot, started_at, last_move_at
  ) VALUES (
    v_uid,
    CASE WHEN v_human_w THEN v_uid    ELSE v_bot_id END,
    CASE WHEN v_human_w THEN v_bot_id ELSE v_uid    END,
    'playing',
    0, 0, 0, true, v_code,
    NOT v_human_w, v_human_w,
    now(), now()
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END $$;
GRANT EXECUTE ON FUNCTION public.chess_start_solo_bot(text, text) TO authenticated;

-- Exclude bots from DM picker
CREATE OR REPLACE FUNCTION public.list_players_for_dm(_search text DEFAULT NULL, _limit int DEFAULT 50)
RETURNS TABLE (id uuid, pseudo text, avatar_url text, unique_code text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'auth'; END IF;
  RETURN QUERY
    SELECT p.id, p.pseudo, p.avatar_url, p.unique_code
    FROM public.profiles p
    WHERE p.id <> auth.uid()
      AND COALESCE(p.banned, FALSE) = FALSE
      AND COALESCE(p.is_bot, FALSE) = FALSE
      AND (_search IS NULL OR _search = '' OR p.pseudo ILIKE '%' || _search || '%')
    ORDER BY p.pseudo ASC
    LIMIT LEAST(COALESCE(_limit, 50), 100);
END $$;
GRANT EXECUTE ON FUNCTION public.list_players_for_dm(text, int) TO authenticated;

-- Exclude bots from leaderboard
DROP FUNCTION IF EXISTS public.leaderboard_winners(text, int, text);
CREATE OR REPLACE FUNCTION public.leaderboard_winners(
  _period text DEFAULT 'all',
  _limit  int  DEFAULT 20,
  _slug   text DEFAULT NULL
)
RETURNS TABLE(rank int, user_id uuid, name text, avatar_url text, wins bigint, total_won numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  WITH bound AS (
    SELECT CASE _period
      WHEN 'week'  THEN now() - interval '7 days'
      WHEN 'month' THEN now() - interval '30 days'
      ELSE 'epoch'::timestamptz
    END AS since
  ),
  raw AS (
    SELECT g.winner_id AS uid, NULLIF(trim(pp.display_name),'') AS dn,
           g.pot * (1 - g.commission_pct/100.0) AS won,
           COALESCE(g.finished_at, g.created_at) AS at
      FROM ludo_games g JOIN ludo_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'ludo')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0),
           COALESCE(g.finished_at, g.created_at)
      FROM domino_games g JOIN domino_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'domino')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0),
           COALESCE(g.finished_at, g.created_at)
      FROM fanorona_games g JOIN fanorona_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'fanorona')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0),
           COALESCE(g.finished_at, g.created_at)
      FROM rami_games g JOIN rami_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'rami')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULL::text,
           g.stake * 2 * (1 - COALESCE((SELECT commission_pct FROM app_settings WHERE id=1),0)/100.0),
           COALESCE(g.finished_at, g.created_at)
      FROM chess_games g, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'chess')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0),
           COALESCE(g.finished_at, g.created_at)
      FROM poker_games g JOIN poker_players pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'poker')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
  ),
  filtered AS (
    SELECT r.uid, r.dn, r.won, r.at FROM raw r
    WHERE NOT EXISTS (SELECT 1 FROM public.profiles pb WHERE pb.id = r.uid AND pb.is_bot = true)
      AND (
        NOT public.has_role(r.uid, 'admin'::public.app_role)
        OR EXISTS (
             SELECT 1 FROM public.admin_persona ap
             WHERE ap.admin_id = r.uid AND ap.is_active
           )
      )
  ),
  named AS (
    SELECT f.uid, f.won, f.at,
           COALESCE(p.pseudo, f.dn, 'Joueur') AS name,
           p.avatar_url
    FROM filtered f LEFT JOIN public.profiles p ON p.id=f.uid
  ),
  agg AS (
    SELECT uid,
           count(*)::bigint AS wins,
           COALESCE(sum(won), 0)::numeric AS total_won
    FROM named
    GROUP BY uid
  ),
  latest_name AS (
    SELECT DISTINCT ON (uid) uid, name, avatar_url
    FROM named
    ORDER BY uid, at DESC
  )
  SELECT (row_number() OVER (ORDER BY a.wins DESC, ln.name ASC))::int AS rank,
         a.uid AS user_id, ln.name, ln.avatar_url, a.wins, a.total_won
  FROM agg a
  JOIN latest_name ln ON ln.uid = a.uid
  ORDER BY a.wins DESC, ln.name ASC
  LIMIT _limit;
$$;

REVOKE ALL ON FUNCTION public.leaderboard_winners(text, int, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.leaderboard_winners(text, int, text) TO authenticated, anon;
