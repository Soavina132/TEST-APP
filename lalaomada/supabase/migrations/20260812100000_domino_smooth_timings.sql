-- Improve timing for professional feel:
-- 1. Bot think delay: 400-1000ms → 700-1600ms (more natural, less robotic)
-- 2. Break phase: 13s → 7s (less waiting between rounds)
-- 3. Reveal phase: 3s → 2.5s (slightly snappier)

-- ═══ 1. Update bot think delay ═══
CREATE OR REPLACE FUNCTION public._domino_arm_bot_think(_game_id uuid, _slot int, _state jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_is_bot boolean := false;
  v_delay_ms int;
BEGIN
  SELECT COALESCE(dp.is_bot, false) INTO v_is_bot
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id AND dp.slot = _slot AND dp.forfeited = false;

  IF v_is_bot THEN
    -- 700ms-1600ms think delay (was 400-1000ms) — feels more natural
    v_delay_ms := 700 + (floor(random() * 900))::int;
    _state := jsonb_set(_state, '{bot_locked_slot}', to_jsonb(_slot), true);
    _state := jsonb_set(_state, '{bot_think_until}',
             to_jsonb((now() + make_interval(secs => v_delay_ms / 1000.0))::text), true);
  ELSE
    _state := _state - 'bot_think_until' - 'bot_locked_slot';
  END IF;

  RETURN _state;
END;
$$;

-- ═══ 2 & 3. Update reveal/break durations in _domino_end_round ═══
-- We need to find and replace the interval constants in the function
CREATE OR REPLACE FUNCTION public._domino_end_round(_game_id uuid, _winner_slot int DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  g record;
  st jsonb;
  v_scores jsonb;
  v_slot int;
  v_pts int;
  v_remaining jsonb;
  v_total int;
  v_rounds int;
  v_winner_overall int;
  v_pass_count int;
  v_target int;
  v_mode text;
  v_next_starter int := 0;
  v_reveal       interval := interval '2.5 seconds';   -- was 3s
  v_break_total  interval := interval '7 seconds';      -- was 13s
  v_part record;
  v_hands jsonb := '{}'::jsonb;
  v_hand jsonb;
  v_all_blocked boolean := false;
  v_lowest int;
  v_lowest_slot int;
  v_deadlock_slots int[];
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id;
  IF NOT FOUND THEN RETURN; END IF;

  st := g.state;
  v_mode := COALESCE(st->>'mode', 'classic');
  v_target := COALESCE(NULLIF(st->>'target_score','')::int, 0);

  -- Determine if all players are blocked (deadlock)
  v_pass_count := COALESCE(NULLIF(st->>'passes','')::int, 0);
  IF v_pass_count >= (SELECT count(*) FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false) THEN
    v_all_blocked := true;
  END IF;

  -- Calculate round scores
  v_scores := COALESCE(st->'round_scores', '{}'::jsonb);

  IF v_all_blocked AND _winner_slot IS NULL THEN
    -- Deadlock: lowest pip count wins
    v_lowest := 999999;
    v_lowest_slot := 0;
    FOR v_slot IN SELECT unnest(array(SELECT DISTINCT (jsonb_object_keys(st->'hands'))::int ORDER BY 1)) LOOP
      v_hand := st->'hands'->v_slot::text;
      IF v_hand IS NOT NULL THEN
        SELECT COALESCE(sum((tile->>0)::int + (tile->>1)::int), 0) INTO v_pts
          FROM jsonb_array_elements(v_hand) AS tile;
        IF v_pts < v_lowest THEN
          v_lowest := v_pts;
          v_lowest_slot := v_slot;
        END IF;
      END IF;
    END LOOP;
    _winner_slot := v_lowest_slot;
  END IF;

  -- Award points to winner (sum of all opponents' remaining pips)
  IF _winner_slot IS NOT NULL THEN
    v_remaining := '{}'::jsonb;
    v_total := 0;
    FOR v_slot IN SELECT unnest(array(SELECT DISTINCT (jsonb_object_keys(st->'hands'))::int ORDER BY 1)) LOOP
      IF v_slot <> _winner_slot THEN
        v_hand := st->'hands'->v_slot::text;
        IF v_hand IS NOT NULL THEN
          SELECT COALESCE(sum((tile->>0)::int + (tile->>1)::int), 0) INTO v_pts
            FROM jsonb_array_elements(v_hand) AS tile;
          v_remaining := v_remaining || jsonb_build_object(v_slot::text, v_pts);
          v_total := v_total + v_pts;
        END IF;
      END IF;
    END LOOP;

    -- Update cumulative scores
    SELECT COALESCE((v_scores->>_winner_slot::text)::int, 0) + v_total INTO v_pts;
    v_scores := jsonb_set(v_scores, ARRAY[_winner_slot::text], to_jsonb(v_pts), true);
  END IF;

  -- Store last round info
  st := jsonb_set(st, '{last_round}', jsonb_build_object(
    'winner_slot', _winner_slot,
    'scores', v_scores,
    'remaining', v_remaining,
    'blocked', v_all_blocked
  ), true);

  -- Check if we have an overall winner
  v_winner_overall := -1;
  IF v_mode = 'points' AND v_target > 0 THEN
    FOR v_slot IN SELECT DISTINCT (jsonb_object_keys(v_scores))::int LOOP
      IF (v_scores->>v_slot::text)::int >= v_target THEN
        v_winner_overall := v_slot;
        EXIT;
      END IF;
    END LOOP;
  ELSE
    -- Classic mode: first round win = game win
    v_winner_overall := COALESCE(_winner_slot, -1);
  END IF;

  IF v_winner_overall >= 0 THEN
    -- Game over
    st := jsonb_set(st, '{phase}', '"reveal"'::jsonb);
    st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text), true);
    st := jsonb_set(st, '{winner_slot}', to_jsonb(v_winner_overall), true);
    st := jsonb_set(st, '{round_scores}', v_scores, true);

    UPDATE public.domino_games
       SET state = st, status = 'finished',
           winner_id = (SELECT user_id FROM public.domino_participants WHERE game_id = _game_id AND slot = v_winner_overall),
           current_turn = -1, turn_deadline = NULL
     WHERE id = _game_id;

    -- Award pot to winner
    PERFORM public._domino_payout(_game_id, v_winner_overall);
    RETURN;
  END IF;

  -- Start new round
  v_rounds := COALESCE(NULLIF(st->>'round','')::int, 0) + 1;
  st := jsonb_set(st, '{round}', to_jsonb(v_rounds), true);
  st := jsonb_set(st, '{round_scores}', v_scores, true);

  -- Re-deal tiles
  PERFORM public._domino_deal(_game_id, st, v_next_starter);

  -- Set reveal then break phase
  st := jsonb_set(st, '{phase}', '"reveal"'::jsonb);
  st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text), true);
  st := jsonb_set(st, '{break_until}',  to_jsonb((now() + v_break_total)::text), true);

  UPDATE public.domino_games
     SET state = st, current_turn = v_next_starter,
         turn_deadline = now() + interval '30 seconds'
   WHERE id = _game_id;
END;
$$;
