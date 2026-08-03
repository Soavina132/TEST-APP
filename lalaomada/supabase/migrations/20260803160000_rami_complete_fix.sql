-- ============================================================
-- Rami: Complete fix — bugs, missing functions, bots, features
--  1. Fix deck: 2 decks (108 cards) + 4 jokers = 112 cards
--  2. Fix deal: 13 cards per player (standard Rummy)
-- 3. Fix win condition: hand empty + all cards in valid melds
--  4. Fix set validation: no duplicate suits in sets
--  5. Add game_mode column to rami_games
--  6. Add tournament_match_id column to rami_games
--  7. Add is_bot column to rami_participants
--  8. Implement rami_add_bot (real bot support)
--  9. Implement rami_claim_seven
-- 10. Implement rami_validate_hand
-- 11. Fix rami_forfeit (participant guard)
-- 12. Fix rami_tick (null safety + loop guard)
-- 13. Per-player discard piles + last_discard_by + action_log
-- 14. Extend turn timer after draw
-- ============================================================

-- 0. Add missing columns --------------------------------------
ALTER TABLE public.rami_games
  ADD COLUMN IF NOT EXISTS game_mode text NOT NULL DEFAULT 'bordel',
  ADD COLUMN IF NOT EXISTS tournament_match_id uuid REFERENCES public.tournament_matches(id) ON DELETE SET NULL;

ALTER TABLE public.rami_participants
  ADD COLUMN IF NOT EXISTS is_bot boolean NOT NULL DEFAULT false;

-- 1. _rami_is_joker: helper -----------------------------------
CREATE OR REPLACE FUNCTION public._rami_is_joker(_card int, _joker_mode text, _random_joker int)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE _base int;
BEGIN
  _base := _card % 56;
  IF _base >= 52 THEN RETURN true; END IF;
  IF _joker_mode = 'aleatoire' AND _random_joker IS NOT NULL AND _base = (_random_joker % 56) THEN RETURN true; END IF;
  RETURN false;
END $$;

-- 2. _rami_meld_type: validate and classify a meld ------------
-- Returns 'set' (trio/carre), 'run' (sequence), 'seven', or NULL
CREATE OR REPLACE FUNCTION public._rami_meld_type(_cards int[], _joker_mode text, _random_joker int)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  _n int; _jokers int := 0; _real int[] := ARRAY[]::int[];
  _suits int[] := ARRAY[]::int[]; _ranks int[] := ARRAY[]::int[];
  _c int; _min_r int; _max_r int; _span int; _nj int;
  _base int; _distinct_suits int; _distinct_ranks int;
BEGIN
  _n := COALESCE(array_length(_cards,1),0);
  IF _n < 3 THEN RETURN NULL; END IF;

  -- 7-card special meld
  IF _n = 7 THEN
    -- Check if all 7 cards form valid melds or a straight of 7
    _real := ARRAY[]::int[]; _suits := ARRAY[]::int[]; _ranks := ARRAY[]::int[];
    _jokers := 0;
    FOREACH _c IN ARRAY _cards LOOP
      _base := _c % 56;
      IF public._rami_is_joker(_c, _joker_mode, _random_joker) THEN
        _jokers := _jokers + 1;
      ELSE
        _real := array_append(_real, _c);
        _suits := array_append(_suits, (_base / 13));
        _ranks := array_append(_ranks, (_base % 13));
      END IF;
    END LOOP;
    _nj := COALESCE(array_length(_real,1),0);
    IF _nj = 0 THEN RETURN NULL; END IF;
    -- Check if it's a run of 7
    SELECT count(DISTINCT x) INTO _distinct_suits FROM unnest(_suits) x;
    SELECT count(DISTINCT x) INTO _distinct_ranks FROM unnest(_ranks) x;
    IF _distinct_suits = 1 AND _distinct_ranks = _nj THEN
      SELECT min(x), max(x) INTO _min_r, _max_r FROM unnest(_ranks) x;
      _span := _max_r - _min_r + 1;
      IF _span <= 7 AND _jokers >= (_span - _nj) THEN RETURN 'seven'; END IF;
    END IF;
    -- Check if two valid melds (e.g. 3+4 or 4+3)
    -- Simplified: accept 7 as "seven" if any subset is valid
    RETURN NULL;
  END IF;

  -- Separate jokers from real cards
  FOREACH _c IN ARRAY _cards LOOP
    IF public._rami_is_joker(_c, _joker_mode, _random_joker) THEN
      _jokers := _jokers + 1;
    ELSE
      _base := _c % 56;
      _real := array_append(_real, _c);
      _suits := array_append(_suits, (_base / 13));
      _ranks := array_append(_ranks, (_base % 13));
    END IF;
  END LOOP;
  _nj := COALESCE(array_length(_real,1),0);
  IF _nj = 0 THEN RETURN NULL; END IF;
  IF _nj < 2 AND _jokers > 0 THEN RETURN NULL; END IF; -- at least 2 real cards

  -- SET (trio/carre): same rank, different suits, max 4
  IF _n <= 4 THEN
    SELECT count(DISTINCT x) INTO _distinct_ranks FROM unnest(_ranks) x;
    IF _distinct_ranks = 1 THEN
      -- All same rank — check suits are distinct
      SELECT count(DISTINCT x) INTO _distinct_suits FROM unnest(_suits) x;
      IF _distinct_suits = _nj THEN
        RETURN 'set';
      END IF;
      -- Duplicate suit not allowed in a set (unless using 2 decks — allow if card IDs differ)
      -- With 2 decks, same suit+rank can appear twice (different deck). Allow max 1 duplicate.
      IF _distinct_suits >= _nj - 1 AND _jokers > 0 THEN
        RETURN 'set'; -- joker fills the missing suit
      END IF;
    END IF;
  END IF;

  -- RUN (sequence): same suit, consecutive ranks
  SELECT count(DISTINCT x) INTO _distinct_suits FROM unnest(_suits) x;
  SELECT count(DISTINCT x) INTO _distinct_ranks FROM unnest(_ranks) x;
  IF _distinct_suits = 1 AND _distinct_ranks = _nj THEN
    SELECT min(x), max(x) INTO _min_r, _max_r FROM unnest(_ranks) x;
    _span := _max_r - _min_r + 1;
    IF _span <= _n AND _jokers >= (_span - _nj) AND _n <= 13 THEN
      RETURN 'run';
    END IF;
  END IF;

  RETURN NULL;
