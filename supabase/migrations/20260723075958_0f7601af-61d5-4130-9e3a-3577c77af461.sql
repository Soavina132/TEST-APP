
-- ============================================================
-- Rami: per-player discard piles
--  state.discards : jsonb { "<player_key>": int[] }
--  state.last_discard_by : text (player_key or '_seed')
--  Legacy state.discard (single array) is treated as the seed pile.
-- ============================================================

-- Helper: build discards map (fallback to legacy 'discard' as '_seed')
CREATE OR REPLACE FUNCTION public._rami_discards_map(_state jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE _m jsonb;
BEGIN
  _m := _state->'discards';
  IF _m IS NULL OR jsonb_typeof(_m) <> 'object' THEN
    IF _state ? 'discard' AND jsonb_array_length(COALESCE(_state->'discard','[]'::jsonb)) > 0 THEN
      RETURN jsonb_build_object('_seed', _state->'discard');
    END IF;
    RETURN '{}'::jsonb;
  END IF;
  RETURN _m;
END $$;

CREATE OR REPLACE FUNCTION public._rami_last_discarder(_state jsonb)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT COALESCE(_state->>'last_discard_by', '_seed')
$$;

-- Gather every card across every pile
CREATE OR REPLACE FUNCTION public._rami_all_discards(_state jsonb)
RETURNS int[] LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE _m jsonb := public._rami_discards_map(_state);
  _k text; _acc int[] := ARRAY[]::int[]; _arr int[];
BEGIN
  FOR _k IN SELECT jsonb_object_keys(_m) LOOP
    _arr := ARRAY(SELECT jsonb_array_elements_text(_m->_k))::int[];
    _acc := _acc || _arr;
  END LOOP;
  RETURN _acc;
END $$;

-- Reshuffle: returns (new_deck, new_discards jsonb, new_last_by)
-- Keeps ONLY the top of last_discard_by pile, everything else goes back into deck.
CREATE OR REPLACE FUNCTION public._rami_reshuffle(_state jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  _m jsonb := public._rami_discards_map(_state);
  _last text := public._rami_last_discarder(_state);
  _top_pile int[] := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_m->_last))::int[], ARRAY[]::int[]);
  _keep int; _pool int[] := ARRAY[]::int[]; _k text; _arr int[]; _new_deck int[]; _new_map jsonb;
BEGIN
  IF array_length(_top_pile,1) IS NULL THEN
    RETURN jsonb_build_object('deck','[]'::jsonb,'discards','{}'::jsonb,'last', _last);
  END IF;
  _keep := _top_pile[array_length(_top_pile,1)];
  FOR _k IN SELECT jsonb_object_keys(_m) LOOP
    _arr := ARRAY(SELECT jsonb_array_elements_text(_m->_k))::int[];
    IF _k = _last THEN
      _arr := _arr[1:array_length(_arr,1)-1];
    END IF;
    IF array_length(_arr,1) IS NOT NULL THEN
      _pool := _pool || _arr;
    END IF;
  END LOOP;
  _new_deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_pool) c);
  _new_map := jsonb_build_object(_last, jsonb_build_array(_keep));
  RETURN jsonb_build_object(
    'deck', COALESCE(to_jsonb(_new_deck), '[]'::jsonb),
    'discards', _new_map,
    'last', _last
  );
END $$;

