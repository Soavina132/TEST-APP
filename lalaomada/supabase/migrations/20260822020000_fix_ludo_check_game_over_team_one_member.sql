-- ═══════════════════════════════════════════════════════════════════════════
-- FIX v2: _ludo_check_game_over
--
-- Changements:
-- 1. Solo: un joueur avec tous ses pions arrivés gagne immédiatement
-- 2. 2v2 (groupe): si N'IMPORTE QUEL membre d'une équipe a tous ses pions
--    arrivés, l'équipe gagne (avant: il fallait TOUS les membres)
-- 3. Nettoyage de la logique
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
  v_pawn_arr jsonb;
  v_all_finished BOOLEAN;
  v_finish_slot INT;
  v_team INT;
  v_winner_user UUID;
  v_team_val INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN FALSE; END IF;

  SELECT count(*) INTO v_count
    FROM public.ludo_participants WHERE game_id=_game_id AND forfeited=FALSE;
  SELECT count(*) INTO v_humans
    FROM public.ludo_participants WHERE game_id=_game_id AND is_bot=FALSE AND forfeited=FALSE;

  v_is_solo := COALESCE(g.is_solo, FALSE) OR g.match_type = 'solo';

  -- ═══ Check if any player has ALL pawns finished ═══
  v_pawns := g.state->'pawns';
  IF v_pawns IS NOT NULL THEN
    v_finish_slot := -1;
    FOR v_slot IN 0..3 LOOP
      v_pawn_arr := v_pawns->v_slot::text;
      IF v_pawn_arr IS NULL THEN CONTINUE; END IF;
      -- Skip forfeited slots
      IF EXISTS(SELECT 1 FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot AND forfeited=TRUE) THEN
        CONTINUE;
      END IF;
      v_all_finished := TRUE;
      FOR i IN 0..3 LOOP
        IF v_pawn_arr->i IS NULL OR v_pawn_arr->i->>'s' <> 'finished' THEN
          v_all_finished := FALSE;
          EXIT;
        END IF;
      END LOOP;
      IF v_all_finished THEN
        v_finish_slot := v_slot;
        EXIT;
      END IF;
    END LOOP;

    IF v_finish_slot >= 0 THEN
      -- Get the winner's user_id and team
      SELECT user_id, team INTO v_winner_user, v_team
        FROM public.ludo_participants
        WHERE game_id=_game_id AND slot=v_finish_slot AND forfeited=FALSE
        LIMIT 1;

      IF v_is_solo THEN
        -- Solo: this player wins
        IF v_winner_user IS NOT NULL AND NOT EXISTS(
          SELECT 1 FROM public.ludo_participants
          WHERE game_id=_game_id AND user_id=v_winner_user AND is_bot=TRUE
        ) THEN
          PERFORM public.finish_game(_game_id, v_winner_user);
        ELSE
          -- Bot won
          UPDATE public.ludo_games SET status='finished', finished_at=now() WHERE id=_game_id;
          PERFORM public._ludo_purge(_game_id);
        END IF;
        RETURN TRUE;
      ELSE
        -- Team mode (groupe 2v2): ONE member finishing is enough for the team to win
        IF v_winner_user IS NOT NULL AND v_team IS NOT NULL THEN
          -- Find the non-bot human teammate (could be the finisher or their partner)
          SELECT user_id INTO v_winner_user FROM public.ludo_participants
            WHERE game_id=_game_id AND team=v_team AND is_bot=FALSE AND forfeited=FALSE
            LIMIT 1;
          PERFORM public._ludo_finish_team(_game_id, v_winner_user, v_team);
        ELSE
          -- Bot team won
          UPDATE public.ludo_games SET status='finished', finished_at=now() WHERE id=_game_id;
          PERFORM public._ludo_purge(_game_id);
        END IF;
        RETURN TRUE;
      END IF;
    END IF;
  END IF;

  -- ═══ Solo mode — all humans left ═══
  IF v_is_solo AND v_humans = 0 THEN
    UPDATE public.ludo_games SET status='finished', finished_at=now() WHERE id=_game_id;
    PERFORM public._ludo_purge(_game_id);
    RETURN TRUE;
  END IF;

  -- ═══ Only one non-forfeited participant left ═══
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
