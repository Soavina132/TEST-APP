
-- ============ CHESS TABLES ============
CREATE TABLE public.chess_games (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id uuid NOT NULL REFERENCES auth.users(id),
  white_id uuid REFERENCES auth.users(id),
  black_id uuid REFERENCES auth.users(id),
  status game_status NOT NULL DEFAULT 'open',
  stake numeric NOT NULL CHECK (stake >= 0),
  pot numeric NOT NULL DEFAULT 0,
  commission_pct numeric NOT NULL DEFAULT 10,
  turn text NOT NULL DEFAULT 'w' CHECK (turn IN ('w','b')),
  fen text NOT NULL DEFAULT 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
  ply integer NOT NULL DEFAULT 0,
  winner_id uuid REFERENCES auth.users(id),
  draw boolean NOT NULL DEFAULT false,
  is_private boolean NOT NULL DEFAULT false,
  room_code text UNIQUE,
  last_move_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  finished_at timestamptz
);

GRANT SELECT, INSERT, UPDATE ON public.chess_games TO authenticated;
GRANT ALL ON public.chess_games TO service_role;
ALTER TABLE public.chess_games ENABLE ROW LEVEL SECURITY;

CREATE POLICY "chess_games_select" ON public.chess_games FOR SELECT
USING (
  (status IN ('open','playing') AND is_private = false)
  OR host_id = auth.uid()
  OR white_id = auth.uid()
  OR black_id = auth.uid()
  OR is_admin()
);

CREATE TABLE public.chess_moves (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id uuid NOT NULL REFERENCES public.chess_games(id) ON DELETE CASCADE,
  ply integer NOT NULL,
  san text NOT NULL,
  uci text NOT NULL,
  fen_after text NOT NULL,
  by_user uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(game_id, ply)
);

GRANT SELECT, INSERT ON public.chess_moves TO authenticated;
GRANT ALL ON public.chess_moves TO service_role;
ALTER TABLE public.chess_moves ENABLE ROW LEVEL SECURITY;

CREATE POLICY "chess_moves_select" ON public.chess_moves FOR SELECT
USING (
  EXISTS (SELECT 1 FROM public.chess_games g WHERE g.id = chess_moves.game_id
    AND (g.is_private = false OR g.white_id = auth.uid() OR g.black_id = auth.uid() OR g.host_id = auth.uid() OR is_admin()))
);

-- Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.chess_games;
ALTER PUBLICATION supabase_realtime ADD TABLE public.chess_moves;

-- ============ CHESS RPCs ============
CREATE OR REPLACE FUNCTION public.chess_create(_stake numeric, _private boolean DEFAULT true, _commission numeric DEFAULT 10)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_bal numeric; v_code text; v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'invalid stake'; END IF;
  SELECT balance_ar INTO v_bal FROM profiles WHERE id = v_uid;
  IF v_bal < _stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;
  IF _private THEN v_code := upper(substring(md5(random()::text||clock_timestamp()::text) from 1 for 6)); END IF;
  INSERT INTO chess_games(host_id, white_id, stake, pot, commission_pct, is_private, room_code)
  VALUES (v_uid, v_uid, _stake, _stake, _commission, _private, v_code)
  RETURNING id INTO v_id;
  UPDATE profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO transactions(user_id, type, amount, ref_id, note) VALUES (v_uid, 'chess_stake', -_stake, v_id, 'Create chess');
  RETURN v_id;
END $$;
GRANT EXECUTE ON FUNCTION public.chess_create(numeric, boolean, numeric) TO authenticated;

