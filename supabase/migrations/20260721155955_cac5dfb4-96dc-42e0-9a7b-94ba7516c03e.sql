
CREATE OR REPLACE FUNCTION public._tournament_build_round(_tid uuid, _round integer, _player_ids uuid[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_t public.tournaments%ROWTYPE;
  v_size integer;
  v_idx integer := 0;
  v_players uuid[];
  v_ordered uuid[];
  v_total integer;
  v_i integer;
  v_remaining integer;
BEGIN
  SELECT * INTO v_t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  v_size := GREATEST(COALESCE(v_t.players_per_match, 2), 2);
  v_ordered := public._tournament_order_players(_player_ids, COALESCE(v_t.bye_strategy,'random'));
  v_total := COALESCE(array_length(v_ordered, 1), 0);

  IF v_total <= 1 THEN
    IF v_total = 1 THEN
      INSERT INTO public.tournament_matches(tournament_id, round, match_index, player_ids, status, winner_id, finished_at, is_bye)
        VALUES (_tid, _round, 0, v_ordered, 'finished', v_ordered[1], now(), true);
    END IF;
    RETURN;
  END IF;

  v_i := 1;
  WHILE v_i <= v_total LOOP
    v_remaining := v_total - v_i + 1;

    -- 1v1 mode: 3 restants -> un unique groupe de 3 (1 seul qualifié)
    IF v_size = 2 AND v_remaining = 3 THEN
      v_players := v_ordered[v_i : v_total];
      INSERT INTO public.tournament_matches(tournament_id, round, match_index, player_ids, status, is_bye)
        VALUES (_tid, _round, v_idx, v_players, 'pending', false);
      v_idx := v_idx + 1;
      EXIT;
    END IF;

    -- Groupes >=3 avec (v_size+1) restants -> split (v_size-1) + 2
    IF v_remaining = v_size + 1 AND v_size >= 3 THEN
      v_players := v_ordered[v_i : v_i + v_size - 2];
      INSERT INTO public.tournament_matches(tournament_id, round, match_index, player_ids, status, is_bye)
        VALUES (_tid, _round, v_idx, v_players, 'pending', false);
      v_idx := v_idx + 1;
      v_i := v_i + v_size - 1;
      v_players := v_ordered[v_i : v_total];
      INSERT INTO public.tournament_matches(tournament_id, round, match_index, player_ids, status, is_bye)
        VALUES (_tid, _round, v_idx, v_players, 'pending', false);
      v_idx := v_idx + 1;
      EXIT;
    END IF;

    v_players := v_ordered[v_i : LEAST(v_i + v_size - 1, v_total)];
    INSERT INTO public.tournament_matches(tournament_id, round, match_index, player_ids, status, is_bye)
      VALUES (_tid, _round, v_idx, v_players, 'pending', false);
    v_idx := v_idx + 1;
    v_i := v_i + v_size;
  END LOOP;
END $function$;
