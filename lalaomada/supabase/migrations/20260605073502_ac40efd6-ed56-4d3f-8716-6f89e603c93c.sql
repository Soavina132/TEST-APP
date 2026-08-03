
-- ===================== TOURNAMENTS SCHEMA =====================

CREATE TABLE IF NOT EXISTS public.tournaments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  mode text NOT NULL CHECK (mode IN ('1v1','4p')),
  players_per_match integer NOT NULL,
  max_players integer NOT NULL CHECK (max_players >= 2 AND max_players <= 64),
  stake numeric NOT NULL DEFAULT 0 CHECK (stake >= 0),
  is_free boolean NOT NULL DEFAULT false,
  season integer NOT NULL DEFAULT 1,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','running','finished','cancelled')),
  current_round integer NOT NULL DEFAULT 0,
  total_rounds integer NOT NULL DEFAULT 0,
  prize_pool numeric NOT NULL DEFAULT 0,
  commission_pct numeric NOT NULL DEFAULT 10,
  winner_id uuid,
  top3 jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  finished_at timestamptz
);
GRANT SELECT ON public.tournaments TO anon, authenticated;
GRANT ALL ON public.tournaments TO service_role;
ALTER TABLE public.tournaments ENABLE ROW LEVEL SECURITY;
CREATE POLICY tournaments_read ON public.tournaments FOR SELECT TO anon, authenticated USING (true);

CREATE TABLE IF NOT EXISTS public.tournament_registrations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid NOT NULL REFERENCES public.tournaments(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  registered_at timestamptz NOT NULL DEFAULT now(),
  eliminated_round integer,
  final_position integer,
  UNIQUE (tournament_id, user_id)
);
GRANT SELECT ON public.tournament_registrations TO anon, authenticated;
GRANT ALL ON public.tournament_registrations TO service_role;
ALTER TABLE public.tournament_registrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY treg_read ON public.tournament_registrations FOR SELECT TO anon, authenticated USING (true);

CREATE TABLE IF NOT EXISTS public.tournament_matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid NOT NULL REFERENCES public.tournaments(id) ON DELETE CASCADE,
  round integer NOT NULL,
  match_index integer NOT NULL,
  player_ids uuid[] NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','running','finished','bye')),
  game_id uuid,
  winner_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  UNIQUE (tournament_id, round, match_index)
);
GRANT SELECT ON public.tournament_matches TO anon, authenticated;
GRANT ALL ON public.tournament_matches TO service_role;
ALTER TABLE public.tournament_matches ENABLE ROW LEVEL SECURITY;
CREATE POLICY tmatch_read ON public.tournament_matches FOR SELECT TO anon, authenticated USING (true);

-- Link a ludo game to a tournament match (nullable, only for tournament games)
ALTER TABLE public.ludo_games ADD COLUMN IF NOT EXISTS tournament_match_id uuid;
CREATE INDEX IF NOT EXISTS idx_ludo_games_tournament_match ON public.ludo_games(tournament_match_id);

-- ===================== HELPER: build next round =====================