CREATE OR REPLACE FUNCTION public.chess_join_code(_code text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_g chess_games%ROWTYPE; v_bal numeric; v_flip boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE room_code = upper(_code) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status <> 'open' THEN RAISE EXCEPTION 'game not open'; END IF;
  IF v_g.host_id = v_uid THEN RAISE EXCEPTION 'cannot join own game'; END IF;
  SELECT balance_ar INTO v_bal FROM profiles WHERE id = v_uid;
  IF v_bal < v_g.stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;
  -- random colour assignment
  v_flip := (random() < 0.5);
  IF v_flip THEN
    UPDATE chess_games SET black_id = v_uid, status='playing', started_at=now(), pot = pot + v_g.stake
      WHERE id = v_g.id;
  ELSE
    UPDATE chess_games SET white_id = v_uid, black_id = v_g.host_id, status='playing', started_at=now(), pot = pot + v_g.stake
      WHERE id = v_g.id;
  END IF;
  UPDATE profiles SET balance_ar = balance_ar - v_g.stake WHERE id = v_uid;
  INSERT INTO transactions(user_id, type, amount, ref_id, note) VALUES (v_uid, 'chess_stake', -v_g.stake, v_g.id, 'Join chess');
  RETURN v_g.id;
END $$;
GRANT EXECUTE ON FUNCTION public.chess_join_code(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.chess_move(_game_id uuid, _san text, _uci text, _fen_after text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_g chess_games%ROWTYPE; v_my text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  v_my := CASE WHEN v_g.white_id = v_uid THEN 'w' WHEN v_g.black_id = v_uid THEN 'b' ELSE NULL END;
  IF v_my IS NULL THEN RAISE EXCEPTION 'not a player'; END IF;
  IF v_my <> v_g.turn THEN RAISE EXCEPTION 'not your turn'; END IF;
  INSERT INTO chess_moves(game_id, ply, san, uci, fen_after, by_user)
    VALUES (_game_id, v_g.ply + 1, _san, _uci, _fen_after, v_uid);
  UPDATE chess_games SET fen = _fen_after, turn = CASE WHEN v_g.turn='w' THEN 'b' ELSE 'w' END,
    ply = v_g.ply + 1, last_move_at = now() WHERE id = _game_id;
END $$;
GRANT EXECUTE ON FUNCTION public.chess_move(uuid, text, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public._chess_payout(_game_id uuid, _winner uuid, _draw boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_g chess_games%ROWTYPE; v_net numeric; v_each numeric;
BEGIN
  SELECT * INTO v_g FROM chess_games WHERE id = _game_id;
  IF v_g.status = 'finished' THEN RETURN; END IF;
  v_net := v_g.pot - (v_g.pot * v_g.commission_pct / 100.0);
  IF _draw THEN
    v_each := v_net / 2;
    IF v_g.white_id IS NOT NULL THEN
      UPDATE profiles SET balance_ar = balance_ar + v_each WHERE id = v_g.white_id;
      INSERT INTO transactions(user_id,type,amount,ref_id,note) VALUES (v_g.white_id,'chess_payout',v_each,_game_id,'Chess draw');
    END IF;
    IF v_g.black_id IS NOT NULL THEN
      UPDATE profiles SET balance_ar = balance_ar + v_each WHERE id = v_g.black_id;
      INSERT INTO transactions(user_id,type,amount,ref_id,note) VALUES (v_g.black_id,'chess_payout',v_each,_game_id,'Chess draw');
    END IF;
    UPDATE chess_games SET status='finished', draw=true, finished_at=now() WHERE id=_game_id;
  ELSE
    UPDATE profiles SET balance_ar = balance_ar + v_net WHERE id = _winner;
    INSERT INTO transactions(user_id,type,amount,ref_id,note) VALUES (_winner,'chess_payout',v_net,_game_id,'Chess win');
    UPDATE chess_games SET status='finished', winner_id=_winner, finished_at=now() WHERE id=_game_id;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.chess_resign(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_g chess_games%ROWTYPE; v_winner uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id = _game_id FOR UPDATE;
  IF v_g.status <> 'playing' THEN RAISE EXCEPTION 'not active'; END IF;
  IF v_uid = v_g.white_id THEN v_winner := v_g.black_id;
  ELSIF v_uid = v_g.black_id THEN v_winner := v_g.white_id;
  ELSE RAISE EXCEPTION 'not a player'; END IF;
  PERFORM public._chess_payout(_game_id, v_winner, false);
END $$;
GRANT EXECUTE ON FUNCTION public.chess_resign(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.chess_claim_win(_game_id uuid, _winner uuid, _draw boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_g chess_games%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id = _game_id FOR UPDATE;
  IF v_g.status <> 'playing' THEN RAISE EXCEPTION 'not active'; END IF;
  IF v_uid <> v_g.white_id AND v_uid <> v_g.black_id THEN RAISE EXCEPTION 'not a player'; END IF;
  IF NOT _draw AND _winner <> v_g.white_id AND _winner <> v_g.black_id THEN RAISE EXCEPTION 'invalid winner'; END IF;
  PERFORM public._chess_payout(_game_id, _winner, _draw);
END $$;
GRANT EXECUTE ON FUNCTION public.chess_claim_win(uuid, uuid, boolean) TO authenticated;

-- ============ ONLINE COUNT + PLAYER STATUS RPCs ============
CREATE OR REPLACE FUNCTION public.game_online_count(_slug text)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COUNT(DISTINCT user_id)::int FROM (
    SELECT lp.user_id FROM ludo_participants lp
      JOIN ludo_games g ON g.id = lp.game_id
      WHERE _slug='ludo' AND g.status IN ('open','playing') AND lp.user_id IS NOT NULL
    UNION ALL
    SELECT dp.user_id FROM domino_participants dp
      JOIN domino_games g ON g.id = dp.game_id
      WHERE _slug='domino' AND g.status IN ('open','playing') AND dp.user_id IS NOT NULL
    UNION ALL
    SELECT fp.user_id FROM fanorona_participants fp
      JOIN fanorona_games g ON g.id = fp.game_id
      WHERE _slug='fanorona' AND g.status IN ('open','playing') AND fp.user_id IS NOT NULL
    UNION ALL
    SELECT g.white_id AS user_id FROM chess_games g WHERE _slug='chess' AND g.status IN ('open','playing') AND g.white_id IS NOT NULL
    UNION ALL
    SELECT g.black_id FROM chess_games g WHERE _slug='chess' AND g.status IN ('open','playing') AND g.black_id IS NOT NULL
  ) u;
$$;
GRANT EXECUTE ON FUNCTION public.game_online_count(text) TO authenticated, anon;

CREATE OR REPLACE FUNCTION public.game_player_status(_user_id uuid, _slug text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_playing boolean := false; v_pct int := 0; v_state jsonb; v_ply int; v_home int := 0; v_tiles int; v_pieces int;
BEGIN
  IF _slug = 'ludo' THEN
    SELECT lp.id IS NOT NULL FROM ludo_participants lp
      JOIN ludo_games g ON g.id = lp.game_id
      WHERE lp.user_id = _user_id AND g.status='playing' LIMIT 1 INTO v_playing;
    v_playing := COALESCE(v_playing, false);
    IF v_playing THEN v_pct := 25; END IF; -- coarse, refine later
  ELSIF _slug = 'domino' THEN
    SELECT true FROM domino_participants dp JOIN domino_games g ON g.id=dp.game_id
      WHERE dp.user_id=_user_id AND g.status='playing' LIMIT 1 INTO v_playing;
    v_playing := COALESCE(v_playing,false);
    IF v_playing THEN v_pct := 30; END IF;
  ELSIF _slug = 'fanorona' THEN
    SELECT true FROM fanorona_participants fp JOIN fanorona_games g ON g.id=fp.game_id
      WHERE fp.user_id=_user_id AND g.status='playing' LIMIT 1 INTO v_playing;
    v_playing := COALESCE(v_playing,false);
    IF v_playing THEN v_pct := 30; END IF;
  ELSIF _slug = 'chess' THEN
    SELECT ply FROM chess_games WHERE status='playing' AND (white_id=_user_id OR black_id=_user_id) LIMIT 1 INTO v_ply;
    IF v_ply IS NOT NULL THEN v_playing := true; v_pct := LEAST(99, (v_ply * 100) / 80); END IF;
  END IF;
  RETURN jsonb_build_object('playing', v_playing, 'percent', v_pct);
END $$;
GRANT EXECUTE ON FUNCTION public.game_player_status(uuid, text) TO authenticated, anon;
