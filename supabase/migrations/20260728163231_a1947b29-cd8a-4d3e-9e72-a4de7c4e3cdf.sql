CREATE OR REPLACE FUNCTION public._domino_end_round(_game_id uuid, _winner_slot integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','extensions'
AS $function$
DECLARE
  g record;
  st jsonb;
  winner_uid uuid;
  round_score int := 0;
  hand_pips jsonb := '{}'::jsonb;
  v_final_hands jsonb := '{}'::jsonb;
  v_scores jsonb;
  new_total int;
  p record;
  pips int;
  winner_hand jsonb;
  v_blocked boolean;
  v_reveal      interval := interval '2 seconds';
  v_break_total interval := interval '10 seconds';
  v_current_round int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN; END IF;
  st := g.state;
  v_current_round := COALESCE((st->>'round')::int, 1);

  -- Bloquée (aucun gagnant possible) => match nul, nouvelle manche
  IF _winner_slot IS NULL THEN
    FOR p IN SELECT slot, user_id FROM public.domino_participants WHERE game_id = _game_id LOOP
      pips          := public._domino_hand_pips(st->'hands'->p.slot::text);
      hand_pips     := hand_pips     || jsonb_build_object(p.user_id::text, pips);
      v_final_hands := v_final_hands || jsonb_build_object(p.user_id::text, COALESCE(st->'hands'->p.slot::text, '[]'::jsonb));
    END LOOP;

    st := jsonb_set(st, '{phase}',        '"reveal"'::jsonb);
    st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text));
    st := jsonb_set(st, '{break_until}',  to_jsonb((now() + v_break_total)::text));
    st := jsonb_set(st, '{last_round}', jsonb_build_object(
      'winner_uid',  NULL::text,
      'round_score', 0,
      'hand_pips',   hand_pips,
      'final_hands', v_final_hands,
      'blocked',     true,
      'draw',        true,
      'final',       false,
      'round',       v_current_round
    ));
    st := jsonb_set(st, '{scores}', COALESCE(g.scores, '{}'::jsonb));
    UPDATE public.domino_games SET state = st, turn_deadline = NULL WHERE id = _game_id;
    RETURN;
  END IF;

  SELECT user_id INTO winner_uid FROM public.domino_participants WHERE game_id = _game_id AND slot = _winner_slot;

  winner_hand := st->'hands'->_winner_slot::text;
  v_blocked   := COALESCE(jsonb_array_length(winner_hand), 0) > 0;

  FOR p IN SELECT slot, user_id FROM public.domino_participants WHERE game_id = _game_id LOOP
    pips          := public._domino_hand_pips(st->'hands'->p.slot::text);
    hand_pips     := hand_pips     || jsonb_build_object(p.user_id::text, pips);
    v_final_hands := v_final_hands || jsonb_build_object(p.user_id::text, COALESCE(st->'hands'->p.slot::text, '[]'::jsonb));
    IF p.slot <> _winner_slot THEN round_score := round_score + pips; END IF;
  END LOOP;

  IF COALESCE(g.target_score, 0) <= 0 THEN
    PERFORM public._domino_finalize(_game_id, _winner_slot);
    RETURN;
  END IF;

  v_scores  := COALESCE(g.scores, '{}'::jsonb);
  new_total := COALESCE((v_scores->>winner_uid::text)::int, 0) + round_score;
  v_scores  := jsonb_set(v_scores, ARRAY[winner_uid::text], to_jsonb(new_total), true);
  UPDATE public.domino_games SET scores = v_scores WHERE id = _game_id;

  IF new_total >= g.target_score THEN
    st := jsonb_set(st, '{last_round}', jsonb_build_object(
      'winner_uid',  winner_uid,
      'round_score', round_score,
      'hand_pips',   hand_pips,
      'final_hands', v_final_hands,
      'blocked',     v_blocked,
      'final',       true,
      'round',       v_current_round
    ));
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_finalize(_game_id, _winner_slot);
    RETURN;
  END IF;

  st := jsonb_set(st, '{phase}',        '"reveal"'::jsonb);
  st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text));
  st := jsonb_set(st, '{break_until}',  to_jsonb((now() + v_break_total)::text));
  st := jsonb_set(st, '{last_round}', jsonb_build_object(
    'winner_uid',  winner_uid,
    'round_score', round_score,
    'hand_pips',   hand_pips,
    'final_hands', v_final_hands,
    'blocked',     v_blocked,
    'final',       false,
    'round',       v_current_round
  ));
  st := jsonb_set(st, '{scores}', v_scores);
  UPDATE public.domino_games SET state = st, turn_deadline = NULL WHERE id = _game_id;
END $function$;