CREATE OR REPLACE FUNCTION public._tournament_build_round(_tid uuid, _round integer, _player_ids uuid[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_t public.tournaments%ROWTYPE;
  v_size integer;
  v_idx integer := 0;
  v_match uuid;
  v_players uuid[];
  v_total integer;
  v_i integer;
BEGIN
  SELECT * INTO v_t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  v_size := v_t.players_per_match;
  v_total := array_length(_player_ids, 1);
  v_i := 1;
  WHILE v_i <= v_total LOOP
    v_players := _player_ids[v_i : LEAST(v_i + v_size - 1, v_total)];
    IF array_length(v_players,1) = 1 THEN
      -- bye: auto-advance
      INSERT INTO public.tournament_matches(tournament_id, round, match_index, player_ids, status, winner_id, finished_at)
        VALUES (_tid, _round, v_idx, v_players, 'bye', v_players[1], now());
    ELSE
      INSERT INTO public.tournament_matches(tournament_id, round, match_index, player_ids, status)
        VALUES (_tid, _round, v_idx, v_players, 'pending');
    END IF;
    v_idx := v_idx + 1;
    v_i := v_i + v_size;
  END LOOP;
END $$;

-- ===================== ADMIN: CREATE / CANCEL =====================

CREATE OR REPLACE FUNCTION public.tournament_create(
  _name text, _mode text, _max_players integer, _stake numeric, _season integer, _is_free boolean
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_uid uuid := auth.uid(); v_tid uuid; v_size int; v_comm numeric;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  IF _mode NOT IN ('1v1','4p') THEN RAISE EXCEPTION 'mode invalide'; END IF;
  v_size := CASE WHEN _mode = '1v1' THEN 2 ELSE 4 END;
  IF _max_players < v_size OR _max_players > 64 THEN RAISE EXCEPTION 'capacité invalide'; END IF;
  SELECT game_commission_pct INTO v_comm FROM public.app_settings WHERE id = 1;
  INSERT INTO public.tournaments(name, mode, players_per_match, max_players, stake, is_free, season, created_by, commission_pct)
    VALUES (_name, _mode, v_size, _max_players, CASE WHEN _is_free THEN 0 ELSE _stake END, _is_free, COALESCE(_season,1), v_uid, COALESCE(v_comm,10))
    RETURNING id INTO v_tid;
  RETURN v_tid;
END $$;
REVOKE EXECUTE ON FUNCTION public.tournament_create(text,text,integer,numeric,integer,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tournament_create(text,text,integer,numeric,integer,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.tournament_cancel(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_t public.tournaments%ROWTYPE; r record;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT * INTO v_t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF v_t.id IS NULL THEN RAISE EXCEPTION 'introuvable'; END IF;
  IF v_t.status = 'finished' THEN RAISE EXCEPTION 'déjà terminé'; END IF;
  -- Refund only if running (stakes already taken) and not free
  IF v_t.status = 'running' AND NOT v_t.is_free AND v_t.stake > 0 THEN
    FOR r IN SELECT user_id FROM public.tournament_registrations WHERE tournament_id = _tid LOOP
      UPDATE public.profiles SET balance_ar = balance_ar + v_t.stake WHERE id = r.user_id;
      INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
        VALUES (r.user_id,'refund', v_t.stake, _tid, 'Annulation tournoi: ' || v_t.name);
    END LOOP;
  END IF;
  UPDATE public.tournaments SET status = 'cancelled', finished_at = now() WHERE id = _tid;
END $$;
REVOKE EXECUTE ON FUNCTION public.tournament_cancel(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tournament_cancel(uuid) TO authenticated;

-- ===================== REGISTER / UNREGISTER =====================

CREATE OR REPLACE FUNCTION public.tournament_register(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_uid uuid := auth.uid(); v_t public.tournaments%ROWTYPE; v_count int; v_phone_ok boolean; v_balance numeric;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth'; END IF;
  SELECT phone_verified, balance_ar INTO v_phone_ok, v_balance FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_phone_ok, false) THEN RAISE EXCEPTION 'Téléphone non vérifié'; END IF;
  SELECT * INTO v_t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF v_t.id IS NULL THEN RAISE EXCEPTION 'introuvable'; END IF;
  IF v_t.status <> 'open' THEN RAISE EXCEPTION 'inscriptions fermées'; END IF;
  SELECT count(*) INTO v_count FROM public.tournament_registrations WHERE tournament_id = _tid;
  IF v_count >= v_t.max_players THEN RAISE EXCEPTION 'tournoi complet'; END IF;
  IF NOT v_t.is_free AND v_balance < v_t.stake THEN RAISE EXCEPTION 'solde insuffisant'; END IF;
  INSERT INTO public.tournament_registrations(tournament_id, user_id) VALUES (_tid, v_uid);
END $$;
REVOKE EXECUTE ON FUNCTION public.tournament_register(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tournament_register(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.tournament_unregister(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_uid uuid := auth.uid(); v_status text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth'; END IF;
  SELECT status INTO v_status FROM public.tournaments WHERE id = _tid;
  IF v_status <> 'open' THEN RAISE EXCEPTION 'tournoi déjà démarré'; END IF;
  DELETE FROM public.tournament_registrations WHERE tournament_id = _tid AND user_id = v_uid;
END $$;
REVOKE EXECUTE ON FUNCTION public.tournament_unregister(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tournament_unregister(uuid) TO authenticated;

-- ===================== START TOURNAMENT (build round 1 + create games) =====================

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
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT * INTO v_t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF v_t.id IS NULL THEN RAISE EXCEPTION 'introuvable'; END IF;
  IF v_t.status <> 'open' THEN RAISE EXCEPTION 'déjà démarré'; END IF;
  SELECT count(*) INTO v_count FROM public.tournament_registrations WHERE tournament_id = _tid;
  IF v_count < v_t.players_per_match THEN RAISE EXCEPTION 'pas assez de joueurs'; END IF;

  -- Charge stakes (if not free)
  IF NOT v_t.is_free AND v_t.stake > 0 THEN
    FOR r IN SELECT user_id FROM public.tournament_registrations WHERE tournament_id = _tid LOOP
      UPDATE public.profiles SET balance_ar = balance_ar - v_t.stake WHERE id = r.user_id AND balance_ar >= v_t.stake;
      IF NOT FOUND THEN RAISE EXCEPTION 'solde insuffisant pour un joueur'; END IF;
      INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
        VALUES (r.user_id,'stake',-v_t.stake,_tid,'Inscription tournoi: '||v_t.name);
      v_pool := v_pool + v_t.stake;
    END LOOP;
  END IF;

  -- Shuffle players
  SELECT array_agg(user_id ORDER BY random()) INTO v_players
    FROM public.tournament_registrations WHERE tournament_id = _tid;

  -- Compute rounds (ceil(log_size(N)))
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

  -- Create ludo_games for each pending match in round 1
  FOR m IN SELECT * FROM public.tournament_matches WHERE tournament_id = _tid AND round = 1 AND status = 'pending' ORDER BY match_index LOOP
    v_first := m.player_ids[1];
    INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, room_code, is_private, mode, tournament_match_id, status)
      VALUES (v_first, v_t.players_per_match, 0, 0, 0, NULL, TRUE, 'classic', m.id, 'open')
      RETURNING id INTO v_game_id;
    v_slot := 0;
    FOREACH r.user_id IN ARRAY m.player_ids LOOP
      v_color := (ARRAY['red','blue','green','yellow'])[v_slot+1];
      SELECT pseudo INTO v_name FROM public.profiles WHERE id = r.user_id;
      INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
        VALUES (v_game_id, r.user_id, v_slot, v_color, COALESCE(v_name,'Joueur'));
      v_slot := v_slot + 1;
    END LOOP;
    UPDATE public.tournament_matches SET game_id = v_game_id, status = 'running' WHERE id = m.id;
  END LOOP;
END $$;
REVOKE EXECUTE ON FUNCTION public.tournament_start(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tournament_start(uuid) TO authenticated;

-- ===================== AUTO-ADVANCE WHEN GAME FINISHES =====================

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
BEGIN
  IF NEW.status <> 'finished' OR OLD.status = 'finished' THEN RETURN NEW; END IF;
  IF NEW.tournament_match_id IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_match FROM public.tournament_matches WHERE id = NEW.tournament_match_id FOR UPDATE;
  IF v_match.id IS NULL OR v_match.status = 'finished' THEN RETURN NEW; END IF;

  UPDATE public.tournament_matches
    SET status='finished', winner_id = NEW.winner_id, finished_at = now()
    WHERE id = v_match.id;

  -- Mark losers eliminated for this round
  SELECT * INTO v_t FROM public.tournaments WHERE id = v_match.tournament_id FOR UPDATE;
  UPDATE public.tournament_registrations
    SET eliminated_round = v_t.current_round
    WHERE tournament_id = v_t.id
      AND user_id = ANY(v_match.player_ids)
      AND user_id IS DISTINCT FROM NEW.winner_id
      AND eliminated_round IS NULL;

  -- Are all matches of current round done?
  SELECT count(*) INTO v_remaining
    FROM public.tournament_matches
    WHERE tournament_id = v_t.id AND round = v_t.current_round AND status NOT IN ('finished','bye');
  IF v_remaining > 0 THEN RETURN NEW; END IF;

  -- All done: gather winners
  SELECT array_agg(winner_id ORDER BY match_index) INTO v_winners
    FROM public.tournament_matches
    WHERE tournament_id = v_t.id AND round = v_t.current_round AND winner_id IS NOT NULL;
  v_total := COALESCE(array_length(v_winners,1),0);

  IF v_total <= 1 THEN
    -- Tournament finished
    v_top3 := '[]'::jsonb;
    -- Build top3: champion + 2nd (loser of final) + 3rd (best by latest elimination)
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

    -- Distribute prize pool to champion (minus commission)
    IF NOT v_t.is_free AND v_t.prize_pool > 0 THEN
      v_payout := v_t.prize_pool * (100 - v_t.commission_pct) / 100.0;
      UPDATE public.profiles SET balance_ar = balance_ar + v_payout WHERE id = v_winners[1];
      INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
        VALUES (v_winners[1],'win', v_payout, v_t.id, 'Victoire tournoi: '||v_t.name);
    END IF;
    RETURN NEW;
  END IF;

  -- Build next round
  UPDATE public.tournaments SET current_round = current_round + 1 WHERE id = v_t.id;
  PERFORM public._tournament_build_round(v_t.id, v_t.current_round + 1, v_winners);

  -- Create games for next round pending matches
  FOR m IN SELECT * FROM public.tournament_matches
           WHERE tournament_id = v_t.id AND round = v_t.current_round + 1 AND status = 'pending' ORDER BY match_index LOOP
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

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_tournament_on_game_finished ON public.ludo_games;
CREATE TRIGGER trg_tournament_on_game_finished
  AFTER UPDATE OF status ON public.ludo_games
  FOR EACH ROW EXECUTE FUNCTION public._tournament_on_game_finished();

-- ===================== LIST / DETAIL RPCs =====================

CREATE OR REPLACE FUNCTION public.list_tournaments(_status text DEFAULT NULL)
RETURNS TABLE (
  id uuid, name text, mode text, max_players int, stake numeric, is_free boolean, season int,
  status text, current_round int, total_rounds int, prize_pool numeric, winner_id uuid,
  created_at timestamptz, finished_at timestamptz, registered_count bigint
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT t.id, t.name, t.mode, t.max_players, t.stake, t.is_free, t.season,
         t.status, t.current_round, t.total_rounds, t.prize_pool, t.winner_id,
         t.created_at, t.finished_at,
         (SELECT count(*) FROM public.tournament_registrations r WHERE r.tournament_id = t.id) AS registered_count
    FROM public.tournaments t
    WHERE _status IS NULL OR t.status = _status
    ORDER BY (CASE WHEN t.status='running' THEN 0 WHEN t.status='open' THEN 1 WHEN t.status='finished' THEN 2 ELSE 3 END),
             t.created_at DESC;
$$;
REVOKE EXECUTE ON FUNCTION public.list_tournaments(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_tournaments(text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_tournament_detail(_tid uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb;
BEGIN
  SELECT jsonb_build_object(
    'tournament', to_jsonb(t),
    'players', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'user_id', r.user_id, 'pseudo', p.pseudo, 'avatar_url', p.avatar_url,
        'eliminated_round', r.eliminated_round, 'final_position', r.final_position
      ) ORDER BY r.registered_at)
      FROM public.tournament_registrations r
      LEFT JOIN public.profiles p ON p.id = r.user_id
      WHERE r.tournament_id = t.id
    ), '[]'::jsonb),
    'matches', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', m.id, 'round', m.round, 'match_index', m.match_index,
        'player_ids', m.player_ids, 'status', m.status,
        'game_id', m.game_id, 'winner_id', m.winner_id, 'finished_at', m.finished_at
      ) ORDER BY m.round, m.match_index)
      FROM public.tournament_matches m WHERE m.tournament_id = t.id
    ), '[]'::jsonb)
  ) INTO v
  FROM public.tournaments t WHERE t.id = _tid;
  RETURN v;
END $$;
REVOKE EXECUTE ON FUNCTION public.get_tournament_detail(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_tournament_detail(uuid) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.hall_of_fame()
RETURNS TABLE (
  id uuid, name text, mode text, season int, finished_at timestamptz,
  winner_id uuid, winner_pseudo text, top3 jsonb, prize_pool numeric
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT t.id, t.name, t.mode, t.season, t.finished_at,
         t.winner_id, p.pseudo AS winner_pseudo, t.top3, t.prize_pool
  FROM public.tournaments t
  LEFT JOIN public.profiles p ON p.id = t.winner_id
  WHERE t.status = 'finished'
  ORDER BY t.finished_at DESC;
$$;
REVOKE EXECUTE ON FUNCTION public.hall_of_fame() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hall_of_fame() TO anon, authenticated;