-- Migrate legacy state fields to new shape, if needed. Returns cleaned state.
CREATE OR REPLACE FUNCTION public._rami_normalize_state(_state jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE _s jsonb := _state;
BEGIN
  IF _s IS NULL THEN RETURN _s; END IF;
  IF NOT (_s ? 'discards') THEN
    _s := jsonb_set(_s, '{discards}', public._rami_discards_map(_state), true);
  END IF;
  IF NOT (_s ? 'last_discard_by') THEN
    _s := jsonb_set(_s, '{last_discard_by}', to_jsonb(public._rami_last_discarder(_state)), true);
  END IF;
  -- keep old 'discard' field for any legacy reader, but sync it to combined top view (removed on next write)
  RETURN _s;
END $$;

-- ============================================================
-- rami_start: initialize per-player discards + seed pile
-- ============================================================
CREATE OR REPLACE FUNCTION public.rami_start(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  _g public.rami_games;
  _rows RECORD;
  _deck int[]; _i int; _j int; _tmp int;
  _hands jsonb := '{}'::jsonb; _hand int[]; _state jsonb;
  _max int; _rj int := NULL; _first int; _top int; _key text;
  _n int;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'waiting' THEN RETURN; END IF;

  SELECT count(*) INTO _n FROM public.rami_participants WHERE game_id=_game_id;
  IF _n < 2 THEN RAISE EXCEPTION 'pas assez de joueurs'; END IF;

  IF _g.joker_mode IN ('classique','double') THEN _max := 56; ELSE _max := 52; END IF;
  _deck := ARRAY(SELECT generate_series(0,_max-1));

  FOR _i IN REVERSE _max..2 LOOP
    _j := 1 + floor(random()*_i)::int;
    _tmp := _deck[_i]; _deck[_i] := _deck[_j]; _deck[_j] := _tmp;
  END LOOP;

  FOR _rows IN SELECT slot, user_id, is_bot FROM public.rami_participants
                WHERE game_id=_game_id ORDER BY slot LOOP
    _hand := _deck[1:13];
    _deck := _deck[14:array_length(_deck,1)];
    _key := CASE WHEN COALESCE(_rows.is_bot,false) OR _rows.user_id IS NULL
                 THEN 'bot:' || _rows.slot::text
                 ELSE _rows.user_id::text END;
    _hands := _hands || jsonb_build_object(_key, to_jsonb(_hand));
    UPDATE public.rami_participants SET hand_count=13
      WHERE game_id=_game_id AND slot=_rows.slot;
  END LOOP;

  IF _g.joker_mode IN ('aleatoire','double') THEN
    _i := 1;
    WHILE _i <= array_length(_deck,1) AND _deck[_i] >= 52 LOOP _i := _i + 1; END LOOP;
    IF _i <= array_length(_deck,1) THEN
      _rj := _deck[_i];
      _deck := _deck[1:_i-1] || _deck[_i+1:array_length(_deck,1)];
    END IF;
  END IF;

  _top := _deck[1];
  _deck := _deck[2:array_length(_deck,1)];
  _first := floor(random() * _n)::int;

  _state := jsonb_build_object(
    'deck', to_jsonb(_deck),
    'discards', jsonb_build_object('_seed', jsonb_build_array(_top)),
    'last_discard_by', '_seed',
    'hands', _hands,
    'melds', '[]'::jsonb,
    'first_player', _first
  );

  UPDATE public.rami_games
    SET status='playing', state=_state, started_at=now(),
        current_turn=_first, turn_phase='draw',
        random_joker=_rj,
        turn_deadline=now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('rami')),60) || ' seconds')::interval
  WHERE id=_game_id;

  PERFORM public._rami_autoplay_bots(_game_id);
END $$;

