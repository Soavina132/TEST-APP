
-- Ludo tournaments: allow smaller final group (1v1 or 3 players) when leftovers don't fill a 4-seat match.
-- Fix: ludo_games.max_players must match actual match size, otherwise the room never fills.

CREATE OR REPLACE FUNCTION public.tournament_start(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_t public.tournaments%ROWTYPE;
  v_players uuid[];
  v_count int;
  v_pool numeric := 0;
  r record;
  v_total_rounds int;
  v_n int;
  m record;
  v_game_id uuid;
  v_first uuid;
  v_color text;
  v_slot int;
  v_name text;
  v_pid uuid;
  v_size int;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT * INTO v_t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF v_t.id IS NULL THEN RAISE EXCEPTION 'introuvable'; END IF;
  IF v_t.status <> 'open' THEN RAISE EXCEPTION 'déjà démarré'; END IF;
  SELECT count(*) INTO v_count FROM public.tournament_registrations WHERE tournament_id = _tid;
  IF v_count < 2 THEN RAISE EXCEPTION 'pas assez de joueurs'; END IF;

  IF NOT v_t.is_free AND v_t.stake > 0 THEN
    FOR r IN SELECT user_id FROM public.tournament_registrations WHERE tournament_id = _tid LOOP
      UPDATE public.profiles SET balance_ar = balance_ar - v_t.stake WHERE id = r.user_id AND balance_ar >= v_t.stake;
      IF NOT FOUND THEN RAISE EXCEPTION 'solde insuffisant pour un joueur'; END IF;
      INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
        VALUES (r.user_id,'stake',-v_t.stake,_tid,'Inscription tournoi: '||v_t.name);
      v_pool := v_pool + v_t.stake;
    END LOOP;
  END IF;

  SELECT array_agg(user_id ORDER BY random()) INTO v_players
    FROM public.tournament_registrations WHERE tournament_id = _tid;

  v_n := array_length(v_players,1);
  v_total_rounds := 0;
  WHILE v_n > 1 LOOP
    v_n := CEIL(v_n::numeric / GREATEST(v_t.players_per_match,2));
    v_total_rounds := v_total_rounds + 1;
  END LOOP;

  UPDATE public.tournaments
    SET status='running', started_at=now(), prize_pool=v_pool, current_round=1, total_rounds=v_total_rounds
    WHERE id=_tid;

  PERFORM public._tournament_build_round(_tid, 1, v_players);

  FOR m IN SELECT * FROM public.tournament_matches WHERE tournament_id = _tid AND round = 1 AND status = 'pending' ORDER BY match_index LOOP
    v_first := m.player_ids[1];
    v_size := GREATEST(array_length(m.player_ids,1), 2);  -- actual seats for this match (2 or 3 or 4)
    INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, room_code, is_private, mode, tournament_match_id, status)
      VALUES (v_first, v_size, 0, 0, 0, NULL, TRUE, 'classic', m.id, 'open')
      RETURNING id INTO v_game_id;
    v_slot := 0;
    FOREACH v_pid IN ARRAY m.player_ids LOOP
      v_color := (ARRAY['red','blue','green','yellow'])[v_slot+1];
      SELECT pseudo INTO v_name FROM public.profiles WHERE id = v_pid;
      INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
        VALUES (v_game_id, v_pid, v_slot, v_color, COALESCE(v_name,'Joueur'));
      v_slot := v_slot + 1;
    END LOOP;
    UPDATE public.tournament_matches SET game_id = v_game_id, status = 'running' WHERE id = m.id;
  END LOOP;
END $$;

-- Auto-advance trigger: also use actual match size
CREATE OR REPLACE FUNCTION public._tournament_on_game_finished()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_match public.tournament_matches%ROWTYPE;
  v_t public.tournaments%ROWTYPE;
  v_remaining int;
  v_winners uuid[];
  v_total int;
  m record;
  v_game_id uuid;
  v_first uuid;
  v_color text;
  v_slot int;
  v_name text;
  v_pid uuid;
  v_payout numeric;
  v_top3 jsonb;
  v_size int;
