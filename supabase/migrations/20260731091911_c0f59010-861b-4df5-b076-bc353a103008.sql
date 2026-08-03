CREATE OR REPLACE FUNCTION public._t_draw_pools(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  t public.tournaments%ROWTYPE;
  ids uuid[]; pids uuid[];
  n int; pos int := 1; k int := 0; v_take int; v_rest int; v_pool uuid;
  a int; b int; v_mno int;
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid;
  SELECT array_agg(id ORDER BY random()) INTO ids
    FROM public.tournament_entrants WHERE tournament_id = _tid AND status = 'active';
  n := COALESCE(array_length(ids, 1), 0);
  IF n < 2 THEN RETURN; END IF;

  WHILE pos <= n LOOP
    v_rest := n - pos + 1;
    v_take := LEAST(t.pool_size, v_rest);
    IF v_rest - v_take = 1 THEN v_take := v_take + 1; END IF;
    v_take := LEAST(v_take, v_rest);
    pids := ids[pos : pos + v_take - 1];

    k := k + 1;
    INSERT INTO public.tournament_pools(tournament_id, label, status)
      VALUES (_tid, 'Poule ' || chr(64 + k), 'running') RETURNING id INTO v_pool;

    INSERT INTO public.tournament_pool_entrants(pool_id, entrant_id)
      SELECT v_pool, unnest(pids);

    IF t.players_per_match = 2 THEN
      v_mno := 0;
      FOR a IN 1 .. v_take - 1 LOOP
        FOR b IN a + 1 .. v_take LOOP
          v_mno := v_mno + 1;
          INSERT INTO public.tournament_matches(tournament_id, pool_id, phase, round, match_no, entrant_ids)
            VALUES (_tid, v_pool, 'pool', 1, v_mno, ARRAY[pids[a], pids[b]]);
        END LOOP;
      END LOOP;
    ELSE
      INSERT INTO public.tournament_matches(tournament_id, pool_id, phase, round, match_no, entrant_ids)
        VALUES (_tid, v_pool, 'pool', 1, k, pids);
    END IF;

    pos := pos + v_take;
  END LOOP;

  UPDATE public.tournaments SET stage = 'pools', current_round = 1 WHERE id = _tid;
END $$;