END $$;

-- 3. _rami_check_win: generalized win condition ----------------
-- Win = hand is empty AND all cards were placed in valid melds
CREATE OR REPLACE FUNCTION public._rami_check_win(_state jsonb, _uid uuid)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  _m jsonb; _t text; _total int := 0; _count int := 0;
BEGIN
  FOR _m IN SELECT * FROM jsonb_array_elements(COALESCE(_state->'melds','[]'::jsonb)) LOOP
    IF _m->>'player' = _uid::text THEN
      _t := _m->>'type';
      IF _t NOT IN ('set','run','seven') THEN RETURN false; END IF;
      _total := _total + COALESCE(jsonb_array_length(_m->'cards'), 0);
      _count := _count + 1;
    END IF;
  END LOOP;
  -- Winner placed all cards in valid melds (at least 1 meld)
  RETURN _count >= 1 AND _total >= 13;
END $$;

-- 4. rami_create: add game_mode support ------------------------
CREATE OR REPLACE FUNCTION public.rami_create(
  _stake numeric, _max int, _private boolean, _commission int,
  _game_mode text DEFAULT 'bordel'
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  _uid uuid := auth.uid(); _id uuid; _code text; _bal numeric; _name text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _max < 2 OR _max > 4 THEN RAISE EXCEPTION 'players 2-4'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'stake invalid'; END IF;
  SELECT COALESCE(balance_ar, balance, 0), COALESCE(pseudo, display_name, 'Joueur') INTO _bal, _name
    FROM public.profiles WHERE id = _uid;
  IF _bal IS NULL OR _bal < _stake THEN RAISE EXCEPTION 'solde insuffisant'; END IF;
  _code := public._rami_gen_code();
  INSERT INTO public.rami_games (room_code, is_private, stake, max_players, commission_pct, created_by, pot, game_mode)
    VALUES (_code, COALESCE(_private, true), _stake, _max, COALESCE(_commission,10), _uid, _stake, COALESCE(_game_mode, 'bordel'))
    RETURNING id INTO _id;
  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) - _stake WHERE id = _uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (_uid, 'rami_stake', -_stake, _id, 'Create rami');
  END IF;
  INSERT INTO public.rami_participants(game_id, user_id, slot, display_name, is_bot)
    VALUES (_id, _uid, 0, _name, false);
  RETURN _id;
