-- ═══════════════════════════════════════════════════════════════════════
-- BYE FIX: Instead of auto-winning, merge the bye player into a random
-- 1v1 match to make it a 3-player match (Ludo only).
-- For Domino (2 players max), falls back to bye auto-win.
-- ═══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._t_build_round(_tid uuid, _round integer, _ids uuid[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  t public.tournaments%ROWTYPE;
  n int; i int := 1; v_take int; v_rest int; v_mno int := 0;
  v_bye uuid;
  v_target uuid;
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid;
  n := COALESCE(array_length(_ids,1),0);
  IF n = 0 THEN RETURN; END IF;

  IF n = 1 THEN
    UPDATE public.tournaments SET champion_entrant_id = _ids[1] WHERE id = _tid;
    PERFORM public._t_finish(_tid);
    RETURN;
  END IF;

  v_bye := NULL;

  WHILE i <= n LOOP
    v_rest := n - i + 1;
    v_take := LEAST(t.players_per_match, v_rest);

    -- 3 players left in Ludo -> table of 3 (no bye)
    IF v_rest = 3 AND t.game_slug = 'ludo' AND t.players_per_match >= 3 THEN
      v_take := 3;
    END IF;

    -- 1 player left (bye) -> save for later, don't create a 1-player match
    IF v_rest = 1 AND v_take = 1 THEN
      v_bye := _ids[i];
      i := i + 1;
      CONTINUE;
    END IF;

    -- Avoid leaving exactly 1 player after this match when possible
    IF v_rest - v_take = 1 AND t.players_per_match >= 3 THEN
      v_take := v_take + 1;
    END IF;

    v_mno := v_mno + 1;
    INSERT INTO public.tournament_matches(tournament_id, phase, round, match_no, entrant_ids)
      VALUES (_tid, 'final', _round, v_mno, (SELECT array_agg(_ids[j]) FROM generate_series(i, i + v_take - 1) j));
    i := i + v_take;
  END LOOP;

  -- ═══ Handle the bye player ═══
  IF v_bye IS NOT NULL THEN
    -- Strategy: find a random 1v1 match and add the bye player to make it 3 players
    -- This works for Ludo (3-4 players per match). For Domino (2 max), skip.
    IF t.players_per_match >= 3 THEN
      -- Find a random match with exactly 2 players (a 1v1)
      SELECT id INTO v_target FROM public.tournament_matches
       WHERE tournament_id = _tid AND round = _round AND phase = 'final'
         AND array_length(entrant_ids, 1) = 2
       ORDER BY random() LIMIT 1;

      IF v_target IS NOT NULL THEN
        -- Merge the bye player into this match -> 3-player match
        UPDATE public.tournament_matches
           SET entrant_ids = entrant_ids || ARRAY[v_bye]
         WHERE id = v_target;
      ELSE
        -- No 1v1 match found -> find any match with room
        SELECT id INTO v_target FROM public.tournament_matches
         WHERE tournament_id = _tid AND round = _round AND phase = 'final'
           AND array_length(entrant_ids, 1) < t.players_per_match
         ORDER BY array_length(entrant_ids, 1) ASC, random() LIMIT 1;

        IF v_target IS NOT NULL THEN
          UPDATE public.tournament_matches
             SET entrant_ids = entrant_ids || ARRAY[v_bye]
           WHERE id = v_target;
        ELSE
          -- All matches are full -> create a bye match (engine auto-finishes)
          v_mno := v_mno + 1;
          INSERT INTO public.tournament_matches(tournament_id, phase, round, match_no, entrant_ids)
            VALUES (_tid, 'final', _round, v_mno, ARRAY[v_bye]);
        END IF;
      END IF;
    ELSE
      -- Domino (2 players max) -> can't make 3-player matches, create bye
      v_mno := v_mno + 1;
      INSERT INTO public.tournament_matches(tournament_id, phase, round, match_no, entrant_ids)
        VALUES (_tid, 'final', _round, v_mno, ARRAY[v_bye]);
    END IF;
  END IF;

  UPDATE public.tournaments SET stage = 'finals', current_round = _round, current_round_started_at = now() WHERE id = _tid;
END;
$$;
