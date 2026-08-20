-- ════════════════════════════════════════════════════════════════════════
-- Fix: domino_forfeit_internal — le gagnant n'était pas défini quand
--       le trigger _maybe_end_bot_only_domino finissait la partie avant
--       que _domino_finalize ne puisse s'exécuter.
--
-- Cause: L'UPDATE domino_participants SET forfeited=true déclenche le trigger
--        _trg_domino_participant_end_check qui appelle _maybe_end_bot_only_domino.
--        Quand il ne reste que des bots, _maybe_end_bot_only_domino met
--        status='finished' immédiatement. Ensuite, _domino_finalize voit
--        status='finished' et retourne sans définir winner_id ni faire le payout.
--
-- Fix: Réorganiser domino_forfeit_internal pour:
--   1. Compter les joueurs restants AVANT l'UPDATE
--   2. S'il ne reste que des bots ou 1 joueur, appeler _domino_finalize
--      AVANT l'UPDATE qui déclenche le trigger
--   3. Le trigger verra alors status='finished' et ne fera rien
-- ════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.domino_forfeit_internal(_game_id uuid, _part domino_participants)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  g record;
  st jsonb;
  v_slot int;
  v_remaining int;
  v_remaining_humans int;
  v_last_slot int;
  v_next int;
  v_turn_seconds int;
  v_required int;
  v_board_empty boolean;
BEGIN
  v_slot := _part.slot;

  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;

  -- Préparer le state: vider la main du joueur qui quitte
  st := g.state;
  st := jsonb_set(st, ARRAY['hands', v_slot::text], '[]'::jsonb, true);

  -- Compter les joueurs qui resteront APRÈS le forfeit (excluant le joueur actuel)
  SELECT count(*) INTO v_remaining FROM public.domino_participants
    WHERE game_id = _game_id AND forfeited = false AND slot <> v_slot;

  -- Compter les joueurs humains qui resteront
  SELECT count(*) INTO v_remaining_humans FROM public.domino_participants
    WHERE game_id = _game_id AND forfeited = false AND slot <> v_slot AND is_bot = false;

  IF v_remaining = 0 THEN
    -- Tous les joueurs ont quitté: annuler
    UPDATE public.domino_games SET status = 'cancelled', finished_at = now(), state = st WHERE id = _game_id;
    UPDATE public.domino_participants SET forfeited = true WHERE game_id = _game_id AND slot = v_slot;
    RETURN;
  END IF;

  IF v_remaining <= 1 OR v_remaining_humans = 0 THEN
    -- La partie va se terminer (1 joueur reste OU plus aucun humain).
    -- Il faut finaliser AVANT l'UPDATE domino_participants pour éviter
    -- que le trigger _maybe_end_bot_only_domino ne finisse la partie
    -- sans définir le gagnant.
    IF v_remaining = 1 THEN
      SELECT slot INTO v_last_slot FROM public.domino_participants
        WHERE game_id = _game_id AND forfeited = false AND slot <> v_slot
        ORDER BY slot LIMIT 1;
    ELSE
      v_last_slot := public._domino_lowest_pip_slot(_game_id, st);
    END IF;

    UPDATE public.domino_games SET state = st WHERE id = _game_id;

    IF v_last_slot IS NOT NULL THEN
      PERFORM public._domino_finalize(_game_id, v_last_slot);
    ELSE
      UPDATE public.domino_games SET status = 'cancelled', finished_at = now(), state = st WHERE id = _game_id;
    END IF;

    -- Maintenant marquer comme forfeit.
    -- Le trigger _maybe_end_bot_only_domino verra status='finished' et ne fera rien.
    UPDATE public.domino_participants SET forfeited = true
      WHERE game_id = _game_id AND slot = v_slot;
    RETURN;
  END IF;

  -- La partie continue: il reste au moins un joueur humain.
  -- Le trigger ne finira pas la partie.

  UPDATE public.domino_participants SET forfeited = true
    WHERE game_id = _game_id AND slot = v_slot;

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
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
  END IF;
END $function$;

-- Aussi ajouter SET search_path à domino_forfeit pour sécurité
CREATE OR REPLACE FUNCTION public.domino_forfeit(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  _uid uuid := auth.uid();
  _game record;
  _part record;
  _is_host boolean;
  _remaining int;
  _p record;
BEGIN
  SELECT * INTO _game FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF _game.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;

  SELECT * INTO _part FROM public.domino_participants
    WHERE game_id = _game_id AND user_id = _uid AND forfeited = false;
  IF NOT FOUND THEN RAISE EXCEPTION 'Non participant'; END IF;

  IF _game.status = 'open' THEN
    _is_host := (_game.host_id = _uid);
    IF _is_host THEN
      FOR _p IN SELECT user_id FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false LOOP
        UPDATE public.profiles SET balance_ar = balance_ar + _game.stake WHERE id = _p.user_id;
        INSERT INTO public.transactions(user_id, type, amount, description)
          VALUES (_p.user_id, 'domino_refund', _game.stake, 'Annulation salle d''attente (hôte)');
      END LOOP;
      UPDATE public.domino_games SET status = 'cancelled', finished_at = now(), updated_at = now() WHERE id = _game_id;
    ELSE
      UPDATE public.profiles SET balance_ar = balance_ar + _game.stake WHERE id = _uid;
      INSERT INTO public.transactions(user_id, type, amount, description)
        VALUES (_uid, 'domino_refund', _game.stake, 'Quitter salle d''attente');
      DELETE FROM public.domino_participants WHERE id = _part.id;
      UPDATE public.domino_games SET pot = pot - _game.stake, updated_at = now() WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;

  PERFORM public.domino_forfeit_internal(_game_id, _part);
END;
$function$;

REVOKE ALL ON FUNCTION public.domino_forfeit(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.domino_forfeit(uuid) TO authenticated;