-- ============================================================
-- rami_draw: pick from previous player's discard pile only
-- ============================================================
CREATE OR REPLACE FUNCTION public.rami_draw(_game_id uuid, _from text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  _uid uuid := auth.uid(); _g rami_games; _slot int; _state jsonb;
  _deck int[]; _hand int[]; _card int; _hands jsonb;
  _discards jsonb; _last text; _pile int[]; _reshuffle jsonb;
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM rami_participants
   WHERE game_id=_game_id AND user_id=_uid AND is_bot=false;
  IF _slot IS NULL OR _slot <> _g.current_turn THEN RAISE EXCEPTION 'pas ton tour'; END IF;
  IF _g.turn_phase <> 'draw' THEN RAISE EXCEPTION 'déjà pioché'; END IF;

  _state := public._rami_normalize_state(_g.state);
  _deck := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'deck'))::int[], ARRAY[]::int[]);
  _hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[], ARRAY[]::int[]);
  _discards := public._rami_discards_map(_state);
  _last := public._rami_last_discarder(_state);

  IF _from = 'discard' THEN
    _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_last))::int[], ARRAY[]::int[]);
    IF array_length(_pile,1) IS NULL THEN RAISE EXCEPTION 'défausse vide'; END IF;
    _card := _pile[array_length(_pile,1)];
    _pile := _pile[1:array_length(_pile,1)-1];
    IF array_length(_pile,1) IS NULL THEN
      _discards := _discards - _last;
    ELSE
      _discards := jsonb_set(_discards, ARRAY[_last], to_jsonb(_pile));
    END IF;
  ELSE
    IF array_length(_deck,1) IS NULL THEN
      _reshuffle := public._rami_reshuffle(_state);
      _deck := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_reshuffle->'deck'))::int[], ARRAY[]::int[]);
      _discards := _reshuffle->'discards';
      IF array_length(_deck,1) IS NULL THEN RAISE EXCEPTION 'plus de cartes'; END IF;
    END IF;
    _card := _deck[1];
    _deck := _deck[2:array_length(_deck,1)];
  END IF;

  _hand := array_append(_hand, _card);
  _hands := jsonb_set(_state->'hands', ARRAY[_uid::text], to_jsonb(_hand));
  _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
  _state := jsonb_set(_state, '{discards}', _discards);
  _state := jsonb_set(_state, '{hands}', _hands);
  -- strip legacy field to avoid confusion for readers
  _state := _state - 'discard';

  UPDATE rami_games SET state=_state, turn_phase='play', updated_at=now() WHERE id=_game_id;
  UPDATE rami_participants SET hand_count=array_length(_hand,1) WHERE game_id=_game_id AND user_id=_uid;
END $$;

-- ============================================================
-- rami_discard: push card into current player's own pile
-- ============================================================
CREATE OR REPLACE FUNCTION public.rami_discard(_game_id uuid, _card integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _hand int[]; _new_hand int[]; _hands jsonb;
  _discards jsonb; _pile int[];
  _parts int[]; _next int; _payout numeric; _comm numeric; _won boolean;
  _cfg record; _key text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _state := public._rami_normalize_state(_g.state);
  _key := _uid::text;
  _hand := ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_key))::int[];
  IF NOT (_card = ANY(_hand)) THEN RAISE EXCEPTION 'carte absente'; END IF;
  _new_hand := public._rami_remove_one(_hand,_card);

  _discards := public._rami_discards_map(_state);
  _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_key))::int[], ARRAY[]::int[]);
  _pile := array_append(_pile, _card);
  _discards := jsonb_set(_discards, ARRAY[_key], to_jsonb(_pile), true);

  _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_new_hand));
  _state := jsonb_set(_state,'{hands}',_hands);
  _state := jsonb_set(_state,'{discards}',_discards);
  _state := jsonb_set(_state,'{last_discard_by}', to_jsonb(_key));
  _state := _state - 'discard';

  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand,1),0)
   WHERE game_id=_game_id AND user_id=_uid;

  IF COALESCE(array_length(_new_hand,1),0) = 0 THEN
    _won := public._rami_check_win(_state, _uid);
    IF _won THEN
      _comm := round(_g.pot * _g.commission_pct / 100.0, 0);
      _payout := _g.pot - _comm;
      UPDATE public.profiles SET balance_ar=balance_ar+_payout WHERE id=_uid;
      INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (_uid,'rami_win',_payout,_game_id,'Win rami');
      UPDATE public.rami_games SET status='finished', winner_id=_uid,
        finished_at=now(), state=_state WHERE id=_game_id;
      RETURN;
    ELSE
      RAISE EXCEPTION 'combinaisons incomplètes: pose toutes tes cartes en combinaisons valides avant de finir';
    END IF;
  END IF;

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

  PERFORM public._rami_autoplay_bots(_game_id);
END $$;

