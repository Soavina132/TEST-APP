-- Migration: 20260810230000_rami_critical_fixes.sql
-- CRITICAL FIXES for Rami game

-- 0. Add winner_name column
ALTER TABLE public.rami_games ADD COLUMN IF NOT EXISTS winner_name text;

-- 1. Fix rami_start: use bot:<slot> for bots with NULL user_id
CREATE OR REPLACE FUNCTION public.rami_start(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  _g public.rami_games; _deck int[]; _i int; _j int; _tmp int;
  _hands jsonb := '{}'::jsonb; _hand int[]; _state jsonb;
  _first_discard int; _cfg record; _joker_mode text; _random_joker int;
  _discards jsonb; _action_log jsonb; _n int;
  _slot int; _uid uuid; _is_bot boolean; _key text;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status NOT IN ('waiting','open') THEN RETURN; END IF;
  IF (SELECT count(*) FROM public.rami_participants WHERE game_id=_game_id) < 2 THEN
    RAISE EXCEPTION 'pas assez de joueurs';
  END IF;
  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _joker_mode := _g.joker_mode;
  IF _joker_mode IN ('classique','double') THEN
    _deck := ARRAY(SELECT generate_series(0, 111));
  ELSE
    _deck := ARRAY(SELECT generate_series(0, 51)) || ARRAY(SELECT generate_series(56, 107));
  END IF;
  _n := array_length(_deck,1);
  FOR _i IN REVERSE _n..2 LOOP
    _j := 1 + floor(random()*_i)::int;
    _tmp := _deck[_i]; _deck[_i] := _deck[_j]; _deck[_j] := _tmp;
  END LOOP;
  FOR _slot, _uid, _is_bot IN
    SELECT slot, user_id, is_bot FROM public.rami_participants
    WHERE game_id=_game_id ORDER BY slot
  LOOP
    _hand := _deck[1:13];
    _deck := _deck[14:array_length(_deck,1)];
    _key := CASE WHEN COALESCE(_is_bot, false) THEN 'bot:' || _slot::text ELSE _uid::text END;
    _hands := _hands || jsonb_build_object(_key, to_jsonb(_hand));
    UPDATE public.rami_participants SET hand_count = 13
      WHERE game_id=_game_id AND slot=_slot;
  END LOOP;
  _first_discard := _deck[1];
  _deck := _deck[2:array_length(_deck,1)];
  _random_joker := NULL;
  IF _joker_mode IN ('aleatoire','double') THEN
    _random_joker := floor(random()*52)::int;
  END IF;
  _discards := jsonb_build_object('_seed', jsonb_build_array(_first_discard));
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
END $function$;
REVOKE ALL ON FUNCTION public.rami_start(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_start(uuid) TO authenticated;

-- 2. Fix rami_discard: ADD WIN CONDITION CHECK (was missing!)
CREATE OR REPLACE FUNCTION public.rami_discard(_game_id uuid, _card integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _hand int[]; _new_hand int[]; _pile int[]; _hands jsonb; _discards jsonb;
  _parts int[]; _next int; _cfg record; _won boolean; _winner_name text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;
  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _state := public._rami_normalize_state(_g.state);
  _discards := public._rami_discards_map(_state);
  _hand := public._rami_jarr(_state->'hands'->_uid::text);
  IF NOT (_card = ANY(_hand)) THEN RAISE EXCEPTION 'carte absente'; END IF;
  _new_hand := public._rami_remove_one(_hand,_card);
  _pile := public._rami_jarr(_discards->_uid::text);
  _pile := array_append(_pile, _card);
  _discards := jsonb_set(COALESCE(_discards,'{}'::jsonb), ARRAY[_uid::text], public._rami_jset(_pile), true);
  _hands := jsonb_set(_state->'hands', ARRAY[_uid::text], public._rami_jset(_new_hand), true);
  _state := jsonb_set(_state,'{hands}',_hands, true);
  _state := jsonb_set(_state,'{discards}',_discards, true);
  _state := jsonb_set(_state,'{last_discard_by}', to_jsonb(_uid::text), true);
  _state := _state - 'discard';
  UPDATE public.rami_participants
     SET hand_count=COALESCE(array_length(_new_hand,1),0)
   WHERE game_id=_game_id AND user_id=_uid;

  -- WIN CONDITION CHECK (was completely missing!)
  IF COALESCE(array_length(_new_hand,1),0) = 0 THEN
    _won := public._rami_check_win(_state, _uid::text);
    IF _won THEN
      SELECT COALESCE(pseudo, 'Joueur') INTO _winner_name FROM public.profiles WHERE id = _uid;
      DECLARE _payout numeric; _comm numeric;
      BEGIN
        _comm := round(_g.pot * _g.commission_pct / 100.0, 0);
        _payout := _g.pot - _comm;
        UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) + _payout WHERE id=_uid;
        INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
          VALUES (_uid,'rami_win',_payout,_game_id,'Win rami');
        UPDATE public.rami_games SET status='finished', winner_id=_uid,
          winner_name=_winner_name, finished_at=now(), state=_state WHERE id=_game_id;
      END;
      RETURN;
    ELSE
      RAISE EXCEPTION 'combinaisons incomplètes';
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
  _state := _state - 'bot_think_until';
  _state := public._rami_arm_bot_think(_game_id, _next, _state);
  UPDATE public.rami_games
     SET state=_state, current_turn=_next, turn_phase='draw',
         turn_deadline=now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval,
         updated_at=now()
   WHERE id=_game_id;
  BEGIN
    PERFORM public._rami_autoplay_bots(_game_id);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END $function$;
REVOKE ALL ON FUNCTION public.rami_discard(uuid,int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_discard(uuid,int) TO authenticated;

-- 3. Fix _rami_autoplay_bots: fix winner_name for bot wins + use bot:<slot> key
CREATE OR REPLACE FUNCTION public._rami_autoplay_bots(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
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
    _key   := 'bot:' || part.slot::text;
    _intel := COALESCE(part.bot_intelligence, 70);
    SELECT * INTO _cfg FROM public._game_cfg('rami');
    _state := public._rami_normalize_state(g.state);
    _discards := public._rami_discards_map(_state);
    _last := public._rami_last_discarder(_state);

    IF g.turn_phase = 'draw' THEN
      _deck := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'deck'))::int[], ARRAY[]::int[]);
      _hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_key))::int[], ARRAY[]::int[]);
      _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_last))::int[], ARRAY[]::int[]);
      _card := NULL; _matched := false;
      IF _intel >= 70 AND array_length(_pile,1) IS NOT NULL AND array_length(_pile,1) > 0 THEN
        _top := _pile[array_length(_pile,1)];
        IF (NOT public._rami_is_joker(_top, g.joker_mode, g.random_joker))
           AND EXISTS (SELECT 1 FROM unnest(_hand) c
                        WHERE NOT public._rami_is_joker(c, g.joker_mode, g.random_joker)
                          AND (c % 56) % 13 = (_top % 56) % 13) THEN
          _matched := true; _card := _top;
          _pile := _pile[1:array_length(_pile,1)-1];
          IF array_length(_pile,1) IS NULL THEN _discards := _discards - _last;
          ELSE _discards := jsonb_set(_discards, ARRAY[_last], to_jsonb(_pile)); END IF;
        END IF;
      END IF;
      IF NOT _matched THEN
        IF array_length(_deck,1) IS NULL THEN
          _reshuffle := public._rami_reshuffle(_state);
          _deck := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_reshuffle->'deck'))::int[], ARRAY[]::int[]);
          _discards := _reshuffle->'discards';
          IF array_length(_deck,1) IS NULL THEN EXIT; END IF;
        END IF;
        _card := _deck[1]; _deck := _deck[2:array_length(_deck,1)];
      END IF;
      _hand := array_append(_hand, _card);
      _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_hand));
      _state := jsonb_set(_state,'{deck}',to_jsonb(_deck));
      _state := jsonb_set(_state,'{discards}',_discards);
      _state := jsonb_set(_state,'{hands}',_hands);
      _state := _state - 'discard';
      UPDATE public.rami_games SET state = _state, turn_phase = 'play',
        turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
        updated_at = now() WHERE id = _game_id;
      UPDATE public.rami_participants SET hand_count = COALESCE(array_length(_hand,1),0)
       WHERE game_id = _game_id AND slot = part.slot;
      CONTINUE;
    END IF;

    -- PLAY PHASE
    _hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_key))::int[], ARRAY[]::int[]);
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
          'player', _key, 'cards', public._rami_jset(_melded), 'type', _type));
        _hands := jsonb_set(_state->'hands', ARRAY[_key], public._rami_jset(_new_hand));
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
        ORDER BY (CASE WHEN public._rami_is_joker(c, g.joker_mode, g.random_joker) THEN -2
          ELSE (c % 56) % 13 END) DESC, random() LIMIT 1;
    END IF;
    _new_hand := public._rami_remove_one(_hand, _card);
    _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_key))::int[], ARRAY[]::int[]);
    _pile := array_append(_pile, _card);
    _discards := jsonb_set(_discards, ARRAY[_key], to_jsonb(_pile), true);
    _hands := jsonb_set(_state->'hands', ARRAY[_key], public._rami_jset(_new_hand));

    -- WIN CHECK: set winner_name for bots
    IF COALESCE(array_length(_new_hand,1),0) = 0 THEN
      _state := jsonb_set(_state,'{hands}',_hands);
      _state := jsonb_set(_state,'{discards}',_discards);
      _state := jsonb_set(_state,'{last_discard_by}',to_jsonb(_key));
      _state := _state - 'discard';
      IF public._rami_check_win(_state, _key) THEN
        UPDATE public.rami_games SET status='finished', winner_id=NULL,
          winner_name=part.display_name, finished_at=now(), state=_state WHERE id=_game_id;
        UPDATE public.rami_participants SET hand_count=0 WHERE game_id=_game_id AND slot=part.slot;
        EXIT;
      END IF;
    END IF;

    -- Advance turn
    SELECT array_agg(slot ORDER BY slot) INTO _parts
      FROM public.rami_participants WHERE game_id = _game_id AND NOT forfeited;
    _next := g.current_turn;
    LOOP _next := (_next + 1) % g.max_players; EXIT WHEN _next = ANY(_parts); END LOOP;
    _state := jsonb_set(_state,'{hands}',_hands);
    _state := jsonb_set(_state,'{discards}',_discards);
    _state := jsonb_set(_state,'{last_discard_by}',to_jsonb(_key));
    _state := _state - 'discard';
    _state := _state - 'bot_think_until';
    _state := public._rami_arm_bot_think(_game_id, _next, _state);
    UPDATE public.rami_games SET state = _state, current_turn = _next, turn_phase = 'draw',
      turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
      updated_at = now() WHERE id = _game_id;
    UPDATE public.rami_participants SET hand_count = COALESCE(array_length(_new_hand,1),0)
     WHERE game_id = _game_id AND slot = part.slot;
  END LOOP;