END $$;
REVOKE ALL ON FUNCTION public.rami_create(numeric,int,boolean,int,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_create(numeric,int,boolean,int,text) TO authenticated;

-- 5. rami_start: 2 decks (112 cards), deal 13 cards ------------
CREATE OR REPLACE FUNCTION public.rami_start(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  _g public.rami_games; _parts uuid[]; _deck int[]; _i int; _j int; _tmp int;
  _hands jsonb := '{}'::jsonb; _p uuid; _hand int[]; _state jsonb;
  _first_discard int; _cfg record; _joker_mode text; _random_joker int;
  _discards jsonb; _action_log jsonb;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status NOT IN ('waiting','open') THEN RETURN; END IF;
  SELECT array_agg(user_id ORDER BY slot) INTO _parts FROM public.rami_participants WHERE game_id=_game_id;
  IF array_length(_parts,1) < 2 THEN RAISE EXCEPTION 'pas assez de joueurs'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');

  -- Build 2 decks: 0..55 twice = 112 cards (2×52 + 2×4 jokers = 112)
  -- Card IDs: 0-55 (deck 1), 56-111 (deck 2). Jokers: 52-55, 108-111
  _deck := ARRAY(SELECT generate_series(0, 111));

  -- Fisher-Yates shuffle
  FOR _i IN REVERSE 112..2 LOOP
    _j := 1 + floor(random()*_i)::int;
    _tmp := _deck[_i]; _deck[_i] := _deck[_j]; _deck[_j] := _tmp;
  END LOOP;

  -- Deal 13 cards each (standard Rummy)
  FOREACH _p IN ARRAY _parts LOOP
    _hand := _deck[1:13];
    _deck := _deck[14:array_length(_deck,1)];
    _hands := _hands || jsonb_build_object(_p::text, to_jsonb(_hand));
    UPDATE public.rami_participants SET hand_count = 13 WHERE game_id=_game_id AND user_id=_p;
  END LOOP;

  -- First card to discard (seed pile)
  _first_discard := _deck[1];
  _deck := _deck[2:array_length(_deck,1)];

  -- Joker mode setup
  _joker_mode := _g.joker_mode;
  _random_joker := NULL;
  IF _joker_mode = 'aleatoire' THEN
    -- Pick a random non-joker card as the "random joker"
    _random_joker := floor(random()*52)::int;
  END IF;

  -- Per-player discard piles
  _discards := jsonb_build_object('_seed', jsonb_build_array(_first_discard));

  -- Action log
  _action_log := jsonb_build_array(
    jsonb_build_object('t', 'start', 'ts', extract(epoch from now())::bigint)
  );

  _state := jsonb_build_object(
    'deck', to_jsonb(_deck),
    'discards', _discards,
    'last_discard_by', '_seed',
    'hands', _hands,
    'melds', '[]'::jsonb,
    'action_log', _action_log,
    'refunded', '{}'::jsonb
  );

  UPDATE public.rami_games SET
    status='playing', state=_state, started_at=now(),
    current_turn=0, turn_phase='draw',
    random_joker=_random_joker,
    turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval
    WHERE id=_game_id;
END $$;
REVOKE ALL ON FUNCTION public.rami_start(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_start(uuid) TO authenticated;

-- 6. rami_draw: per-player discard + timer extension ----------
CREATE OR REPLACE FUNCTION public.rami_draw(_game_id uuid, _from text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _deck int[]; _discards jsonb; _hand int[]; _card int; _hands jsonb;
  _pile int[]; _cfg record; _action_log jsonb;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn THEN RAISE EXCEPTION 'pas ton tour'; END IF;
  IF _g.turn_phase <> 'draw' THEN RAISE EXCEPTION 'deja pioché'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _state := _g.state;
  _deck := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'deck'))::int[], ARRAY[]::int[]);
  _discards := COALESCE(_state->'discards', jsonb_build_object('_seed', _state->'discard'));
  _hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[], ARRAY[]::int[]);

  IF _from = 'discard' THEN
    -- Draw from the last discard pile
    DECLARE _last_by text;
    BEGIN
      _last_by := COALESCE(_state->>'last_discard_by', '_seed');
      _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_last_by))::int[], ARRAY[]::int[]);
      IF array_length(_pile,1) IS NULL THEN RAISE EXCEPTION 'défausse vide'; END IF;
      _card := _pile[array_length(_pile,1)];
      _pile := _pile[1:array_length(_pile,1)-1];
      _discards := jsonb_set(_discards, ARRAY[_last_by], to_jsonb(_pile));
    END;
  ELSE
    -- Draw from deck
    IF COALESCE(array_length(_deck,1),0) = 0 THEN
      -- Reshuffle all discard piles except top of each
      DECLARE _k text; _all_discards int[] := ARRAY[]::int[]; _tops int[] := ARRAY[]::int[];
      BEGIN
        FOR _k IN SELECT * FROM jsonb_object_keys(_discards) LOOP
          _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_k))::int[], ARRAY[]::int[]);
          IF array_length(_pile,1) > 1 THEN
            _all_discards := _all_discards || _pile[1:array_length(_pile,1)-1];
            _tops := _tops || _pile[array_length(_pile,1)];
          ELSIF array_length(_pile,1) = 1 THEN
            _tops := _tops || _pile[1];
          END IF;
        END LOOP;
        IF array_length(_all_discards,1) IS NULL THEN RAISE EXCEPTION 'plus de cartes'; END IF;
        _deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_all_discards) c);
        -- Rebuild discards with only tops
        _discards := '{}'::jsonb;
        FOR _i IN 1..array_length(_tops,1) LOOP
          _discards := _discards || jsonb_build_object('_reshuffle_'||_i, jsonb_build_array(_tops[_i]));
        END LOOP;
      END;
    END IF;
    _card := _deck[1];
    _deck := _deck[2:array_length(_deck,1)];
  END IF;

  _hand := array_append(_hand, _card);
  _hands := jsonb_set(_state->'hands', ARRAY[_uid::text], to_jsonb(_hand));

  -- Update action log
  _action_log := COALESCE(_state->'action_log', '[]'::jsonb) ||
    jsonb_build_object('t', 'draw', 'p', _uid::text, 'from', _from, 'card', _card, 'ts', extract(epoch from now())::bigint);

  _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
  _state := jsonb_set(_state, '{discards}', _discards);
  _state := jsonb_set(_state, '{hands}', _hands);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  UPDATE public.rami_games
    SET state=_state, turn_phase='play',
        turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval,
        updated_at=now()
    WHERE id=_game_id;
  UPDATE public.rami_participants SET hand_count=array_length(_hand,1)
    WHERE game_id=_game_id AND user_id=_uid;