-- ============================================================
-- rami_tick: adapt for per-player discards
-- ============================================================
CREATE OR REPLACE FUNCTION public.rami_tick(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  _g public.rami_games; _state jsonb; _uid uuid; _hand int[]; _new_hand int[];
  _deck int[]; _card int; _next int; _cfg record; _skips int;
  _best_card int; _best_pts int := -1; _pts int; _rank int; _c int;
  _is_bot boolean; _key text;
  _discards jsonb; _pile int[]; _reshuffle jsonb;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RETURN; END IF;

  SELECT COALESCE(is_bot,false), user_id INTO _is_bot, _uid
    FROM public.rami_participants WHERE game_id=_game_id AND slot=_g.current_turn;

  IF _is_bot THEN
    PERFORM public._rami_autoplay_bots(_game_id);
    RETURN;
  END IF;

  IF _g.turn_deadline IS NULL OR _g.turn_deadline > now() THEN RETURN; END IF;
  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _skips := COALESCE((_g.turn_skips->>_uid::text)::int, 0) + 1;

  IF _skips >= COALESCE(_cfg.max_turn_skips,3) THEN
    UPDATE public.rami_participants SET forfeited = true WHERE game_id=_game_id AND user_id=_uid;
    IF (SELECT count(*) FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited) <= 1 THEN
      DECLARE _win uuid;
      BEGIN
        SELECT user_id INTO _win FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited LIMIT 1;
        UPDATE public.rami_games SET status='finished', winner_id=_win, finished_at=now() WHERE id=_game_id;
        IF _win IS NOT NULL THEN
          UPDATE public.profiles SET balance_ar = balance_ar + (_g.pot * (100 - _g.commission_pct) / 100) WHERE id=_win;
          INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
            VALUES (_win,'rami_win', _g.pot * (100 - _g.commission_pct) / 100, _game_id, 'Rami win (forfait)');
        END IF;
        RETURN;
      END;
    END IF;
  END IF;

  _state := public._rami_normalize_state(_g.state);
  _key := _uid::text;
  _deck := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'deck'))::int[], ARRAY[]::int[]);
  _discards := public._rami_discards_map(_state);
  _hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_key))::int[], ARRAY[]::int[]);

  IF _g.turn_phase = 'draw' THEN
    IF COALESCE(array_length(_deck,1),0) = 0 THEN
      _reshuffle := public._rami_reshuffle(_state);
      _deck := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_reshuffle->'deck'))::int[], ARRAY[]::int[]);
      _discards := _reshuffle->'discards';
      IF COALESCE(array_length(_deck,1),0) = 0 THEN
        UPDATE public.rami_games SET status='finished', finished_at=now(),
          state = jsonb_set(_state,'{end_reason}', to_jsonb('deck exhausted'::text))
          WHERE id=_game_id;
        RETURN;
      END IF;
    END IF;
    _card := _deck[1]; _deck := _deck[2:array_length(_deck,1)];
    _hand := array_append(_hand, _card);
  END IF;

  FOREACH _c IN ARRAY _hand LOOP
    IF public._rami_is_joker(_c, _g.joker_mode, _g.random_joker) THEN CONTINUE; END IF;
    _rank := _c % 13;
    _pts := CASE WHEN _rank = 0 THEN 11
                 WHEN _rank >= 10 THEN 10
                 ELSE _rank + 1 END;
    IF _pts > _best_pts THEN _best_pts := _pts; _best_card := _c; END IF;
  END LOOP;
  IF _best_card IS NULL THEN
    _best_card := _hand[1 + floor(random()*array_length(_hand,1))::int];
  END IF;
  _card := _best_card;

  _new_hand := public._rami_remove_one(_hand, _card);
  _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_key))::int[], ARRAY[]::int[]);
  _pile := array_append(_pile, _card);
  _discards := jsonb_set(_discards, ARRAY[_key], to_jsonb(_pile), true);

  _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
  _state := jsonb_set(_state, '{discards}', _discards);
  _state := jsonb_set(_state, '{last_discard_by}', to_jsonb(_key));
  _state := jsonb_set(_state, ARRAY['hands',_key], to_jsonb(_new_hand));
  _state := _state - 'discard';
  UPDATE public.rami_participants SET hand_count=array_length(_new_hand,1) WHERE game_id=_game_id AND user_id=_uid;

  _next := _g.current_turn;
  LOOP
    _next := (_next + 1) % _g.max_players;
    EXIT WHEN _next IN (SELECT slot FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited);
  END LOOP;

  UPDATE public.rami_games SET state=_state, current_turn=_next, turn_phase='draw',
    turn_skips = jsonb_set(COALESCE(_g.turn_skips,'{}'::jsonb), ARRAY[_uid::text], to_jsonb(_skips)),
    turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval,
    updated_at=now()
    WHERE id=_game_id;

  PERFORM public._rami_autoplay_bots(_game_id);
