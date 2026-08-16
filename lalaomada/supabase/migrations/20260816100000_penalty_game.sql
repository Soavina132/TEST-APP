-- ════════════════════════════════════════════════════════════════════════
-- PENALTY — jeu de tirs au but 1v1
-- ════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.penalty_games (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id uuid NOT NULL REFERENCES auth.users(id),
  player1_id uuid REFERENCES auth.users(id),
  player2_id uuid REFERENCES auth.users(id),
  status game_status NOT NULL DEFAULT 'open',
  stake numeric NOT NULL CHECK (stake >= 0),
  pot numeric NOT NULL DEFAULT 0,
  commission_pct numeric NOT NULL DEFAULT 10,
  is_private boolean NOT NULL DEFAULT false,
  room_code text UNIQUE,
  num_balls int NOT NULL DEFAULT 5 CHECK (num_balls >= 1 AND num_balls <= 20),
  num_keeper_choices int NOT NULL DEFAULT 2 CHECK (num_keeper_choices >= 1 AND num_keeper_choices <= 3),
  player1_ready boolean NOT NULL DEFAULT false,
  player2_ready boolean NOT NULL DEFAULT false,
  first_shooter_id uuid REFERENCES auth.users(id),
  current_round int NOT NULL DEFAULT 0,
  current_shooter uuid REFERENCES auth.users(id),
  p1_score int NOT NULL DEFAULT 0,
  p2_score int NOT NULL DEFAULT 0,
  is_overtime boolean NOT NULL DEFAULT false,
  overtime_round int NOT NULL DEFAULT 0,
  winner_id uuid REFERENCES auth.users(id),
  finished_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz
);

GRANT SELECT, INSERT, UPDATE ON public.penalty_games TO authenticated;
GRANT ALL ON public.penalty_games TO service_role;
ALTER TABLE public.penalty_games ENABLE ROW LEVEL SECURITY;

CREATE POLICY "penalty_games_select" ON public.penalty_games FOR SELECT
USING (
  (status IN ('open','playing') AND is_private = false)
  OR host_id = auth.uid()
  OR player1_id = auth.uid()
  OR player2_id = auth.uid()
  OR public.is_admin()
);

CREATE POLICY "penalty_games_update" ON public.penalty_games FOR UPDATE
USING (
  host_id = auth.uid()
  OR player1_id = auth.uid()
  OR player2_id = auth.uid()
  OR public.is_admin()
);

CREATE TABLE IF NOT EXISTS public.penalty_rounds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id uuid NOT NULL REFERENCES public.penalty_games(id) ON DELETE CASCADE,
  round_num int NOT NULL,
  shooter_id uuid NOT NULL REFERENCES auth.users(id),
  keeper_id uuid NOT NULL REFERENCES auth.users(id),
  shooter_choice int,
  keeper_choices int[],
  result text,
  is_overtime boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  UNIQUE(game_id, round_num)
);

GRANT SELECT, INSERT, UPDATE ON public.penalty_rounds TO authenticated;
GRANT ALL ON public.penalty_rounds TO service_role;
ALTER TABLE public.penalty_rounds ENABLE ROW LEVEL SECURITY;

CREATE POLICY "penalty_rounds_select" ON public.penalty_rounds FOR SELECT
USING (
  EXISTS (SELECT 1 FROM public.penalty_games g WHERE g.id = penalty_rounds.game_id
    AND (g.is_private = false OR g.player1_id = auth.uid() OR g.player2_id = auth.uid() OR g.host_id = auth.uid() OR public.is_admin()))
);

ALTER PUBLICATION supabase_realtime ADD TABLE public.penalty_games;
ALTER PUBLICATION supabase_realtime ADD TABLE public.penalty_rounds;