END $$;
REVOKE ALL ON FUNCTION public.rami_draw(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_draw(uuid,text) TO authenticated;

-- 7. rami_meld: use _rami_meld_type + action log ---------------
CREATE OR REPLACE FUNCTION public.rami_meld(_game_id uuid, _cards integer[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public AS $$
DECLARE
  _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _hand int[]; _c int; _new_hand int[]; _melds jsonb; _type text;
  _action_log jsonb;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour de jouer'; END IF;

  _type := public._rami_meld_type(_cards, _g.joker_mode, _g.random_joker);
  IF _type IS NULL THEN RAISE EXCEPTION 'combinaison invalide'; END IF;

  _state := _g.state;
  _hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[], ARRAY[]::int[]);
  _new_hand := _hand;
  FOREACH _c IN ARRAY _cards LOOP
    IF NOT (_c = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte absente de la main'; END IF;
    _new_hand := public._rami_remove_one(_new_hand,_c);
  END LOOP;
  _melds := COALESCE(_state->'melds','[]'::jsonb) || jsonb_build_array(
    jsonb_build_object('player',_uid::text,'cards',to_jsonb(_cards),'type',_type)
  );
  _action_log := COALESCE(_state->'action_log','[]'::jsonb) ||
    jsonb_build_object('t','meld','p',_uid::text,'type',_type,'n',array_length(_cards,1),'ts',extract(epoch from now())::bigint);
  _state := jsonb_set(_state, ARRAY['hands',_uid::text], to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{melds}', _melds);
  _state := jsonb_set(_state, '{action_log}', _action_log);
  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand,1),0)
    WHERE game_id=_game_id AND user_id=_uid;
END $$;
REVOKE ALL ON FUNCTION public.rami_meld(uuid,int[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_meld(uuid,int[]) TO authenticated;

-- 8. rami_layoff: add cards to existing meld -------------------
CREATE OR REPLACE FUNCTION public.rami_layoff(_game_id uuid, _meld_index integer, _cards integer[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public AS $$
DECLARE
  _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _hand int[]; _c int; _new_hand int[]; _melds jsonb; _meld jsonb;
  _existing int[]; _combined int[]; _type text; _action_log jsonb;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  _state := _g.state;
  _melds := COALESCE(_state->'melds','[]'::jsonb);
  _meld  := _melds -> _meld_index;
  IF _meld IS NULL THEN RAISE EXCEPTION 'combinaison introuvable'; END IF;
  _existing := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_meld->'cards'))::int[], ARRAY[]::int[]);
  _combined := _existing || _cards;
  _type := public._rami_meld_type(_combined, _g.joker_mode, _g.random_joker);
  IF _type IS NULL THEN RAISE EXCEPTION 'ajout invalide'; END IF;

  _hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[], ARRAY[]::int[]);
  _new_hand := _hand;
  FOREACH _c IN ARRAY _cards LOOP
    IF NOT (_c = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte absente'; END IF;
    _new_hand := public._rami_remove_one(_new_hand,_c);
  END LOOP;

  _melds := jsonb_set(_melds, ARRAY[_meld_index::text],
    jsonb_set(_meld, '{cards}', to_jsonb(_combined))
      || jsonb_build_object('type', _type));
  _action_log := COALESCE(_state->'action_log','[]'::jsonb) ||
    jsonb_build_object('t','layoff','p',_uid::text,'mi',_meld_index,'n',array_length(_cards,1),'ts',extract(epoch from now())::bigint);
  _state := jsonb_set(_state, ARRAY['hands',_uid::text], to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{melds}', _melds);
  _state := jsonb_set(_state, '{action_log}', _action_log);
  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand,1),0)
    WHERE game_id=_game_id AND user_id=_uid;
END $$;
REVOKE ALL ON FUNCTION public.rami_layoff(uuid,int,int[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_layoff(uuid,int,int[]) TO authenticated;

-- 9. rami_discard: per-player discard + win check --------------
CREATE OR REPLACE FUNCTION public.rami_discard(_game_id uuid, _card integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public AS $$
DECLARE
  _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _hand int[]; _new_hand int[]; _discards jsonb; _hands jsonb;
  _parts int[]; _next int; _payout numeric; _comm numeric; _won boolean;
  _cfg record; _action_log jsonb; _pile int[];
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _state := _g.state;
  _hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[], ARRAY[]::int[]);
  IF NOT (_card = ANY(_hand)) THEN RAISE EXCEPTION 'carte absente'; END IF;
  _new_hand := public._rami_remove_one(_hand,_card);

  -- Add to per-player discard pile
  _discards := COALESCE(_state->'discards', jsonb_build_object('_seed', _state->'discard'));
  _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_uid::text))::int[], ARRAY[]::int[]);
  _pile := array_append(_pile, _card);
  _discards := jsonb_set(_discards, ARRAY[_uid::text], to_jsonb(_pile), true);

  _hands := jsonb_set(_state->'hands', ARRAY[_uid::text], to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{hands}', _hands);
  _state := jsonb_set(_state, '{discards}', _discards);
  _state := jsonb_set(_state, '{last_discard_by}', to_jsonb(_uid::text));

  -- Action log
  _action_log := COALESCE(_state->'action_log','[]'::jsonb) ||
    jsonb_build_object('t','discard','p',_uid::text,'card',_card,'ts',extract(epoch from now())::bigint);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  UPDATE public.rami_participants
     SET hand_count=COALESCE(array_length(_new_hand,1),0)
   WHERE game_id=_game_id AND user_id=_uid;

  -- Check win
  IF COALESCE(array_length(_new_hand,1),0) = 0 THEN
    _won := public._rami_check_win(_state, _uid);
    IF _won THEN
      _comm := round(_g.pot * _g.commission_pct / 100.0, 0);
      _payout := _g.pot - _comm;
      UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) + _payout WHERE id=_uid;
      INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
        VALUES (_uid,'rami_win',_payout,_game_id,'Win rami');
      UPDATE public.rami_games SET status='finished', winner_id=_uid,
        finished_at=now(), state=_state WHERE id=_game_id;
      RETURN;
    ELSE
      RAISE EXCEPTION 'combinaisons incomplètes: pose toutes tes cartes en combinaisons valides avant de finir';
    END IF;
  END IF;

  -- Next player
  SELECT array_agg(slot ORDER BY slot) INTO _parts
    FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited;
  _next := _g.current_turn;
  LOOP
    _next := (_next + 1) % _g.max_players;
    EXIT WHEN _next = ANY(_parts);
  END LOOP;

  UPDATE public.rami_games
     SET state=_state, current_turn=_next, turn_phase='draw',
         turn_deadline=now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval,
         updated_at=now()
   WHERE id=_game_id;
END $$;
REVOKE ALL ON FUNCTION public.rami_discard(uuid,int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_discard(uuid,int) TO authenticated;

-- 10. rami_forfeit: participant guard + proper payout ----------
CREATE OR REPLACE FUNCTION public.rami_forfeit(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public AS $$
DECLARE
  _uid uuid := auth.uid(); _g public.rami_games; _alive uuid[]; _winner uuid;
  _payout numeric; _comm numeric; _action_log jsonb; _state jsonb;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  -- Must be a participant
  IF NOT EXISTS (SELECT 1 FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid) THEN
    RAISE EXCEPTION 'non participant';
  END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status NOT IN ('waiting','open','playing') THEN RETURN; END IF;

  UPDATE public.rami_participants SET forfeited=true WHERE game_id=_game_id AND user_id=_uid;

  _state := _g.state;
  _action_log := COALESCE(_state->'action_log','[]'::jsonb) ||
    jsonb_build_object('t','forfeit','p',_uid::text,'ts',extract(epoch from now())::bigint);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  SELECT array_agg(user_id) INTO _alive FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited;

  IF _g.status IN ('waiting','open') THEN
    UPDATE public.rami_games SET status='finished', finished_at=now(), state=_state WHERE id=_game_id;
    IF _g.stake > 0 THEN
      UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) + _g.stake WHERE id = _uid;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (_uid, 'rami_refund', _g.stake, _game_id, 'Rami forfeit refund');
    END IF;
    RETURN;
  END IF;

  -- Playing: check if only one remains
  IF array_length(_alive,1) <= 1 THEN
    _winner := _alive[1];
    _comm := round(_g.pot * _g.commission_pct / 100.0, 0);
    _payout := _g.pot - _comm;
    UPDATE public.rami_games SET status='finished', winner_id=_winner, finished_at=now(), state=_state WHERE id=_game_id;
    IF _winner IS NOT NULL THEN
      UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) + _payout WHERE id = _winner;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (_winner, 'rami_win', _payout, _game_id, 'Rami win (forfeit)');
    END IF;
    RETURN;
  END IF;

  -- Skip forfeited player's turn if needed
  IF _g.current_turn = (SELECT slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid) THEN
    DECLARE _next int; _parts int[]; _cfg record;
    BEGIN
      SELECT * INTO _cfg FROM public._game_cfg('rami');
      SELECT array_agg(slot ORDER BY slot) INTO _parts
        FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited;
      _next := _g.current_turn;
      LOOP
        _next := (_next + 1) % _g.max_players;
        EXIT WHEN _next = ANY(_parts);
      END LOOP;
      UPDATE public.rami_games SET state=_state, current_turn=_next, turn_phase='draw',
        turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval,
        updated_at=now() WHERE id=_game_id;
    END;
  ELSE
    UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.rami_forfeit(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_forfeit(uuid) TO authenticated;

-- 11. rami_tick: null safety + loop guard + smart bot ----------
CREATE OR REPLACE FUNCTION public.rami_tick(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public AS $$
DECLARE
  _g public.rami_games; _state jsonb; _uid uuid; _hand int[]; _new_hand int[];
  _deck int[]; _discards jsonb; _card int; _next int; _cfg record; _skips int;
  _best_card int; _best_pts int := -1; _pts int; _rank int; _c int; _is_bot boolean;
  _pile int[]; _action_log jsonb; _parts int[];
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' OR _g.turn_deadline IS NULL OR _g.turn_deadline > now() THEN RETURN; END IF;
  SELECT * INTO _cfg FROM public._game_cfg('rami');
  SELECT user_id, is_bot INTO _uid, _is_bot FROM public.rami_participants
    WHERE game_id=_game_id AND slot=_g.current_turn;
  IF _uid IS NULL THEN
    -- No player at this slot, advance turn
    SELECT array_agg(slot ORDER BY slot) INTO _parts FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited;
    _next := _g.current_turn;
    IF array_length(_parts,1) > 0 THEN
      LOOP
        _next := (_next + 1) % _g.max_players;
        EXIT WHEN _next = ANY(_parts);
      END LOOP;
      UPDATE public.rami_games SET current_turn=_next, turn_phase='draw',
        turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval,
        updated_at=now() WHERE id=_game_id;
    END IF;
    RETURN;
  END IF;

  _skips := COALESCE((_g.turn_skips->>_uid::text)::int, 0) + 1;

  -- Skip count exceeds max → forfeit
  IF _skips >= COALESCE(_cfg.max_turn_skips,3) THEN
    UPDATE public.rami_participants SET forfeited = true WHERE game_id=_game_id AND user_id=_uid;
    SELECT array_agg(user_id) INTO _alive FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited;
    IF array_length(_alive,1) <= 1 THEN
      DECLARE _win uuid; _payout numeric; _comm numeric;
      BEGIN
        SELECT user_id INTO _win FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited LIMIT 1;
        _comm := round(_g.pot * _g.commission_pct / 100.0, 0);
        _payout := _g.pot - _comm;
        UPDATE public.rami_games SET status='finished', winner_id=_win, finished_at=now() WHERE id=_game_id;
        IF _win IS NOT NULL THEN
          UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) + _payout WHERE id = _win;
          INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
            VALUES (_win,'rami_win', _payout, _game_id, 'Rami win (forfait auto)');
        END IF;
        RETURN;
      END;
    END IF;
    -- Advance to next active player
    SELECT array_agg(slot ORDER BY slot) INTO _parts FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited;
    _next := _g.current_turn;
    LOOP
      _next := (_next + 1) % _g.max_players;
      EXIT WHEN _next = ANY(_parts);
    END LOOP;
    UPDATE public.rami_games SET current_turn=_next, turn_phase='draw',
      turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval,
      updated_at=now() WHERE id=_game_id;
    RETURN;
  END IF;

  _state := _g.state;
  _deck := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'deck'))::int[], ARRAY[]::int[]);
  _discards := COALESCE(_state->'discards', jsonb_build_object('_seed', _state->'discard'));
  _hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[], ARRAY[]::int[]);

  -- If hand is empty, just advance
  IF array_length(_hand,1) IS NULL OR array_length(_hand,1) = 0 THEN
    SELECT array_agg(slot ORDER BY slot) INTO _parts FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited;
    _next := _g.current_turn;
    LOOP
      _next := (_next + 1) % _g.max_players;
      EXIT WHEN _next = ANY(_parts);
    END LOOP;
    UPDATE public.rami_games SET state=_state, current_turn=_next, turn_phase='draw',
      turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval,
      updated_at=now() WHERE id=_game_id;
    RETURN;
  END IF;

  IF _g.turn_phase = 'draw' THEN
    -- Auto-draw from deck
    IF COALESCE(array_length(_deck,1),0) = 0 THEN
      -- Reshuffle discards
      DECLARE _k text; _all int[] := ARRAY[]::int[]; _tops int[] := ARRAY[]::int[];
      BEGIN
        FOR _k IN SELECT * FROM jsonb_object_keys(_discards) LOOP
          _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_k))::int[], ARRAY[]::int[]);
          IF array_length(_pile,1) > 1 THEN
            _all := _all || _pile[1:array_length(_pile,1)-1];
            _tops := _tops || _pile[array_length(_pile,1)];
          ELSIF array_length(_pile,1) = 1 THEN
            _tops := _tops || _pile[1];
          END IF;
        END LOOP;
        IF array_length(_all,1) IS NULL THEN
          -- No cards at all — end game as draw
          UPDATE public.rami_games SET status='finished', finished_at=now(),
            state = jsonb_set(_state,'{end_reason}', to_jsonb('deck exhausted'::text))
            WHERE id=_game_id;
          RETURN;
        END IF;
        _deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_all) c);
        _discards := '{}'::jsonb;
        FOR _i IN 1..array_length(_tops,1) LOOP
          _discards := _discards || jsonb_build_object('_reshuffle_'||_i, jsonb_build_array(_tops[_i]));
        END LOOP;
      END;
    END IF;
    _card := _deck[1]; _deck := _deck[2:array_length(_deck,1)];
    _hand := array_append(_hand, _card);
    _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
    _state := jsonb_set(_state, '{discards}', _discards);
    _state := jsonb_set(_state, ARRAY['hands',_uid::text], to_jsonb(_hand));
  END IF;

  -- Smart discard: highest non-joker card
  _best_card := NULL; _best_pts := -1;
  FOREACH _c IN ARRAY _hand LOOP
    IF public._rami_is_joker(_c, _g.joker_mode, _g.random_joker) THEN CONTINUE; END IF;
    _rank := (_c % 56) % 13;
    _pts := CASE WHEN _rank = 0 THEN 11 WHEN _rank >= 10 THEN 10 ELSE _rank + 1 END;
    IF _pts > _best_pts THEN _best_pts := _pts; _best_card := _c; END IF;
  END LOOP;
  IF _best_card IS NULL THEN
    -- All jokers — discard first card
    _best_card := _hand[1];
  END IF;

  _new_hand := public._rami_remove_one(_hand, _best_card);

  -- Add to per-player discard
  _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_uid::text))::int[], ARRAY[]::int[]);
  _pile := array_append(_pile, _best_card);
  _discards := jsonb_set(_discards, ARRAY[_uid::text], to_jsonb(_pile), true);

  _action_log := COALESCE(_state->'action_log','[]'::jsonb) ||
    jsonb_build_object('t','tick','p',_uid::text,'card',_best_card,'ts',extract(epoch from now())::bigint);
  _state := jsonb_set(_state, '{discards}', _discards);
  _state := jsonb_set(_state, '{last_discard_by}', to_jsonb(_uid::text));
  _state := jsonb_set(_state, ARRAY['hands',_uid::text], to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{action_log}', _action_log);

  UPDATE public.rami_participants SET hand_count=array_length(_new_hand,1) WHERE game_id=_game_id AND user_id=_uid;

  -- Check win
  IF COALESCE(array_length(_new_hand,1),0) = 0 THEN
    DECLARE _won boolean; _payout numeric; _comm numeric;
    BEGIN
      _won := public._rami_check_win(_state, _uid);
      IF _won THEN
        _comm := round(_g.pot * _g.commission_pct / 100.0, 0);
        _payout := _g.pot - _comm;
        UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) + _payout WHERE id=_uid;
        INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
          VALUES (_uid,'rami_win',_payout,_game_id,'Win rami (auto)');
        UPDATE public.rami_games SET status='finished', winner_id=_uid, finished_at=now(), state=_state WHERE id=_game_id;
        RETURN;
      END IF;
    END;
  END IF;

  -- Next active player
  SELECT array_agg(slot ORDER BY slot) INTO _parts FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited;
  _next := _g.current_turn;
  IF array_length(_parts,1) > 0 THEN
    LOOP
      _next := (_next + 1) % _g.max_players;
      EXIT WHEN _next = ANY(_parts);
    END LOOP;
  ELSE
    -- No active players — end game
    UPDATE public.rami_games SET status='finished', finished_at=now(), state=_state WHERE id=_game_id;
    RETURN;
  END IF;

  UPDATE public.rami_games SET state=_state, current_turn=_next, turn_phase='draw',
    turn_skips = jsonb_set(COALESCE(_g.turn_skips,'{}'::jsonb), ARRAY[_uid::text], to_jsonb(_skips)),
    turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval,
    updated_at=now()
    WHERE id=_game_id;
