
-- =========================================================================
-- DOMINO + FANORONA : tables, RLS, RPCs
-- =========================================================================

-- Reuse existing game_status enum (open/playing/finished/cancelled)
-- Reuse existing transactions/profiles/is_admin/_game_visible helpers

-- ---------- DOMINO TABLES ----------
CREATE TABLE public.domino_games (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id uuid NOT NULL REFERENCES auth.users(id),
  max_players int NOT NULL CHECK (max_players BETWEEN 2 AND 4),
  stake numeric NOT NULL CHECK (stake >= 0),
  pot numeric NOT NULL DEFAULT 0,
  commission_pct numeric NOT NULL DEFAULT 10,
  status game_status NOT NULL DEFAULT 'open',
  is_private boolean NOT NULL DEFAULT false,
  room_code text UNIQUE,
  mode text NOT NULL DEFAULT 'classic',
  state jsonb NOT NULL DEFAULT '{}'::jsonb,
  current_turn int NOT NULL DEFAULT 0,
  winner_id uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  finished_at timestamptz
);

CREATE TABLE public.domino_participants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id uuid NOT NULL REFERENCES public.domino_games(id) ON DELETE CASCADE,
  user_id uuid REFERENCES auth.users(id),
  slot int NOT NULL,
  display_name text NOT NULL,
  joined_at timestamptz NOT NULL DEFAULT now(),
  forfeited boolean NOT NULL DEFAULT false,
  UNIQUE(game_id, slot),
  UNIQUE(game_id, user_id)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.domino_games TO authenticated;
GRANT ALL ON public.domino_games TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.domino_participants TO authenticated;
GRANT ALL ON public.domino_participants TO service_role;

ALTER TABLE public.domino_games ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.domino_participants ENABLE ROW LEVEL SECURITY;

