-- Améliorer le bot Fanorona : moins robotique, plus stratégique
-- 1. Ajouter de l'aléatoire parmi les coups ayant le même nombre de captures
-- 2. Privilégier les captures en approche (plus agressif)
-- 3. Parfois jouer un coup non-optimal pour paraître plus humain

CREATE OR REPLACE FUNCTION public.fanorona_bot_play(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  g record;
  st jsonb; board jsonb;
  my_slot int; my_color int;
  v_cols int; v_rows int;
  is_bot boolean;
  i int; r int; c int; dr int; dc int; nr int; nc int; nidx int;
  is_strong boolean;
  lists jsonb;
  best_from int := -1; best_to int := -1; best_cap jsonb := '[]'::jsonb;
  best_count int := -1;
  chain_from_v int;
  visited jsonb; last_axis text; axis text;
  move_count int;
  cap_count int;
  first_move boolean;
  choose_cap jsonb;
  -- Nouveau : collecter tous les coups candidats
  candidates jsonb := '[]'::jsonb;
  cand_from int; cand_to int; cand_cap jsonb; cand_count int; cand_type text;
  rand_idx int;
  v_seed float;
  v_rand float;
  chosen jsonb;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

  my_slot := g.current_turn;
  SELECT COALESCE(fp.is_bot, false) INTO is_bot FROM public.fanorona_participants fp
    WHERE fp.game_id = _game_id AND fp.slot = my_slot;
  IF NOT COALESCE(is_bot, false) THEN RETURN; END IF;

  st := g.state; board := st -> 'board';
  v_cols := COALESCE(g.cols, 9); v_rows := COALESCE(g.rows, 5);
  my_color := CASE WHEN my_slot = 0 THEN 1 ELSE 2 END;
  move_count := COALESCE((st->>'move_count')::int, 0);
  visited := COALESCE(st->'visited', '[]'::jsonb);
  last_axis := NULLIF(st->>'last_axis', '');
  chain_from_v := CASE WHEN st->'chain_from' IS NULL OR st->'chain_from' = 'null'::jsonb
                       THEN NULL ELSE (st->>'chain_from')::int END;
  first_move := (move_count = 0);

  -- Collecter TOUS les coups possibles avec leurs captures
  FOR i IN 0..(v_cols * v_rows - 1) LOOP
    IF chain_from_v IS NOT NULL AND i <> chain_from_v THEN CONTINUE; END IF;
    IF (board->i)::int <> my_color THEN CONTINUE; END IF;
    r := i / v_cols; c := i % v_cols;
    is_strong := ((r + c) % 2 = 0);
    FOR dr, dc IN
      SELECT a, b FROM (VALUES (-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)) v(a,b)
    LOOP
      IF NOT is_strong AND (dr <> 0 AND dc <> 0) THEN CONTINUE; END IF;
      nr := r + dr; nc := c + dc;
      IF nr < 0 OR nr >= v_rows OR nc < 0 OR nc >= v_cols THEN CONTINUE; END IF;
      nidx := nr * v_cols + nc;
      IF (board->nidx)::int <> 0 THEN CONTINUE; END IF;
      IF chain_from_v IS NOT NULL AND visited @> to_jsonb(nidx) THEN CONTINUE; END IF;
      axis := public._fanorona_axis(dr, dc);
      IF chain_from_v IS NOT NULL AND last_axis IS NOT NULL AND axis = last_axis THEN CONTINUE; END IF;

      lists := public._fanorona_capture_lists(board, my_color, i, nidx, v_cols, v_rows);
      choose_cap := NULL;
      cand_type := 'none';
      IF jsonb_array_length(lists->'approach') > 0 THEN
        choose_cap := lists->'approach';
        cand_type := 'approach';
      END IF;
      IF NOT first_move AND jsonb_array_length(lists->'withdrawal') > COALESCE(jsonb_array_length(choose_cap),0) THEN
        choose_cap := lists->'withdrawal';
        cand_type := 'withdrawal';
      END IF;

      cap_count := COALESCE(jsonb_array_length(choose_cap), 0);
      
      -- Ajouter ce coup aux candidats
      candidates := candidates || jsonb_build_array(jsonb_build_object(
        'from', i, 'to', nidx, 'captured', COALESCE(choose_cap, '[]'::jsonb),
        'count', cap_count, 'type', cand_type
      ));
      
      IF cap_count > best_count THEN
        best_count := cap_count;
        best_from := i; best_to := nidx;
        best_cap := COALESCE(choose_cap, '[]'::jsonb);
      END IF;
    END LOOP;
  END LOOP;

  IF jsonb_array_length(candidates) = 0 THEN
    PERFORM public.fanorona_play_as_bot(_game_id, jsonb_build_object('pass', true));
    RETURN;
  END IF;

  -- Si on est en chaîne et que le meilleur coup n'a 0 capture, passer
  IF chain_from_v IS NOT NULL AND best_count <= 0 THEN
    PERFORM public.fanorona_play_as_bot(_game_id, jsonb_build_object('pass', true));
    RETURN;
  END IF;

  -- Stratégie : 
  -- 70% du temps : jouer le meilleur coup (capture max)
  -- 30% du temps : jouer un coup parmi les candidats avec captures > 0 (variété)
  -- Si aucun coup n'a de capture : choisir aléatoirement parmi tous les coups valides
  v_seed := random();
  
  IF best_count > 0 THEN
    IF v_seed < 0.7 THEN
      -- Jouer le meilleur coup
      PERFORM public.fanorona_play_as_bot(_game_id,
        jsonb_build_object('from', best_from, 'to', best_to, 'captured', best_cap));
      RETURN;
    ELSE
      -- Choisir aléatoirement parmi les coups avec captures
      DECLARE
        cap_candidates jsonb := '[]'::jsonb;
        idx int;
      BEGIN
        FOR idx IN 0..(jsonb_array_length(candidates) - 1) LOOP
          IF (candidates->idx->>'count')::int > 0 THEN
            cap_candidates := cap_candidates || jsonb_build_array(candidates->idx);
          END IF;
        END LOOP;
        IF jsonb_array_length(cap_candidates) > 0 THEN
          rand_idx := floor(random() * jsonb_array_length(cap_candidates))::int;
          chosen := cap_candidates->rand_idx;
          PERFORM public.fanorona_play_as_bot(_game_id,
            jsonb_build_object('from', (chosen->>'from')::int, 'to', (chosen->>'to')::int, 'captured', chosen->'captured'));
          RETURN;
        END IF;
      END;
      -- Fallback au meilleur
      PERFORM public.fanorona_play_as_bot(_game_id,
        jsonb_build_object('from', best_from, 'to', best_to, 'captured', best_cap));
      RETURN;
    END IF;
  ELSE
    -- Aucune capture : choisir aléatoirement parmi tous les coups valides
    -- 80% du temps un coup aléatoire, 20% le premier coup (pour être moins prévisible)
    v_rand := random();
    IF v_rand < 0.8 AND jsonb_array_length(candidates) > 1 THEN
      rand_idx := floor(random() * jsonb_array_length(candidates))::int;
      chosen := candidates->rand_idx;
      PERFORM public.fanorona_play_as_bot(_game_id,
        jsonb_build_object('from', (chosen->>'from')::int, 'to', (chosen->>'to')::int, 'captured', chosen->'captured'));
      RETURN;
    ELSE
      -- Premier coup valide
      chosen := candidates->0;
      PERFORM public.fanorona_play_as_bot(_game_id,
        jsonb_build_object('from', (chosen->>'from')::int, 'to', (chosen->>'to')::int, 'captured', chosen->'captured'));
      RETURN;
    END IF;
  END IF;
END $$;
GRANT EXECUTE ON FUNCTION public.fanorona_bot_play(uuid) TO authenticated;
