DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT g.stake, p.user_id FROM ludo_games g
    JOIN ludo_participants p ON p.game_id=g.id
    WHERE g.status IN ('open','playing','drawing') AND COALESCE(g.stake,0)>0
  LOOP UPDATE profiles SET balance=COALESCE(balance,0)+r.stake WHERE id=r.user_id; END LOOP;
  DELETE FROM ludo_games WHERE status IN ('open','playing','drawing');

  FOR r IN
    SELECT g.stake, p.user_id FROM domino_games g
    JOIN domino_participants p ON p.game_id=g.id
    WHERE g.status IN ('open','playing','drawing') AND COALESCE(g.stake,0)>0
  LOOP UPDATE profiles SET balance=COALESCE(balance,0)+r.stake WHERE id=r.user_id; END LOOP;
  DELETE FROM domino_games WHERE status IN ('open','playing','drawing');

  FOR r IN
    SELECT g.stake, p.user_id FROM fanorona_games g
    JOIN fanorona_participants p ON p.game_id=g.id
    WHERE g.status IN ('open','playing','drawing') AND COALESCE(g.stake,0)>0
  LOOP UPDATE profiles SET balance=COALESCE(balance,0)+r.stake WHERE id=r.user_id; END LOOP;
  DELETE FROM fanorona_games WHERE status IN ('open','playing','drawing');

  FOR r IN
    SELECT g.stake, p.user_id FROM rami_games g
    JOIN rami_participants p ON p.game_id=g.id
    WHERE g.status IN ('open','playing','drawing') AND COALESCE(g.stake,0)>0
  LOOP UPDATE profiles SET balance=COALESCE(balance,0)+r.stake WHERE id=r.user_id; END LOOP;
  DELETE FROM rami_games WHERE status IN ('open','playing','drawing');

  FOR r IN
    SELECT COALESCE(g.stake,0) AS stake, uid
    FROM chess_games g,
    LATERAL (VALUES (g.white_id),(g.black_id)) AS v(uid)
    WHERE g.status IN ('open','playing','drawing') AND uid IS NOT NULL AND COALESCE(g.stake,0)>0
  LOOP UPDATE profiles SET balance=COALESCE(balance,0)+r.stake WHERE id=r.uid; END LOOP;
  DELETE FROM chess_games WHERE status IN ('open','playing','drawing');
END $$;