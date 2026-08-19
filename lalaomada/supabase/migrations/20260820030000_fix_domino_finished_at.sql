-- ═════════════════════════════════════════════════════════════════
-- FIX: Domino — finished_at manquant dans _domino_end_round
--
-- Quand un joueur atteint le target_score en mode points,
-- _domino_end_round met status='finished' mais oublie finished_at=now().
-- Le frontend ne détecte pas correctement la fin de partie.
-- ═════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._domino_end_round(_game_id uuid, _winner_slot int DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $$
DECLARE
  g record;
  st jsonb;
  v_scores jsonb;
  v_col_scores jsonb;
  v_slot int;
  v_pts int;
  v_total int := 0;
  v_rounds int;
  v_winner_overall int;
  v_pass_count int;
  v_target int;
  v_mode text;
  v_reveal      interval := interval '2.5 seconds';
  v_break_total interval := interval '7 seconds';
  v_part record;
  v_all_blocked boolean := false;
  v_lowest int;
  v_lowest_slot int;
  v_tie_count int;
  v_key text;
  v_winner_uid text := null;
  v_round_score int := 0;
  v_hand_pips jsonb := '{}'::jsonb;
  v_final_hands jsonb := '{}'::jsonb;
  v_hand jsonb;
  v_pips int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;

  st := g.state;
  v_mode := COALESCE(g.mode, 'classic');
  v_target := COALESCE(g.target_score, 0);

  v_pass_count := COALESCE(NULLIF(st->>'passes','')::int, 0);
  IF v_pass_count >= (SELECT count(*) FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false) THEN
    v_all_blocked := true;
  END IF;

  v_scores := COALESCE(st->'round_scores', '{}'::jsonb);
  v_col_scores := COALESCE(g.scores, '{}'::jsonb);

  FOR v_part IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
    v_key := COALESCE(v_part.user_id::text, 'bot_'||v_part.slot::text);
    v_hand := st->'hands'->v_part.slot::text;
    IF v_hand IS NOT NULL THEN
      SELECT COALESCE(sum((tile->>0)::int + (tile->>1)::int), 0) INTO v_pips
        FROM jsonb_array_elements(v_hand) AS tile;
    ELSE
      v_pips := 0;
    END IF;
    v_hand_pips := v_hand_pips || jsonb_build_object(v_key, v_pips);
    v_final_hands := v_final_hands || jsonb_build_object(v_key, COALESCE(v_hand, '[]'::jsonb));
    v_total := v_total + v_pips;
  END LOOP;

  IF v_all_blocked AND _winner_slot IS NULL THEN
    v_lowest := 999999;
    v_lowest_slot := 0;
    v_tie_count := 0;
    FOR v_part IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
      v_key := COALESCE(v_part.user_id::text, 'bot_'||v_part.slot::text);
      v_pips := COALESCE((v_hand_pips->>v_key)::int, 0);
      IF v_pips < v_lowest THEN
        v_lowest := v_pips;
        v_lowest_slot := v_part.slot;
        v_tie_count := 1;
      ELSIF v_pips = v_lowest THEN
        v_tie_count := v_tie_count + 1;
      END IF;
    END LOOP;
    IF v_tie_count > 1 THEN
      _winner_slot := NULL;
    ELSE
      _winner_slot := v_lowest_slot;
    END IF;
  END IF;

  IF _winner_slot IS NOT NULL THEN
    SELECT COALESCE(user_id::text, 'bot_'||slot::text) INTO v_key
      FROM public.domino_participants WHERE game_id = _game_id AND slot = _winner_slot;
    v_winner_uid := v_key;
    v_round_score := GREATEST(0, v_total - COALESCE((v_hand_pips->>v_key)::int, 0));
    SELECT COALESCE((v_scores->>_winner_slot::text)::int, 0) + v_round_score INTO v_pts;
    v_scores := jsonb_set(v_scores, ARRAY[_winner_slot::text], to_jsonb(v_pts), true);
    SELECT COALESCE((v_col_scores->>v_key)::int, 0) + v_round_score INTO v_pts;
    v_col_scores := jsonb_set(v_col_scores, ARRAY[v_key], to_jsonb(v_pts), true);
  END IF;

  st := jsonb_set(st, '{last_round}', jsonb_build_object(
    'winner_uid', v_winner_uid,
    'winner_slot', _winner_slot,
    'round_score', v_round_score,
    'hand_pips', v_hand_pips,
    'final_hands', v_final_hands,
    'blocked', v_all_blocked,
    'tie', (v_tie_count > 1),
    'round', COALESCE(NULLIF(st->>'round','')::int, 0)
  ), true);

  v_winner_overall := -1;
  IF v_mode = 'points' AND v_target > 0 THEN
    FOR v_slot IN SELECT DISTINCT (jsonb_object_keys(v_scores))::int LOOP
      IF (v_scores->>v_slot::text)::int >= v_target THEN
        v_winner_overall := v_slot;
        EXIT;
      END IF;
    END LOOP;
  ELSE
    v_winner_overall := COALESCE(_winner_slot, -1);
  END IF;

  IF v_winner_overall >= 0 THEN
    st := jsonb_set(st, '{phase}', '"reveal"'::jsonb);
    st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text), true);
    st := jsonb_set(st, '{winner_slot}', to_jsonb(v_winner_overall), true);
    st := jsonb_set(st, '{round_scores}', v_scores, true);
    SELECT user_id INTO v_key FROM public.domino_participants
      WHERE game_id = _game_id AND slot = v_winner_overall;
    UPDATE public.domino_games
       SET state = st, status = 'finished',
           winner_id = v_key::uuid,
           scores = v_col_scores,
           current_turn = -1, turn_deadline = NULL,
           finished_at = now()           -- FIX: was missing
     WHERE id = _game_id;
    PERFORM public._domino_payout(_game_id, v_winner_overall);
    RETURN;
  END IF;

  IF v_mode <> 'points' OR v_target <= 0 THEN
    st := jsonb_set(st, '{phase}', '"reveal"'::jsonb);
    st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text), true);
    st := jsonb_set(st, '{round_scores}', v_scores, true);
    UPDATE public.domino_games
       SET state = st, scores = v_col_scores,
           current_turn = -1, turn_deadline = NULL,
           finished_at = now()           -- FIX: was missing
     WHERE id = _game_id;
    PERFORM public._domino_finalize(_game_id, NULL);
    RETURN;
  END IF;

  v_rounds := COALESCE(NULLIF(st->>'round','')::int, 0) + 1;
  st := jsonb_set(st, '{round}', to_jsonb(v_rounds), true);
  st := jsonb_set(st, '{round_scores}', v_scores, true);
  st := jsonb_set(st, '{phase}', '"reveal"'::jsonb);
  st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text), true);
  st := jsonb_set(st, '{break_until}',  to_jsonb((now() + v_break_total)::text), true);
  UPDATE public.domino_games
     SET state = st, scores = v_col_scores,
         current_turn = -1, turn_deadline = NULL
   WHERE id = _game_id;
END $$;

REVOKE ALL ON FUNCTION public._domino_end_round(uuid, integer) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public._domino_end_round(uuid, integer) TO authenticated, service_role;
