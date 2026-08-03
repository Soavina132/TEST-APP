
CREATE OR REPLACE FUNCTION public.tournament_auto_forfeit_expired()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_count INT := 0;
  m RECORD;
  v_winner UUID;
  v_ready JSONB;
  v_ready_players UUID[];
  v_pid UUID;
  v_game_status TEXT;
BEGIN
  FOR m IN
    SELECT id, player_ids, player_ready, game_id, status
    FROM public.tournament_matches
    WHERE status IN ('pending','running')
      AND join_deadline IS NOT NULL
      AND join_deadline < now()
      AND COALESCE(array_length(player_ids, 1), 0) >= 2
      AND NOT COALESCE(is_bye, false)
  LOOP
    -- Si le match est 'running', vérifier que la partie n'a pas encore démarré (statut open)
    IF m.status = 'running' AND m.game_id IS NOT NULL THEN
      SELECT status INTO v_game_status FROM public.ludo_games WHERE id = m.game_id;
      IF v_game_status IS NULL OR v_game_status <> 'open' THEN
        CONTINUE; -- partie déjà en cours ou terminée, ne pas forcer
      END IF;
    END IF;

    v_ready := COALESCE(m.player_ready, '{}'::jsonb);
    v_ready_players := ARRAY[]::UUID[];
    FOREACH v_pid IN ARRAY m.player_ids LOOP
      IF v_ready ? v_pid::text THEN
        v_ready_players := array_append(v_ready_players, v_pid);
      END IF;
    END LOOP;

    -- Gagnant : premier joueur prêt (par ordre du bracket). Aucun prêt => pas de gagnant.
    IF array_length(v_ready_players, 1) >= 1 THEN
      v_winner := v_ready_players[1];
    ELSE
      v_winner := NULL;
    END IF;

    UPDATE public.tournament_matches
      SET status = 'finished',
          winner_id = v_winner,
          finished_at = now(),
          admin_notes = COALESCE(admin_notes, '') || ' [auto-forfait deadline]'
      WHERE id = m.id;

    -- Annuler la partie associée si elle n'a jamais démarré
    IF m.game_id IS NOT NULL THEN
      UPDATE public.ludo_games
        SET status = 'cancelled'
        WHERE id = m.game_id AND status = 'open';
    END IF;

    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END $function$;
