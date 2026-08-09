-- ═══════════════════════════════════════════════════════════════════════
-- FIX: Domino tournament now supports "par point" (points-based scoring)
--   _t_launch_match was hardcoding target_score=0 for domino games,
--   meaning every domino tournament match was single-round (elimination).
--   Now it passes the tournament's target_score when domino_scoring='points'.
-- ═══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._t_launch_match(_match_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  m public.tournament_matches%ROWTYPE;
  t public.tournaments%ROWTYPE;
  v_host uuid; v_gid uuid; v_slot int := 0; e record; v_n int;
  v_colors text[] := ARRAY['red','blue','green','yellow'];
  v_link text;
  v_target int;
  v_rule text;
BEGIN
  SELECT * INTO m FROM public.tournament_matches WHERE id = _match_id FOR UPDATE;
  IF m.id IS NULL OR m.status <> 'scheduled' THEN RETURN; END IF;
  SELECT * INTO t FROM public.tournaments WHERE id = m.tournament_id;
  v_n := array_length(m.entrant_ids, 1);

  IF t.is_simulation THEN
    UPDATE public.tournament_matches
       SET status = 'running', game_id = NULL, started_at = now(),
           deadline_at = now() + make_interval(mins => t.lobby_minutes)
     WHERE id = _match_id;
    RETURN;
  END IF;

  SELECT user_id INTO v_host FROM public.tournament_entrants
   WHERE id = ANY(m.entrant_ids) AND user_id IS NOT NULL LIMIT 1;
  v_host := COALESCE(v_host, t.created_by);
  IF v_host IS NULL THEN RETURN; END IF;

  IF t.game_slug = 'ludo' THEN
    INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, is_private, mode, status, ready_deadline, auto_move)
      VALUES (v_host, v_n, 0, 0, 0, TRUE, 'classic', 'open', now() + make_interval(mins => t.lobby_minutes), TRUE)
      RETURNING id INTO v_gid;
    FOR e IN SELECT * FROM public.tournament_entrants WHERE id = ANY(m.entrant_ids)
             ORDER BY array_position(m.entrant_ids, id) LOOP
      INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name, is_bot, bot_name, ready)
        VALUES (v_gid, e.user_id, v_slot, v_colors[v_slot+1], e.display_name, e.is_bot,
                CASE WHEN e.is_bot THEN e.display_name END, e.is_bot);
      v_slot := v_slot + 1;
    END LOOP;
    v_link := '/jeux/ludo/' || v_gid::text;
  ELSE
    -- ═══ Domino: use tournament's target_score based on scoring mode ═══
    -- domino_scoring = 'points'  → multi-round, play to target_score
    -- domino_scoring = 'elimination' (or anything else) → single round
    v_target := CASE WHEN t.domino_scoring = 'points' THEN COALESCE(t.target_score, 100) ELSE 0 END;
    v_rule := COALESCE(NULLIF(t.domino_scoring, ''), 'libre');
    -- If domino_scoring is 'points' or 'elimination', use 'libre' as the first tile rule
    -- (domino_scoring controls scoring mode, not tile rules)
    IF v_rule IN ('points', 'elimination') THEN v_rule := 'libre'; END IF;

    INSERT INTO public.domino_games(host_id, max_players, stake, pot, commission_pct, is_private, mode, status, target_score, first_tile_rule)
      VALUES (v_host, v_n, 0, 0, 0, TRUE, 'classic', 'open', v_target, v_rule)
      RETURNING id INTO v_gid;
    FOR e IN SELECT * FROM public.tournament_entrants WHERE id = ANY(m.entrant_ids)
             ORDER BY array_position(m.entrant_ids, id) LOOP
      INSERT INTO public.domino_participants(game_id, user_id, slot, display_name, is_bot, bot_name, ready)
        VALUES (v_gid, e.user_id, v_slot, e.display_name, e.is_bot,
                CASE WHEN e.is_bot THEN e.display_name END, e.is_bot);
      v_slot := v_slot + 1;
    END LOOP;
    v_link := '/jeux/domino/' || v_gid::text;
  END IF;

  UPDATE public.tournament_matches
     SET status = 'running', game_id = v_gid, started_at = now(),
         deadline_at = now() + make_interval(mins => t.lobby_minutes)
   WHERE id = _match_id;

  FOR e IN SELECT id FROM public.tournament_entrants WHERE id = ANY(m.entrant_ids) LOOP
    PERFORM public._t_notify(e.id, '🎮 Votre match est prêt',
      'Rejoignez la table maintenant, vous avez ' || t.lobby_minutes || ' minutes.',
      v_link);
  END LOOP;
END;
$$;
