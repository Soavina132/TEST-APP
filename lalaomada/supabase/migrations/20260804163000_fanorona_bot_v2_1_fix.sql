-- Fanorona Bot v2.1: fix capture variable corruption + improved chain evaluation

CREATE OR REPLACE FUNCTION public.fanorona_bot_play(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  g record;
  bot_slot int; bot_color int; opp_color int;
  st jsonb; board jsonb;
  v_cols int; v_rows int; v_intelligence int;
  chain_from_v int; visited jsonb; last_axis text; move_count int;

  -- Chain evaluation
  ch_r int; ch_c int; ch_is_strong boolean;
  ch_dr int; ch_dc int; ch_nr int; ch_nc int; ch_nidx int;
  ch_axis text; ch_lists jsonb; ch_cap_count int;
  ch_best_from int; ch_best_to int; ch_best_cap jsonb; ch_best_score int := -99999;
  ch_score int;
  ch_cur_cap jsonb;
  ch_tmp_board jsonb; ch_j int;
  ch_can_continue boolean;

  -- Move evaluation
  i int; r int; c int; dr int; dc int; nr int; nc int; nidx int;
  is_strong boolean; axis text; lists jsonb; cap_count int; score int;
  has_capture boolean := false; tmp_board jsonb; j int;
  best_from int; best_to int; best_cap jsonb; best_score int := -99999;
  cur_cap jsonb;
  sim_board jsonb; sim_can_chain boolean;
  opp_best_cap int; opp_i int; opp_r int; opp_c int; opp_dr int; opp_dc int;
  opp_nr int; opp_nc int; opp_nidx int; opp_lists jsonb; opp_cap int;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;

  SELECT slot, bot_intelligence INTO bot_slot, v_intelligence
    FROM public.fanorona_participants WHERE game_id = _game_id AND is_bot = true;
  IF bot_slot IS NULL THEN RAISE EXCEPTION 'no bot'; END IF;
  IF g.current_turn <> bot_slot THEN RAISE EXCEPTION 'not bot turn'; END IF;

  v_cols := COALESCE(g.cols, 9); v_rows := COALESCE(g.rows, 5);
  bot_color := CASE WHEN bot_slot = 0 THEN 1 ELSE 2 END;
  opp_color := CASE WHEN bot_slot = 0 THEN 2 ELSE 1 END;
  st := g.state; board := st -> 'board';
  move_count := COALESCE((st->>'move_count')::int, 0);
  visited := COALESCE(st->'visited', '[]'::jsonb);
  last_axis := NULLIF(st->>'last_axis', '');
  chain_from_v := CASE WHEN st->'chain_from' IS NULL OR st->'chain_from' = 'null'::jsonb
                       THEN NULL ELSE (st->>'chain_from')::int END;

  -- CHAIN MODE: evaluate ALL capture options, pick the best one
  IF chain_from_v IS NOT NULL THEN
    ch_r := chain_from_v / v_cols; ch_c := chain_from_v % v_cols;
    ch_is_strong := ((ch_r + ch_c) % 2 = 0);

    FOR ch_dr, ch_dc IN SELECT a,b FROM (VALUES
      (-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)
    ) v(a,b) LOOP
      IF NOT ch_is_strong AND (ch_dr <> 0 AND ch_dc <> 0) THEN CONTINUE; END IF;
      ch_nr := ch_r + ch_dr; ch_nc := ch_c + ch_dc;
      IF ch_nr < 0 OR ch_nr >= v_rows OR ch_nc < 0 OR ch_nc >= v_cols THEN CONTINUE; END IF;
      ch_nidx := ch_nr * v_cols + ch_nc;
      IF (board->ch_nidx)::int <> 0 THEN CONTINUE; END IF;
      IF visited @> to_jsonb(ch_nidx) THEN CONTINUE; END IF;
      ch_axis := public._fanorona_axis(ch_dr, ch_dc);
      IF last_axis IS NOT NULL AND ch_axis = last_axis THEN CONTINUE; END IF;

      ch_lists := public._fanorona_capture_lists(board, bot_color, chain_from_v, ch_nidx, v_cols, v_rows);
      ch_cap_count := GREATEST(
        jsonb_array_length(ch_lists->'approach'),
        jsonb_array_length(ch_lists->'withdrawal')
      );

      IF ch_cap_count = 0 THEN CONTINUE; END IF;

      -- Use ch_cur_cap (NOT ch_best_cap) to avoid corrupting the best
      IF jsonb_array_length(ch_lists->'approach') >= jsonb_array_length(ch_lists->'withdrawal') THEN
        ch_cur_cap := ch_lists->'approach';
      ELSE
        ch_cur_cap := ch_lists->'withdrawal';
      END IF;

      ch_score := ch_cap_count * 100;

      IF v_intelligence >= 4 THEN
        ch_tmp_board := board;
        ch_tmp_board := jsonb_set(ch_tmp_board, ARRAY[chain_from_v::text], '0'::jsonb);
        ch_tmp_board := jsonb_set(ch_tmp_board, ARRAY[ch_nidx::text], to_jsonb(bot_color));
        FOR ch_j IN 0..jsonb_array_length(ch_cur_cap) - 1 LOOP
          ch_tmp_board := jsonb_set(ch_tmp_board, ARRAY[((ch_cur_cap->ch_j)::int)::text], '0'::jsonb);
        END LOOP;

        ch_can_continue := public._fanorona_piece_can_capture(
          ch_tmp_board, bot_color, ch_nidx,
          visited || to_jsonb(chain_from_v) || to_jsonb(ch_nidx),
          ch_axis, v_cols, v_rows
        );

        IF ch_can_continue THEN
          ch_score := ch_score + 200;
        END IF;

        IF NOT ch_can_continue AND public._fanorona_player_can_capture(ch_tmp_board, opp_color, v_cols, v_rows) THEN
          ch_score := ch_score - 30;
        END IF;
      END IF;

      IF v_intelligence <= 2 THEN
        ch_score := ch_score + (random() * 80)::int;
      ELSIF v_intelligence = 3 THEN
        ch_score := ch_score + (random() * 30)::int;
      END IF;

      IF ch_score > ch_best_score THEN
        ch_best_score := ch_score;
        ch_best_from := chain_from_v;
        ch_best_to := ch_nidx;
        ch_best_cap := ch_cur_cap;
      END IF;
    END LOOP;

    IF ch_best_from IS NOT NULL THEN
      PERFORM public._fanorona_play_by_slot(_game_id,
        jsonb_build_object('from', ch_best_from, 'to', ch_best_to, 'captured', ch_best_cap, 'chain', false),
        bot_slot
      );
    ELSE
      PERFORM public._fanorona_play_by_slot(_game_id, jsonb_build_object('pass', true), bot_slot);
    END IF;
    RETURN;
  END IF;

  -- NORMAL MODE: evaluate all moves, pick the best one
  has_capture := public._fanorona_player_can_capture(board, bot_color, v_cols, v_rows);

  FOR i IN 0..(v_cols * v_rows - 1) LOOP
    IF (board->i)::int <> bot_color THEN CONTINUE; END IF;
    r := i / v_cols; c := i % v_cols;
    is_strong := ((r + c) % 2 = 0);

    FOR dr, dc IN SELECT a,b FROM (VALUES
      (-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)
    ) v(a,b) LOOP
      IF NOT is_strong AND (dr <> 0 AND dc <> 0) THEN CONTINUE; END IF;
      nr := r + dr; nc := c + dc;
      IF nr < 0 OR nr >= v_rows OR nc < 0 OR nc >= v_cols THEN CONTINUE; END IF;
      nidx := nr * v_cols + nc;
      IF (board->nidx)::int <> 0 THEN CONTINUE; END IF;

      lists := public._fanorona_capture_lists(board, bot_color, i, nidx, v_cols, v_rows);
      cap_count := GREATEST(
        jsonb_array_length(lists->'approach'),
        jsonb_array_length(lists->'withdrawal')
      );

      IF has_capture AND COALESCE(g.mandatory_capture, true) AND cap_count = 0 THEN
        CONTINUE;
      END IF;

      -- Use cur_cap (NOT best_cap) to avoid corrupting the best
      IF cap_count > 0 THEN
        IF jsonb_array_length(lists->'approach') >= jsonb_array_length(lists->'withdrawal') THEN
          cur_cap := lists->'approach';
        ELSE
          cur_cap := lists->'withdrawal';
        END IF;
      ELSE
        cur_cap := '[]'::jsonb;
      END IF;

      score := cap_count * 100 + (v_cols - abs(c - v_cols / 2)) + (v_rows - abs(r - v_rows / 2));

      sim_board := board;
      sim_board := jsonb_set(sim_board, ARRAY[i::text], '0'::jsonb);
      sim_board := jsonb_set(sim_board, ARRAY[nidx::text], to_jsonb(bot_color));
      IF cap_count > 0 THEN
        FOR j IN 0..jsonb_array_length(cur_cap) - 1 LOOP
          sim_board := jsonb_set(sim_board, ARRAY[((cur_cap->j)::int)::text], '0'::jsonb);
        END LOOP;
      END IF;

      IF v_intelligence <= 2 THEN
        score := score + (random() * 50)::int;
      ELSIF v_intelligence = 3 THEN
        score := score + (random() * 20)::int;
      ELSIF v_intelligence = 4 THEN
        IF cap_count > 0 THEN
          sim_can_chain := public._fanorona_piece_can_capture(
            sim_board, bot_color, nidx, '[]'::jsonb,
            public._fanorona_axis(dr, dc), v_cols, v_rows
          );
          IF sim_can_chain THEN
            score := score + 150;
          END IF;
        END IF;
        IF public._fanorona_player_can_capture(sim_board, opp_color, v_cols, v_rows) THEN
          score := score - 50;
        END IF;
      ELSE
        -- Intelligence 5 (Master)
        IF cap_count > 0 THEN
          sim_can_chain := public._fanorona_piece_can_capture(
            sim_board, bot_color, nidx, '[]'::jsonb,
            public._fanorona_axis(dr, dc), v_cols, v_rows
          );
          IF sim_can_chain THEN
            score := score + 200;
          END IF;
        END IF;

        opp_best_cap := 0;
        FOR opp_i IN 0..(v_cols * v_rows - 1) LOOP
          IF (sim_board->opp_i)::int <> opp_color THEN CONTINUE; END IF;
          opp_r := opp_i / v_cols; opp_c := opp_i % v_cols;
          FOR opp_dr, opp_dc IN SELECT a,b FROM (VALUES
            (-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)
          ) v(a,b) LOOP
            IF ((opp_r + opp_c) % 2 <> 0) AND (opp_dr <> 0 AND opp_dc <> 0) THEN CONTINUE; END IF;
            opp_nr := opp_r + opp_dr; opp_nc := opp_c + opp_dc;
            IF opp_nr < 0 OR opp_nr >= v_rows OR opp_nc < 0 OR opp_nc >= v_cols THEN CONTINUE; END IF;
            opp_nidx := opp_nr * v_cols + opp_nc;
            IF (sim_board->opp_nidx)::int <> 0 THEN CONTINUE; END IF;
            opp_lists := public._fanorona_capture_lists(sim_board, opp_color, opp_i, opp_nidx, v_cols, v_rows);
            opp_cap := GREATEST(
              jsonb_array_length(opp_lists->'approach'),
              jsonb_array_length(opp_lists->'withdrawal')
            );
            IF opp_cap > opp_best_cap THEN opp_best_cap := opp_cap; END IF;
          END LOOP;
        END LOOP;
        score := score - opp_best_cap * 80;
      END IF;

      IF score > best_score THEN
        best_score := score;
        best_from := i;
        best_to := nidx;
        best_cap := cur_cap;
      END IF;
    END LOOP;
  END LOOP;

  IF best_from IS NULL THEN
    PERFORM public._fanorona_play_by_slot(_game_id, jsonb_build_object('pass', true), bot_slot);
  ELSE
    PERFORM public._fanorona_play_by_slot(_game_id,
      jsonb_build_object('from', best_from, 'to', best_to, 'captured', best_cap, 'chain', false),
      bot_slot
    );
  END IF;
END $function$;
