
-- Helper: refund a single participant for a tournament match if eligible
CREATE OR REPLACE FUNCTION public._tournament_refund_participant(
  _tournament_id uuid,
  _match_id uuid,
  _user_id uuid,
  _reason text
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_t public.tournaments%ROWTYPE;
  v_is_bot boolean;
  v_fee numeric;
  v_already boolean;
BEGIN
  SELECT * INTO v_t FROM public.tournaments WHERE id = _tournament_id;
  IF v_t.id IS NULL THEN RETURN false; END IF;
  IF COALESCE(v_t.is_free, false) THEN RETURN false; END IF;

  v_fee := COALESCE(v_t.entry_fee_ar, 0);
  IF v_fee <= 0 THEN RETURN false; END IF;

  SELECT COALESCE(is_bot, false) INTO v_is_bot FROM public.profiles WHERE id = _user_id;
  IF COALESCE(v_is_bot, false) THEN RETURN false; END IF;

  -- Guard against double refunds for the same (tournament, match, user)
  SELECT EXISTS (
    SELECT 1 FROM public.transactions
    WHERE user_id = _user_id
      AND type = 'refund'
      AND ref_id = _tournament_id
      AND COALESCE(meta->>'match_id','') = _match_id::text
  ) INTO v_already;
  IF v_already THEN RETURN false; END IF;

  UPDATE public.profiles
    SET balance_ar = balance_ar + v_fee
    WHERE id = _user_id;

  UPDATE public.tournaments
    SET prize_pool = GREATEST(COALESCE(prize_pool,0) - v_fee, 0)
    WHERE id = _tournament_id;

  INSERT INTO public.transactions(user_id, type, amount, ref_id, note, meta)
    VALUES (
      _user_id, 'refund', v_fee, _tournament_id,
      'Remboursement forfait tournoi: ' || COALESCE(v_t.name,''),
      jsonb_build_object(
        'tournament_id', _tournament_id,
        'match_id', _match_id,
        'reason', COALESCE(_reason,'forfait avant démarrage')
      )
    );

  INSERT INTO public.notifications(user_id, kind, title, body, link, ref_id)
    VALUES (
      _user_id, 'wallet',
      'Remboursement tournoi',
      'Vous avez été remboursé de ' || v_fee || ' Ar (' || COALESCE(_reason,'forfait avant démarrage') || ')',
      '/tournaments/' || _tournament_id::text,
      _match_id
    );

  RETURN true;
END $$;

REVOKE ALL ON FUNCTION public._tournament_refund_participant(uuid, uuid, uuid, text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._tournament_refund_participant(uuid, uuid, uuid, text) TO service_role;

-- Update: auto forfeit expired matches now refunds all non-ready human players (game never started)
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
  v_game_started boolean;
BEGIN
  FOR m IN
    SELECT id, tournament_id, player_ids, player_ready, game_id, status
    FROM public.tournament_matches
    WHERE status IN ('pending','running')
      AND join_deadline IS NOT NULL
      AND join_deadline < now()
      AND COALESCE(array_length(player_ids, 1), 0) >= 2
      AND NOT COALESCE(is_bye, false)
  LOOP
    v_game_started := false;
    IF m.status = 'running' AND m.game_id IS NOT NULL THEN
      SELECT status INTO v_game_status FROM public.ludo_games WHERE id = m.game_id;
      IF v_game_status IS NULL OR v_game_status <> 'open' THEN
        -- Game already progressed; skip auto-forfeit
        CONTINUE;
      END IF;
    END IF;

    v_ready := COALESCE(m.player_ready, '{}'::jsonb);
    v_ready_players := ARRAY[]::UUID[];
    FOREACH v_pid IN ARRAY m.player_ids LOOP
      IF v_ready ? v_pid::text THEN
        v_ready_players := array_append(v_ready_players, v_pid);
      END IF;
    END LOOP;

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

    IF m.game_id IS NOT NULL THEN
      UPDATE public.ludo_games
        SET status = 'cancelled'
        WHERE id = m.game_id AND status = 'open';
    END IF;

    -- Refund every player who was NOT ready (they didn't play)
    FOREACH v_pid IN ARRAY m.player_ids LOOP
      IF v_pid IS DISTINCT FROM v_winner AND NOT (v_ready ? v_pid::text) THEN
        PERFORM public._tournament_refund_participant(
          m.tournament_id, m.id, v_pid, 'Forfait automatique (deadline dépassée)'
        );
      END IF;
    END LOOP;

    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END $function$;

-- Update: admin forfeit refunds the loser if the game hasn't effectively started
CREATE OR REPLACE FUNCTION public.admin_forfeit_match_player(_mid uuid, _loser_id uuid, _reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_match record;
  v_winner uuid;
  v_game_status text;
  v_refunded boolean := false;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Accès refusé';
  END IF;

  SELECT * INTO v_match FROM public.tournament_matches WHERE id = _mid FOR UPDATE;
  IF v_match IS NULL THEN RAISE EXCEPTION 'Match introuvable'; END IF;
  IF NOT (_loser_id = ANY(v_match.player_ids)) THEN RAISE EXCEPTION 'Joueur introuvable dans ce match'; END IF;

  SELECT uid INTO v_winner
  FROM unnest(v_match.player_ids) AS uid
  WHERE uid <> _loser_id
  LIMIT 1;

  IF v_winner IS NULL THEN RAISE EXCEPTION 'Impossible de déterminer le vainqueur'; END IF;

  UPDATE public.tournament_matches
    SET status = 'forfeit',
        winner_id = v_winner,
        finished_at = now(),
        admin_notes = COALESCE(admin_notes || ' | ', '') || 'Forfait admin: ' || COALESCE(NULLIF(_reason, ''), 'Sans raison')
    WHERE id = _mid;

  -- If the associated game hasn't started, refund the loser
  IF v_match.game_id IS NOT NULL THEN
    SELECT status INTO v_game_status FROM public.ludo_games WHERE id = v_match.game_id;
    IF v_game_status = 'open' THEN
      UPDATE public.ludo_games SET status = 'cancelled' WHERE id = v_match.game_id AND status = 'open';
      v_refunded := public._tournament_refund_participant(
        v_match.tournament_id, _mid, _loser_id,
        'Forfait admin avant démarrage: ' || COALESCE(NULLIF(_reason,''),'sans raison')
      );
    END IF;
  ELSE
    -- No game yet: safe to refund
    v_refunded := public._tournament_refund_participant(
      v_match.tournament_id, _mid, _loser_id,
      'Forfait admin avant démarrage: ' || COALESCE(NULLIF(_reason,''),'sans raison')
    );
  END IF;

  INSERT INTO public.admin_logs(admin_id, action, target_user_id, old_value, new_value)
    VALUES (v_uid, 'admin_forfeit_match_player', _loser_id,
      jsonb_build_object('match_id', _mid, 'previous_status', v_match.status, 'previous_winner_id', v_match.winner_id),
      jsonb_build_object('match_id', _mid, 'loser_id', _loser_id, 'winner_id', v_winner, 'reason', _reason, 'refunded', v_refunded));

  INSERT INTO public.notifications(user_id, kind, title, body, link, ref_id)
    VALUES
      (v_winner, 'tournament', 'Victoire par forfait', COALESCE(_reason, 'Décision administrateur'), '/tournaments/' || v_match.tournament_id::text, _mid),
      (_loser_id, 'tournament', 'Forfait enregistré', COALESCE(_reason, 'Décision administrateur'), '/tournaments/' || v_match.tournament_id::text, _mid);

  RETURN jsonb_build_object('ok', true, 'winner_id', v_winner, 'refunded', v_refunded);
END;
$function$;

-- Update: admin cancelling a match refunds all human players if the game hasn't started
CREATE OR REPLACE FUNCTION public.admin_cancel_tournament_match(_mid uuid, _reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
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

  UPDATE public.tournament_matches
    SET status = 'cancelled',
        winner_id = NULL,
        finished_at = now(),
        admin_notes = COALESCE(admin_notes || ' | ', '') || 'Match annulé: ' || COALESCE(NULLIF(_reason, ''), 'Sans raison')
    WHERE id = _mid;

  IF v_match.game_id IS NOT NULL THEN
    SELECT status INTO v_game_status FROM public.ludo_games WHERE id = v_match.game_id;
    IF v_game_status IS NOT NULL AND v_game_status <> 'open' THEN
      v_can_refund := false;
    ELSE
      UPDATE public.ludo_games SET status = 'cancelled' WHERE id = v_match.game_id AND status = 'open';
    END IF;
  END IF;

  IF v_can_refund AND v_match.player_ids IS NOT NULL THEN
    FOREACH v_pid IN ARRAY v_match.player_ids LOOP
      IF public._tournament_refund_participant(
           v_match.tournament_id, _mid, v_pid,
           'Match annulé par admin: ' || COALESCE(NULLIF(_reason,''),'sans raison')
         ) THEN
        v_refunded_count := v_refunded_count + 1;
      END IF;
    END LOOP;
  END IF;

  INSERT INTO public.admin_logs(admin_id, action, target_id, old_value, new_value)
    VALUES (v_uid, 'admin_cancel_tournament_match', _mid,
      jsonb_build_object('previous_status', v_match.status, 'previous_winner_id', v_match.winner_id),
      jsonb_build_object('reason', _reason, 'refunded_count', v_refunded_count));

  INSERT INTO public.notifications(user_id, kind, title, body, link, ref_id)
    SELECT uid, 'tournament', 'Match annulé', COALESCE(_reason, 'Décision administrateur'), '/tournaments/' || v_match.tournament_id::text, _mid
    FROM unnest(v_match.player_ids) AS uid;

  RETURN jsonb_build_object('ok', true, 'refunded_count', v_refunded_count);
END;
$function$;
