
CREATE OR REPLACE FUNCTION public.admin_force_match_result(_mid uuid, _winner_id uuid, _reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match record;
  v_game_status text;
  v_can_refund boolean := true;
  v_pid uuid;
  v_refunded_count int := 0;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Accès refusé';
  END IF;

  SELECT * INTO v_match FROM public.tournament_matches WHERE id = _mid FOR UPDATE;
  IF v_match IS NULL THEN RAISE EXCEPTION 'Match introuvable'; END IF;
  IF v_match.player_ids IS NULL OR array_length(v_match.player_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'Aucun joueur dans ce match';
  END IF;
  IF NOT (_winner_id = ANY(v_match.player_ids)) THEN
    RAISE EXCEPTION 'Le vainqueur doit être un joueur du match';
  END IF;

  UPDATE public.tournament_matches
    SET status = 'forfeit',
        winner_id = _winner_id,
        finished_at = now(),
        admin_notes = COALESCE(admin_notes || ' | ', '') ||
          'Forfait forcé par admin (vainqueur: ' || _winner_id::text || '): ' ||
          COALESCE(NULLIF(_reason, ''), 'sans raison')
    WHERE id = _mid;

  -- Cancel associated game if not started; refund losers only when game hadn't started
  IF v_match.game_id IS NOT NULL THEN
    SELECT status INTO v_game_status FROM public.ludo_games WHERE id = v_match.game_id;
    IF v_game_status IS NOT NULL AND v_game_status NOT IN ('open') THEN
      v_can_refund := false;
    ELSE
      UPDATE public.ludo_games SET status = 'cancelled' WHERE id = v_match.game_id AND status = 'open';
    END IF;
  END IF;

  IF v_can_refund THEN
    FOREACH v_pid IN ARRAY v_match.player_ids LOOP
      IF v_pid <> _winner_id THEN
        IF public._tournament_refund_participant(
             v_match.tournament_id, _mid, v_pid,
             'Forfait forcé par admin: ' || COALESCE(NULLIF(_reason,''),'sans raison')
           ) THEN
          v_refunded_count := v_refunded_count + 1;
        END IF;
      END IF;
    END LOOP;
  END IF;

  INSERT INTO public.admin_logs(admin_id, action, target_user_id, old_value, new_value)
    VALUES (v_uid, 'admin_force_match_result', _winner_id,
      jsonb_build_object('match_id', _mid, 'previous_status', v_match.status, 'previous_winner_id', v_match.winner_id),
      jsonb_build_object('match_id', _mid, 'winner_id', _winner_id, 'reason', _reason, 'refunded_count', v_refunded_count));

  INSERT INTO public.notifications(user_id, kind, title, body, link, ref_id)
  SELECT
    uid,
    'tournament',
    CASE WHEN uid = _winner_id THEN 'Victoire par forfait' ELSE 'Forfait enregistré' END,
    COALESCE(_reason, 'Décision administrateur'),
    '/tournaments/' || v_match.tournament_id::text,
    _mid
  FROM unnest(v_match.player_ids) AS uid;

  RETURN jsonb_build_object('ok', true, 'winner_id', _winner_id, 'refunded_count', v_refunded_count);
END;
$$;
