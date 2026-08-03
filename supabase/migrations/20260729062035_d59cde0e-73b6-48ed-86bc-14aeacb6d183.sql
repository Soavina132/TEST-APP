CREATE OR REPLACE FUNCTION public._domino_end_round(_game_id uuid, _winner_slot int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  g record; st jsonb; winner_uid uuid; round_score int := 0;
  hand_pips jsonb := '{}'::jsonb; p record; pips int; p_key text;
  v_scores jsonb; new_total int; winner_key text;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN; END IF;

  SELECT user_id INTO winner_uid FROM public.domino_participants WHERE game_id = _game_id AND slot = _winner_slot;
  st := g.state;

  FOR p IN SELECT slot, user_id FROM public.domino_participants WHERE game_id = _game_id LOOP
    pips := public._domino_hand_pips(st->'hands'->p.slot::text);
    p_key := COALESCE(p.user_id::text, 'bot:'||p.slot);
    hand_pips := hand_pips || jsonb_build_object(p_key, pips);
    IF p.slot <> _winner_slot THEN round_score := round_score + pips; END IF;
  END LOOP;

  IF COALESCE(g.target_score,0) <= 0 THEN
    PERFORM public._domino_finalize(_game_id, _winner_slot);
    RETURN;
  END IF;

  winner_key := COALESCE(winner_uid::text, 'bot:'||_winner_slot);
  v_scores := COALESCE(g.scores, '{}'::jsonb);
  new_total := COALESCE((v_scores->>winner_key)::int, 0) + round_score;
  v_scores := jsonb_set(v_scores, ARRAY[winner_key], to_jsonb(new_total), true);

  UPDATE public.domino_games SET scores = v_scores WHERE id = _game_id;

  IF new_total >= g.target_score THEN
    st := jsonb_set(st, '{last_round}', jsonb_build_object(
      'winner_uid', winner_uid, 'round_score', round_score, 'hand_pips', hand_pips, 'final', true
    ));
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_finalize(_game_id, _winner_slot);
    RETURN;
  END IF;

  st := jsonb_set(st, '{phase}', '"break"'::jsonb);
  st := jsonb_set(st, '{break_until}', to_jsonb((now() + interval '10 seconds')::text));
  st := jsonb_set(st, '{last_round}', jsonb_build_object(
    'winner_uid', winner_uid, 'round_score', round_score, 'hand_pips', hand_pips, 'final', false
  ));
  st := jsonb_set(st, '{scores}', v_scores);
  UPDATE public.domino_games SET state = st, turn_deadline = NULL WHERE id = _game_id;
END $$;

-- Débloque les parties déjà figées : force un tick immédiat sur les parties bot en attente.
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT g.id FROM public.domino_games g
    WHERE g.status='playing'
      AND EXISTS (SELECT 1 FROM public.domino_participants p WHERE p.game_id=g.id AND p.is_bot=true AND p.forfeited=false)
  LOOP
    BEGIN PERFORM public._domino_autoplay_bots(r.id); EXCEPTION WHEN OTHERS THEN NULL; END;
  END LOOP;
END $$;

DROP TABLE IF EXISTS public._dbg_domino;