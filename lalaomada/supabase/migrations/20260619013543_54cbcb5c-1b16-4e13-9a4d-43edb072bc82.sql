
-- =================== TABLES ===================
CREATE TABLE public.rami_games (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_code text UNIQUE,
  is_private boolean NOT NULL DEFAULT true,
  status text NOT NULL DEFAULT 'waiting', -- waiting|playing|finished
  stake numeric NOT NULL DEFAULT 0,
  pot numeric NOT NULL DEFAULT 0,
  commission_pct int NOT NULL DEFAULT 10,
  max_players int NOT NULL DEFAULT 2,
  current_turn int NOT NULL DEFAULT 0,
  turn_phase text NOT NULL DEFAULT 'draw', -- draw|play
  turn_deadline timestamptz,
  winner_id uuid,
  state jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  finished_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.rami_games TO authenticated;
GRANT ALL ON public.rami_games TO service_role;
ALTER TABLE public.rami_games ENABLE ROW LEVEL SECURITY;
CREATE POLICY "rami_games read all auth" ON public.rami_games FOR SELECT TO authenticated USING (true);

CREATE TABLE public.rami_participants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id uuid NOT NULL REFERENCES public.rami_games(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id),
  slot int NOT NULL,
  display_name text,
  hand_count int NOT NULL DEFAULT 0,
  forfeited boolean NOT NULL DEFAULT false,
  joined_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(game_id, slot),
  UNIQUE(game_id, user_id)
);
GRANT SELECT, INSERT, UPDATE ON public.rami_participants TO authenticated;
GRANT ALL ON public.rami_participants TO service_role;
ALTER TABLE public.rami_participants ENABLE ROW LEVEL SECURITY;
CREATE POLICY "rami_participants read all auth" ON public.rami_participants FOR SELECT TO authenticated USING (true);

ALTER PUBLICATION supabase_realtime ADD TABLE public.rami_games;
ALTER PUBLICATION supabase_realtime ADD TABLE public.rami_participants;
ALTER TABLE public.rami_games REPLICA IDENTITY FULL;
ALTER TABLE public.rami_participants REPLICA IDENTITY FULL;

-- =================== HELPERS ===================
CREATE OR REPLACE FUNCTION public._rami_gen_code() RETURNS text LANGUAGE plpgsql AS $$
DECLARE c text; BEGIN
  LOOP
    c := upper(substr(md5(random()::text||clock_timestamp()::text),1,6));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.rami_games WHERE room_code = c);
  END LOOP;
  RETURN c;
END $$;

-- Validate a meld: array of card ids 0..53 (jokers = 52,53)
CREATE OR REPLACE FUNCTION public._rami_validate_meld(_cards int[]) RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  n int; jokers int := 0; non_jokers int[] := ARRAY[]::int[];
  suits int[] := ARRAY[]::int[]; ranks int[] := ARRAY[]::int[];
  c int; min_r int; max_r int; span int; nj int;
BEGIN
  n := COALESCE(array_length(_cards,1),0);
  IF n < 3 OR n > 14 THEN RETURN false; END IF;
  FOREACH c IN ARRAY _cards LOOP
    IF c < 0 OR c > 53 THEN RETURN false; END IF;
    IF c >= 52 THEN jokers := jokers + 1;
    ELSE
      non_jokers := array_append(non_jokers, c);
      suits := array_append(suits, c/13);
      ranks := array_append(ranks, c%13);
    END IF;
  END LOOP;
  nj := COALESCE(array_length(non_jokers,1),0);
  IF nj = 0 THEN RETURN false; END IF;
  -- SET
  IF n <= 4
    AND (SELECT count(DISTINCT x) FROM unnest(ranks) x) = 1
    AND (SELECT count(DISTINCT x) FROM unnest(suits) x) = nj
  THEN RETURN true; END IF;
  -- RUN
  IF (SELECT count(DISTINCT x) FROM unnest(suits) x) = 1
    AND (SELECT count(DISTINCT x) FROM unnest(ranks) x) = nj
  THEN
    SELECT min(x), max(x) INTO min_r, max_r FROM unnest(ranks) x;
    span := max_r - min_r + 1;
    IF span <= n AND n <= 13 AND jokers >= (span - nj) THEN RETURN true; END IF;
  END IF;
  RETURN false;
