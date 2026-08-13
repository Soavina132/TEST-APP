CREATE OR REPLACE FUNCTION public._domino_bot_pick_move(_state jsonb, _slot integer, _intel integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  hand jsonb := COALESCE(_state -> 'hands' -> _slot::text, '[]'::jsonb);
  board_len int := jsonb_array_length(COALESCE(_state->'board','[]'::jsonb));
  le int := NULLIF(_state->>'left_end','null')::int;
  re int := NULLIF(_state->>'right_end','null')::int;
  first_dbl int := NULLIF(_state->>'first_move_double','null')::int;
  v_rule text := COALESCE(_state->>'first_tile_rule','libre');
  draw_mode text := COALESCE(_state->>'draw_mode','with');
  stock_len int := jsonb_array_length(COALESCE(_state->'stock','[]'::jsonb));
  n_players int := 0;
  playable jsonb := '[]'::jsonb;
  scored jsonb := '[]'::jsonb;
  t jsonb;
  a int;
  b int;
  ml boolean;
  mr boolean;
  i int;
  n int;
  pick_idx int;
  best_score numeric := -1000000000;
  cur_score numeric;
  new_le int;
  new_re int;
  other_end int;
  hand_size int := jsonb_array_length(hand);
  min_opp_hand int := 999;
  opp_slot int;
  opp_hand jsonb;
  suit_count int[] := ARRAY[0,0,0,0,0,0,0];
  follow_le int;
  follow_re int;
  is_double boolean;
  difficulty text;
  quality_gate numeric;
BEGIN
  IF hand_size = 0 THEN
    RETURN jsonb_build_object('action','pass');
  END IF;

  SELECT count(*) INTO n_players
    FROM jsonb_object_keys(COALESCE(_state->'hands', '{}'::jsonb));

  IF _intel < 40 THEN
    difficulty := 'easy';
  ELSIF _intel < 75 THEN
    difficulty := 'medium';
  ELSE
    difficulty := 'hard';
  END IF;

  FOR t IN SELECT * FROM jsonb_array_elements(hand) LOOP
    a := (t->>0)::int;
    b := (t->>1)::int;
    IF a BETWEEN 0 AND 6 THEN suit_count[a+1] := suit_count[a+1] + 1; END IF;
    IF b BETWEEN 0 AND 6 AND b <> a THEN suit_count[b+1] := suit_count[b+1] + 1; END IF;
  END LOOP;

  IF n_players > 0 THEN
    FOR opp_slot IN 0..(n_players - 1) LOOP
      IF opp_slot <> _slot THEN
        opp_hand := _state->'hands'->opp_slot::text;
        IF opp_hand IS NOT NULL AND jsonb_typeof(opp_hand) = 'array' THEN
          min_opp_hand := LEAST(min_opp_hand, jsonb_array_length(opp_hand));
        END IF;
      END IF;
    END LOOP;
  END IF;

  IF board_len = 0 THEN
    IF first_dbl IS NOT NULL THEN
      FOR t IN SELECT * FROM jsonb_array_elements(hand) LOOP
        a := (t->>0)::int;
        b := (t->>1)::int;
        IF a = first_dbl AND b = first_dbl THEN
          RETURN jsonb_build_object('action','play','tile', t, 'side','right');
        END IF;
      END LOOP;
      IF draw_mode = 'with' AND stock_len > 0 THEN
        RETURN jsonb_build_object('action','draw');
      END IF;
      RETURN jsonb_build_object('action','pass');
    END IF;

    FOR t IN SELECT * FROM jsonb_array_elements(hand) LOOP
      a := (t->>0)::int;
      b := (t->>1)::int;
      IF v_rule <> 'under6' OR (a + b) < 6 THEN
        playable := playable || jsonb_build_array(jsonb_build_object('tile', t, 'side', 'right'));
      END IF;
    END LOOP;
  ELSE
    FOR t IN SELECT * FROM jsonb_array_elements(hand) LOOP
      a := (t->>0)::int;
      b := (t->>1)::int;
      ml := (a = le OR b = le);
      mr := (a = re OR b = re);
      IF mr THEN
        playable := playable || jsonb_build_array(jsonb_build_object('tile', t, 'side', 'right'));
      END IF;
      IF ml AND NOT (mr AND le = re) THEN
        playable := playable || jsonb_build_array(jsonb_build_object('tile', t, 'side', 'left'));
      END IF;
    END LOOP;
  END IF;

  n := jsonb_array_length(playable);
  IF n = 0 THEN
    IF draw_mode = 'with' AND stock_len > 0 THEN
      RETURN jsonb_build_object('action','draw');
    END IF;
    RETURN jsonb_build_object('action','pass');
  END IF;

  IF difficulty = 'easy' THEN
    pick_idx := floor(random() * n)::int;
    RETURN jsonb_build_object('action','play','tile', playable->pick_idx->'tile','side', playable->pick_idx->>'side');
  END IF;

  FOR i IN 0..(n - 1) LOOP
    a := (playable->i->'tile'->>0)::int;
    b := (playable->i->'tile'->>1)::int;
    is_double := a = b;

    IF board_len = 0 THEN
      new_le := a;
      new_re := b;
    ELSIF playable->i->>'side' = 'right' THEN
      new_le := le;
      other_end := CASE WHEN a = re THEN b ELSE a END;
      new_re := other_end;
    ELSE
      other_end := CASE WHEN a = le THEN b ELSE a END;
      new_le := other_end;
      new_re := re;
    END IF;

    follow_le := CASE WHEN new_le BETWEEN 0 AND 6 THEN suit_count[new_le + 1] ELSE 0 END;
    follow_re := CASE WHEN new_re BETWEEN 0 AND 6 THEN suit_count[new_re + 1] ELSE 0 END;
    IF a = new_le OR b = new_le THEN follow_le := GREATEST(0, follow_le - 1); END IF;
    IF a = new_re OR b = new_re THEN follow_re := GREATEST(0, follow_re - 1); END IF;

    -- Professional-style priorities:
    -- 1) empty the hand quickly, 2) keep follow-up numbers, 3) dump high pips
    -- when opponents are close, 4) avoid creating a dead end for ourselves.
    cur_score := 0;
    cur_score := cur_score + (a + b) * CASE WHEN min_opp_hand <= 2 OR hand_size <= 4 THEN 7 ELSE 3 END;
    cur_score := cur_score + (follow_le + follow_re) * CASE WHEN hand_size <= 4 THEN 18 ELSE 8 END;
    cur_score := cur_score + CASE WHEN is_double THEN 16 + (a * 2) ELSE 0 END;
    cur_score := cur_score + CASE WHEN new_le = new_re AND (follow_le + follow_re) > 0 THEN 12 ELSE 0 END;

    IF hand_size <= 3 AND (follow_le + follow_re) = 0 AND hand_size > 1 THEN
      cur_score := cur_score - 45;
    END IF;

    IF min_opp_hand <= 2 THEN
      -- Defensive endgame: prefer ends we still control and high-pip dumping.
      cur_score := cur_score + (follow_le + follow_re) * 14 + (a + b) * 4;
    END IF;

    IF hand_size = 1 THEN
      cur_score := cur_score + 100000;
    END IF;

    IF difficulty = 'medium' THEN
      cur_score := cur_score + (random() * 30) - 10;
    END IF;

    scored := scored || jsonb_build_array(jsonb_build_object(
      'idx', i,
      'score', cur_score,
      'tile', playable->i->'tile',
      'side', playable->i->>'side'
    ));

    IF cur_score > best_score THEN
      best_score := cur_score;
      pick_idx := i;
    END IF;
  END LOOP;

  IF difficulty = 'medium' AND n > 1 THEN
    quality_gate := best_score - 20;
    SELECT COALESCE((x->>'idx')::int, pick_idx) INTO pick_idx
      FROM jsonb_array_elements(scored) AS x
      WHERE (x->>'score')::numeric >= quality_gate
      ORDER BY random()
      LIMIT 1;
  END IF;

  IF pick_idx IS NULL OR pick_idx < 0 THEN pick_idx := 0; END IF;
  RETURN jsonb_build_object('action','play','tile', playable->pick_idx->'tile','side', playable->pick_idx->>'side');
END;
$function$
