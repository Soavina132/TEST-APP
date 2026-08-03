-- No more automatic qualifications: everyone must play at least one match.
-- If the tail leaves 1 lone player, merge them into the previous group.

CREATE OR REPLACE FUNCTION public._tournament_build_round(_tid uuid, _round integer, _player_ids uuid[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
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

  -- Edge case: a single participant overall -> declare champion (nothing to play).
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

    -- If exactly (v_size + 1) remain, split as (v_size - 1) + 2 so nobody is left alone.
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

    -- Normal slice of v_size (or the whole remainder if smaller and >= 2)
    v_players := v_ordered[v_i : LEAST(v_i + v_size - 1, v_total)];
    INSERT INTO public.tournament_matches(tournament_id, round, match_index, player_ids, status, is_bye)
      VALUES (_tid, _round, v_idx, v_players, 'pending', false);
    v_idx := v_idx + 1;
    v_i := v_i + v_size;
  END LOOP;
END $$;
