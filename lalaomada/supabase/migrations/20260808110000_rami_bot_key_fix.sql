-- Fix: rami_bot_play uses bot:<slot> key instead of NULL user_id
-- Bots have user_id=NULL, so the function was returning immediately

-- Add _pkey variable to the DECLARE section and fix the function
CREATE OR REPLACE FUNCTION public.rami_bot_play(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _g public.rami_games;
  _state jsonb;
  _uid uuid;
  _pkey text;  -- player key: bot:<slot> or uid::text
  _is_bot boolean;
  _slot int;
  _cfg record;
  _hand int[];
  _deck int[];
  _discards jsonb;
  _pile int[];
  _card int;
  _new_hand int[];
  _hands jsonb;
  _melds jsonb;
  _action_log jsonb;
  _parts int[];
  _next int;
  _payout numeric;
  _comm numeric;
  _won boolean;

  -- Meld detection variables
  _i int;
  _j int;
  _k int;
  _c int;
  _base int;
  _suit int;
  _rank int;
  _real_cards int[];
  _joker_count int;
  _jokers int[];
  -- Sets
  _rank_cards int[];
  _rank_suits int[];
  _set_cards int[];
  _distinct_suits int;
  -- Runs
  _suit_cards int[];
  _suit_ranks int[];
  _run_cards int[];
  _run_start int;
  _run_len int;
  _gap int;
  _need_jokers int;
  -- Discard
  _best_card int;
  _best_pts int;
  _pts int;
  _card_rank int;
  _card_suit int;
  _used_in_meld boolean;
  _melded_cards int[];
  _m jsonb;
  _meld_cards int[];
  _potential_count int;
  _card_potential int;
  _keep boolean;
  _last_by text;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RETURN; END IF;

  _state := _g.state;
  _uid := NULL;
  _is_bot := false;
  _slot := NULL;

  SELECT user_id, is_bot, slot INTO _uid, _is_bot, _slot
    FROM public.rami_participants
    WHERE game_id=_game_id AND slot=_g.current_turn;

  IF NOT _is_bot THEN RETURN; END IF;

  -- Use bot:<slot> as the hand key for bots (user_id is NULL)
  _pkey := 'bot:' || _slot::text;

  SELECT * INTO _cfg FROM public._game_cfg('rami');

  _hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_pkey))::int[], ARRAY[]::int[]);
  IF array_length(_hand,1) IS NULL OR array_length(_hand,1) = 0 THEN
    -- Empty hand, just advance
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

  -- ═══ DRAW PHASE: draw a card and return ═══════════════════════════
  IF _g.turn_phase = 'draw' THEN
    _deck := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'deck'))::int[], ARRAY[]::int[]);
    _discards := COALESCE(_state->'discards', jsonb_build_object('_seed', _state->'discard'));

    -- Check if top of discard pile would help (simple heuristic: same rank or suit as existing cards)
    _last_by := COALESCE(_state->>'last_discard_by', '_seed');
    _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_last_by))::int[], ARRAY[]::int[]);

    IF array_length(_pile,1) IS NOT NULL AND array_length(_pile,1) > 0 THEN
      _card := _pile[array_length(_pile,1)];
      _base := _card % 56;
      IF _base < 52 THEN
        _rank := _base % 13;
        _suit := _base / 13;
        -- Check if any card in hand has same rank or same suit+adjacent rank
        _keep := false;
        FOREACH _c IN ARRAY _hand LOOP
          IF (_c % 56) < 52 THEN
            IF ((_c % 56) % 13) = _rank THEN _keep := true; END IF;
            IF ((_c % 56) / 13) = _suit AND abs(((_c % 56) % 13) - _rank) <= 2 THEN _keep := true; END IF;
          END IF;
        END LOOP;
        -- 50% chance to pick up a useful card (humans don't always pick up)
        IF _keep AND (random() < 0.5) THEN
          -- Draw from discard pile
          _pile := _pile[1:array_length(_pile,1)-1];
          _discards := jsonb_set(_discards, ARRAY[_last_by], to_jsonb(_pile));
        ELSE
          _card := NULL;
        END IF;
      ELSE
        _card := NULL; -- Don't pick up jokers from discard (keep them for others)
      END IF;
    ELSE
      _card := NULL;
    END IF;

    IF _card IS NULL THEN
      -- Draw from deck
      IF COALESCE(array_length(_deck,1),0) = 0 THEN
        -- Reshuffle discards (same logic as rami_tick)
        DECLARE _kk text; _all int[] := ARRAY[]::int[]; _tops int[] := ARRAY[]::int[];
        BEGIN
          FOR _kk IN SELECT * FROM jsonb_object_keys(_discards) LOOP
            _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_kk))::int[], ARRAY[]::int[]);
            IF array_length(_pile,1) > 1 THEN
              _all := _all || _pile[1:array_length(_pile,1)-1];
              _tops := _tops || _pile[array_length(_pile,1)];
            ELSIF array_length(_pile,1) = 1 THEN
              _tops := _tops || _pile[1];
            END IF;
          END LOOP;
          IF array_length(_all,1) IS NULL THEN
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
      _card := _deck[1];
      _deck := _deck[2:array_length(_deck,1)];
      _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
    END IF;

    _hand := array_append(_hand, _card);
    _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
    _state := jsonb_set(_state, '{discards}', _discards);
    _state := jsonb_set(_state, ARRAY['hands',_pkey], to_jsonb(_hand));

    _action_log := COALESCE(_state->'action_log','[]'::jsonb) ||
      jsonb_build_object('t','bot_draw','p',_pkey,'from',CASE WHEN _card IS NOT NULL AND _card = ANY(_pile) THEN 'discard' ELSE 'deck' END,'ts',extract(epoch from now())::bigint);
    _state := jsonb_set(_state, '{action_log}', _action_log);

    -- Switch to play phase
    UPDATE public.rami_games
      SET state=_state, turn_phase='play',
          turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval,
          updated_at=now()
      WHERE id=_game_id;
    UPDATE public.rami_participants SET hand_count=array_length(_hand,1)
      WHERE game_id=_game_id AND slot=_slot;
    RETURN;
  END IF;

  -- ═══ PLAY PHASE: find melds, play them, then discard ════════════════
  _melds := COALESCE(_state->'melds','[]'::jsonb);
  _melded_cards := ARRAY[]::int[];

  -- Get already-melded cards by this bot
  FOR _m IN SELECT * FROM jsonb_array_elements(_melds) LOOP
    IF _m->>'player' = _pkey THEN
      _meld_cards := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_m->'cards'))::int[], ARRAY[]::int[]);
      _melded_cards := _melded_cards || _meld_cards;
    END IF;
  END LOOP;

  -- Separate jokers from real cards in hand
  _real_cards := ARRAY[]::int[];
  _jokers := ARRAY[]::int[];
  _joker_count := 0;
  FOREACH _c IN ARRAY _hand LOOP
    IF public._rami_is_joker(_c, _g.joker_mode, _g.random_joker) THEN
      _jokers := _jokers || _c;
      _joker_count := _joker_count + 1;
    ELSE
      _real_cards := _real_cards || _c;
    END IF;
  END LOOP;

  -- ── Find SETS: same rank, 3+ different suits ────────────────────────
  FOR _rank IN 0..12 LOOP
    _set_cards := ARRAY[]::int[];
    _rank_suits := ARRAY[]::int[];
    FOREACH _c IN ARRAY _real_cards LOOP
      IF (_c % 56) % 13 = _rank AND NOT (_c = ANY(_melded_cards)) AND NOT (_c = ANY(_set_cards)) THEN
        _suit := (_c % 56) / 13;
        IF NOT (_suit = ANY(_rank_suits)) THEN
          _rank_suits := _rank_suits || _suit;
          _set_cards := _set_cards || _c;
        END IF;
      END IF;
    END LOOP;
    -- Need at least 3 distinct suits, or 2 + 1 joker
    _distinct_suits := array_length(_rank_suits,1);
    IF _distinct_suits >= 3 THEN
      -- Play the set (use first 3 or 4)
      IF array_length(_set_cards,1) >= 4 THEN
        _set_cards := _set_cards[1:4];
      ELSE
        _set_cards := _set_cards[1:3];
      END IF;
      -- Validate
      IF public._rami_meld_type(_set_cards, _g.joker_mode, _g.random_joker) IS NOT NULL THEN
        _melds := _melds || jsonb_build_array(
          jsonb_build_object('player',_pkey,'cards',to_jsonb(_set_cards),'type','set'));
        _melded_cards := _melded_cards || _set_cards;
        -- Remove from real_cards to avoid reuse
        FOREACH _c IN ARRAY _set_cards LOOP
          _real_cards := public._rami_remove_one(_real_cards, _c);
        END LOOP;
      END IF;
    ELSIF _distinct_suits = 2 AND _joker_count > 0 THEN
      -- Use 1 joker to complete the set
      _set_cards := _set_cards[1:2] || ARRAY[_jokers[1]];
      IF public._rami_meld_type(_set_cards, _g.joker_mode, _g.random_joker) IS NOT NULL THEN
        _melds := _melds || jsonb_build_array(
          jsonb_build_object('player',_pkey,'cards',to_jsonb(_set_cards),'type','set'));
        _melded_cards := _melded_cards || _set_cards;
        FOREACH _c IN ARRAY _set_cards LOOP
          _real_cards := public._rami_remove_one(_real_cards, _c);
        END LOOP;
        _jokers := _jokers[2:array_length(_jokers,1)];
        _joker_count := _joker_count - 1;
      END IF;
    END IF;
  END LOOP;

  -- ── Find RUNS: same suit, 3+ consecutive ranks (with jokers) ─────────
  FOR _suit IN 0..3 LOOP
    -- Collect cards of this suit, sorted by rank
    _suit_cards := ARRAY[]::int[];
    _suit_ranks := ARRAY[]::int[];
    FOREACH _c IN ARRAY _real_cards LOOP
      IF (_c % 56) / 13 = _suit AND NOT (_c = ANY(_melded_cards)) THEN
        -- Insert sorted by rank
        _rank := (_c % 56) % 13;
        _i := 1;
        WHILE _i <= array_length(_suit_cards,1) AND (_suit_cards[_i] % 56) % 13 < _rank LOOP
          _i := _i + 1;
        END LOOP;
        _suit_cards := array_append(_suit_cards[1:_i-1], _c) || _suit_cards[_i:array_length(_suit_cards,1)];
      END IF;
    END LOOP;

    -- Find consecutive sequences
    _i := 1;
    WHILE _i <= array_length(_suit_cards,1) - 2 LOOP
      _run_start := (_suit_cards[_i] % 56) % 13;
      _run_len := 1;
      _run_cards := ARRAY[_suit_cards[_i]];
      _j := _i + 1;
      WHILE _j <= array_length(_suit_cards,1) LOOP
        IF (_suit_cards[_j] % 56) % 13 = _run_start + _run_len THEN
          _run_cards := _run_cards || _suit_cards[_j];
          _run_len := _run_len + 1;
          _j := _j + 1;
        ELSIF (_suit_cards[_j] % 56) % 13 = _run_start + _run_len - 1 THEN
          -- Duplicate rank (same suit from 2 decks), skip
          _j := _j + 1;
        ELSE
          EXIT;
        END IF;
      END LOOP;

      -- Try to extend with jokers if we have a gap or short run
      IF _run_len >= 2 AND _joker_count > 0 THEN
        -- Try to add joker at the end
        IF _run_len + 1 <= 7 THEN
          DECLARE _try int[];
          BEGIN
            _try := _run_cards || ARRAY[_jokers[1]];
            IF public._rami_meld_type(_try, _g.joker_mode, _g.random_joker) IS NOT NULL THEN
              _run_cards := _try;
              _run_len := _run_len + 1;
            END IF;
          END;
        END IF;
      END IF;

      IF _run_len >= 3 THEN
        -- Validate and play the run
        IF public._rami_meld_type(_run_cards, _g.joker_mode, _g.random_joker) IS NOT NULL THEN
          _melds := _melds || jsonb_build_array(
            jsonb_build_object('player',_pkey,'cards',to_jsonb(_run_cards),'type','run'));
          _melded_cards := _melded_cards || _run_cards;
          FOREACH _c IN ARRAY _run_cards LOOP
            _real_cards := public._rami_remove_one(_real_cards, _c);
            IF public._rami_is_joker(_c, _g.joker_mode, _g.random_joker) THEN
              _jokers := public._rami_remove_one(_jokers, _c);
              _joker_count := _joker_count - 1;
            END IF;
          END LOOP;
        END IF;
        _i := _j;
      ELSE
        _i := _i + 1;
      END IF;
    END LOOP;
  END LOOP;

  -- Update melds in state
  IF array_length(_melded_cards,1) > 0 THEN
    _state := jsonb_set(_state, '{melds}', _melds);
    _action_log := COALESCE(_state->'action_log','[]'::jsonb) ||
      jsonb_build_object('t','bot_meld','p',_pkey,'n',array_length(_melded_cards,1),'ts',extract(epoch from now())::bigint);
    _state := jsonb_set(_state, '{action_log}', _action_log);
    -- Remove melded cards from hand
    _new_hand := _hand;
    FOREACH _c IN ARRAY _melded_cards LOOP
      _new_hand := public._rami_remove_one(_new_hand, _c);
    END LOOP;
    _hand := _new_hand;
    _state := jsonb_set(_state, ARRAY['hands',_pkey], to_jsonb(_hand));
    UPDATE public.rami_participants SET hand_count=array_length(_hand,1)
      WHERE game_id=_game_id AND slot=_slot;
  END IF;

  -- ── Smart discard: keep useful cards, discard deadwood ──────────────
  IF array_length(_hand,1) IS NULL OR array_length(_hand,1) = 0 THEN
    -- Check win
    _won := public._rami_check_win(_state, _pkey);
    IF _won THEN
      -- Bot wins: mark game finished but no payout (bots don't have profiles)
      UPDATE public.rami_games SET status='finished', winner_id=NULL, finished_at=now(), state=_state WHERE id=_game_id;
      RETURN;
    END IF;
    -- Hand empty but not valid win — shouldn't happen, but advance
    SELECT array_agg(slot ORDER BY slot) INTO _parts FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited;
    _next := _g.current_turn;
    LOOP _next := (_next + 1) % _g.max_players; EXIT WHEN _next = ANY(_parts); END LOOP;
    UPDATE public.rami_games SET state=_state, current_turn=_next, turn_phase='draw',
      turn_deadline=now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval, updated_at=now()
      WHERE id=_game_id;
    RETURN;
  END IF;

  -- Evaluate each card: keep jokers and cards in potential melds, discard deadwood
  _best_card := NULL;
  _best_pts := -1;
  FOREACH _c IN ARRAY _hand LOOP
    IF public._rami_is_joker(_c, _g.joker_mode, _g.random_joker) THEN
      CONTINUE; -- Never discard jokers
    END IF;

    _base := _c % 56;
    _rank := _base % 13;
    _suit := _base / 13;
    _pts := CASE WHEN _rank = 0 THEN 11 WHEN _rank >= 10 THEN 10 ELSE _rank + 1 END;

    -- Check if this card is in a potential meld (2 of 3 for a set or run)
    _card_potential := 0;
    -- Same rank count (potential set)
    _potential_count := 0;
    FOREACH _k IN ARRAY _hand LOOP
      IF _k <> _c AND NOT public._rami_is_joker(_k, _g.joker_mode, _g.random_joker) THEN
        IF (_k % 56) % 13 = _rank THEN _potential_count := _potential_count + 1; END IF;
      END IF;
    END LOOP;
    IF _potential_count >= 1 THEN _card_potential := _card_potential + 1; END IF;

    -- Adjacent rank same suit (potential run)
    _potential_count := 0;
    FOREACH _k IN ARRAY _hand LOOP
      IF _k <> _c AND NOT public._rami_is_joker(_k, _g.joker_mode, _g.random_joker) THEN
        IF (_k % 56) / 13 = _suit AND abs(((_k % 56) % 13) - _rank) <= 2 THEN
          _potential_count := _potential_count + 1;
        END IF;
      END IF;
    END LOOP;
    IF _potential_count >= 1 THEN _card_potential := _card_potential + 1; END IF;

    -- If card has no potential, it's deadwood → candidate for discard
    IF _card_potential = 0 AND _pts > _best_pts THEN
      _best_pts := _pts;
      _best_card := _c;
    END IF;
  END LOOP;

  -- If all cards have potential, discard highest non-joker
  IF _best_card IS NULL THEN
    FOREACH _c IN ARRAY _hand LOOP
      IF NOT public._rami_is_joker(_c, _g.joker_mode, _g.random_joker) THEN
        _rank := (_c % 56) % 13;
        _pts := CASE WHEN _rank = 0 THEN 11 WHEN _rank >= 10 THEN 10 ELSE _rank + 1 END;
        IF _pts > _best_pts THEN _best_pts := _pts; _best_card := _c; END IF;
      END IF;
    END LOOP;
  END IF;

  -- If still NULL (all jokers), discard first card
  IF _best_card IS NULL THEN
    _best_card := _hand[1];
  END IF;

  -- Execute discard
  _new_hand := public._rami_remove_one(_hand, _best_card);
  _discards := COALESCE(_state->'discards', jsonb_build_object('_seed', _state->'discard'));
  _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_pkey))::int[], ARRAY[]::int[]);
  _pile := array_append(_pile, _best_card);
  _discards := jsonb_set(_discards, ARRAY[_pkey], to_jsonb(_pile), true);

  _action_log := COALESCE(_state->'action_log','[]'::jsonb) ||
    jsonb_build_object('t','bot_discard','p',_pkey,'card',_best_card,'ts',extract(epoch from now())::bigint);
  _state := jsonb_set(_state, '{discards}', _discards);
  _state := jsonb_set(_state, '{last_discard_by}', to_jsonb(_pkey));
  _state := jsonb_set(_state, ARRAY['hands',_pkey], to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{action_log}', _action_log);

  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand,1),0)
    WHERE game_id=_game_id AND slot=_slot;

  -- Check win
  IF COALESCE(array_length(_new_hand,1),0) = 0 THEN
    _won := public._rami_check_win(_state, _pkey);
    IF _won THEN
      -- Bot wins: mark game finished but no payout
      UPDATE public.rami_games SET status='finished', winner_id=NULL, finished_at=now(), state=_state WHERE id=_game_id;
      RETURN;
    END IF;
  END IF;

  -- Next player
  SELECT array_agg(slot ORDER BY slot) INTO _parts FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited;
  _next := _g.current_turn;
  IF array_length(_parts,1) > 0 THEN
    LOOP _next := (_next + 1) % _g.max_players; EXIT WHEN _next = ANY(_parts); END LOOP;
  ELSE
    UPDATE public.rami_games SET status='finished', finished_at=now(), state=_state WHERE id=_game_id;
    RETURN;
  END IF;

  UPDATE public.rami_games
    SET state=_state, current_turn=_next, turn_phase='draw',
        turn_deadline=now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval,
        updated_at=now()
    WHERE id=_game_id;
