-- ════════════════════════════════════════════════════════════════════════
-- PENALTY BOT — vs bot mode (no waiting room, immediate start)
-- ════════════════════════════════════════════════════════════════════════

-- Add bot_difficulty column to penalty_games
ALTER TABLE public.penalty_games ADD COLUMN IF NOT EXISTS bot_difficulty int;

-- Make shooter_id and keeper_id nullable (for bot games, bot has no user_id)
ALTER TABLE public.penalty_rounds ALTER COLUMN shooter_id DROP NOT NULL;
ALTER TABLE public.penalty_rounds ALTER COLUMN keeper_id DROP NOT NULL;

-- ============ RPC: penalty_create_solo ============
-- Creates a penalty game vs bot that starts immediately (no waiting room)
CREATE OR REPLACE FUNCTION public.penalty_create_solo(
  _num_balls int DEFAULT 5,
  _num_keeper_choices int DEFAULT 2,
  _bot_difficulty int DEFAULT 3
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
  v_name text;
  v_human_first boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _num_balls < 1 OR _num_balls > 20 THEN RAISE EXCEPTION 'balls must be 1-20'; END IF;
  IF _num_keeper_choices < 1 OR _num_keeper_choices > 3 THEN RAISE EXCEPTION 'keeper choices must be 1-3'; END IF;
  IF _bot_difficulty < 1 OR _bot_difficulty > 5 THEN RAISE EXCEPTION 'difficulty must be 1-5'; END IF;

  v_human_first := (random() < 0.5);

  INSERT INTO penalty_games(
    host_id, player1_id, player2_id,
    status, stake, pot, commission_pct,
    is_private, room_code,
    num_balls, num_keeper_choices,
    bot_difficulty,
    player1_ready, player2_ready,
    first_shooter_id, current_shooter, current_round,
    started_at
  )
  VALUES (
    v_uid, v_uid, NULL,
    'playing', 0, 0, 0,
    true, NULL,
    _num_balls, _num_keeper_choices,
    _bot_difficulty,
    true, true,
    CASE WHEN v_human_first THEN v_uid ELSE NULL END,
    CASE WHEN v_human_first THEN v_uid ELSE NULL END,
    1,
    now()
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public.penalty_create_solo(int, int, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.penalty_create_solo(int, int, int) TO authenticated;

-- ============ Update penalty_submit_choice to handle bot ============
CREATE OR REPLACE FUNCTION public.penalty_submit_choice(_game_id uuid, _choice int[]) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid(); v_g penalty_games%ROWTYPE; v_round penalty_rounds%ROWTYPE;
  v_shooter_choice int; v_keeper_choices int[]; v_is_shooter boolean; v_is_keeper boolean;
  v_all_submitted boolean; v_result text; v_opponent uuid; v_total_rounds int;
  v_p1_score int; v_p2_score int; v_new_shooter uuid;
  v_is_bot_game boolean; v_bot_choice int[]; v_bot_zone int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM penalty_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status <> 'playing' THEN RAISE EXCEPTION 'game not playing'; END IF;
  IF array_length(_choice, 1) IS NULL THEN RAISE EXCEPTION 'no choices'; END IF;

  v_is_bot_game := (v_g.player2_id IS NULL AND v_g.bot_difficulty IS NOT NULL);

  IF v_is_bot_game THEN
    -- Bot game: human is player1_id, bot is "virtual player 2"
    -- current_shooter = v_uid → human shoots, bot keeps
    -- current_shooter = NULL → bot shoots, human keeps
    v_is_shooter := (v_g.current_shooter = v_uid);
    v_is_keeper := (v_g.current_shooter IS NULL);
  ELSE
    v_is_shooter := (v_uid = v_g.current_shooter);
    v_opponent := CASE WHEN v_uid = v_g.player1_id THEN v_g.player2_id ELSE v_g.player1_id END;
    v_is_keeper := (v_uid = v_opponent);
  END IF;

  IF NOT v_is_shooter AND NOT v_is_keeper THEN RAISE EXCEPTION 'not your turn'; END IF;

  SELECT * INTO v_round FROM penalty_rounds WHERE game_id = _game_id AND round_num = v_g.current_round;
  IF NOT FOUND THEN
    INSERT INTO penalty_rounds(game_id, round_num, shooter_id, keeper_id, is_overtime)
    VALUES (
      _game_id, v_g.current_round,
      -- shooter_id: human's id if human shoots, NULL if bot shoots
      CASE WHEN v_is_bot_game THEN (CASE WHEN v_g.current_shooter = v_uid THEN v_uid ELSE NULL END)
           ELSE v_g.current_shooter END,
      -- keeper_id: NULL if bot keeps, human's id if human keeps
      CASE WHEN v_is_bot_game THEN (CASE WHEN v_g.current_shooter = v_uid THEN NULL ELSE v_uid END)
           ELSE CASE WHEN v_g.current_shooter = v_g.player1_id THEN v_g.player2_id ELSE v_g.player1_id END END,
      v_g.is_overtime
    )
    RETURNING * INTO v_round;
  END IF;

  -- Process human's choice
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

  -- If bot game, auto-play the bot's role
  IF v_is_bot_game THEN
    SELECT * INTO v_round FROM penalty_rounds WHERE id = v_round.id;
    -- Bot is keeper (human shot) → auto-generate keeper choices
    IF v_round.shooter_choice IS NOT NULL AND v_round.keeper_choices IS NULL THEN
      SELECT array_agg(z ORDER BY random()) INTO v_bot_choice
      FROM (SELECT unnest(ARRAY[1,2,3,4,5,6]) AS z LIMIT v_g.num_keeper_choices) sub;
      UPDATE penalty_rounds SET keeper_choices = v_bot_choice WHERE id = v_round.id;
    END IF;
    -- Bot is shooter (human kept) → auto-generate shooter choice
    IF v_round.keeper_choices IS NOT NULL AND v_round.shooter_choice IS NULL THEN
      v_bot_zone := floor(random() * 6 + 1)::int;
      UPDATE penalty_rounds SET shooter_choice = v_bot_zone WHERE id = v_round.id;
    END IF;
  END IF;

  -- Check if both submitted
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
    -- In bot game: shooter_id = v_uid means human (player1) scored, NULL means bot (player2) scored
    IF v_is_bot_game THEN
      IF v_round.shooter_id = v_uid THEN v_p1_score := v_p1_score + 1; ELSE v_p2_score := v_p2_score + 1; END IF;
    ELSE
      IF v_round.shooter_id = v_g.player1_id THEN v_p1_score := v_p1_score + 1; ELSE v_p2_score := v_p2_score + 1; END IF;
    END IF;
  END IF;

  v_total_rounds := v_g.num_balls * 2;
  IF v_g.is_overtime THEN v_total_rounds := v_g.num_balls * 2 + v_g.overtime_round * 2; END IF;

  IF v_g.current_round < v_total_rounds THEN
    IF v_is_bot_game THEN
      v_new_shooter := CASE WHEN v_g.current_shooter = v_uid THEN NULL ELSE v_uid END;
    ELSE
      v_new_shooter := CASE WHEN v_g.current_shooter = v_g.player1_id THEN v_g.player2_id ELSE v_g.player1_id END;
    END IF;
    UPDATE penalty_games SET p1_score = v_p1_score, p2_score = v_p2_score, current_round = v_g.current_round + 1, current_shooter = v_new_shooter WHERE id = _game_id;
    RETURN jsonb_build_object('resolved', true, 'result', v_result, 'shooter_choice', v_shooter_choice, 'keeper_choices', v_keeper_choices, 'p1_score', v_p1_score, 'p2_score', v_p2_score, 'round', v_g.current_round, 'game_over', false);
  ELSE
    IF NOT v_g.is_overtime THEN
      IF v_p1_score > v_p2_score THEN
        PERFORM public._penalty_settle(_game_id, v_g.player1_id);
        RETURN jsonb_build_object('resolved', true, 'result', v_result, 'shooter_choice', v_shooter_choice, 'keeper_choices', v_keeper_choices, 'p1_score', v_p1_score, 'p2_score', v_p2_score, 'round', v_g.current_round, 'game_over', true, 'winner', 'p1');
      ELSIF v_p2_score > v_p1_score THEN
        -- In bot game, player2_id is NULL, so _penalty_settle would try to pay NULL
        IF NOT v_is_bot_game THEN PERFORM public._penalty_settle(_game_id, v_g.player2_id); END IF;
        UPDATE penalty_games SET status = 'finished', winner_id = NULL, finished_at = now() WHERE id = _game_id;
        RETURN jsonb_build_object('resolved', true, 'result', v_result, 'shooter_choice', v_shooter_choice, 'keeper_choices', v_keeper_choices, 'p1_score', v_p1_score, 'p2_score', v_p2_score, 'round', v_g.current_round, 'game_over', true, 'winner', 'p2');
      ELSE
        -- Overtime
        IF v_is_bot_game THEN
          UPDATE penalty_games SET p1_score = v_p1_score, p2_score = v_p2_score, is_overtime = true, overtime_round = 1, current_round = v_g.current_round + 1,
            current_shooter = CASE WHEN v_g.first_shooter_id = v_uid THEN NULL ELSE v_uid END WHERE id = _game_id;
        ELSE
          UPDATE penalty_games SET p1_score = v_p1_score, p2_score = v_p2_score, is_overtime = true, overtime_round = 1, current_round = v_g.current_round + 1,
            current_shooter = CASE WHEN v_g.first_shooter_id = v_g.player1_id THEN v_g.player2_id ELSE v_g.player1_id END WHERE id = _game_id;
        END IF;
        RETURN jsonb_build_object('resolved', true, 'result', v_result, 'shooter_choice', v_shooter_choice, 'keeper_choices', v_keeper_choices, 'p1_score', v_p1_score, 'p2_score', v_p2_score, 'round', v_g.current_round, 'game_over', false, 'overtime', true);
      END IF;
    ELSE
      IF v_g.current_round % 2 = 0 THEN
        IF v_p1_score > v_p2_score THEN
          PERFORM public._penalty_settle(_game_id, v_g.player1_id);
          RETURN jsonb_build_object('resolved', true, 'result', v_result, 'shooter_choice', v_shooter_choice, 'keeper_choices', v_keeper_choices, 'p1_score', v_p1_score, 'p2_score', v_p2_score, 'round', v_g.current_round, 'game_over', true, 'winner', 'p1');
        ELSIF v_p2_score > v_p1_score THEN
          IF NOT v_is_bot_game THEN PERFORM public._penalty_settle(_game_id, v_g.player2_id); END IF;
          UPDATE penalty_games SET status = 'finished', winner_id = NULL, finished_at = now() WHERE id = _game_id;
          RETURN jsonb_build_object('resolved', true, 'result', v_result, 'shooter_choice', v_shooter_choice, 'keeper_choices', v_keeper_choices, 'p1_score', v_p1_score, 'p2_score', v_p2_score, 'round', v_g.current_round, 'game_over', true, 'winner', 'p2');
        ELSE
          IF v_is_bot_game THEN
            UPDATE penalty_games SET p1_score = v_p1_score, p2_score = v_p2_score, overtime_round = v_g.overtime_round + 1, current_round = v_g.current_round + 1,
              current_shooter = CASE WHEN v_g.current_shooter = v_uid THEN NULL ELSE v_uid END WHERE id = _game_id;
          ELSE
            UPDATE penalty_games SET p1_score = v_p1_score, p2_score = v_p2_score, overtime_round = v_g.overtime_round + 1, current_round = v_g.current_round + 1,
              current_shooter = CASE WHEN v_g.current_shooter = v_g.player1_id THEN v_g.player2_id ELSE v_g.player1_id END WHERE id = _game_id;
          END IF;
          RETURN jsonb_build_object('resolved', true, 'result', v_result, 'shooter_choice', v_shooter_choice, 'keeper_choices', v_keeper_choices, 'p1_score', v_p1_score, 'p2_score', v_p2_score, 'round', v_g.current_round, 'game_over', false, 'overtime', true);
        END IF;
      ELSE
        IF v_is_bot_game THEN
          v_new_shooter := CASE WHEN v_g.current_shooter = v_uid THEN NULL ELSE v_uid END;
        ELSE
          v_new_shooter := CASE WHEN v_g.current_shooter = v_g.player1_id THEN v_g.player2_id ELSE v_g.player1_id END;
        END IF;
        UPDATE penalty_games SET p1_score = v_p1_score, p2_score = v_p2_score, current_round = v_g.current_round + 1, current_shooter = v_new_shooter WHERE id = _game_id;
        RETURN jsonb_build_object('resolved', true, 'result', v_result, 'shooter_choice', v_shooter_choice, 'keeper_choices', v_keeper_choices, 'p1_score', v_p1_score, 'p2_score', v_p2_score, 'round', v_g.current_round, 'game_over', false, 'overtime', true);
      END IF;
    END IF;
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.penalty_submit_choice(uuid, int[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.penalty_submit_choice(uuid, int[]) TO authenticated;

-- ============ Update penalty_forfeit to handle bot games ============
CREATE OR REPLACE FUNCTION public.penalty_forfeit(_game_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_g penalty_games%ROWTYPE;
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
    IF v_g.player2_id IS NULL AND v_g.bot_difficulty IS NOT NULL THEN
      -- Bot game: human forfeits, bot wins (no payout since stake=0)
      UPDATE penalty_games SET status = 'finished', winner_id = NULL, finished_at = now() WHERE id = _game_id;
      RETURN;
    END IF;
    PERFORM public._penalty_settle(_game_id, CASE WHEN v_uid = v_g.player1_id THEN v_g.player2_id ELSE v_g.player1_id END);
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.penalty_forfeit(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.penalty_forfeit(uuid) TO authenticated;
