
-- ============================================================
-- READY SYSTEM for Rami, Fanorona, Chess (Ludo & Domino already have it)
-- ============================================================

-- ============= RAMI =============
ALTER TABLE public.rami_participants ADD COLUMN IF NOT EXISTS ready boolean NOT NULL DEFAULT false;

-- Remove auto-start from rami_join_code
CREATE OR REPLACE FUNCTION public.rami_join_code(_code text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid uuid := auth.uid(); _g rami_games; _slot int; _bal numeric; _name text; _count int;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM rami_games WHERE room_code = upper(_code) FOR UPDATE;
  IF _g.id IS NULL THEN RAISE EXCEPTION 'partie introuvable'; END IF;
  IF _g.status <> 'waiting' THEN RAISE EXCEPTION 'partie déjà commencée'; END IF;
  IF EXISTS (SELECT 1 FROM rami_participants WHERE game_id=_g.id AND user_id=_uid) THEN RETURN _g.id; END IF;
  SELECT count(*) INTO _count FROM rami_participants WHERE game_id=_g.id;
  IF _count >= _g.max_players THEN RAISE EXCEPTION 'partie pleine'; END IF;
  SELECT balance, COALESCE(display_name, pseudo, 'Joueur') INTO _bal, _name FROM profiles WHERE id = _uid;
  IF _bal IS NULL OR _bal < _g.stake THEN RAISE EXCEPTION 'solde insuffisant'; END IF;
  _slot := _count;
  IF _g.stake > 0 THEN
    UPDATE profiles SET balance = balance - _g.stake WHERE id = _uid;
    UPDATE rami_games SET pot = pot + _g.stake WHERE id = _g.id;
    INSERT INTO transactions (user_id, type, amount, status, metadata)
      VALUES (_uid, 'game_stake', -_g.stake, 'completed', jsonb_build_object('game','rami','game_id',_g.id));
  END IF;
  INSERT INTO rami_participants (game_id, user_id, slot, display_name) VALUES (_g.id, _uid, _slot, _name);
  -- No auto-start: wait for all participants to mark themselves ready.
  RETURN _g.id;
END $$;

CREATE OR REPLACE FUNCTION public.rami_set_ready(_game_id uuid, _ready boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_g rami_games; v_total int; v_ready int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  UPDATE rami_participants SET ready = COALESCE(_ready, false)
    WHERE game_id = _game_id AND user_id = v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'not a participant'; END IF;
  SELECT * INTO v_g FROM rami_games WHERE id = _game_id AND status = 'waiting';
  IF v_g.id IS NULL THEN RETURN; END IF;
  SELECT count(*), count(*) FILTER (WHERE ready) INTO v_total, v_ready
    FROM rami_participants WHERE game_id = _game_id;
  IF v_total = v_g.max_players AND v_ready = v_total THEN
    PERFORM public.rami_start(_game_id);
  END IF;
END $$;
GRANT EXECUTE ON FUNCTION public.rami_set_ready(uuid, boolean) TO authenticated;


-- ============= FANORONA =============
ALTER TABLE public.fanorona_participants ADD COLUMN IF NOT EXISTS ready boolean NOT NULL DEFAULT false;

-- Split join: insert participant but don't start the game
CREATE OR REPLACE FUNCTION public.fanorona_join(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  g record;
  v_balance numeric;
  v_name text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL OR g.status <> 'open' THEN RAISE EXCEPTION 'game not joinable'; END IF;
  IF EXISTS(SELECT 1 FROM public.fanorona_participants WHERE game_id = _game_id AND user_id = v_uid) THEN RETURN; END IF;
  SELECT balance_ar, pseudo INTO v_balance, v_name FROM public.profiles WHERE id = v_uid;
  IF v_balance < g.stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;
  IF (SELECT count(*) FROM public.fanorona_participants WHERE game_id = _game_id) >= 2 THEN RAISE EXCEPTION 'full'; END IF;

  INSERT INTO public.fanorona_participants(game_id, user_id, slot, color, display_name)
    VALUES (_game_id, v_uid, 1, 'black', COALESCE(v_name,'Player'));
  UPDATE public.profiles SET balance_ar = balance_ar - g.stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
    VALUES (v_uid, 'fanorona_stake', -g.stake, _game_id, 'Join fanorona');
  UPDATE public.fanorona_games SET pot = pot + g.stake WHERE id = _game_id;
  -- No auto-start: wait for both players to mark themselves ready.
END $$;

CREATE OR REPLACE FUNCTION public.fanorona_set_ready(_game_id uuid, _ready boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_total int; v_ready int; v_status text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  UPDATE public.fanorona_participants SET ready = COALESCE(_ready, false)
    WHERE game_id = _game_id AND user_id = v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'not a participant'; END IF;
  SELECT status INTO v_status FROM public.fanorona_games WHERE id = _game_id;
  IF v_status <> 'open' THEN RETURN; END IF;
  SELECT count(*), count(*) FILTER (WHERE ready) INTO v_total, v_ready
    FROM public.fanorona_participants WHERE game_id = _game_id;
  IF v_total = 2 AND v_ready = 2 THEN
    UPDATE public.fanorona_games
       SET status = 'playing',
           started_at = now(),
           state = jsonb_set(state, '{phase}', '"playing"'::jsonb),
           current_turn = 0
     WHERE id = _game_id AND status = 'open';
  END IF;
END $$;
GRANT EXECUTE ON FUNCTION public.fanorona_set_ready(uuid, boolean) TO authenticated;


-- ============= CHESS =============
ALTER TABLE public.chess_games
  ADD COLUMN IF NOT EXISTS ready_white boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS ready_black boolean NOT NULL DEFAULT false;

-- Split chess_join_code: assign player but don't start
CREATE OR REPLACE FUNCTION public.chess_join_code(_code text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_g chess_games%ROWTYPE; v_bal numeric; v_flip boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE room_code = upper(_code) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status <> 'open' THEN RAISE EXCEPTION 'game not open'; END IF;
  IF v_g.host_id = v_uid THEN RAISE EXCEPTION 'cannot join own game'; END IF;
  SELECT balance_ar INTO v_bal FROM profiles WHERE id = v_uid;
  IF v_bal < v_g.stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;
  v_flip := (random() < 0.5);
  IF v_flip THEN
    UPDATE chess_games SET black_id = v_uid, pot = pot + v_g.stake WHERE id = v_g.id;
  ELSE
    UPDATE chess_games SET white_id = v_uid, black_id = v_g.host_id, pot = pot + v_g.stake WHERE id = v_g.id;
  END IF;
  UPDATE profiles SET balance_ar = balance_ar - v_g.stake WHERE id = v_uid;
  INSERT INTO transactions(user_id, type, amount, ref_id, note) VALUES (v_uid, 'chess_stake', -v_g.stake, v_g.id, 'Join chess');
  -- No auto-start: both players must mark themselves ready first.
  RETURN v_g.id;
END $$;

CREATE OR REPLACE FUNCTION public.chess_set_ready(_game_id uuid, _ready boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_g chess_games%ROWTYPE; _cfg record;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id = _game_id FOR UPDATE;
  IF v_g.id IS NULL THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status <> 'open' THEN RETURN; END IF;
  IF v_uid = v_g.white_id THEN
    UPDATE chess_games SET ready_white = COALESCE(_ready, false) WHERE id = _game_id;
  ELSIF v_uid = v_g.black_id THEN
    UPDATE chess_games SET ready_black = COALESCE(_ready, false) WHERE id = _game_id;
  ELSE
    RAISE EXCEPTION 'not a player';
  END IF;
  SELECT * INTO v_g FROM chess_games WHERE id = _game_id;
  IF v_g.white_id IS NOT NULL AND v_g.black_id IS NOT NULL AND v_g.ready_white AND v_g.ready_black THEN
    SELECT * INTO _cfg FROM public._game_cfg('chess');
    UPDATE chess_games
       SET status = 'playing',
           started_at = now(),
           turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval
     WHERE id = _game_id AND status = 'open';
  END IF;
END $$;
GRANT EXECUTE ON FUNCTION public.chess_set_ready(uuid, boolean) TO authenticated;