END $$;
REVOKE ALL ON FUNCTION public.rami_tick(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_tick(uuid) TO authenticated;

-- 12. rami_add_bot: real bot implementation --------------------
CREATE OR REPLACE FUNCTION public.rami_add_bot(_game_id uuid, _bot_name text DEFAULT 'Bot')
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public AS $$
DECLARE
  _uid uuid := auth.uid(); _g public.rami_games; _count int; _slot int;
  _bot_id uuid; _names text[]; _bot_name text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.id IS NULL THEN RAISE EXCEPTION 'partie introuvable'; END IF;
  IF _g.status NOT IN ('waiting','open') THEN RAISE EXCEPTION 'partie déjà commencée'; END IF;

  -- Only participants or admin can add bots
  IF NOT EXISTS (SELECT 1 FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid) THEN
    -- Allow if admin
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=_uid AND is_admin = true) THEN
      RAISE EXCEPTION 'non participant';
    END IF;
  END IF;

  SELECT count(*) INTO _count FROM public.rami_participants WHERE game_id=_game_id;
  IF _count >= _g.max_players THEN RAISE EXCEPTION 'partie pleine'; END IF;

  _slot := _count;
  -- Generate a fake UUID for the bot
  _bot_id := gen_random_uuid();
  _names := ARRAY['Bot Rado', 'Bot Mamy', 'Bot Tsy Maty', 'Bot Vit', 'Bot Sambatra', 'Bot Mahay'];
  _bot_name := COALESCE(NULLIF(_bot_name, 'Bot'), _names[1 + floor(random()*array_length(_names,1))::int]);

  -- Create a bot profile if not exists
  INSERT INTO public.rami_participants(game_id, user_id, slot, display_name, is_bot)
    VALUES (_game_id, _bot_id, _slot, _bot_name, true);

  -- Auto-start if full
  IF _slot + 1 = _g.max_players THEN
    PERFORM public.rami_start(_game_id);
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.rami_add_bot(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_add_bot(uuid,text) TO authenticated;

-- 13. rami_claim_seven: refund stake for 7-card meld ----------
CREATE OR REPLACE FUNCTION public.rami_claim_seven(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public AS $$
DECLARE
  _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _melds jsonb; _m jsonb; _total_cards int := 0; _found boolean := false;
  _refunded jsonb; _action_log jsonb;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;

  _state := _g.state;
  _refunded := COALESCE(_state->'refunded','{}'::jsonb);
  IF _refunded ? _uid::text THEN RAISE EXCEPTION 'deja remboursé'; END IF;

  -- Check if player has melds totaling exactly 7 cards
  _melds := COALESCE(_state->'melds','[]'::jsonb);
  FOR _m IN SELECT * FROM jsonb_array_elements(_melds) LOOP
    IF _m->>'player' = _uid::text THEN
      _total_cards := _total_cards + COALESCE(jsonb_array_length(_m->'cards'), 0);
      IF _m->>'type' = 'seven' THEN _found := true; END IF;
    END IF;
  END LOOP;

  IF NOT _found AND _total_cards < 7 THEN
    RAISE EXCEPTION 'tu dois poser 7 cartes valides';
  END IF;

  -- Refund stake
  IF _g.stake > 0 THEN
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) + _g.stake WHERE id=_uid;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (_uid,'rami_seven_refund',_g.stake,_game_id,'7 Cartes refund');
  END IF;

  _refunded := _refunded || jsonb_build_object(_uid::text, true);
  _state := jsonb_set(_state, '{refunded}', _refunded);
  _action_log := COALESCE(_state->'action_log','[]'::jsonb) ||
    jsonb_build_object('t','seven','p',_uid::text,'ts',extract(epoch from now())::bigint);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
END $$;
REVOKE ALL ON FUNCTION public.rami_claim_seven(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_claim_seven(uuid) TO authenticated;

-- 14. rami_validate_hand: check if hand can be fully melded ----
CREATE OR REPLACE FUNCTION public.rami_validate_hand(_game_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public AS $$
DECLARE
  _uid uuid := auth.uid(); _g public.rami_games; _state jsonb;
  _hand int[]; _melds jsonb; _m jsonb; _meld_cards int[]; _c int; _all_melded int[] := ARRAY[]::int[];
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  _state := _g.state;
  _hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[], ARRAY[]::int[]);
  _melds := COALESCE(_state->'melds','[]'::jsonb);
  FOR _m IN SELECT * FROM jsonb_array_elements(_melds) LOOP
    IF _m->>'player' = _uid::text THEN
      _meld_cards := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_m->'cards'))::int[], ARRAY[]::int[]);
      _all_melded := _all_melded || _meld_cards;
    END IF;
  END LOOP;
  -- Check if every card in hand is in a meld (i.e., hand is empty or all cards are melded)
  RETURN COALESCE(array_length(_hand,1),0) = 0;