END $function$;
REVOKE ALL ON FUNCTION public._rami_autoplay_bots(uuid) FROM PUBLIC;

-- 4. Fix rami_bot_play: fix run detection (% 13 -> (% 56) % 13) + winner_name
CREATE OR REPLACE FUNCTION public.rami_bot_play(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  _g public.rami_games; _state jsonb; _uid uuid; _pkey text;
  _is_bot boolean; _slot int; _cfg record;
  _hand int[]; _deck int[]; _discards jsonb; _pile int[]; _card int;
  _new_hand int[]; _hands jsonb; _melds jsonb; _action_log jsonb;
  _parts int[]; _next int;
  _i int; _j int; _k int; _c int; _base int; _suit int; _rank int;
  _rank_cards int[]; _rank_suits int[]; _set_cards int[]; _distinct_suits int;
  _suit_cards int[]; _suit_ranks int[]; _run_cards int[];
  _run_start int; _run_len int;
  _best_card int; _best_pts int; _pts int;
  _melded_cards int[]; _m jsonb;
  _potential_count int;
  _last_by text; v_delay_ms int;
  _won boolean;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RETURN; END IF;
  _state := _g.state;
  SELECT user_id, is_bot, slot INTO _uid, _is_bot, _slot
    FROM public.rami_participants WHERE game_id=_game_id AND slot=_g.current_turn;
  IF NOT _is_bot THEN RETURN; END IF;
  _pkey := 'bot:' || _slot::text;
  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_pkey))::int[], ARRAY[]::int[]);
  IF array_length(_hand,1) IS NULL OR array_length(_hand,1) = 0 THEN
    SELECT array_agg(slot ORDER BY slot) INTO _parts FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited;
    _next := _g.current_turn;
    IF array_length(_parts,1) > 0 THEN
      LOOP _next := (_next + 1) % _g.max_players; EXIT WHEN _next = ANY(_parts); END LOOP;
      _state := _state - 'bot_think_until';
      _state := public._rami_arm_bot_think(_game_id, _next, _state);
      UPDATE public.rami_games SET state=_state, current_turn=_next, turn_phase='draw',
        turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval, updated_at=now() WHERE id=_game_id;
    END IF;
    RETURN;
  END IF;

  -- DRAW PHASE
  IF _g.turn_phase = 'draw' THEN
    _deck := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'deck'))::int[], ARRAY[]::int[]);
    _discards := COALESCE(_state->'discards', jsonb_build_object('_seed', _state->'discard'));
    _last_by := COALESCE(_state->>'last_discard_by', '_seed');
    _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_last_by))::int[], ARRAY[]::int[]);
    _card := NULL;
    IF array_length(_pile,1) IS NOT NULL AND array_length(_pile,1) > 0 THEN
      _card := _pile[array_length(_pile,1)];
      IF (NOT public._rami_is_joker(_card, _g.joker_mode, _g.random_joker)) AND EXISTS (SELECT 1 FROM unnest(_hand) c WHERE NOT public._rami_is_joker(c, _g.joker_mode, _g.random_joker) AND (c % 56) % 13 = (_card % 56) % 13) THEN
        _pile := _pile[1:array_length(_pile,1)-1];
        IF array_length(_pile,1) IS NULL THEN _discards := _discards - _last_by;
        ELSE _discards := jsonb_set(_discards, ARRAY[_last_by], to_jsonb(_pile)); END IF;
      ELSE _card := NULL; END IF;
    END IF;
    IF _card IS NULL THEN
      IF array_length(_deck,1) IS NULL THEN
        IF array_length(_pile,1) > 1 THEN
          _deck := _pile[1:array_length(_pile,1)-1]; _pile := ARRAY[_pile[array_length(_pile,1)]];
          _deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_deck) c);
          _discards := jsonb_set(_discards, ARRAY[_last_by], to_jsonb(_pile));
        END IF;
      END IF;
      IF array_length(_deck,1) IS NULL THEN
        SELECT array_agg(slot ORDER BY slot) INTO _parts FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited;
        _next := _g.current_turn;
        LOOP _next := (_next + 1) % _g.max_players; EXIT WHEN _next = ANY(_parts); END LOOP;
        _state := _state - 'bot_think_until';
        _state := public._rami_arm_bot_think(_game_id, _next, _state);
        UPDATE public.rami_games SET state=_state, current_turn=_next, turn_phase='draw',
          turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval, updated_at=now() WHERE id=_game_id;
        RETURN;
      END IF;
      _card := _deck[1]; _deck := _deck[2:array_length(_deck,1)];
    END IF;
    _hand := array_append(_hand, _card);
    _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
    _state := jsonb_set(_state, '{discards}', COALESCE(_discards,'{}'::jsonb), true);
    _state := _state - 'discard';
    _state := jsonb_set(_state, ARRAY['hands',_pkey], to_jsonb(_hand));
    v_delay_ms := 800 + (floor(random() * 1200))::int;
    _state := jsonb_set(_state, '{bot_think_until}', to_jsonb((now() + make_interval(secs => v_delay_ms / 1000.0))::text), true);
    -- FIX: Use 'play' not 'discard' to match human turn_phase
    UPDATE public.rami_games SET state=_state, turn_phase='play',
      turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval, updated_at=now() WHERE id=_game_id;
    RETURN;
  END IF;

  -- PLAY PHASE: meld + discard
  _melds := COALESCE(_state->'melds', '[]'::jsonb);
  _melded_cards := ARRAY[]::int[];

  -- Find sets: same rank, 3+ different suits
  FOR _rank IN 0..12 LOOP
    _rank_cards := ARRAY[]::int[]; _rank_suits := ARRAY[]::int[];
    FOR _i IN 1..array_length(_hand,1) LOOP
      _c := _hand[_i]; _base := _c % 56;
      IF _base < 52 AND _base % 13 = _rank AND NOT (_c = ANY(_melded_cards)) THEN
        _rank_cards := array_append(_rank_cards, _c);
        _rank_suits := array_append(_rank_suits, _base / 13);
      END IF;
    END LOOP;
    _distinct_suits := array_length(ARRAY(SELECT DISTINCT x FROM unnest(_rank_suits) x), 1);
    IF array_length(_rank_cards,1) >= 3 AND _distinct_suits = array_length(_rank_cards,1) THEN
      _set_cards := _rank_cards[1:LEAST(array_length(_rank_cards,1),4)];
      IF public._rami_meld_type(_set_cards, _g.joker_mode, _g.random_joker) IS NOT NULL THEN
        _melds := _melds || jsonb_build_array(jsonb_build_object('player',_pkey,'cards',to_jsonb(_set_cards),'type','set'));
        _melded_cards := _melded_cards || _set_cards;
      END IF;
    END IF;
  END LOOP;

  -- Find runs: FIX - use (_c % 56) % 13 instead of _c % 13
  FOR _suit IN 0..3 LOOP
    _suit_cards := ARRAY[]::int[];
    FOR _i IN 1..array_length(_hand,1) LOOP
      _c := _hand[_i]; _base := _c % 56;
      IF _base < 52 AND _base / 13 = _suit AND NOT (_c = ANY(_melded_cards)) THEN
        _suit_cards := array_append(_suit_cards, _c);
      END IF;
    END LOOP;
    IF array_length(_suit_cards,1) >= 3 THEN
      _suit_ranks := ARRAY(SELECT DISTINCT ((_sc % 56) % 13) FROM unnest(_suit_cards) AS _sc ORDER BY 1);
      _run_start := 1; _run_len := 1;
      FOR _i IN 2..array_length(_suit_ranks,1) LOOP
        IF _suit_ranks[_i] = _suit_ranks[_i-1] + 1 THEN _run_len := _run_len + 1;
        ELSE
          IF _run_len >= 3 THEN
            _run_cards := ARRAY[]::int[];
            FOR _j IN _run_start.._run_start+_run_len-1 LOOP
              FOR _k IN 1..array_length(_suit_cards,1) LOOP
                IF (_suit_cards[_k] % 56) % 13 = _suit_ranks[_j] AND NOT (_suit_cards[_k] = ANY(_melded_cards)) THEN
                  _run_cards := array_append(_run_cards, _suit_cards[_k]); EXIT;
                END IF;
              END LOOP;
            END LOOP;
            IF array_length(_run_cards,1) >= 3 AND public._rami_meld_type(_run_cards, _g.joker_mode, _g.random_joker) IS NOT NULL THEN
              _melds := _melds || jsonb_build_array(jsonb_build_object('player',_pkey,'cards',to_jsonb(_run_cards),'type','run'));
              _melded_cards := _melded_cards || _run_cards;
            END IF;
          END IF;
          _run_start := _i; _run_len := 1;
        END IF;
      END LOOP;
      IF _run_len >= 3 THEN
        _run_cards := ARRAY[]::int[];
        FOR _j IN _run_start.._run_start+_run_len-1 LOOP
          FOR _k IN 1..array_length(_suit_cards,1) LOOP
            IF (_suit_cards[_k] % 56) % 13 = _suit_ranks[_j] AND NOT (_suit_cards[_k] = ANY(_melded_cards)) THEN
              _run_cards := array_append(_run_cards, _suit_cards[_k]); EXIT;
            END IF;
          END LOOP;
        END LOOP;
        IF array_length(_run_cards,1) >= 3 AND public._rami_meld_type(_run_cards, _g.joker_mode, _g.random_joker) IS NOT NULL THEN
          _melds := _melds || jsonb_build_array(jsonb_build_object('player',_pkey,'cards',to_jsonb(_run_cards),'type','run'));
          _melded_cards := _melded_cards || _run_cards;
        END IF;
      END IF;
    END IF;
  END LOOP;

  _state := jsonb_set(_state, '{melds}', _melds, true);
  _action_log := COALESCE(_state->'action_log', '[]'::jsonb);
  _action_log := _action_log || jsonb_build_array(jsonb_build_object('p',_pkey,'a','discard'));
  IF jsonb_array_length(_action_log) > 20 THEN _action_log := _action_log[jsonb_array_length(_action_log)-19:jsonb_array_length(_action_log)]; END IF;
  _state := jsonb_set(_state, '{action_log}', _action_log, true);

  -- Discard: highest points not in melds
  _best_card := _hand[1]; _best_pts := 999;
  FOR _i IN 1..array_length(_hand,1) LOOP
    _c := _hand[_i];
    IF _c = ANY(_melded_cards) THEN CONTINUE; END IF;
    _base := _c % 56;
    IF _base >= 52 THEN _pts := 15;
    ELSIF _base % 13 = 0 THEN _pts := 11;
    ELSIF _base % 13 >= 10 THEN _pts := 10;
    ELSE _pts := _base % 13 + 1; END IF;
    _potential_count := 0;
    FOR _j IN 1..array_length(_hand,1) LOOP
      IF _j <> _i AND NOT (_hand[_j] = ANY(_melded_cards)) THEN
        _base := _hand[_j] % 56;
        IF _base < 52 AND (_base / 13 = (_c % 56) / 13 OR _base % 13 = (_c % 56) % 13) THEN
          _potential_count := _potential_count + 1;
        END IF;
      END IF;
    END LOOP;
    _pts := _pts - _potential_count;
    IF _pts < _best_pts THEN _best_pts := _pts; _best_card := _c; END IF;
  END LOOP;

  _card := _best_card;
  _new_hand := public._rami_remove_one(_hand, _card);
  _discards := public._rami_discards_map(_state);
  _pile := public._rami_jarr(_discards->_pkey);
  _pile := array_append(_pile, _card);
  _discards := jsonb_set(_discards, ARRAY[_pkey], public._rami_jset(_pile), true);
  _state := jsonb_set(_state, '{discards}', COALESCE(_discards,'{}'::jsonb), true);
  _state := _state - 'discard';
  _state := jsonb_set(_state, '{last_discard_by}', to_jsonb(_pkey), true);
  _state := jsonb_set(_state, ARRAY['hands',_pkey], to_jsonb(_new_hand));
  UPDATE public.rami_participants SET hand_count=array_length(_new_hand,1) WHERE game_id=_game_id AND slot=_slot;

  -- Check win
  IF array_length(_new_hand,1) = 0 THEN
    _won := public._rami_check_win(_state, _pkey);
    IF _won THEN
      -- FIX: Set winner_name
      UPDATE public.rami_games SET status='finished', winner_id=NULL,
        winner_name=(SELECT display_name FROM public.rami_participants WHERE game_id=_game_id AND slot=_slot),
        finished_at=now(), state=_state WHERE id=_game_id;
      RETURN;
    END IF;
  END IF;

  -- Advance to next player
  _next := _g.current_turn;
  SELECT array_agg(slot ORDER BY slot) INTO _parts FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited;
  IF array_length(_parts,1) > 0 THEN
    LOOP _next := (_next + 1) % _g.max_players; EXIT WHEN _next = ANY(_parts); END LOOP;
    _state := _state - 'bot_think_until';
    _state := public._rami_arm_bot_think(_game_id, _next, _state);
    UPDATE public.rami_games SET state=_state, current_turn=_next, turn_phase='draw',
      turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval, updated_at=now() WHERE id=_game_id;
  ELSE
    UPDATE public.rami_games SET status='finished', finished_at=now(), state=_state WHERE id=_game_id;
  END IF;
END $function$;
REVOKE ALL ON FUNCTION public.rami_bot_play(uuid) FROM PUBLIC;

-- 5. Clean up: set winner_name for finished games with winner_id
UPDATE public.rami_games g SET winner_name = p.display_name
  FROM public.rami_participants p
  WHERE g.winner_id = p.user_id AND g.winner_name IS NULL AND g.status = 'finished';