END $$;

CREATE OR REPLACE FUNCTION public._rami_remove_one(_arr int[], _v int) RETURNS int[] LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE i int; out int[] := ARRAY[]::int[]; removed boolean := false;
BEGIN
  IF _arr IS NULL THEN RETURN ARRAY[]::int[]; END IF;
  FOR i IN 1..array_length(_arr,1) LOOP
    IF NOT removed AND _arr[i] = _v THEN removed := true;
    ELSE out := array_append(out, _arr[i]);
    END IF;
  END LOOP;
  RETURN out;
END $$;

-- =================== CREATE / JOIN / START ===================
CREATE OR REPLACE FUNCTION public.rami_create(_stake numeric, _max int, _private boolean, _commission int)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid uuid := auth.uid(); _id uuid; _code text; _bal numeric; _name text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _max < 2 OR _max > 4 THEN RAISE EXCEPTION 'players 2-4'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'stake invalid'; END IF;
  SELECT balance, COALESCE(display_name, pseudo, 'Joueur') INTO _bal, _name FROM profiles WHERE id = _uid;
  IF _bal IS NULL OR _bal < _stake THEN RAISE EXCEPTION 'solde insuffisant'; END IF;
  _code := _rami_gen_code();
  INSERT INTO rami_games (room_code, is_private, stake, max_players, commission_pct, created_by, pot)
    VALUES (_code, COALESCE(_private, true), _stake, _max, COALESCE(_commission,10), _uid, _stake)
    RETURNING id INTO _id;
  IF _stake > 0 THEN
    UPDATE profiles SET balance = balance - _stake WHERE id = _uid;
    INSERT INTO transactions (user_id, type, amount, status, metadata)
      VALUES (_uid, 'game_stake', -_stake, 'completed', jsonb_build_object('game','rami','game_id',_id));
  END IF;
  INSERT INTO rami_participants (game_id, user_id, slot, display_name) VALUES (_id, _uid, 0, _name);
  RETURN _id;
END $$;
GRANT EXECUTE ON FUNCTION public.rami_create(numeric,int,boolean,int) TO authenticated;

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
  -- auto-start when full
  IF _slot + 1 = _g.max_players THEN PERFORM rami_start(_g.id); END IF;
  RETURN _g.id;