END $$;

-- ============================================================
-- _rami_autoplay_bots: adapt draw/discard for per-player piles
-- ============================================================
CREATE OR REPLACE FUNCTION public._rami_autoplay_bots(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','extensions' AS $$
DECLARE
  g public.rami_games; part public.rami_participants; guard int := 0;
  _key text; _hand int[]; _card int; _deck int[]; _new_hand int[]; _hands jsonb;
  _melds jsonb; _melded int[]; _type text; _intel int; _parts int[]; _next int;
  _top int; _matched boolean;
  _cfg record;
  _state jsonb; _discards jsonb; _pile int[]; _last text; _reshuffle jsonb;
BEGIN
  LOOP
    guard := guard + 1;
    IF guard > 100 THEN EXIT; END IF;

    SELECT * INTO g FROM public.rami_games WHERE id = _game_id FOR UPDATE;
    IF NOT FOUND OR g.status <> 'playing' THEN EXIT; END IF;
    IF COALESCE(g.paused, false) THEN EXIT; END IF;

    SELECT * INTO part FROM public.rami_participants
     WHERE game_id = _game_id AND slot = g.current_turn AND forfeited = false;
    IF NOT FOUND OR NOT COALESCE(part.is_bot,false) THEN EXIT; END IF;

    _key   := COALESCE(part.user_id::text, 'bot:' || part.slot::text);
    _intel := COALESCE(part.bot_intelligence, 70);
    SELECT * INTO _cfg FROM public._game_cfg('rami');
    _state := public._rami_normalize_state(g.state);
    _discards := public._rami_discards_map(_state);
    _last := public._rami_last_discarder(_state);

    ------------------------------------------------------------
    -- DRAW PHASE
    ------------------------------------------------------------
    IF g.turn_phase = 'draw' THEN
      _deck    := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'deck'))::int[], ARRAY[]::int[]);
      _hand    := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_key))::int[], ARRAY[]::int[]);
      _pile    := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_last))::int[], ARRAY[]::int[]);
      _card    := NULL;
      _matched := false;

      IF _intel >= 70 AND array_length(_pile,1) IS NOT NULL AND array_length(_pile,1) > 0 THEN
        _top := _pile[array_length(_pile,1)];
        IF _top < 52 AND EXISTS (SELECT 1 FROM unnest(_hand) c WHERE c < 52 AND c%13 = _top%13) THEN
          _matched := true;
          _card := _top;
          _pile := _pile[1:array_length(_pile,1)-1];
          IF array_length(_pile,1) IS NULL THEN
            _discards := _discards - _last;
          ELSE
            _discards := jsonb_set(_discards, ARRAY[_last], to_jsonb(_pile));
          END IF;
        END IF;
      END IF;

      IF NOT _matched THEN
        IF array_length(_deck,1) IS NULL THEN
          _reshuffle := public._rami_reshuffle(_state);
          _deck := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_reshuffle->'deck'))::int[], ARRAY[]::int[]);
          _discards := _reshuffle->'discards';
          IF array_length(_deck,1) IS NULL THEN EXIT; END IF;
        END IF;
        _card := _deck[1];
        _deck := _deck[2:array_length(_deck,1)];
      END IF;

      _hand := array_append(_hand, _card);
      _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_hand));
      _state := jsonb_set(_state,'{deck}',to_jsonb(_deck));
      _state := jsonb_set(_state,'{discards}',_discards);
      _state := jsonb_set(_state,'{hands}',_hands);
      _state := _state - 'discard';

      UPDATE public.rami_games
         SET state = _state,
             turn_phase = 'play',
             updated_at = now()
       WHERE id = _game_id;
      UPDATE public.rami_participants
         SET hand_count = COALESCE(array_length(_hand,1),0)
       WHERE game_id = _game_id AND slot = part.slot;
      CONTINUE;
    END IF;

    ------------------------------------------------------------
    -- PLAY PHASE
    ------------------------------------------------------------
    _hand  := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_key))::int[], ARRAY[]::int[]);
    _melds := COALESCE(_state->'melds','[]'::jsonb);

    IF _intel >= 50 AND COALESCE(array_length(_hand,1),0) >= 4 THEN
      SELECT ARRAY[_hand[i], _hand[j], _hand[k]] INTO _melded
        FROM generate_subscripts(_hand,1) i, generate_subscripts(_hand,1) j, generate_subscripts(_hand,1) k
       WHERE i < j AND j < k
         AND public._rami_meld_type(ARRAY[_hand[i],_hand[j],_hand[k]], g.joker_mode, g.random_joker) IS NOT NULL
       LIMIT 1;

      IF _melded IS NOT NULL THEN
        _type := public._rami_meld_type(_melded, g.joker_mode, g.random_joker);
        _new_hand := _hand;
        FOREACH _card IN ARRAY _melded LOOP
          _new_hand := public._rami_remove_one(_new_hand, _card);
        END LOOP;
        _melds := _melds || jsonb_build_array(jsonb_build_object(
          'player', _key,
          'cards',  to_jsonb(_melded),
          'type',   _type
        ));
        _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_new_hand));
        _state := jsonb_set(_state,'{hands}',_hands);
        _state := jsonb_set(_state,'{melds}',_melds);
        UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
        UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand,1),0)
          WHERE game_id=_game_id AND slot=part.slot;
        _melded := NULL;
        CONTINUE;
      END IF;
    END IF;

    IF COALESCE(array_length(_hand,1),0) = 0 THEN EXIT; END IF;

    IF _intel < 50 THEN
      _card := _hand[1 + floor(random() * array_length(_hand,1))::int];
    ELSE
      SELECT c INTO _card FROM unnest(_hand) c
        ORDER BY (CASE WHEN c < 52 THEN c%13 ELSE -1 END) DESC, random()
        LIMIT 1;
    END IF;

    _new_hand := public._rami_remove_one(_hand, _card);
    _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_key))::int[], ARRAY[]::int[]);
    _pile := array_append(_pile, _card);
    _discards := jsonb_set(_discards, ARRAY[_key], to_jsonb(_pile), true);
    _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_new_hand));

    IF COALESCE(array_length(_new_hand,1),0) = 0 THEN
      _state := jsonb_set(_state,'{hands}',_hands);
      _state := jsonb_set(_state,'{discards}',_discards);
      _state := jsonb_set(_state,'{last_discard_by}',to_jsonb(_key));
      _state := _state - 'discard';
      IF public._rami_check_win(_state, _key) THEN
        UPDATE public.rami_games
           SET status='finished', winner_id=part.user_id, finished_at=now(), state=_state
         WHERE id=_game_id;
        UPDATE public.rami_participants SET hand_count=0
         WHERE game_id=_game_id AND slot=part.slot;
        EXIT;
      ELSE
        _card := _hand[1 + floor(random() * array_length(_hand,1))::int];
        _new_hand := public._rami_remove_one(_hand, _card);
        _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(g.state->'discards'->_key))::int[], ARRAY[]::int[]);
        _pile := array_append(_pile, _card);
        _discards := public._rami_discards_map(g.state);
        _discards := jsonb_set(_discards, ARRAY[_key], to_jsonb(_pile), true);
        _hands := jsonb_set(g.state->'hands', ARRAY[_key], to_jsonb(_new_hand));
      END IF;
    END IF;

    SELECT array_agg(slot ORDER BY slot) INTO _parts
      FROM public.rami_participants WHERE game_id = _game_id AND NOT forfeited;
    _next := g.current_turn;
    LOOP
      _next := (_next + 1) % g.max_players;
      EXIT WHEN _next = ANY(_parts);
    END LOOP;

    _state := jsonb_set(_state,'{hands}',_hands);
    _state := jsonb_set(_state,'{discards}',_discards);
    _state := jsonb_set(_state,'{last_discard_by}',to_jsonb(_key));
    _state := _state - 'discard';

    UPDATE public.rami_games
       SET state = _state,
           current_turn = _next,
           turn_phase = 'draw',
           turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
           updated_at = now()
     WHERE id = _game_id;
    UPDATE public.rami_participants
       SET hand_count = COALESCE(array_length(_new_hand,1),0)
     WHERE game_id = _game_id AND slot = part.slot;
  END LOOP;
END $$;
