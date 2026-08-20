CREATE OR REPLACE FUNCTION public.domino_forfeit_internal(_game_id uuid, _part public.domino_participants)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $$
DECLARE
  g record;
  st jsonb;
  v_slot int;
  v_remaining int;
  v_last_slot int;
  v_next int;
  v_turn_seconds int;
  v_required int;
  v_board_empty boolean;
BEGIN
  v_slot := _part.slot;

  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;

  -- Marquer le joueur comme forfeit
  UPDATE public.domino_participants SET forfeited = true
    WHERE game_id = _game_id AND slot = v_slot;

  -- Vider sa main
  st := g.state;
  st := jsonb_set(st, ARRAY['hands', v_slot::text], '[]'::jsonb, true);

  -- Vérifier combien de joueurs actifs restent
  SELECT count(*) INTO v_remaining FROM public.domino_participants
    WHERE game_id = _game_id AND forfeited = false;

  IF v_remaining <= 1 THEN
    -- Partie terminée
    SELECT slot INTO v_last_slot FROM public.domino_participants
      WHERE game_id = _game_id AND forfeited = false
      ORDER BY slot LIMIT 1;
    IF v_last_slot IS NOT NULL THEN
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
      PERFORM public._domino_finalize(_game_id, v_last_slot);
    ELSE
      UPDATE public.domino_games SET status = 'cancelled', finished_at = now(), state = st WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;

  -- La partie continue : avancer le tour si c'était au joueur qui quitte
  SELECT COALESCE((SELECT turn_seconds FROM public.app_settings WHERE id = 1), 30) INTO v_turn_seconds;

  IF g.current_turn = v_slot THEN
    v_board_empty := jsonb_array_length(COALESCE(st->'board', '[]'::jsonb)) = 0;
    v_required := public._domino_required_starter_slot(_game_id, st);
    IF v_board_empty AND v_required IS NOT NULL THEN
      UPDATE public.domino_games SET state = st, current_turn = v_required,
        turn_deadline = now() + (v_turn_seconds || ' seconds')::interval
        WHERE id = _game_id;
    ELSE
      v_next := public._domino_next_playable_slot(_game_id, v_slot, st);
      IF v_next IS NULL THEN
        v_next := public._domino_lowest_pip_slot(_game_id, st);
        IF v_next IS NOT NULL THEN
          UPDATE public.domino_games SET state = st WHERE id = _game_id;
          PERFORM public._domino_end_round(_game_id, v_next);
        ELSE
          UPDATE public.domino_games SET state = st WHERE id = _game_id;
          PERFORM public._domino_end_round(_game_id, NULL);
        END IF;
      ELSE
        UPDATE public.domino_games SET state = st, current_turn = v_next,
          turn_deadline = now() + (v_turn_seconds || ' seconds')::interval
          WHERE id = _game_id;
      END IF;
    END IF;
  ELSE
    -- Pas son tour, juste mettre à jour le state
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
  END IF;
END $$;

REVOKE ALL ON FUNCTION public.domino_forfeit_internal(uuid, public.domino_participants) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.domino_forfeit_internal(uuid, public.domino_participants) TO authenticated, service_role;