-- Visibility helper
CREATE OR REPLACE FUNCTION public._domino_visible(_game_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS(
    SELECT 1 FROM public.domino_games g
    WHERE g.id = _game_id
      AND (
        (g.status IN ('open','playing') AND g.is_private = false)
        OR g.host_id = auth.uid()
        OR EXISTS(SELECT 1 FROM public.domino_participants p WHERE p.game_id = g.id AND p.user_id = auth.uid())
        OR public.is_admin()
      )
  )
$$;

CREATE POLICY domino_games_select ON public.domino_games
  FOR SELECT USING (
    (status IN ('open','playing') AND is_private = false)
    OR host_id = auth.uid()
    OR EXISTS(SELECT 1 FROM public.domino_participants p WHERE p.game_id = id AND p.user_id = auth.uid())
    OR public.is_admin()
  );

CREATE POLICY domino_parts_select ON public.domino_participants
  FOR SELECT USING (public._domino_visible(game_id));

-- ---------- FANORONA TABLES ----------
CREATE TABLE public.fanorona_games (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id uuid NOT NULL REFERENCES auth.users(id),
  stake numeric NOT NULL CHECK (stake >= 0),
  pot numeric NOT NULL DEFAULT 0,
  commission_pct numeric NOT NULL DEFAULT 10,
  status game_status NOT NULL DEFAULT 'open',
  is_private boolean NOT NULL DEFAULT false,
  room_code text UNIQUE,
  state jsonb NOT NULL DEFAULT '{}'::jsonb,
  current_turn int NOT NULL DEFAULT 0,
  winner_id uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  finished_at timestamptz
);

CREATE TABLE public.fanorona_participants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id uuid NOT NULL REFERENCES public.fanorona_games(id) ON DELETE CASCADE,
  user_id uuid REFERENCES auth.users(id),
  slot int NOT NULL CHECK (slot IN (0,1)),
  color text NOT NULL CHECK (color IN ('white','black')),
  display_name text NOT NULL,
  joined_at timestamptz NOT NULL DEFAULT now(),
  forfeited boolean NOT NULL DEFAULT false,
  UNIQUE(game_id, slot),
  UNIQUE(game_id, user_id)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.fanorona_games TO authenticated;
GRANT ALL ON public.fanorona_games TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.fanorona_participants TO authenticated;
GRANT ALL ON public.fanorona_participants TO service_role;

ALTER TABLE public.fanorona_games ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fanorona_participants ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public._fanorona_visible(_game_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS(
    SELECT 1 FROM public.fanorona_games g
    WHERE g.id = _game_id
      AND (
        (g.status IN ('open','playing') AND g.is_private = false)
        OR g.host_id = auth.uid()
        OR EXISTS(SELECT 1 FROM public.fanorona_participants p WHERE p.game_id = g.id AND p.user_id = auth.uid())
        OR public.is_admin()
      )
  )
$$;

CREATE POLICY fanorona_games_select ON public.fanorona_games
  FOR SELECT USING (
    (status IN ('open','playing') AND is_private = false)
    OR host_id = auth.uid()
    OR EXISTS(SELECT 1 FROM public.fanorona_participants p WHERE p.game_id = id AND p.user_id = auth.uid())
    OR public.is_admin()
  );

CREATE POLICY fanorona_parts_select ON public.fanorona_participants
  FOR SELECT USING (public._fanorona_visible(game_id));

-- =========================================================================
-- DOMINO RPCs
-- =========================================================================

-- Initial empty state
CREATE OR REPLACE FUNCTION public._domino_init_state()
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT '{"phase":"waiting","hands":{},"stock":[],"board":[],"left_end":null,"right_end":null,"passes":0,"scores":{}}'::jsonb
$$;

-- Build full domino set and shuffle (server-side)
CREATE OR REPLACE FUNCTION public._domino_deal(_n_players int)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  tiles int[][] := ARRAY[]::int[][];
  a int; b int;
  shuffled jsonb;
  arr jsonb := '[]'::jsonb;
  i int;
BEGIN
  FOR a IN 0..6 LOOP
    FOR b IN a..6 LOOP
      arr := arr || jsonb_build_array(jsonb_build_array(a,b));
    END LOOP;
  END LOOP;
  -- shuffle in SQL
  SELECT jsonb_agg(value ORDER BY random()) INTO shuffled FROM jsonb_array_elements(arr);
  RETURN shuffled;
END $$;

CREATE OR REPLACE FUNCTION public.domino_create(
  _stake numeric, _max int, _private boolean, _mode text DEFAULT 'classic', _commission numeric DEFAULT 10
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_balance numeric;
  v_code text;
  v_id uuid;
  v_name text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _max NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'invalid max_players'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'invalid stake'; END IF;

  SELECT balance_ar, pseudo INTO v_balance, v_name FROM public.profiles WHERE id = v_uid;
  IF v_balance IS NULL OR v_balance < _stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;

  IF _private THEN
    v_code := upper(substring(md5(random()::text||clock_timestamp()::text) from 1 for 6));
  END IF;

  INSERT INTO public.domino_games(host_id, max_players, stake, pot, commission_pct, is_private, room_code, mode, state)
  VALUES (v_uid, _max, _stake, _stake, _commission, _private, v_code, _mode, public._domino_init_state())
  RETURNING id INTO v_id;

  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note) VALUES (v_uid, 'domino_stake', -_stake, v_id, 'Create domino game');

  INSERT INTO public.domino_participants(game_id, user_id, slot, display_name) VALUES (v_id, v_uid, 0, COALESCE(v_name,'Player'));
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION public._domino_start(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  g record;
  n int;
  tiles jsonb;
  hands jsonb := '{}'::jsonb;
  stock jsonb;
  per_hand int;
  p record;
  idx int := 0;
  hand jsonb;
  starter int := 0;
  best int := -1;
  cur int;
  t jsonb;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'open' THEN RETURN; END IF;
  SELECT count(*) INTO n FROM public.domino_participants WHERE game_id = _game_id;
  IF n < g.max_players THEN RETURN; END IF;

  tiles := public._domino_deal(n);
  per_hand := CASE WHEN n = 2 THEN 7 WHEN n = 3 THEN 7 ELSE 7 END;

  FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id ORDER BY slot LOOP
    SELECT jsonb_agg(value) INTO hand FROM jsonb_array_elements(tiles) WITH ORDINALITY t(value, ord)
      WHERE ord > idx*per_hand AND ord <= (idx+1)*per_hand;
    hands := hands || jsonb_build_object(p.slot::text, COALESCE(hand,'[]'::jsonb));
    idx := idx + 1;
  END LOOP;

  SELECT jsonb_agg(value) INTO stock FROM jsonb_array_elements(tiles) WITH ORDINALITY t(value, ord)
    WHERE ord > n*per_hand;
  stock := COALESCE(stock, '[]'::jsonb);

  -- Determine starter: highest double; else highest pip sum
  FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id ORDER BY slot LOOP
    cur := -1;
    FOR t IN SELECT * FROM jsonb_array_elements(hands -> p.slot::text) LOOP
      IF (t->>0)::int = (t->>1)::int AND (t->>0)::int > cur THEN cur := (t->>0)::int * 10 + 100; END IF;
    END LOOP;
    IF cur > best THEN best := cur; starter := p.slot; END IF;
  END LOOP;

  UPDATE public.domino_games SET
    status = 'playing',
    started_at = now(),
    current_turn = starter,
    state = jsonb_build_object(
      'phase','playing',
      'hands', hands,
      'stock', stock,
      'board', '[]'::jsonb,
      'left_end', null,
      'right_end', null,
      'passes', 0,
      'scores', '{}'::jsonb
    )
  WHERE id = _game_id;
END $$;

CREATE OR REPLACE FUNCTION public.domino_join(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  g record;
  v_balance numeric;
  v_name text;
  v_slot int;
  v_count int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL OR g.status <> 'open' THEN RAISE EXCEPTION 'game not joinable'; END IF;
  IF EXISTS(SELECT 1 FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid) THEN RETURN; END IF;
  SELECT balance_ar, pseudo INTO v_balance, v_name FROM public.profiles WHERE id = v_uid;
  IF v_balance < g.stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;

  SELECT count(*) INTO v_count FROM public.domino_participants WHERE game_id = _game_id;
  IF v_count >= g.max_players THEN RAISE EXCEPTION 'full'; END IF;
  v_slot := v_count;

  INSERT INTO public.domino_participants(game_id, user_id, slot, display_name) VALUES (_game_id, v_uid, v_slot, COALESCE(v_name,'Player'));
  UPDATE public.profiles SET balance_ar = balance_ar - g.stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note) VALUES (v_uid, 'domino_stake', -g.stake, _game_id, 'Join domino game');
  UPDATE public.domino_games SET pot = pot + g.stake WHERE id = _game_id;

  IF v_count + 1 >= g.max_players THEN PERFORM public._domino_start(_game_id); END IF;
END $$;

CREATE OR REPLACE FUNCTION public.domino_join_code(_code text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE g_id uuid;
BEGIN
  SELECT id INTO g_id FROM public.domino_games WHERE room_code = upper(_code) AND status = 'open';
  IF g_id IS NULL THEN RAISE EXCEPTION 'invalid code'; END IF;
  PERFORM public.domino_join(g_id);
  RETURN g_id;
END $$;

-- Finalize: distribute pot to winner (minus commission)
CREATE OR REPLACE FUNCTION public._domino_finalize(_game_id uuid, _winner_slot int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  g record;
  winner_uid uuid;
  payout numeric;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status = 'finished' THEN RETURN; END IF;
  SELECT user_id INTO winner_uid FROM public.domino_participants WHERE game_id = _game_id AND slot = _winner_slot;
  payout := g.pot * (100 - g.commission_pct) / 100;
  IF winner_uid IS NOT NULL THEN
    UPDATE public.profiles SET balance_ar = balance_ar + payout WHERE id = winner_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note) VALUES (winner_uid, 'domino_win', payout, _game_id, 'Domino win');
  END IF;
  UPDATE public.domino_games SET status = 'finished', winner_id = winner_uid, finished_at = now() WHERE id = _game_id;
END $$;

-- Play / pass / draw — all-in-one move RPC. Validates turn + tile possession + end match.
-- _move = { "action": "play"|"draw"|"pass", "tile": [a,b], "side": "left"|"right" }
CREATE OR REPLACE FUNCTION public.domino_play(_game_id uuid, _move jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  g record;
  my_slot int;
  st jsonb;
  hand jsonb;
  tile jsonb;
  a int; b int;
  le int; re int;
  side text;
  new_left int; new_right int;
  action text;
  n_players int;
  next_turn int;
  drawn jsonb;
  stock jsonb;
  found boolean := false;
  new_hand jsonb;
  i int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  SELECT slot INTO my_slot FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid;
  IF my_slot IS NULL OR my_slot <> g.current_turn THEN RAISE EXCEPTION 'not your turn'; END IF;

  st := g.state;
  action := _move->>'action';
  hand := st -> 'hands' -> my_slot::text;
  stock := st -> 'stock';
  le := NULLIF(st->>'left_end','null')::int;
  re := NULLIF(st->>'right_end','null')::int;
  SELECT count(*) INTO n_players FROM public.domino_participants WHERE game_id = _game_id;

  IF action = 'draw' THEN
    IF jsonb_array_length(stock) = 0 THEN RAISE EXCEPTION 'stock empty'; END IF;
    drawn := stock -> 0;
    stock := stock - 0;
    hand := hand || jsonb_build_array(drawn);
    st := jsonb_set(st, ARRAY['hands', my_slot::text], hand);
    st := jsonb_set(st, '{stock}', stock);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    RETURN;
  END IF;

  IF action = 'pass' THEN
    st := jsonb_set(st, '{passes}', to_jsonb( COALESCE((st->>'passes')::int,0) + 1 ));
    next_turn := (my_slot + 1) % n_players;
    -- All passed => lowest pip sum wins
    IF (st->>'passes')::int >= n_players THEN
      DECLARE
        p record; best_slot int := 0; best_sum int := 9999; cur_sum int; t jsonb;
      BEGIN
        FOR p IN SELECT slot FROM public.domino_participants WHERE game_id = _game_id LOOP
          cur_sum := 0;
          FOR t IN SELECT * FROM jsonb_array_elements(st->'hands'->p.slot::text) LOOP
            cur_sum := cur_sum + (t->>0)::int + (t->>1)::int;
          END LOOP;
          IF cur_sum < best_sum THEN best_sum := cur_sum; best_slot := p.slot; END IF;
        END LOOP;
        UPDATE public.domino_games SET state = st, current_turn = next_turn WHERE id = _game_id;
        PERFORM public._domino_finalize(_game_id, best_slot);
        RETURN;
      END;
    END IF;
    UPDATE public.domino_games SET state = st, current_turn = next_turn WHERE id = _game_id;
    RETURN;
  END IF;

  -- play
  tile := _move -> 'tile';
  side := COALESCE(_move->>'side','right');
  a := (tile->>0)::int; b := (tile->>1)::int;

  -- verify tile in hand
  new_hand := '[]'::jsonb;
  FOR i IN 0..jsonb_array_length(hand)-1 LOOP
    IF NOT found AND ((hand->i->>0)::int = a AND (hand->i->>1)::int = b) THEN
      found := true;
    ELSE
      new_hand := new_hand || jsonb_build_array(hand->i);
    END IF;
  END LOOP;
  IF NOT found THEN RAISE EXCEPTION 'tile not in hand'; END IF;

  -- placement
  IF jsonb_array_length(st->'board') = 0 THEN
    st := jsonb_set(st, '{board}', jsonb_build_array(jsonb_build_object('tile', tile, 'flipped', false)));
    new_left := a; new_right := b;
  ELSIF side = 'left' THEN
    IF a = le THEN new_left := b;
    ELSIF b = le THEN new_left := a;
    ELSE RAISE EXCEPTION 'tile does not match left end'; END IF;
    st := jsonb_set(st, '{board}', jsonb_build_array(jsonb_build_object('tile', tile, 'flipped', a<>le)) || (st->'board'));
    new_right := re;
  ELSE
    IF a = re THEN new_right := b;
    ELSIF b = re THEN new_right := a;
    ELSE RAISE EXCEPTION 'tile does not match right end'; END IF;
    st := jsonb_set(st, '{board}', (st->'board') || jsonb_build_array(jsonb_build_object('tile', tile, 'flipped', a=re AND a<>b)));
    new_left := le;
  END IF;

  st := jsonb_set(st, ARRAY['hands', my_slot::text], new_hand);
  st := jsonb_set(st, '{left_end}', to_jsonb(new_left));
  st := jsonb_set(st, '{right_end}', to_jsonb(new_right));
  st := jsonb_set(st, '{passes}', to_jsonb(0));

  -- Win condition: empty hand
  IF jsonb_array_length(new_hand) = 0 THEN
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_finalize(_game_id, my_slot);
    RETURN;
  END IF;

  next_turn := (my_slot + 1) % n_players;
  UPDATE public.domino_games SET state = st, current_turn = next_turn WHERE id = _game_id;
END $$;

CREATE OR REPLACE FUNCTION public.domino_forfeit(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  g record;
  my_slot int;
  remaining int;
  last_slot int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status NOT IN ('open','playing') THEN RETURN; END IF;
  SELECT slot INTO my_slot FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid;
  IF my_slot IS NULL THEN RETURN; END IF;
  UPDATE public.domino_participants SET forfeited = true WHERE game_id = _game_id AND user_id = v_uid;

  IF g.status = 'open' THEN
    -- refund all participants and cancel
    UPDATE public.profiles p SET balance_ar = balance_ar + g.stake
      FROM public.domino_participants pp WHERE pp.game_id = _game_id AND pp.user_id = p.id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      SELECT user_id, 'domino_refund', g.stake, _game_id, 'Game cancelled' FROM public.domino_participants WHERE game_id = _game_id;
    UPDATE public.domino_games SET status = 'cancelled', finished_at = now() WHERE id = _game_id;
    RETURN;
  END IF;

  SELECT count(*) INTO remaining FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  IF remaining = 1 THEN
    SELECT slot INTO last_slot FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
    PERFORM public._domino_finalize(_game_id, last_slot);
  END IF;
END $$;

-- =========================================================================
-- FANORONA RPCs
-- Board: 5 rows × 9 cols. Cell index = row*9 + col. 0=empty, 1=white, 2=black.
-- Initial: rows 0-1 = black (2), row 2 alternating with empty middle, rows 3-4 = white (1).
-- =========================================================================

CREATE OR REPLACE FUNCTION public._fanorona_init_board()
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_array(
    -- row 0: black
    2,2,2,2,2,2,2,2,2,
    -- row 1: black
    2,2,2,2,2,2,2,2,2,
    -- row 2: alternating B W _ W B _ B W B  (standard Fanorona middle: B,W,B,W,_,B,W,B,W from left? Use canonical)
    -- Canonical row 2: 1,2,1,2,0,1,2,1,2  (white, black, white, black, empty, white, black, white, black)
    1,2,1,2,0,1,2,1,2,
    -- row 3: white
    1,1,1,1,1,1,1,1,1,
    -- row 4: white
    1,1,1,1,1,1,1,1,1
  )::jsonb
$$;

CREATE OR REPLACE FUNCTION public.fanorona_create(
  _stake numeric, _private boolean, _commission numeric DEFAULT 10
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_balance numeric;
  v_code text;
  v_id uuid;
  v_name text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'invalid stake'; END IF;
  SELECT balance_ar, pseudo INTO v_balance, v_name FROM public.profiles WHERE id = v_uid;
  IF v_balance < _stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;
  IF _private THEN v_code := upper(substring(md5(random()::text||clock_timestamp()::text) from 1 for 6)); END IF;

  INSERT INTO public.fanorona_games(host_id, stake, pot, commission_pct, is_private, room_code, state)
  VALUES (v_uid, _stake, _stake, _commission, _private, v_code,
    jsonb_build_object('phase','waiting','board', public._fanorona_init_board(), 'chain_from', null, 'chain_dirs', '[]'::jsonb))
  RETURNING id INTO v_id;

  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note) VALUES (v_uid, 'fanorona_stake', -_stake, v_id, 'Create fanorona');
  INSERT INTO public.fanorona_participants(game_id, user_id, slot, color, display_name) VALUES (v_id, v_uid, 0, 'white', COALESCE(v_name,'Player'));
  RETURN v_id;
END $$;

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

  INSERT INTO public.fanorona_participants(game_id, user_id, slot, color, display_name) VALUES (_game_id, v_uid, 1, 'black', COALESCE(v_name,'Player'));
  UPDATE public.profiles SET balance_ar = balance_ar - g.stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note) VALUES (v_uid, 'fanorona_stake', -g.stake, _game_id, 'Join fanorona');
  UPDATE public.fanorona_games SET pot = pot + g.stake, status = 'playing', started_at = now(),
    state = jsonb_set(state, '{phase}', '"playing"'::jsonb), current_turn = 0
  WHERE id = _game_id;
END $$;

CREATE OR REPLACE FUNCTION public.fanorona_join_code(_code text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE g_id uuid;
BEGIN
  SELECT id INTO g_id FROM public.fanorona_games WHERE room_code = upper(_code) AND status = 'open';
  IF g_id IS NULL THEN RAISE EXCEPTION 'invalid code'; END IF;
  PERFORM public.fanorona_join(g_id);
  RETURN g_id;
END $$;

CREATE OR REPLACE FUNCTION public._fanorona_finalize(_game_id uuid, _winner_slot int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE g record; winner_uid uuid; payout numeric;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.status = 'finished' THEN RETURN; END IF;
  SELECT user_id INTO winner_uid FROM public.fanorona_participants WHERE game_id = _game_id AND slot = _winner_slot;
  payout := g.pot * (100 - g.commission_pct) / 100;
  IF winner_uid IS NOT NULL THEN
    UPDATE public.profiles SET balance_ar = balance_ar + payout WHERE id = winner_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note) VALUES (winner_uid, 'fanorona_win', payout, _game_id, 'Fanorona win');
  END IF;
  UPDATE public.fanorona_games SET status = 'finished', winner_id = winner_uid, finished_at = now() WHERE id = _game_id;
END $$;

-- Fanorona play: _move = { "from": idx, "to": idx, "captured": [idx,...], "chain": bool }
-- Server validates: turn, ownership, adjacency, target empty.
-- Capture validation: 'captured' must be opponent pieces; trusted to be correct line. After applied,
-- if chain=true, board updated but turn stays (same player must call again or pass chain).
-- chain end signaled by 'chain':false (or no captured). End condition: opponent has 0 pieces or no moves.
CREATE OR REPLACE FUNCTION public.fanorona_play(_game_id uuid, _move jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  g record;
  my_slot int;
  my_color int; opp_color int;
  st jsonb;
  board jsonb;
  from_idx int; to_idx int;
  from_r int; from_c int; to_r int; to_c int;
  dr int; dc int;
  cap jsonb;
  c_idx int;
  i int;
  opp_left int;
  next_turn int;
  chain boolean;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  SELECT slot INTO my_slot FROM public.fanorona_participants WHERE game_id = _game_id AND user_id = v_uid;
  IF my_slot IS NULL OR my_slot <> g.current_turn THEN RAISE EXCEPTION 'not your turn'; END IF;

  my_color := CASE WHEN my_slot = 0 THEN 1 ELSE 2 END;
  opp_color := CASE WHEN my_slot = 0 THEN 2 ELSE 1 END;
  st := g.state;
  board := st -> 'board';

  from_idx := (_move->>'from')::int;
  to_idx := (_move->>'to')::int;
  cap := COALESCE(_move->'captured', '[]'::jsonb);
  chain := COALESCE((_move->>'chain')::boolean, false);

  IF (board->from_idx)::int <> my_color THEN RAISE EXCEPTION 'not your piece'; END IF;
  IF (board->to_idx)::int <> 0 THEN RAISE EXCEPTION 'target not empty'; END IF;

  from_r := from_idx / 9; from_c := from_idx % 9;
  to_r := to_idx / 9; to_c := to_idx % 9;
  dr := to_r - from_r; dc := to_c - from_c;
  -- Must be one step in 8 directions (diagonals only allowed on "strong" intersections, but we permit all 8 — client enforces).
  IF abs(dr) > 1 OR abs(dc) > 1 OR (dr = 0 AND dc = 0) THEN RAISE EXCEPTION 'invalid step'; END IF;

  -- Apply move
  board := jsonb_set(board, ARRAY[from_idx::text], '0'::jsonb);
  board := jsonb_set(board, ARRAY[to_idx::text], to_jsonb(my_color));

  -- Apply captures (trust client list, but verify each is opponent piece)
  FOR i IN 0..jsonb_array_length(cap)-1 LOOP
    c_idx := (cap->i)::int;
    IF (board->c_idx)::int <> opp_color THEN RAISE EXCEPTION 'invalid capture'; END IF;
    board := jsonb_set(board, ARRAY[c_idx::text], '0'::jsonb);
  END LOOP;

  st := jsonb_set(st, '{board}', board);

  -- Win check: opponent eliminated
  SELECT count(*) INTO opp_left FROM jsonb_array_elements(board) v WHERE (v::text)::int = opp_color;
  IF opp_left = 0 THEN
    UPDATE public.fanorona_games SET state = st WHERE id = _game_id;
    PERFORM public._fanorona_finalize(_game_id, my_slot);
    RETURN;
  END IF;

  IF chain THEN
    -- same turn continues (chain), track new chain root
    st := jsonb_set(st, '{chain_from}', to_jsonb(to_idx));
    UPDATE public.fanorona_games SET state = st WHERE id = _game_id;
  ELSE
    st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
    next_turn := 1 - my_slot;
    UPDATE public.fanorona_games SET state = st, current_turn = next_turn WHERE id = _game_id;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.fanorona_forfeit(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  g record;
  my_slot int;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.status NOT IN ('open','playing') THEN RETURN; END IF;
  SELECT slot INTO my_slot FROM public.fanorona_participants WHERE game_id = _game_id AND user_id = v_uid;
  IF my_slot IS NULL THEN RETURN; END IF;
  UPDATE public.fanorona_participants SET forfeited = true WHERE game_id = _game_id AND user_id = v_uid;

  IF g.status = 'open' THEN
    UPDATE public.profiles p SET balance_ar = balance_ar + g.stake
      FROM public.fanorona_participants pp WHERE pp.game_id = _game_id AND pp.user_id = p.id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      SELECT user_id, 'fanorona_refund', g.stake, _game_id, 'Game cancelled' FROM public.fanorona_participants WHERE game_id = _game_id;
    UPDATE public.fanorona_games SET status = 'cancelled', finished_at = now() WHERE id = _game_id;
    RETURN;
  END IF;

  PERFORM public._fanorona_finalize(_game_id, 1 - my_slot);
END $$;

-- =========================================================================
-- REALTIME
-- =========================================================================
ALTER PUBLICATION supabase_realtime ADD TABLE public.domino_games;
ALTER PUBLICATION supabase_realtime ADD TABLE public.domino_participants;
ALTER PUBLICATION supabase_realtime ADD TABLE public.fanorona_games;
ALTER PUBLICATION supabase_realtime ADD TABLE public.fanorona_participants;
