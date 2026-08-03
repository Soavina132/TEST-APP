
CREATE OR REPLACE FUNCTION public.admin_advance_tournament_round(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_is_admin   boolean;
  trn          record;
  v_winners    uuid[];
  v_count      int;
  v_next_round int;
  i            int;
  m            record;
  v_game_id    uuid;
  v_first      uuid;
  v_color      text;
  v_slot       int;
  v_name       text;
  v_pid        uuid;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO trn FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF trn IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;
  IF trn.status <> 'running' THEN RAISE EXCEPTION 'Tournoi non en cours'; END IF;

  IF EXISTS (
    SELECT 1 FROM public.tournament_matches
    WHERE tournament_id = _tid
      AND round = trn.current_round
      AND status NOT IN ('finished','forfeit','cancelled')
      AND is_bye = false
  ) THEN
    RAISE EXCEPTION 'Des matchs du round actuel ne sont pas encore terminés';
  END IF;

  SELECT ARRAY_AGG(winner_id ORDER BY random())
    INTO v_winners
    FROM public.tournament_matches
    WHERE tournament_id = _tid
      AND round = trn.current_round
      AND winner_id IS NOT NULL;

  v_count := COALESCE(array_length(v_winners, 1), 0);

  IF v_count <= 1 THEN
    UPDATE public.tournaments
      SET status = 'finished',
          winner_id = v_winners[1],
          finished_at = now()
      WHERE id = _tid;

    IF v_winners[1] IS NOT NULL THEN
      UPDATE public.profiles
        SET balance_ar = balance_ar + COALESCE(trn.prize_pool, 0)
        WHERE id = v_winners[1];

      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (
          v_winners[1], 'tournament_win',
          COALESCE(trn.prize_pool, 0), _tid,
          'Gains tournoi ' || COALESCE(trn.game_slug, 'multi')
        );
    END IF;
    RETURN;
  END IF;

  v_next_round := trn.current_round + 1;
  UPDATE public.tournaments SET current_round = v_next_round WHERE id = _tid;

  -- Créer les matchs du prochain round
  i := 1;
  WHILE i + 1 <= v_count LOOP
    INSERT INTO public.tournament_matches(
      tournament_id, round, player_ids, status, is_bye, join_deadline
    ) VALUES (
      _tid, v_next_round, ARRAY[v_winners[i], v_winners[i+1]],
      'pending', false, now() + interval '5 minutes'
    );
    i := i + 2;
  END LOOP;

  -- Bye si nombre impair
  IF v_count % 2 = 1 THEN
    INSERT INTO public.tournament_matches(
      tournament_id, round, player_ids, status, is_bye, winner_id
    ) VALUES (
      _tid, v_next_round, ARRAY[v_winners[v_count]], 'finished', true, v_winners[v_count]
    );
  END IF;

  -- Pour les jeux type Ludo : créer les parties liées aux nouveaux matchs
  IF trn.game_slug IN ('ludo') THEN
    FOR m IN
      SELECT * FROM public.tournament_matches
      WHERE tournament_id = _tid
        AND round = v_next_round
        AND status = 'pending'
        AND is_bye = false
      ORDER BY created_at
    LOOP
      v_first := m.player_ids[1];
      INSERT INTO public.ludo_games(
        host_id, max_players, stake, pot, commission_pct,
        room_code, is_private, mode, tournament_match_id, status
      )
      VALUES (
        v_first, COALESCE(trn.players_per_match, 2), 0, 0, 0,
        NULL, TRUE, 'classic', m.id, 'open'
      )
      RETURNING id INTO v_game_id;

      v_slot := 0;
      FOREACH v_pid IN ARRAY m.player_ids LOOP
        v_color := (ARRAY['red','blue','green','yellow'])[v_slot+1];
        SELECT pseudo INTO v_name FROM public.profiles WHERE id = v_pid;
        INSERT INTO public.ludo_participants(
          game_id, user_id, slot, color, display_name
        )
        VALUES (
          v_game_id, v_pid, v_slot, v_color, COALESCE(v_name, 'Joueur')
        );
        v_slot := v_slot + 1;
      END LOOP;

      UPDATE public.tournament_matches
        SET game_id = v_game_id, status = 'running'
        WHERE id = m.id;
    END LOOP;
  END IF;
END;
$$;