END $$;
GRANT EXECUTE ON FUNCTION public.rami_join_code(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.rami_start(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _g rami_games; _parts uuid[]; _deck int[]; _i int; _j int; _tmp int;
  _hands jsonb := '{}'::jsonb; _p uuid; _hand int[]; _state jsonb;
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'waiting' THEN RETURN; END IF;
  SELECT array_agg(user_id ORDER BY slot) INTO _parts FROM rami_participants WHERE game_id=_game_id;
  IF array_length(_parts,1) < 2 THEN RAISE EXCEPTION 'pas assez de joueurs'; END IF;
  -- Build deck 0..53 (52 cards + 2 jokers)
  _deck := ARRAY(SELECT generate_series(0,53));
  -- Fisher-Yates shuffle
  FOR _i IN REVERSE 54..2 LOOP
    _j := 1 + floor(random()*_i)::int;
    _tmp := _deck[_i]; _deck[_i] := _deck[_j]; _deck[_j] := _tmp;
  END LOOP;
  -- Deal 7 cards each
  FOREACH _p IN ARRAY _parts LOOP
    _hand := _deck[1:7];
    _deck := _deck[8:array_length(_deck,1)];
    _hands := _hands || jsonb_build_object(_p::text, to_jsonb(_hand));
    UPDATE rami_participants SET hand_count = 7 WHERE game_id=_game_id AND user_id=_p;
  END LOOP;
  -- First discard
  _state := jsonb_build_object(
    'deck', to_jsonb(_deck[2:array_length(_deck,1)]),
    'discard', jsonb_build_array(_deck[1]),
    'hands', _hands,
    'melds', '[]'::jsonb
  );
  UPDATE rami_games SET status='playing', state=_state, started_at=now(),
    current_turn=0, turn_phase='draw',
    turn_deadline = now() + interval '45 seconds'
    WHERE id=_game_id;
END $$;
GRANT EXECUTE ON FUNCTION public.rami_start(uuid) TO authenticated;

-- =================== GAMEPLAY ===================
CREATE OR REPLACE FUNCTION public.rami_draw(_game_id uuid, _from text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid uuid := auth.uid(); _g rami_games; _slot int; _state jsonb;
  _deck int[]; _discard int[]; _hand int[]; _card int; _hands jsonb;
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL OR _slot <> _g.current_turn THEN RAISE EXCEPTION 'pas ton tour'; END IF;
  IF _g.turn_phase <> 'draw' THEN RAISE EXCEPTION 'déjà pioché'; END IF;
  _state := _g.state;
  _deck := ARRAY(SELECT jsonb_array_elements_text(_state->'deck'))::int[];
  _discard := ARRAY(SELECT jsonb_array_elements_text(_state->'discard'))::int[];
  _hand := ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[];
  IF _from = 'discard' THEN
    IF array_length(_discard,1) IS NULL THEN RAISE EXCEPTION 'défausse vide'; END IF;
    _card := _discard[array_length(_discard,1)];
    _discard := _discard[1:array_length(_discard,1)-1];
  ELSE
    IF array_length(_deck,1) IS NULL THEN
      -- reshuffle discard except top
      IF array_length(_discard,1) <= 1 THEN RAISE EXCEPTION 'plus de cartes'; END IF;
      _deck := _discard[1:array_length(_discard,1)-1];
      _discard := ARRAY[_discard[array_length(_discard,1)]];
      -- shuffle
      _deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_deck) c);
    END IF;
    _card := _deck[1];
    _deck := _deck[2:array_length(_deck,1)];
  END IF;
  _hand := array_append(_hand, _card);
  _hands := jsonb_set(_state->'hands', ARRAY[_uid::text], to_jsonb(_hand));
  _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard));
  _state := jsonb_set(_state, '{hands}', _hands);
  UPDATE rami_games SET state=_state, turn_phase='play', updated_at=now() WHERE id=_game_id;
  UPDATE rami_participants SET hand_count=array_length(_hand,1) WHERE game_id=_game_id AND user_id=_uid;