END $function$;

-- Also fix rami_tick to handle bot turns: if it's a bot's turn and timeout expired,
-- call rami_bot_play instead of trying to auto-play with NULL user_id
CREATE OR REPLACE FUNCTION public.rami_tick(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _g rami_games; _state jsonb; _uid uuid; _is_bot boolean; _slot int; _hand int[]; _new_hand int[];
  _deck int[]; _discard int[]; _card int; _next int; _cfg record; _skips int;
  _pkey text;
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' OR _g.turn_deadline IS NULL OR _g.turn_deadline > now() THEN RETURN; END IF;

  -- Check if current player is a bot
  SELECT user_id, is_bot, slot INTO _uid, _is_bot, _slot
    FROM rami_participants WHERE game_id=_game_id AND slot=_g.current_turn;

  -- If it's a bot's turn and timeout expired, let the bot play
  IF _is_bot THEN
    PERFORM public.rami_bot_play(_game_id);
    RETURN;
  END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _skips := COALESCE((_g.turn_skips->>_uid::text)::int, 0) + 1;

  IF _skips >= _cfg.max_turn_skips THEN
    UPDATE rami_participants SET forfeited = true WHERE game_id=_game_id AND user_id=_uid;
    -- advance to next non-forfeited, finalize if only one left
    IF (SELECT count(*) FROM rami_participants WHERE game_id=_game_id AND NOT forfeited) <= 1 THEN
      DECLARE _win uuid;
      BEGIN
        SELECT user_id INTO _win FROM rami_participants WHERE game_id=_game_id AND NOT forfeited LIMIT 1;
        UPDATE rami_games SET status='finished', winner_id=_win, finished_at=now() WHERE id=_game_id;
        IF _win IS NOT NULL THEN
          UPDATE profiles SET balance_ar = balance_ar + (_g.pot * (100 - _g.commission_pct) / 100) WHERE id=_win;
          INSERT INTO transactions(user_id,type,amount,ref_id,note)
            VALUES (_win,'rami_win', _g.pot * (100 - _g.commission_pct) / 100, _game_id, 'Rami win (forfait)');
        END IF;
        RETURN;
      END;
    END IF;
  END IF;

  _state := _g.state;
  _pkey := _uid::text;
  _deck := ARRAY(SELECT jsonb_array_elements_text(_state->'deck'))::int[];
  _discard := ARRAY(SELECT jsonb_array_elements_text(_state->'discard'))::int[];
  _hand := ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_pkey))::int[];

  IF _g.turn_phase = 'draw' THEN
    IF array_length(_deck,1) IS NULL THEN
      _deck := _discard[1:array_length(_discard,1)-1];
      _discard := ARRAY[_discard[array_length(_discard,1)]];
      _deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_deck) c);
    END IF;
    _card := _deck[1]; _deck := _deck[2:array_length(_deck,1)];
    _hand := array_append(_hand, _card);
  END IF;

  _card := _hand[1 + floor(random()*array_length(_hand,1))::int];
  _new_hand := _rami_remove_one(_hand, _card);
  _discard := array_append(_discard, _card);
  _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard));
  _state := jsonb_set(_state, ARRAY['hands',_pkey], to_jsonb(_new_hand));
  UPDATE rami_participants SET hand_count=array_length(_new_hand,1) WHERE game_id=_game_id AND user_id=_uid;

  _next := _g.current_turn;
  LOOP
    _next := (_next + 1) % _g.max_players;
    EXIT WHEN _next IN (SELECT slot FROM rami_participants WHERE game_id=_game_id AND NOT forfeited);
  END LOOP;

  UPDATE rami_games SET state=_state, current_turn=_next, turn_phase='draw',
    turn_skips = jsonb_set(_g.turn_skips, ARRAY[_uid::text], to_jsonb(_skips)),
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
    updated_at=now()
    WHERE id=_game_id;
END $function$;
