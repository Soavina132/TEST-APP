CREATE OR REPLACE FUNCTION public.game_player_status(_user_id uuid, _slug text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_playing boolean := false;
  v_pct int := 0;
  v_state jsonb;
  v_slot int;
  v_sum numeric := 0;
  v_count int := 0;
  v_pawn jsonb;
  v_board jsonb;
  v_ply int;
  v_my_color int;
  v_opp_color int;
  v_opp_remaining int := 0;
  i int;
BEGIN
  IF _slug = 'ludo' THEN
    SELECT g.state, lp.slot INTO v_state, v_slot
      FROM ludo_participants lp JOIN ludo_games g ON g.id = lp.game_id
      WHERE lp.user_id = _user_id AND g.status='playing' LIMIT 1;
    IF v_state IS NOT NULL THEN
      v_playing := true;
      FOR v_pawn IN SELECT * FROM jsonb_array_elements(COALESCE(v_state->'pawns'->v_slot::text, '[]'::jsonb))
      LOOP
        v_count := v_count + 1;
        IF v_pawn->>'s' = 'home' THEN v_sum := v_sum + 100;
        ELSIF v_pawn->>'s' = 'track' THEN v_sum := v_sum + LEAST(95, ((v_pawn->>'k')::int * 100.0) / 56);
        END IF;
      END LOOP;
      IF v_count > 0 THEN v_pct := ROUND(v_sum / v_count); END IF;
    END IF;
  ELSIF _slug = 'domino' THEN
    SELECT g.state INTO v_state FROM domino_participants dp JOIN domino_games g ON g.id=dp.game_id
      WHERE dp.user_id=_user_id AND g.status='playing' LIMIT 1;
    IF v_state IS NOT NULL THEN
      v_playing := true;
      v_pct := LEAST(99, (jsonb_array_length(COALESCE(v_state->'board','[]'::jsonb)) * 100) / 28);
    END IF;
  ELSIF _slug = 'fanorona' THEN
    SELECT g.state, fp.slot INTO v_state, v_slot
      FROM fanorona_participants fp JOIN fanorona_games g ON g.id=fp.game_id
      WHERE fp.user_id=_user_id AND g.status='playing' LIMIT 1;
    IF v_state IS NOT NULL THEN
      v_playing := true;
      v_my_color := CASE WHEN v_slot = 0 THEN 1 ELSE 2 END;
      v_opp_color := CASE WHEN v_my_color = 1 THEN 2 ELSE 1 END;
      v_board := COALESCE(v_state->'board', '[]'::jsonb);
      FOR i IN 0..jsonb_array_length(v_board)-1 LOOP
        IF (v_board->i)::int = v_opp_color THEN v_opp_remaining := v_opp_remaining + 1; END IF;
      END LOOP;
      v_pct := LEAST(99, ROUND(((22 - v_opp_remaining)::numeric * 100) / 22));
      IF v_pct < 0 THEN v_pct := 0; END IF;
    END IF;
  ELSIF _slug = 'chess' THEN
    SELECT ply FROM chess_games WHERE status='playing' AND (white_id=_user_id OR black_id=_user_id) LIMIT 1 INTO v_ply;
    IF v_ply IS NOT NULL THEN v_playing := true; v_pct := LEAST(99, (v_ply * 100) / 80); END IF;
  END IF;
  RETURN jsonb_build_object('playing', v_playing, 'percent', v_pct);
END $$;