BEGIN
  IF NEW.status <> 'finished' OR OLD.status = 'finished' THEN RETURN NEW; END IF;
  IF NEW.tournament_match_id IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_match FROM public.tournament_matches WHERE id = NEW.tournament_match_id FOR UPDATE;
  IF v_match.id IS NULL OR v_match.status = 'finished' THEN RETURN NEW; END IF;

  UPDATE public.tournament_matches
    SET status='finished', winner_id = NEW.winner_id, finished_at = now()
    WHERE id = v_match.id;

  SELECT * INTO v_t FROM public.tournaments WHERE id = v_match.tournament_id FOR UPDATE;
  UPDATE public.tournament_registrations
    SET eliminated_round = v_t.current_round
    WHERE tournament_id = v_t.id
      AND user_id = ANY(v_match.player_ids)
      AND user_id IS DISTINCT FROM NEW.winner_id
      AND eliminated_round IS NULL;

  SELECT count(*) INTO v_remaining
    FROM public.tournament_matches
    WHERE tournament_id = v_t.id AND round = v_t.current_round AND status NOT IN ('finished','bye');
  IF v_remaining > 0 THEN RETURN NEW; END IF;

  SELECT array_agg(winner_id ORDER BY match_index) INTO v_winners
    FROM public.tournament_matches
    WHERE tournament_id = v_t.id AND round = v_t.current_round AND winner_id IS NOT NULL;
  v_total := COALESCE(array_length(v_winners,1),0);

  IF v_total <= 1 THEN
    v_top3 := '[]'::jsonb;
    SELECT jsonb_agg(jsonb_build_object('user_id', user_id, 'eliminated_round', eliminated_round)
                     ORDER BY (CASE WHEN user_id = v_winners[1] THEN 999999 ELSE eliminated_round END) DESC) INTO v_top3
      FROM (
        SELECT user_id, COALESCE(eliminated_round, 999999) as eliminated_round
          FROM public.tournament_registrations
          WHERE tournament_id = v_t.id
          ORDER BY (CASE WHEN user_id = v_winners[1] THEN 999999 ELSE eliminated_round END) DESC NULLS LAST
          LIMIT 3
      ) s;

    UPDATE public.tournaments
      SET status='finished', finished_at=now(), winner_id = v_winners[1], top3 = COALESCE(v_top3,'[]'::jsonb)
      WHERE id = v_t.id;

    IF NOT v_t.is_free AND v_t.prize_pool > 0 THEN
      v_payout := v_t.prize_pool * (100 - v_t.commission_pct) / 100.0;
      UPDATE public.profiles SET balance_ar = balance_ar + v_payout WHERE id = v_winners[1];
      INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
        VALUES (v_winners[1],'win', v_payout, v_t.id, 'Victoire tournoi: '||v_t.name);
    END IF;
    RETURN NEW;
  END IF;

  UPDATE public.tournaments SET current_round = current_round + 1 WHERE id = v_t.id;
  PERFORM public._tournament_build_round(v_t.id, v_t.current_round + 1, v_winners);

  FOR m IN SELECT * FROM public.tournament_matches
           WHERE tournament_id = v_t.id AND round = v_t.current_round + 1 AND status = 'pending' ORDER BY match_index LOOP
    v_first := m.player_ids[1];
    v_size := GREATEST(array_length(m.player_ids,1), 2);
    INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, room_code, is_private, mode, tournament_match_id, status)
      VALUES (v_first, v_size, 0, 0, 0, NULL, TRUE, 'classic', m.id, 'open')
      RETURNING id INTO v_game_id;
    v_slot := 0;
    FOREACH v_pid IN ARRAY m.player_ids LOOP
      v_color := (ARRAY['red','blue','green','yellow'])[v_slot+1];
      SELECT pseudo INTO v_name FROM public.profiles WHERE id = v_pid;
      INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
        VALUES (v_game_id, v_pid, v_slot, v_color, COALESCE(v_name,'Joueur'));
      v_slot := v_slot + 1;
    END LOOP;
    UPDATE public.tournament_matches SET game_id = v_game_id, status = 'running' WHERE id = m.id;
  END LOOP;

  RETURN NEW;
END $$;