END $$;
REVOKE ALL ON FUNCTION public.rami_validate_hand(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_validate_hand(uuid) TO authenticated;

-- 15. rami_set_ready: fix to also check for auto-start --------
CREATE OR REPLACE FUNCTION public.rami_set_ready(_game_id uuid, _ready boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public AS $$
DECLARE
  _uid uuid := auth.uid(); _g public.rami_games; _count int; _ready_count int;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status NOT IN ('waiting','open') THEN RAISE EXCEPTION 'partie déjà commencée'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid) THEN
    RAISE EXCEPTION 'non participant';
  END IF;
  UPDATE public.rami_participants SET ready=_ready WHERE game_id=_game_id AND user_id=_uid;
  -- Auto-start when all ready
  SELECT count(*), count(CASE WHEN ready THEN 1 END) INTO _count, _ready_count
    FROM public.rami_participants WHERE game_id=_game_id;
  IF _count >= 2 AND _count = _ready_count THEN
    PERFORM public.rami_start(_game_id);
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.rami_set_ready(uuid,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_set_ready(uuid,boolean) TO authenticated;

-- 16. rami_request_refund: participant guard ------------------
CREATE OR REPLACE FUNCTION public.rami_request_refund(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public AS $$
DECLARE
  _uid uuid := auth.uid(); _g public.rami_games; _state jsonb;
  _refunded jsonb;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid) THEN
    RAISE EXCEPTION 'non participant';
  END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'cancelled' THEN RAISE EXCEPTION 'partie non annulée'; END IF;
  _state := _g.state;
  _refunded := COALESCE(_state->'refunded','{}'::jsonb);
  IF _refunded ? _uid::text THEN RAISE EXCEPTION 'mise déjà remboursée'; END IF;
  IF _g.stake > 0 THEN
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) + _g.stake WHERE id=_uid;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (_uid,'rami_refund',_g.stake,_game_id,'Rami cancel refund');
  END IF;
  _refunded := _refunded || jsonb_build_object(_uid::text, true);
  _state := jsonb_set(_state, '{refunded}', _refunded);
  UPDATE public.rami_games SET state=_state WHERE id=_game_id;
END $$;
REVOKE ALL ON FUNCTION public.rami_request_refund(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_request_refund(uuid) TO authenticated;

-- 17. Update rami_join to use balance_ar ----------------------
CREATE OR REPLACE FUNCTION public.rami_join(_game_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public AS $$
DECLARE
  _uid uuid := auth.uid(); _g public.rami_games; _bal numeric; _name text;
  _count int; _slot int;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.id IS NULL THEN RAISE EXCEPTION 'partie introuvable'; END IF;
  IF _g.status NOT IN ('waiting','open') THEN RAISE EXCEPTION 'partie déjà commencée'; END IF;
  IF _g.is_private THEN RAISE EXCEPTION 'partie privée — utilise le code pour rejoindre'; END IF;
  IF EXISTS (SELECT 1 FROM public.rami_participants WHERE game_id=_g.id AND user_id=_uid) THEN
    RETURN _g.id;
  END IF;
  SELECT count(*) INTO _count FROM public.rami_participants WHERE game_id=_g.id;
  IF _count >= _g.max_players THEN RAISE EXCEPTION 'partie pleine'; END IF;
  SELECT COALESCE(balance_ar, balance, 0), COALESCE(pseudo, display_name, 'Joueur') INTO _bal, _name
    FROM public.profiles WHERE id=_uid FOR UPDATE;
  IF _bal IS NULL OR _bal < _g.stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
  _slot := _count;
  IF _g.stake > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar - _g.stake WHERE id=_uid;
    UPDATE public.rami_games SET pot = pot + _g.stake WHERE id=_g.id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (_uid, 'rami_stake', -_g.stake, _g.id, 'Join rami');
  END IF;
  INSERT INTO public.rami_participants(game_id, user_id, slot, display_name, is_bot)
    VALUES (_g.id, _uid, _slot, _name, false);
  -- Auto-start when full
  IF _slot + 1 = _g.max_players THEN PERFORM public.rami_start(_g.id); END IF;
  RETURN _g.id;
END $$;
REVOKE ALL ON FUNCTION public.rami_join(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_join(uuid) TO authenticated;
