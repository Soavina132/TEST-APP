-- ═══ FIX: domino result always null — _domino_end_round never set state.winner_slot ═══
-- When a domino game ends (player empties hand or game blocked), _domino_end_round
-- calls _domino_finalize without setting winner_slot in the game state.
-- The frontend reads game.state.winner_slot to display the winner.
-- When winner_slot is missing and winner_id is NULL (bot wins), the UI shows "Match nul".
--
-- This migration re-creates _domino_end_round with winner_slot set in state
-- before _domino_finalize is called.

CREATE OR REPLACE FUNCTION public._domino_end_round(_game_id uuid, _winner_slot integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  g record; st jsonb; winner_uid uuid; winner_key text; round_score int := 0;
  hand_pips jsonb := '{}'::jsonb; p record; pips int; v_scores jsonb; new_total int;
  v_final_hands jsonb := '{}'::jsonb; v_blocked boolean := false; winner_hand jsonb;
  v_reveal interval := interval '3 seconds';
  v_break_total interval := interval '10 seconds';
  p_key text;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN; END IF;
  SELECT user_id INTO winner_uid FROM public.domino_participants WHERE game_id = _game_id AND slot = _winner_slot;
  winner_key := COALESCE(winner_uid::text, 'bot_' || _winner_slot::text);
  st := g.state;
  winner_hand := st->'hands'->_winner_slot::text;
  v_blocked := COALESCE(jsonb_array_length(winner_hand), 0) > 0;

  -- ═══ FIX: Set winner_slot in state so the frontend can display the winner ═══
  st := jsonb_set(st, '{winner_slot}', to_jsonb(_winner_slot), true);

  FOR p IN SELECT slot, user_id FROM public.domino_participants WHERE game_id = _game_id LOOP
    p_key := COALESCE(p.user_id::text, 'bot_' || p.slot::text);
    pips := public._domino_hand_pips(st->'hands'->p.slot::text);
    hand_pips := hand_pips || jsonb_build_object(p_key, pips);
    v_final_hands := v_final_hands || jsonb_build_object(p_key, COALESCE(st->'hands'->p.slot::text, '[]'::jsonb));
    IF p.slot <> _winner_slot THEN round_score := round_score + pips; END IF;
  END LOOP;

  -- Classic mode: finalize immediately
  IF COALESCE(g.target_score,0) <= 0 THEN
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_finalize(_game_id, _winner_slot);
    RETURN;
  END IF;

  -- Points mode: update scores
  v_scores := COALESCE(g.scores, '{}'::jsonb);
  new_total := COALESCE((v_scores->>winner_key)::int, 0) + round_score;
  v_scores := jsonb_set(v_scores, ARRAY[winner_key], to_jsonb(new_total), true);
  UPDATE public.domino_games SET scores = v_scores WHERE id = _game_id;

  -- Target reached: finalize
  IF new_total >= g.target_score THEN
    st := jsonb_set(st, '{last_round}', jsonb_build_object('winner_uid', winner_uid, 'winner_slot', _winner_slot,
      'round_score', round_score, 'hand_pips', hand_pips, 'final_hands', v_final_hands, 'blocked', v_blocked, 'final', true));
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_finalize(_game_id, _winner_slot);
    RETURN;
  END IF;

  -- Target not reached: show reveal phase, then start next round
  st := jsonb_set(st, '{phase}', '"reveal"'::jsonb);
  st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text));
  st := jsonb_set(st, '{break_until}', to_jsonb((now() + v_break_total)::text));
  st := jsonb_set(st, '{last_round}', jsonb_build_object('winner_uid', winner_uid, 'winner_slot', _winner_slot,
    'round_score', round_score, 'hand_pips', hand_pips, 'final_hands', v_final_hands, 'blocked', v_blocked, 'final', false));
  st := jsonb_set(st, '{scores}', v_scores);
  UPDATE public.domino_games SET state = st, turn_deadline = NULL WHERE id = _game_id;
END;
$$;
