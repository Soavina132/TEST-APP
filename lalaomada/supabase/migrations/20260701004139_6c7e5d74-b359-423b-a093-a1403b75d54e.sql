DO $$
DECLARE r record;
BEGIN
  -- LUDO
  FOR r IN
    SELECT g.stake, p.user_id
    FROM public.ludo_games g
    JOIN public.ludo_participants p ON p.game_id = g.id
    WHERE g.status::text IN ('open','playing','drawing') AND COALESCE(g.stake,0) > 0
  LOOP
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar,0) + r.stake WHERE id = r.user_id;
  END LOOP;
  DELETE FROM public.ludo_games WHERE status::text IN ('open','playing','drawing');

  -- DOMINO
  FOR r IN
    SELECT g.stake, p.user_id
    FROM public.domino_games g
    JOIN public.domino_participants p ON p.game_id = g.id
    WHERE g.status::text IN ('open','playing','drawing') AND COALESCE(g.stake,0) > 0
  LOOP
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar,0) + r.stake WHERE id = r.user_id;
  END LOOP;
  DELETE FROM public.domino_games WHERE status::text IN ('open','playing','drawing');

  -- FANORONA
  FOR r IN
    SELECT g.stake, p.user_id
    FROM public.fanorona_games g
    JOIN public.fanorona_participants p ON p.game_id = g.id
    WHERE g.status::text IN ('open','playing','drawing') AND COALESCE(g.stake,0) > 0
  LOOP
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar,0) + r.stake WHERE id = r.user_id;
  END LOOP;
  DELETE FROM public.fanorona_games WHERE status::text IN ('open','playing','drawing');

  -- RAMI
  FOR r IN
    SELECT g.stake, p.user_id
    FROM public.rami_games g
    JOIN public.rami_participants p ON p.game_id = g.id
    WHERE g.status::text IN ('open','playing','drawing') AND COALESCE(g.stake,0) > 0
  LOOP
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar,0) + r.stake WHERE id = r.user_id;
  END LOOP;
  DELETE FROM public.rami_games WHERE status::text IN ('open','playing','drawing');

  -- CHESS
  FOR r IN
    SELECT COALESCE(g.stake,0) AS stake, uid
    FROM public.chess_games g,
    LATERAL (VALUES (g.white_id),(g.black_id)) AS v(uid)
    WHERE g.status::text IN ('open','playing','drawing')
      AND uid IS NOT NULL AND COALESCE(g.stake,0) > 0
  LOOP
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar,0) + r.stake WHERE id = r.uid;
  END LOOP;
  DELETE FROM public.chess_games WHERE status::text IN ('open','playing','drawing');
END $$;