-- ═══════════════════════════════════════════════════════════════════════
-- FIX: Tournament finals — 4p Ludo (KO+pools), 2p Domino, placements
--
-- Rules:
-- 1. Ludo (ppm>=3, any format): final = 4 players (2 finalists + 2 R1 runner-ups), NO 3rd place
-- 2. Domino (ppm=2, any format): final = 2 players + 3rd place when winners_count >= 3
-- 3. Placements stored for pool + 4p final matches
-- ═══════════════════════════════════════════════════════════════════════

ALTER TABLE public.tournament_matches ADD COLUMN IF NOT EXISTS placements jsonb DEFAULT NULL;

-- _t_build_round: uses players_per_match for all formats (pools included)
CREATE OR REPLACE FUNCTION public._t_build_round(_tid uuid, _round integer, _ids uuid[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  t public.tournaments%ROWTYPE; n int; i int := 1; v_take int; v_rest int; v_mno int := 0;
  v_bye uuid; v_target uuid;
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid;
  n := COALESCE(array_length(_ids,1),0); IF n = 0 THEN RETURN; END IF;
  IF n = 1 THEN UPDATE public.tournaments SET champion_entrant_id = _ids[1] WHERE id = _tid; PERFORM public._t_finish(_tid); RETURN; END IF;
  v_bye := NULL;
  WHILE i <= n LOOP
    v_rest := n - i + 1; v_take := LEAST(t.players_per_match, v_rest);
    IF v_rest = 3 AND t.game_slug = 'ludo' AND t.players_per_match >= 3 THEN v_take := 3; END IF;
    IF v_rest = 1 AND v_take = 1 THEN v_bye := _ids[i]; i := i + 1; CONTINUE; END IF;
    IF v_rest - v_take = 1 AND t.players_per_match >= 3 THEN v_take := v_take + 1; END IF;
    v_mno := v_mno + 1;
    INSERT INTO public.tournament_matches(tournament_id, phase, round, match_no, entrant_ids)
      VALUES (_tid, 'final', _round, v_mno, (SELECT array_agg(_ids[j]) FROM generate_series(i, i + v_take - 1) j));
    i := i + v_take;
  END LOOP;
  IF v_bye IS NOT NULL THEN
    IF t.players_per_match >= 3 THEN
      SELECT id INTO v_target FROM public.tournament_matches WHERE tournament_id = _tid AND round = _round AND phase = 'final' AND array_length(entrant_ids, 1) = 2 ORDER BY random() LIMIT 1;
      IF v_target IS NOT NULL THEN UPDATE public.tournament_matches SET entrant_ids = entrant_ids || ARRAY[v_bye] WHERE id = v_target;
      ELSE
        SELECT id INTO v_target FROM public.tournament_matches WHERE tournament_id = _tid AND round = _round AND phase = 'final' AND array_length(entrant_ids, 1) < t.players_per_match ORDER BY array_length(entrant_ids, 1) ASC, random() LIMIT 1;
        IF v_target IS NOT NULL THEN UPDATE public.tournament_matches SET entrant_ids = entrant_ids || ARRAY[v_bye] WHERE id = v_target;
        ELSE v_mno := v_mno + 1; INSERT INTO public.tournament_matches(tournament_id, phase, round, match_no, entrant_ids) VALUES (_tid, 'final', _round, v_mno, ARRAY[v_bye]); END IF;
      END IF;
    ELSE v_mno := v_mno + 1; INSERT INTO public.tournament_matches(tournament_id, phase, round, match_no, entrant_ids) VALUES (_tid, 'final', _round, v_mno, ARRAY[v_bye]);
    END IF;
  END IF;
  UPDATE public.tournaments SET stage = 'finals', current_round = _round, current_round_started_at = now() WHERE id = _tid;
END;
$$;

-- _t_match_finish: placements for pool + 4p final
CREATE OR REPLACE FUNCTION public._t_match_finish(_match_id uuid, _winner uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  m public.tournament_matches%ROWTYPE; e uuid; v_placements jsonb := '{}'::jsonb; v_game_slug text; v_slot int; v_rank int; v_ppm int; v_pos int := 1;
BEGIN
  SELECT * INTO m FROM public.tournament_matches WHERE id = _match_id FOR UPDATE;
  IF m.id IS NULL OR m.status = 'finished' THEN RETURN; END IF;
  IF _winner IS NULL AND m.phase = 'pool' THEN UPDATE public.tournament_matches SET status = 'finished', winner_entrant_id = NULL, is_draw = true, finished_at = now() WHERE id = _match_id;
  ELSE UPDATE public.tournament_matches SET status = 'finished', winner_entrant_id = _winner, is_draw = false, finished_at = now() WHERE id = _match_id; END IF;
  IF (m.phase = 'pool' AND m.pool_id IS NOT NULL) OR (m.phase = 'final' AND array_length(m.entrant_ids, 1) > 2) THEN
    SELECT game_slug, players_per_match INTO v_game_slug, v_ppm FROM public.tournaments WHERE id = m.tournament_id;
    IF m.game_id IS NOT NULL AND v_game_slug = 'ludo' THEN
      FOR v_slot IN 0..array_length(m.entrant_ids, 1) - 1 LOOP
        SELECT COALESCE(finish_rank, 99) INTO v_rank FROM public.ludo_participants WHERE game_id = m.game_id AND slot = v_slot;
        v_placements := v_placements || jsonb_build_object(m.entrant_ids[v_slot + 1]::text, v_rank);
      END LOOP;
    ELSE
      v_pos := 2; FOREACH e IN ARRAY m.entrant_ids LOOP
        IF e = _winner THEN v_placements := v_placements || jsonb_build_object(e::text, 1);
        ELSE v_placements := v_placements || jsonb_build_object(e::text, v_pos); v_pos := v_pos + 1; END IF;
      END LOOP;
    END IF;
    UPDATE public.tournament_matches SET placements = v_placements WHERE id = _match_id;
  END IF;
  IF m.phase = 'pool' AND m.pool_id IS NOT NULL THEN PERFORM public._t_pool_recompute(m.pool_id);
  ELSE FOREACH e IN ARRAY m.entrant_ids LOOP
    IF m.phase = 'third_place' OR _winner IS NULL OR e <> _winner THEN
      UPDATE public.tournament_entrants SET status = 'eliminated', eliminated_round = m.round WHERE id = e AND status = 'active'; END IF;
  END LOOP; END IF;
  FOREACH e IN ARRAY m.entrant_ids LOOP
    IF _winner IS NOT NULL AND e = _winner THEN PERFORM public._t_notify(e, '✅ Match gagné', 'Vous passez à la suite du tournoi.', '/tournaments/' || m.tournament_id);
    ELSIF _winner IS NULL THEN PERFORM public._t_notify(e, '🤝 Match nul', 'Le match se termine sans vainqueur.', '/tournaments/' || m.tournament_id);
    ELSE PERFORM public._t_notify(e, '❌ Match perdu', 'Merci d''avoir participé.', '/tournaments/' || m.tournament_id); END IF;
  END LOOP;
END;
$$;

-- _t_next_round: Ludo 4p final (any format, no 3rd place); Domino 2p + 3rd place
CREATE OR REPLACE FUNCTION public._t_next_round(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  t public.tournaments%ROWTYPE; ids uuid[]; losers uuid[]; v_final_players uuid[];
  v_r1_match uuid; v_r1_placements jsonb; v_entrant uuid; v_rank int; v_runner_ups uuid[];
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF t.id IS NULL OR t.status <> 'running' THEN RETURN; END IF;
  SELECT array_agg(e.id ORDER BY random()) INTO ids FROM public.tournament_entrants e WHERE e.tournament_id = _tid AND e.status = 'active';
  IF COALESCE(array_length(ids,1),0) <= 1 THEN
    UPDATE public.tournaments SET champion_entrant_id = COALESCE(champion_entrant_id, ids[1]) WHERE id = _tid; PERFORM public._t_finish(_tid); RETURN;
  END IF;
  IF array_length(ids,1) = 2 AND NOT EXISTS (SELECT 1 FROM public.tournament_matches WHERE tournament_id = _tid AND phase = 'third_place') THEN
    IF t.players_per_match >= 3 THEN
      v_runner_ups := ARRAY[]::uuid[];
      FOR v_r1_match, v_r1_placements IN SELECT m.id, m.placements FROM public.tournament_matches m
        WHERE m.tournament_id = _tid AND m.phase = 'final' AND m.status = 'finished' AND m.round = t.current_round ORDER BY m.match_no
      LOOP
        FOR v_entrant, v_rank IN SELECT key::uuid, value::int FROM jsonb_each_text(v_r1_placements) LOOP
          IF v_rank = 2 THEN v_runner_ups := v_runner_ups || ARRAY[v_entrant]; END IF;
        END LOOP;
      END LOOP;
      IF COALESCE(array_length(v_runner_ups, 1), 0) >= 2 THEN
        v_runner_ups := v_runner_ups[1:2];
        UPDATE public.tournament_entrants SET status = 'active' WHERE id = ANY(v_runner_ups) AND status = 'eliminated';
        v_final_players := ids || v_runner_ups;
        INSERT INTO public.tournament_matches(tournament_id, phase, round, match_no, entrant_ids) VALUES (_tid, 'final', t.current_round + 1, 1, v_final_players);
        UPDATE public.tournaments SET stage = 'finals', current_round = t.current_round + 1, current_round_started_at = now() WHERE id = _tid; RETURN;
      END IF;
    ELSIF t.winners_count >= 3 THEN
      SELECT array_agg(x.eid) INTO losers FROM (
        SELECT unnest(m.entrant_ids) eid, m.winner_entrant_id w FROM public.tournament_matches m
         WHERE m.tournament_id = _tid AND m.phase = 'final' AND m.status = 'finished' AND m.round = t.current_round) x
       WHERE x.eid IS DISTINCT FROM x.w;
      IF COALESCE(array_length(losers,1),0) = 2 THEN
        UPDATE public.tournament_entrants SET status = 'active' WHERE id = ANY(losers) AND status = 'eliminated';
        INSERT INTO public.tournament_matches(tournament_id, phase, round, match_no, entrant_ids) VALUES (_tid, 'third_place', t.current_round + 1, 1, losers);
        INSERT INTO public.tournament_matches(tournament_id, phase, round, match_no, entrant_ids) VALUES (_tid, 'final', t.current_round + 1, 1, ids);
        UPDATE public.tournaments SET stage = 'finals', current_round = t.current_round + 1, current_round_started_at = now() WHERE id = _tid; RETURN;
      END IF;
    END IF;
  END IF;
  PERFORM public._t_build_round(_tid, t.current_round + 1, ids);
END;
$$;

-- _t_finish: uses placements for 4p Ludo final ranking (no 3rd place match)
CREATE OR REPLACE FUNCTION public._t_finish(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  t public.tournaments%ROWTYPE; v_net numeric; v_pcts numeric[]; r record; i int; v_amt numeric;
  v_final_loser uuid; v_tp_win uuid; v_tp_lose uuid; v_final_match_id uuid; v_final_placements jsonb; v_entrant uuid; v_rank int;
BEGIN
  SELECT * INTO t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF t.status IN ('finished','cancelled') THEN RETURN; END IF;
  SELECT m.winner_entrant_id INTO v_tp_win FROM public.tournament_matches m WHERE m.tournament_id = _tid AND m.phase = 'third_place' AND m.status = 'finished' LIMIT 1;
  IF v_tp_win IS NOT NULL THEN
    SELECT x.eid INTO v_tp_lose FROM (SELECT unnest(m.entrant_ids) eid FROM public.tournament_matches m WHERE m.tournament_id = _tid AND m.phase = 'third_place' AND m.status = 'finished') x WHERE x.eid IS DISTINCT FROM v_tp_win LIMIT 1;
    SELECT x.eid INTO v_final_loser FROM (SELECT unnest(m.entrant_ids) eid, m.winner_entrant_id w, m.round FROM public.tournament_matches m WHERE m.tournament_id = _tid AND m.phase = 'final' AND m.status = 'finished' AND t.champion_entrant_id = ANY(m.entrant_ids) ORDER BY m.round DESC LIMIT 4) x WHERE x.eid IS DISTINCT FROM t.champion_entrant_id LIMIT 1;
  ELSE
    SELECT id, placements INTO v_final_match_id, v_final_placements FROM public.tournament_matches WHERE tournament_id = _tid AND phase = 'final' AND status = 'finished' AND array_length(entrant_ids, 1) > 2 ORDER BY round DESC LIMIT 1;
    IF v_final_placements IS NOT NULL THEN
      FOR v_entrant, v_rank IN SELECT key::uuid, value::int FROM jsonb_each_text(v_final_placements) LOOP
        IF v_rank = 2 AND v_entrant <> t.champion_entrant_id THEN v_final_loser := v_entrant;
        ELSIF v_rank = 3 THEN v_tp_win := v_entrant;
        ELSIF v_rank = 4 THEN v_tp_lose := v_entrant; END IF;
      END LOOP;
    END IF;
    IF v_final_loser IS NULL THEN
      SELECT x.eid INTO v_final_loser FROM (SELECT unnest(m.entrant_ids) eid, m.winner_entrant_id w, m.round FROM public.tournament_matches m WHERE m.tournament_id = _tid AND m.phase = 'final' AND m.status = 'finished' AND t.champion_entrant_id = ANY(m.entrant_ids) ORDER BY m.round DESC LIMIT 4) x WHERE x.eid IS DISTINCT FROM t.champion_entrant_id LIMIT 1;
    END IF;
  END IF;
  WITH keyed AS (SELECT e.id, CASE WHEN e.id = t.champion_entrant_id THEN 0 WHEN e.id = v_final_loser THEN 1 WHEN e.id = v_tp_win THEN 2 WHEN e.id = v_tp_lose THEN 3 ELSE 10 END AS k, e.eliminated_round, e.created_at FROM public.tournament_entrants e WHERE e.tournament_id = _tid),
  ranked AS (SELECT id, row_number() OVER (ORDER BY k, eliminated_round DESC NULLS FIRST, created_at) AS rk FROM keyed)
  UPDATE public.tournament_entrants e SET final_rank = ranked.rk FROM ranked WHERE e.id = ranked.id;
  IF t.entry_fee_ar > 0 THEN v_net := round(t.prize_pool_ar * (100 - t.platform_pct) / 100) + t.admin_prize_pool_ar; ELSE v_net := t.admin_prize_pool_ar; END IF;
  v_pcts := ARRAY[t.prize_1_pct, t.prize_2_pct, t.prize_3_pct, COALESCE(t.prize_4_pct, 0)];
  FOR r IN SELECT * FROM public.tournament_entrants WHERE tournament_id = _tid AND final_rank IS NOT NULL AND final_rank <= t.winners_count ORDER BY final_rank LOOP
    i := r.final_rank; v_amt := round(v_net * COALESCE(v_pcts[i],0) / 100);
    IF v_amt > 0 AND r.user_id IS NOT NULL AND NOT r.is_bot AND NOT t.is_simulation THEN
      PERFORM public.credit_user_balance(r.user_id, v_amt, 'tournament_prize', _tid, 'Récompense tournoi: ' || t.name, jsonb_build_object('rank', i)); END IF;
    PERFORM public._t_notify(r.id, '🏆 Tournoi terminé', 'Vous terminez ' || i || 'e. Gain : ' || v_amt || ' Ar', '/tournaments/' || _tid);
  END LOOP;
  UPDATE public.tournaments SET status = 'finished', stage = 'done', finished_at = now(), rewards_paid_at = now(), platform_cut_ar = CASE WHEN entry_fee_ar > 0 THEN round(prize_pool_ar * platform_pct / 100) ELSE 0 END WHERE id = _tid;
END;
$$;