-- ============ RPC: penalty_create ============
CREATE OR REPLACE FUNCTION public.penalty_create(
  _stake numeric, _private boolean DEFAULT true, _commission numeric DEFAULT 10,
  _num_balls int DEFAULT 5, _num_keeper_choices int DEFAULT 2
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_bal numeric; v_code text; v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'invalid stake'; END IF;
  IF _num_balls < 1 OR _num_balls > 20 THEN RAISE EXCEPTION 'balls must be 1-20'; END IF;
  IF _num_keeper_choices < 1 OR _num_keeper_choices > 3 THEN RAISE EXCEPTION 'keeper choices must be 1-3'; END IF;
  SELECT balance_ar INTO v_bal FROM profiles WHERE id = v_uid;
  IF v_bal < _stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;
  IF _private THEN v_code := upper(substring(md5(random()::text || clock_timestamp()::text) from 1 for 6)); END IF;
  INSERT INTO penalty_games(host_id, player1_id, stake, pot, commission_pct, is_private, room_code, num_balls, num_keeper_choices)
  VALUES (v_uid, v_uid, _stake, _stake, _commission, _private, v_code, _num_balls, _num_keeper_choices)
  RETURNING id INTO v_id;
  UPDATE profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO transactions(user_id, type, amount, ref_id, note) VALUES (v_uid, 'penalty_stake', -_stake, v_id, 'Create penalty');
  RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public.penalty_create(numeric, boolean, numeric, int, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.penalty_create(numeric, boolean, numeric, int, int) TO authenticated;

-- ============ RPC: penalty_join ============
CREATE OR REPLACE FUNCTION public.penalty_join(_game_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_g penalty_games%ROWTYPE; v_bal numeric;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM penalty_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status <> 'open' THEN RAISE EXCEPTION 'game not open'; END IF;
  IF v_g.host_id = v_uid THEN RAISE EXCEPTION 'cannot join own game'; END IF;
  SELECT balance_ar INTO v_bal FROM profiles WHERE id = v_uid;
  IF v_bal < v_g.stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;
  UPDATE penalty_games SET player2_id = v_uid, pot = pot + v_g.stake WHERE id = _game_id;
  UPDATE profiles SET balance_ar = balance_ar - v_g.stake WHERE id = v_uid;
  INSERT INTO transactions(user_id, type, amount, ref_id, note) VALUES (v_uid, 'penalty_stake', -v_g.stake, _game_id, 'Join penalty');
END $$;
REVOKE ALL ON FUNCTION public.penalty_join(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.penalty_join(uuid) TO authenticated;

-- ============ RPC: penalty_join_code ============
CREATE OR REPLACE FUNCTION public.penalty_join_code(_code text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_g penalty_games%ROWTYPE; v_bal numeric;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM penalty_games WHERE room_code = upper(_code) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status <> 'open' THEN RAISE EXCEPTION 'game not open'; END IF;
  IF v_g.host_id = v_uid THEN RAISE EXCEPTION 'cannot join own game'; END IF;
  SELECT balance_ar INTO v_bal FROM profiles WHERE id = v_uid;
  IF v_bal < v_g.stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;
  UPDATE penalty_games SET player2_id = v_uid, pot = pot + v_g.stake WHERE id = v_g.id;
  UPDATE profiles SET balance_ar = balance_ar - v_g.stake WHERE id = v_uid;
  INSERT INTO transactions(user_id, type, amount, ref_id, note) VALUES (v_uid, 'penalty_stake', -v_g.stake, v_g.id, 'Join penalty by code');
  RETURN v_g.id;
END $$;
REVOKE ALL ON FUNCTION public.penalty_join_code(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.penalty_join_code(text) TO authenticated;

-- ============ RPC: penalty_set_ready ============
CREATE OR REPLACE FUNCTION public.penalty_set_ready(_game_id uuid, _ready boolean DEFAULT true) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_g penalty_games%ROWTYPE; v_first uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM penalty_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status <> 'open' THEN RAISE EXCEPTION 'game already started'; END IF;
  IF v_uid = v_g.player1_id THEN UPDATE penalty_games SET player1_ready = _ready WHERE id = _game_id;
  ELSIF v_uid = v_g.player2_id THEN UPDATE penalty_games SET player2_ready = _ready WHERE id = _game_id;
  ELSE RAISE EXCEPTION 'not a participant'; END IF;
  SELECT * INTO v_g FROM penalty_games WHERE id = _game_id;
  IF v_g.player1_ready AND v_g.player2_ready AND v_g.player2_id IS NOT NULL THEN
    IF random() < 0.5 THEN v_first := v_g.player1_id; ELSE v_first := v_g.player2_id; END IF;
    UPDATE penalty_games SET status = 'playing', started_at = now(), first_shooter_id = v_first, current_shooter = v_first, current_round = 1 WHERE id = _game_id;
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.penalty_set_ready(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.penalty_set_ready(uuid, boolean) TO authenticated;

-- ============ RPC: penalty_submit_choice ============
CREATE OR REPLACE FUNCTION public.penalty_submit_choice(_game_id uuid, _choice int[]) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid(); v_g penalty_games%ROWTYPE; v_round penalty_rounds%ROWTYPE;
  v_shooter_choice int; v_keeper_choices int[]; v_is_shooter boolean; v_is_keeper boolean;
  v_all_submitted boolean; v_result text; v_opponent uuid; v_total_rounds int;
  v_p1_score int; v_p2_score int; v_new_shooter uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM penalty_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status <> 'playing' THEN RAISE EXCEPTION 'game not playing'; END IF;
  IF array_length(_choice, 1) IS NULL THEN RAISE EXCEPTION 'no choices'; END IF;
  v_is_shooter := (v_uid = v_g.current_shooter);
  v_opponent := CASE WHEN v_uid = v_g.player1_id THEN v_g.player2_id ELSE v_g.player1_id END;
  v_is_keeper := (v_uid = v_opponent);
  IF NOT v_is_shooter AND NOT v_is_keeper THEN RAISE EXCEPTION 'not your turn'; END IF;
  SELECT * INTO v_round FROM penalty_rounds WHERE game_id = _game_id AND round_num = v_g.current_round;
  IF NOT FOUND THEN
    INSERT INTO penalty_rounds(game_id, round_num, shooter_id, keeper_id, is_overtime)
    VALUES (_game_id, v_g.current_round, v_g.current_shooter,
      CASE WHEN v_g.current_shooter = v_g.player1_id THEN v_g.player2_id ELSE v_g.player1_id END, v_g.is_overtime)
    RETURNING * INTO v_round;
  END IF;
  IF v_is_shooter THEN
    IF array_length(_choice, 1) <> 1 THEN RAISE EXCEPTION 'shooter must pick exactly 1 zone'; END IF;
    IF _choice[1] < 1 OR _choice[1] > 6 THEN RAISE EXCEPTION 'invalid zone'; END IF;
    IF v_round.shooter_choice IS NOT NULL THEN RAISE EXCEPTION 'already submitted'; END IF;
    UPDATE penalty_rounds SET shooter_choice = _choice[1] WHERE id = v_round.id;
  ELSE
    IF array_length(_choice, 1) <> v_g.num_keeper_choices THEN RAISE EXCEPTION 'keeper must pick % zones', v_g.num_keeper_choices; END IF;
    IF EXISTS (SELECT 1 FROM unnest(_choice) z WHERE z < 1 OR z > 6) THEN RAISE EXCEPTION 'invalid zone'; END IF;
    IF array_length(_choice, 1) > (SELECT count(DISTINCT z) FROM unnest(_choice) z) THEN RAISE EXCEPTION 'duplicate zones'; END IF;
    IF v_round.keeper_choices IS NOT NULL THEN RAISE EXCEPTION 'already submitted'; END IF;
    UPDATE penalty_rounds SET keeper_choices = _choice WHERE id = v_round.id;
  END IF;
  SELECT * INTO v_round FROM penalty_rounds WHERE id = v_round.id;
  v_all_submitted := (v_round.shooter_choice IS NOT NULL AND v_round.keeper_choices IS NOT NULL);
  IF NOT v_all_submitted THEN
    RETURN jsonb_build_object('resolved', false, 'waiting_for', CASE WHEN v_round.shooter_choice IS NULL THEN 'shooter' ELSE 'keeper' END);
  END IF;
  v_shooter_choice := v_round.shooter_choice;
  v_keeper_choices := v_round.keeper_choices;
  IF v_shooter_choice = ANY(v_keeper_choices) THEN v_result := 'save'; ELSE v_result := 'goal'; END IF;
  UPDATE penalty_rounds SET result = v_result, resolved_at = now() WHERE id = v_round.id;
  v_p1_score := v_g.p1_score; v_p2_score := v_g.p2_score;
  IF v_result = 'goal' THEN
    IF v_round.shooter_id = v_g.player1_id THEN v_p1_score := v_p1_score + 1; ELSE v_p2_score := v_p2_score + 1; END IF;
  END IF;
  v_total_rounds := v_g.num_balls * 2;
  IF v_g.is_overtime THEN v_total_rounds := v_g.num_balls * 2 + v_g.overtime_round * 2; END IF;
  IF v_g.current_round < v_total_rounds THEN
    v_new_shooter := CASE WHEN v_g.current_shooter = v_g.player1_id THEN v_g.player2_id ELSE v_g.player1_id END;
    UPDATE penalty_games SET p1_score = v_p1_score, p2_score = v_p2_score, current_round = v_g.current_round + 1, current_shooter = v_new_shooter WHERE id = _game_id;
    RETURN jsonb_build_object('resolved', true, 'result', v_result, 'shooter_choice', v_shooter_choice, 'keeper_choices', v_keeper_choices, 'p1_score', v_p1_score, 'p2_score', v_p2_score, 'round', v_g.current_round, 'game_over', false);
  ELSE
    IF NOT v_g.is_overtime THEN
      IF v_p1_score > v_p2_score THEN PERFORM public._penalty_settle(_game_id, v_g.player1_id);
        RETURN jsonb_build_object('resolved', true, 'result', v_result, 'shooter_choice', v_shooter_choice, 'keeper_choices', v_keeper_choices, 'p1_score', v_p1_score, 'p2_score', v_p2_score, 'round', v_g.current_round, 'game_over', true, 'winner', 'p1');
      ELSIF v_p2_score > v_p1_score THEN PERFORM public._penalty_settle(_game_id, v_g.player2_id);
        RETURN jsonb_build_object('resolved', true, 'result', v_result, 'shooter_choice', v_shooter_choice, 'keeper_choices', v_keeper_choices, 'p1_score', v_p1_score, 'p2_score', v_p2_score, 'round', v_g.current_round, 'game_over', true, 'winner', 'p2');
      ELSE
        UPDATE penalty_games SET p1_score = v_p1_score, p2_score = v_p2_score, is_overtime = true, overtime_round = 1, current_round = v_g.current_round + 1, current_shooter = CASE WHEN v_g.first_shooter_id = v_g.player1_id THEN v_g.player2_id ELSE v_g.player1_id END WHERE id = _game_id;
        RETURN jsonb_build_object('resolved', true, 'result', v_result, 'shooter_choice', v_shooter_choice, 'keeper_choices', v_keeper_choices, 'p1_score', v_p1_score, 'p2_score', v_p2_score, 'round', v_g.current_round, 'game_over', false, 'overtime', true);
      END IF;
    ELSE
      IF v_g.current_round % 2 = 0 THEN
        IF v_p1_score > v_p2_score THEN PERFORM public._penalty_settle(_game_id, v_g.player1_id);
          RETURN jsonb_build_object('resolved', true, 'result', v_result, 'shooter_choice', v_shooter_choice, 'keeper_choices', v_keeper_choices, 'p1_score', v_p1_score, 'p2_score', v_p2_score, 'round', v_g.current_round, 'game_over', true, 'winner', 'p1');
        ELSIF v_p2_score > v_p1_score THEN PERFORM public._penalty_settle(_game_id, v_g.player2_id);
          RETURN jsonb_build_object('resolved', true, 'result', v_result, 'shooter_choice', v_shooter_choice, 'keeper_choices', v_keeper_choices, 'p1_score', v_p1_score, 'p2_score', v_p2_score, 'round', v_g.current_round, 'game_over', true, 'winner', 'p2');
        ELSE
          UPDATE penalty_games SET p1_score = v_p1_score, p2_score = v_p2_score, overtime_round = v_g.overtime_round + 1, current_round = v_g.current_round + 1, current_shooter = CASE WHEN v_g.current_shooter = v_g.player1_id THEN v_g.player2_id ELSE v_g.player1_id END WHERE id = _game_id;
          RETURN jsonb_build_object('resolved', true, 'result', v_result, 'shooter_choice', v_shooter_choice, 'keeper_choices', v_keeper_choices, 'p1_score', v_p1_score, 'p2_score', v_p2_score, 'round', v_g.current_round, 'game_over', false, 'overtime', true);
        END IF;
      ELSE
        v_new_shooter := CASE WHEN v_g.current_shooter = v_g.player1_id THEN v_g.player2_id ELSE v_g.player1_id END;
        UPDATE penalty_games SET p1_score = v_p1_score, p2_score = v_p2_score, current_round = v_g.current_round + 1, current_shooter = v_new_shooter WHERE id = _game_id;
        RETURN jsonb_build_object('resolved', true, 'result', v_result, 'shooter_choice', v_shooter_choice, 'keeper_choices', v_keeper_choices, 'p1_score', v_p1_score, 'p2_score', v_p2_score, 'round', v_g.current_round, 'game_over', false, 'overtime', true);
      END IF;
    END IF;
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.penalty_submit_choice(uuid, int[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.penalty_submit_choice(uuid, int[]) TO authenticated;

-- ============ RPC: _penalty_settle (internal) ============
CREATE OR REPLACE FUNCTION public._penalty_settle(_game_id uuid, _winner_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_g penalty_games%ROWTYPE; v_payout numeric; v_comm numeric;
BEGIN
  SELECT * INTO v_g FROM penalty_games WHERE id = _game_id FOR UPDATE;
  IF v_g.status = 'finished' THEN RETURN; END IF;
  v_comm := round(v_g.pot * v_g.commission_pct / 100.0, 0);
  v_payout := v_g.pot - v_comm;
  UPDATE profiles SET balance_ar = balance_ar + v_payout WHERE id = _winner_id;
  INSERT INTO transactions(user_id, type, amount, ref_id, note) VALUES (_winner_id, 'penalty_win', v_payout, _game_id, 'Penalty win');
  UPDATE penalty_games SET status = 'finished', winner_id = _winner_id, finished_at = now() WHERE id = _game_id;
END $$;
REVOKE ALL ON FUNCTION public._penalty_settle(uuid, uuid) FROM PUBLIC;

-- ============ RPC: penalty_forfeit ============
CREATE OR REPLACE FUNCTION public.penalty_forfeit(_game_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_g penalty_games%ROWTYPE; v_winner uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM penalty_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status = 'open' THEN
    IF v_uid = v_g.host_id THEN
      UPDATE profiles SET balance_ar = balance_ar + v_g.stake WHERE id = v_g.host_id;
      INSERT INTO transactions(user_id, type, amount, ref_id, note) VALUES (v_g.host_id, 'penalty_refund', v_g.stake, _game_id, 'Cancel penalty (host)');
      IF v_g.player2_id IS NOT NULL THEN
        UPDATE profiles SET balance_ar = balance_ar + v_g.stake WHERE id = v_g.player2_id;
        INSERT INTO transactions(user_id, type, amount, ref_id, note) VALUES (v_g.player2_id, 'penalty_refund', v_g.stake, _game_id, 'Cancel penalty (host)');
      END IF;
      UPDATE penalty_games SET status = 'cancelled', finished_at = now() WHERE id = _game_id;
    ELSE
      UPDATE profiles SET balance_ar = balance_ar + v_g.stake WHERE id = v_uid;
      INSERT INTO transactions(user_id, type, amount, ref_id, note) VALUES (v_uid, 'penalty_refund', v_g.stake, _game_id, 'Quit penalty waiting');
      UPDATE penalty_games SET player2_id = NULL, player2_ready = false, pot = pot - v_g.stake WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;
  IF v_g.status = 'playing' THEN
    v_winner := CASE WHEN v_uid = v_g.player1_id THEN v_g.player2_id ELSE v_g.player1_id END;
    PERFORM public._penalty_settle(_game_id, v_winner);
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.penalty_forfeit(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.penalty_forfeit(uuid) TO authenticated;

-- ============ Update list_all_open_games (add penalty) ============
CREATE OR REPLACE FUNCTION public.list_all_open_games()
RETURNS TABLE(game_id uuid, slug text, stake numeric, pot numeric, created_at timestamptz, max_players int, players_count int, host_id uuid, host_name text, target_score numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT g.id, 'ludo'::text, g.stake, g.pot, g.created_at, g.max_players,
    (SELECT count(*)::int FROM public.ludo_participants p WHERE p.game_id = g.id),
    g.host_id, COALESCE(h.pseudo, 'Joueur'), NULL::numeric
  FROM public.ludo_games g LEFT JOIN public.profiles h ON h.id = g.host_id WHERE g.status = 'open' AND g.is_private = false
  UNION ALL
  SELECT g.id, 'domino', g.stake, g.pot, g.created_at, g.max_players,
    (SELECT count(*)::int FROM public.domino_participants p WHERE p.game_id = g.id),
    g.host_id, COALESCE(h.pseudo, 'Joueur'), NULL::numeric
  FROM public.domino_games g LEFT JOIN public.profiles h ON h.id = g.host_id WHERE g.status = 'open' AND g.is_private = false
  UNION ALL
  SELECT g.id, 'fanorona', g.stake, g.pot, g.created_at, 2,
    (SELECT count(*)::int FROM public.fanorona_participants p WHERE p.game_id = g.id),
    g.host_id, COALESCE(h.pseudo, 'Joueur'), NULL::numeric
  FROM public.fanorona_games g LEFT JOIN public.profiles h ON h.id = g.host_id WHERE g.status = 'open' AND g.is_private = false
  UNION ALL
  SELECT g.id, 'chess', g.stake, g.pot, g.created_at, 2,
    ((CASE WHEN g.white_id IS NOT NULL THEN 1 ELSE 0 END) + (CASE WHEN g.black_id IS NOT NULL THEN 1 ELSE 0 END)),
    COALESCE(g.white_id, g.black_id), COALESCE(hw.pseudo, hb.pseudo, 'Joueur'), NULL::numeric
  FROM public.chess_games g LEFT JOIN public.profiles hw ON hw.id = g.white_id LEFT JOIN public.profiles hb ON hb.id = g.black_id WHERE g.status = 'open' AND g.is_private = false
  UNION ALL
  SELECT g.id, 'rami', g.stake, g.pot, g.created_at, g.max_players,
    (SELECT count(*)::int FROM public.rami_participants p WHERE p.game_id = g.id),
    g.created_by, COALESCE(h.pseudo, 'Joueur'), NULL::numeric
  FROM public.rami_games g LEFT JOIN public.profiles h ON h.id = g.created_by WHERE g.status = 'open' AND g.is_private = false
  UNION ALL
  SELECT g.id, 'poker', g.stake, g.pot, g.created_at, g.max_players,
    (SELECT count(*)::int FROM public.poker_players p WHERE p.game_id = g.id),
    g.host_id, COALESCE(h.pseudo, 'Joueur'), NULL::numeric
  FROM public.poker_games g LEFT JOIN public.profiles h ON h.id = g.host_id WHERE g.status = 'open' AND g.is_private = false
  UNION ALL
  SELECT g.id, 'penalty', g.stake, g.pot, g.created_at, 2,
    ((CASE WHEN g.player1_id IS NOT NULL THEN 1 ELSE 0 END) + (CASE WHEN g.player2_id IS NOT NULL THEN 1 ELSE 0 END)),
    g.host_id, COALESCE(h.pseudo, 'Joueur'), NULL::numeric
  FROM public.penalty_games g LEFT JOIN public.profiles h ON h.id = g.host_id WHERE g.status = 'open' AND g.is_private = false
  ORDER BY created_at DESC;
$$;
REVOKE ALL ON FUNCTION public.list_all_open_games() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_all_open_games() TO authenticated;

-- ============ Update game_online_counts_all (add penalty) ============
CREATE OR REPLACE FUNCTION public.game_online_counts_all()
RETURNS TABLE(slug text, online_count bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT 'ludo'::text, (SELECT count(*) FROM public.ludo_participants p JOIN public.ludo_games g ON g.id = p.game_id WHERE g.status = 'playing' AND p.user_id IS NOT NULL AND p.is_bot = false)
  UNION ALL SELECT 'domino', (SELECT count(*) FROM public.domino_participants p JOIN public.domino_games g ON g.id = p.game_id WHERE g.status = 'playing' AND p.user_id IS NOT NULL AND p.is_bot = false)
  UNION ALL SELECT 'fanorona', (SELECT count(*) FROM public.fanorona_participants p JOIN public.fanorona_games g ON g.id = p.game_id WHERE g.status = 'playing' AND p.user_id IS NOT NULL AND p.is_bot = false)
  UNION ALL SELECT 'chess', (SELECT count(*) FROM public.chess_games g WHERE g.status = 'playing' AND (g.white_id IS NOT NULL OR g.black_id IS NOT NULL) AND COALESCE(g.white_is_bot, false) = false)
  UNION ALL SELECT 'rami', (SELECT count(*) FROM public.rami_participants p JOIN public.rami_games g ON g.id = p.game_id WHERE g.status = 'playing' AND p.user_id IS NOT NULL AND p.is_bot = false)
  UNION ALL SELECT 'poker', (SELECT count(*) FROM public.poker_players p JOIN public.poker_games g ON g.id = p.game_id WHERE g.status = 'playing' AND p.user_id IS NOT NULL AND p.is_bot = false)
  UNION ALL SELECT 'penalty', (SELECT count(*) FROM public.penalty_games g WHERE g.status = 'playing' AND (g.player1_id IS NOT NULL OR g.player2_id IS NOT NULL));
$$;
REVOKE ALL ON FUNCTION public.game_online_counts_all() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.game_online_counts_all() TO authenticated;

-- ============ Update my_ongoing_all (add penalty) ============
CREATE OR REPLACE FUNCTION public.my_ongoing_all() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.eliminated ASC, t.created_at DESC), '[]'::jsonb) INTO v_result FROM (
    SELECT g.id, 'ludo'::text AS game_type, g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at, false AS eliminated,
      (SELECT count(*) FROM ludo_participants pp WHERE pp.game_id=g.id) AS players_count
    FROM ludo_games g JOIN ludo_participants p ON p.game_id=g.id WHERE p.user_id=v_uid AND g.status IN ('open','playing') AND p.forfeited=false
    UNION ALL SELECT g.id, 'ludo', g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at, true,
      (SELECT count(*) FROM ludo_participants pp WHERE pp.game_id=g.id)
    FROM ludo_games g JOIN ludo_participants p ON p.game_id=g.id WHERE p.user_id=v_uid AND g.status='playing' AND p.forfeited=true
    UNION ALL SELECT g.id, 'domino', g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at, false,
      (SELECT count(*) FROM domino_participants pp WHERE pp.game_id=g.id)
    FROM domino_games g JOIN domino_participants p ON p.game_id=g.id WHERE p.user_id=v_uid AND g.status IN ('open','playing') AND p.forfeited=false
    UNION ALL SELECT g.id, 'domino', g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at, true,
      (SELECT count(*) FROM domino_participants pp WHERE pp.game_id=g.id)
    FROM domino_games g JOIN domino_participants p ON p.game_id=g.id WHERE p.user_id=v_uid AND g.status='playing' AND p.forfeited=true
    UNION ALL SELECT g.id, 'fanorona', g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at, false,
      (SELECT count(*) FROM fanorona_participants pp WHERE pp.game_id=g.id)
    FROM fanorona_games g JOIN fanorona_participants p ON p.game_id=g.id WHERE p.user_id=v_uid AND g.status IN ('open','playing') AND p.forfeited=false
    UNION ALL SELECT g.id, 'fanorona', g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at, true,
      (SELECT count(*) FROM fanorona_participants pp WHERE pp.game_id=g.id)
    FROM fanorona_games g JOIN fanorona_participants p ON p.game_id=g.id WHERE p.user_id=v_uid AND g.status='playing' AND p.forfeited=true
    UNION ALL SELECT g.id, 'rami', g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at, false,
      (SELECT count(*) FROM rami_participants pp WHERE pp.game_id=g.id)
    FROM rami_games g JOIN rami_participants p ON p.game_id=g.id WHERE p.user_id=v_uid AND g.status IN ('open','playing') AND p.forfeited=false
    UNION ALL SELECT g.id, 'rami', g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at, true,
      (SELECT count(*) FROM rami_participants pp WHERE pp.game_id=g.id)
    FROM rami_games g JOIN rami_participants p ON p.game_id=g.id WHERE p.user_id=v_uid AND g.status='playing' AND p.forfeited=true
    UNION ALL SELECT g.id, 'chess', g.status, 2 AS max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at, false,
      (CASE WHEN g.black_id IS NULL THEN 1 ELSE 2 END)::bigint
    FROM chess_games g WHERE (g.white_id=v_uid OR g.black_id=v_uid) AND g.status IN ('open','playing')
    UNION ALL SELECT g.id, 'poker', g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at, false,
      (SELECT count(*) FROM poker_players pp WHERE pp.game_id=g.id)
    FROM poker_games g JOIN poker_players p ON p.game_id=g.id WHERE p.user_id=v_uid AND g.status IN ('open','playing') AND p.status <> 'out'
    UNION ALL SELECT g.id, 'poker', g.status, g.max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at, true,
      (SELECT count(*) FROM poker_players pp WHERE pp.game_id=g.id)
    FROM poker_games g JOIN poker_players p ON p.game_id=g.id WHERE p.user_id=v_uid AND g.status='playing' AND p.status='out'
    UNION ALL SELECT g.id, 'penalty', g.status, 2 AS max_players, g.stake, g.pot, g.room_code, g.is_private, g.created_at, false,
      ((CASE WHEN g.player1_id IS NOT NULL THEN 1 ELSE 0 END) + (CASE WHEN g.player2_id IS NOT NULL THEN 1 ELSE 0 END))::bigint
    FROM penalty_games g WHERE (g.player1_id=v_uid OR g.player2_id=v_uid) AND g.status IN ('open','playing')
  ) t;
  RETURN v_result;
END $$;
GRANT EXECUTE ON FUNCTION public.my_ongoing_all() TO authenticated;