END $$;
GRANT EXECUTE ON FUNCTION public.rami_draw(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.rami_meld(_game_id uuid, _cards int[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid uuid := auth.uid(); _g rami_games; _slot int; _state jsonb;
  _hand int[]; _c int; _new_hand int[]; _melds jsonb;
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour de jouer'; END IF;
  IF NOT _rami_validate_meld(_cards) THEN RAISE EXCEPTION 'combinaison invalide'; END IF;
  _state := _g.state;
  _hand := ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[];
  _new_hand := _hand;
  FOREACH _c IN ARRAY _cards LOOP
    IF NOT (_c = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte absente de la main'; END IF;
    _new_hand := _rami_remove_one(_new_hand, _c);
  END LOOP;
  _melds := COALESCE(_state->'melds','[]'::jsonb) || jsonb_build_array(
    jsonb_build_object('player', _uid::text, 'cards', to_jsonb(_cards))
  );
  _state := jsonb_set(_state, '{hands,'||_uid::text||'}', to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{melds}', _melds);
  UPDATE rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  UPDATE rami_participants SET hand_count=array_length(_new_hand,1) WHERE game_id=_game_id AND user_id=_uid;
END $$;
GRANT EXECUTE ON FUNCTION public.rami_meld(uuid,int[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.rami_layoff(_game_id uuid, _meld_index int, _cards int[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid uuid := auth.uid(); _g rami_games; _slot int; _state jsonb;
  _hand int[]; _c int; _new_hand int[]; _melds jsonb; _existing int[]; _combined int[];
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  SELECT slot INTO _slot FROM rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;
  _state := _g.state;
  _melds := _state->'melds';
  IF _meld_index < 0 OR _meld_index >= jsonb_array_length(_melds) THEN RAISE EXCEPTION 'meld inexistant'; END IF;
  _existing := ARRAY(SELECT jsonb_array_elements_text(_melds->_meld_index->'cards'))::int[];
  _combined := _existing || _cards;
  IF NOT _rami_validate_meld(_combined) THEN RAISE EXCEPTION 'ajout invalide'; END IF;
  _hand := ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[];
  _new_hand := _hand;
  FOREACH _c IN ARRAY _cards LOOP
    IF NOT (_c = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte absente'; END IF;
    _new_hand := _rami_remove_one(_new_hand, _c);
  END LOOP;
  _melds := jsonb_set(_melds, ARRAY[_meld_index::text, 'cards'], to_jsonb(_combined));
  _state := jsonb_set(_state, '{hands,'||_uid::text||'}', to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{melds}', _melds);
  UPDATE rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  UPDATE rami_participants SET hand_count=array_length(_new_hand,1) WHERE game_id=_game_id AND user_id=_uid;
END $$;
GRANT EXECUTE ON FUNCTION public.rami_layoff(uuid,int,int[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.rami_discard(_game_id uuid, _card int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid uuid := auth.uid(); _g rami_games; _slot int; _state jsonb;
  _hand int[]; _new_hand int[]; _discard int[]; _hands jsonb;
  _parts uuid[]; _next int; _payout numeric; _comm numeric;
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;
  _state := _g.state;
  _hand := ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[];
  IF NOT (_card = ANY(_hand)) THEN RAISE EXCEPTION 'carte absente'; END IF;
  _new_hand := _rami_remove_one(_hand, _card);
  _discard := ARRAY(SELECT jsonb_array_elements_text(_state->'discard'))::int[];
  _discard := array_append(_discard, _card);
  _hands := jsonb_set(_state->'hands', ARRAY[_uid::text], to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{hands}', _hands);
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard));
  UPDATE rami_participants SET hand_count=array_length(_new_hand,1) WHERE game_id=_game_id AND user_id=_uid;
  -- WIN: empty hand
  IF COALESCE(array_length(_new_hand,1),0) = 0 THEN
    _comm := round(_g.pot * _g.commission_pct / 100.0, 0);
    _payout := _g.pot - _comm;
    UPDATE profiles SET balance = balance + _payout WHERE id = _uid;
    INSERT INTO transactions (user_id, type, amount, status, metadata)
      VALUES (_uid, 'game_win', _payout, 'completed', jsonb_build_object('game','rami','game_id',_game_id,'commission',_comm));
    UPDATE rami_games SET status='finished', winner_id=_uid, finished_at=now(), state=_state WHERE id=_game_id;
    RETURN;
  END IF;
  -- next active slot
  SELECT array_agg(slot ORDER BY slot) INTO _parts FROM rami_participants WHERE game_id=_game_id AND NOT forfeited;
  _next := _g.current_turn;
  LOOP
    _next := (_next + 1) % _g.max_players;
    EXIT WHEN _next = ANY (
      SELECT slot FROM rami_participants WHERE game_id=_game_id AND NOT forfeited
    );
  END LOOP;
  UPDATE rami_games SET state=_state, current_turn=_next, turn_phase='draw',
    turn_deadline = now() + interval '45 seconds', updated_at=now()
    WHERE id=_game_id;
END $$;
GRANT EXECUTE ON FUNCTION public.rami_discard(uuid,int) TO authenticated;

CREATE OR REPLACE FUNCTION public.rami_forfeit(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid uuid := auth.uid(); _g rami_games; _alive uuid[]; _winner uuid;
  _payout numeric; _comm numeric; _next int;
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status NOT IN ('waiting','playing') THEN RETURN; END IF;
  UPDATE rami_participants SET forfeited=true WHERE game_id=_game_id AND user_id=_uid;
  SELECT array_agg(user_id) INTO _alive FROM rami_participants WHERE game_id=_game_id AND NOT forfeited;
  IF _g.status='waiting' THEN
    UPDATE rami_games SET status='finished', finished_at=now() WHERE id=_game_id;
    IF _g.stake > 0 THEN
      UPDATE profiles SET balance = balance + _g.stake WHERE id = _uid;
      INSERT INTO transactions (user_id, type, amount, status, metadata)
        VALUES (_uid, 'game_refund', _g.stake, 'completed', jsonb_build_object('game','rami','game_id',_game_id));
    END IF;
    RETURN;
  END IF;
  IF COALESCE(array_length(_alive,1),0) = 1 THEN
    _winner := _alive[1];
    _comm := round(_g.pot * _g.commission_pct / 100.0, 0);
    _payout := _g.pot - _comm;
    UPDATE profiles SET balance = balance + _payout WHERE id = _winner;
    INSERT INTO transactions (user_id, type, amount, status, metadata)
      VALUES (_winner, 'game_win', _payout, 'completed', jsonb_build_object('game','rami','game_id',_game_id,'reason','forfeit'));
    UPDATE rami_games SET status='finished', winner_id=_winner, finished_at=now() WHERE id=_game_id;
    RETURN;
  END IF;
  -- skip turn if it was theirs
  IF (SELECT slot FROM rami_participants WHERE game_id=_game_id AND user_id=_uid) = _g.current_turn THEN
    _next := _g.current_turn;
    LOOP
      _next := (_next + 1) % _g.max_players;
      EXIT WHEN _next IN (SELECT slot FROM rami_participants WHERE game_id=_game_id AND NOT forfeited);
    END LOOP;
    UPDATE rami_games SET current_turn=_next, turn_phase='draw',
      turn_deadline = now() + interval '45 seconds' WHERE id=_game_id;
  END IF;
END $$;
GRANT EXECUTE ON FUNCTION public.rami_forfeit(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.rami_tick(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _g rami_games; _state jsonb; _uid uuid; _hand int[]; _new_hand int[];
  _deck int[]; _discard int[]; _card int; _next int;
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' OR _g.turn_deadline IS NULL OR _g.turn_deadline > now() THEN RETURN; END IF;
  SELECT user_id INTO _uid FROM rami_participants WHERE game_id=_game_id AND slot=_g.current_turn;
  _state := _g.state;
  _deck := ARRAY(SELECT jsonb_array_elements_text(_state->'deck'))::int[];
  _discard := ARRAY(SELECT jsonb_array_elements_text(_state->'discard'))::int[];
  _hand := ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[];
  -- auto-draw from deck if needed
  IF _g.turn_phase = 'draw' THEN
    IF array_length(_deck,1) IS NULL THEN
      _deck := _discard[1:array_length(_discard,1)-1];
      _discard := ARRAY[_discard[array_length(_discard,1)]];
      _deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_deck) c);
    END IF;
    _card := _deck[1]; _deck := _deck[2:array_length(_deck,1)];
    _hand := array_append(_hand, _card);
  END IF;
  -- auto-discard random card
  _card := _hand[1 + floor(random()*array_length(_hand,1))::int];
  _new_hand := _rami_remove_one(_hand, _card);
  _discard := array_append(_discard, _card);
  _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard));
  _state := jsonb_set(_state, ARRAY['hands',_uid::text], to_jsonb(_new_hand));
  UPDATE rami_participants SET hand_count=array_length(_new_hand,1) WHERE game_id=_game_id AND user_id=_uid;
  _next := _g.current_turn;
  LOOP
    _next := (_next + 1) % _g.max_players;
    EXIT WHEN _next IN (SELECT slot FROM rami_participants WHERE game_id=_game_id AND NOT forfeited);
  END LOOP;
  UPDATE rami_games SET state=_state, current_turn=_next, turn_phase='draw',
    turn_deadline = now() + interval '45 seconds', updated_at=now()
    WHERE id=_game_id;
END $$;
GRANT EXECUTE ON FUNCTION public.rami_tick(uuid) TO authenticated;
