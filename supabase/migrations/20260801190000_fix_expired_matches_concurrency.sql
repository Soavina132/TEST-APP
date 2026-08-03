-- ============================================================
-- FIX BUG CRITIQUE: _t_handle_expired_matches lance tous les matches
-- sans respecter max_concurrent_matches ni le v_busy check
-- ============================================================

CREATE OR REPLACE FUNCTION public._t_handle_expired_matches(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  m record;
  v_ready_slot int;
  v_winner uuid;
  v_game text;
  v_table text;
  v_busy uuid[];
  v_live int;
  v_max int;
BEGIN
  SELECT game_slug INTO v_game FROM public.tournaments WHERE id = _tid;
  v_table := CASE WHEN v_game = 'ludo' THEN 'ludo_games' ELSE 'domino_games' END;

  -- 1) Gérer les matches en cours expirés (deadline dépassée)
  FOR m IN SELECT * FROM public.tournament_matches
            WHERE tournament_id = _tid
              AND status = 'running'
              AND deadline_at IS NOT NULL
              AND deadline_at < now()
              AND game_id IS NOT NULL LOOP
    BEGIN
      EXECUTE format('SELECT status FROM public.%I WHERE id = $1', v_table)
        INTO v_game USING m.game_id;

      IF v_game = 'open' THEN
        IF m.tournament_id IN (SELECT id FROM public.tournaments WHERE game_slug = 'ludo') THEN
          SELECT slot INTO v_ready_slot FROM public.ludo_participants
           WHERE game_id = m.game_id AND (ready OR is_bot) ORDER BY slot LIMIT 1;
        ELSE
          SELECT slot INTO v_ready_slot FROM public.domino_participants
           WHERE game_id = m.game_id AND (ready OR is_bot) ORDER BY slot LIMIT 1;
        END IF;

        v_winner := m.entrant_ids[COALESCE(v_ready_slot, 0) + 1];

        IF m.tournament_id IN (SELECT id FROM public.tournaments WHERE game_slug = 'ludo') THEN
          UPDATE public.ludo_games SET status = 'cancelled', finished_at = now()
           WHERE id = m.game_id;
        ELSE
          UPDATE public.domino_games SET status = 'cancelled', finished_at = now()
           WHERE id = m.game_id;
        END IF;

        PERFORM public._t_match_finish(m.id, v_winner);
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;

  -- 2) Relancer les matches scheduled SANS game_id
  --    MAIS avec les mêmes checks de concurrence que le moteur
  SELECT max_concurrent_matches INTO v_max FROM public.tournaments WHERE id = _tid;
  
  SELECT count(*) INTO v_live FROM public.tournament_matches
   WHERE tournament_id = _tid AND status = 'running';
  
  SELECT COALESCE(array_agg(x), ARRAY[]::uuid[]) INTO v_busy FROM (
    SELECT unnest(entrant_ids) x FROM public.tournament_matches
     WHERE tournament_id = _tid AND status = 'running') s;

  FOR m IN SELECT * FROM public.tournament_matches
            WHERE tournament_id = _tid
              AND status = 'scheduled'
              AND game_id IS NULL
            ORDER BY round, match_no LOOP
    EXIT WHEN v_live >= v_max;
    CONTINUE WHEN m.entrant_ids && v_busy;
    PERFORM public._t_launch_match(m.id);
    v_busy := v_busy || m.entrant_ids;
    v_live := v_live + 1;
  END LOOP;
END $$;
