-- ═══════════════════════════════════════════════════════════════════════════
-- FIX: _ludo_check_game_over ne vérifiait jamais si un joueur avait tous
-- ses pions arrivés (s='finished'). Le jeu continuait indéfiniment même
-- après qu'un joueur ait gagné.
--
-- Ajout d'un check qui scanne l'état JSON des pions: si tous les pions
-- d'un slot sont 'finished', ce joueur gagne.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._ludo_check_game_over(_game_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_count INT;
  v_humans INT;
  v_winner UUID;
  g public.ludo_games%ROWTYPE;
  v_is_solo BOOLEAN;
  v_slot INT;
  v_pawns jsonb;
  v_pawn jsonb;
  v_all_finished BOOLEAN;
  v_finish_slot INT;
  v_team INT;
  v_team_all_finished BOOLEAN;
  v_mate_pawns jsonb;
  v_winner_user UUID;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN FALSE; END IF;

  SELECT count(*) INTO v_count
    FROM public.ludo_participants WHERE game_id=_game_id AND forfeited=FALSE;
  SELECT count(*) INTO v_humans
    FROM public.ludo_participants WHERE game_id=_game_id AND is_bot=FALSE AND forfeited=FALSE;

  v_is_solo := COALESCE(g.is_solo, FALSE) OR g.match_type = 'solo';

  -- ═══ NEW: Check if any player has ALL pawns finished ═══
  v_pawns := g.state->'pawns';
  IF v_pawns IS NOT NULL THEN
    v_finish_slot := -1;
    FOR v_slot IN 0..3 LOOP
      v_all_finished := TRUE;
      v_pawn := v_pawns->v_slot::text;
      IF v_pawn IS NULL THEN CONTINUE; END IF;
      -- Check each pawn in this slot
      FOR i IN 0..3 LOOP
        IF v_pawn->i IS NULL THEN
          v_all_finished := FALSE;
          EXIT;
        END IF;
        IF v_pawn->i->>'s' <> 'finished' THEN
          v_all_finished := FALSE;
          EXIT;
        END IF;
      END LOOP;
      IF v_all_finished THEN
        v_finish_slot := v_slot;
        EXIT;
      END IF;
    END LOOP;

    -- A player has all pawns finished!
    IF v_finish_slot >= 0 THEN
      -- Get the winner's user_id
      SELECT user_id, team INTO v_winner_user, v_team
        FROM public.ludo_participants
        WHERE game_id=_game_id AND slot=v_finish_slot AND forfeited=FALSE
        LIMIT 1;

      IF v_is_solo THEN
        -- Solo mode: find the non-bot winner
        IF v_winner_user IS NOT NULL AND NOT EXISTS(
          SELECT 1 FROM public.ludo_participants
          WHERE game_id=_game_id AND user_id=v_winner_user AND is_bot=TRUE
        ) THEN
          PERFORM public.finish_game(_game_id, v_winner_user);
        ELSE
          -- Bot won — just mark finished
          UPDATE public.ludo_games SET status='finished', finished_at=now() WHERE id=_game_id;
          PERFORM public._ludo_purge(_game_id);
        END IF;
        RETURN TRUE;
      ELSE
        -- Team mode (groupe 2v2): check if entire team has all pawns finished
        v_team_all_finished := TRUE;
        -- Check all members of the same team
        FOR v_slot IN 0..3 LOOP
          -- Skip if this slot is not on the same team
          DECLARE v_slot_team INT; v_slot_forfeited BOOLEAN;
          BEGIN
            SELECT team, forfeited INTO v_slot_team, v_slot_forfeited
              FROM public.ludo_participants
              WHERE game_id=_game_id AND slot=v_slot LIMIT 1;
            IF v_slot_team = v_team AND NOT COALESCE(v_slot_forfeited, TRUE) THEN
              -- Check if this slot's pawns are all finished
              v_mate_pawns := v_pawns->v_slot::text;
              IF v_mate_pawns IS NOT NULL THEN
                FOR i IN 0..3 LOOP
                  IF v_mate_pawns->i IS NULL OR v_mate_pawns->i->>'s' <> 'finished' THEN
                    v_team_all_finished := FALSE;
                    EXIT;
                  END IF;
                END LOOP;
              END IF;
            END IF;
          END;
        END LOOP;

        IF v_team_all_finished AND v_winner_user IS NOT NULL THEN
          PERFORM public._ludo_finish_team(_game_id, v_winner_user, v_team);
          RETURN TRUE;
        ELSIF v_team_all_finished THEN
          -- Bot team won
          UPDATE public.ludo_games SET status='finished', finished_at=now() WHERE id=_game_id;
          PERFORM public._ludo_purge(_game_id);
          RETURN TRUE;
        END IF;

        -- In team mode, a single player finishing doesn't end the game
        -- The team needs ALL members to finish. Continue playing.
      END IF;
    END IF;
  END IF;

  -- ═══ EXISTING: Solo mode — all humans left ═══
  IF v_is_solo AND v_humans = 0 THEN
    UPDATE public.ludo_games SET status='finished', finished_at=now() WHERE id=_game_id;
    PERFORM public._ludo_purge(_game_id);
    RETURN TRUE;
  END IF;

  -- ═══ EXISTING: Only one non-forfeited participant left ═══
  IF v_count <= 1 THEN
    v_winner := public._ludo_check_last_standing(_game_id);
    IF v_winner IS NOT NULL AND v_humans > 0 THEN
      PERFORM public.finish_game(_game_id, v_winner);
    ELSE
      UPDATE public.ludo_games SET status='finished', finished_at=now() WHERE id=_game_id;
      PERFORM public._ludo_purge(_game_id);
    END IF;
    RETURN TRUE;
  END IF;

  RETURN FALSE;
END;
$function$;
