
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
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT * INTO v_t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF v_t.id IS NULL THEN RAISE EXCEPTION 'introuvable'; END IF;
  IF v_t.status <> 'open' THEN RAISE EXCEPTION 'déjà démarré'; END IF;
  SELECT count(*) INTO v_count FROM public.tournament_registrations WHERE tournament_id = _tid;
  IF v_count < v_t.players_per_match THEN RAISE EXCEPTION 'pas assez de joueurs'; END IF;

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
    v_n := CEIL(v_n::numeric / v_t.players_per_match);
    v_total_rounds := v_total_rounds + 1;
  END LOOP;

  UPDATE public.tournaments
    SET status='running', started_at=now(), prize_pool=v_pool, current_round=1, total_rounds=v_total_rounds
    WHERE id=_tid;

  PERFORM public._tournament_build_round(_tid, 1, v_players);

  FOR m IN SELECT * FROM public.tournament_matches WHERE tournament_id = _tid AND round = 1 AND status = 'pending' ORDER BY match_index LOOP
    v_first := m.player_ids[1];
    INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, room_code, is_private, mode, tournament_match_id, status)
      VALUES (v_first, v_t.players_per_match, 0, 0, 0, NULL, TRUE, 'classic', m.id, 'open')
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
