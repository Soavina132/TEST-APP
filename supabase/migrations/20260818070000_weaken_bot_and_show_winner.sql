CREATE OR REPLACE FUNCTION public._rami_autoplay_bots(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  g public.rami_games; part public.rami_participants; guard int := 0;
  _key text; _hand int[]; _card int; _deck int[]; _new_hand int[]; _hands jsonb;
  _melds jsonb; _melded int[]; _type text; _intel int; _parts int[];
  _next int; _top int; _matched boolean;
  _cfg record;
  _state jsonb; _last text;
  _discard_arr int[];
  _discard_by text[];
  _all int[];
  _winner_name text; _payout numeric; _comm numeric;
  _seven boolean;
  _action_log jsonb;
  _rnd int;
  _skip_meld boolean;
BEGIN
  LOOP
    guard := guard + 1;
    IF guard > 100 THEN EXIT; END IF;

    SELECT * INTO g FROM public.rami_games WHERE id = _game_id FOR UPDATE;
    IF NOT FOUND OR g.status <> 'playing' THEN EXIT; END IF;
    IF COALESCE(g.paused, false) THEN EXIT; END IF;

    SELECT * INTO part FROM public.rami_participants
     WHERE game_id = _game_id AND slot = g.current_turn AND forfeited = false;
    IF NOT FOUND OR NOT COALESCE(part.is_bot, false) THEN EXIT; END IF;

    _key   := COALESCE(part.user_id::text, 'bot:' || part.slot::text);
    _intel := COALESCE(part.bot_intelligence, 70);
    _seven := COALESCE(g.seven_cards, false);
    SELECT * INTO _cfg FROM public._game_cfg('rami');
    _state := public._rami_normalize_state(g.state);
    _discard_arr := COALESCE(public._rami_jarr(_state->'discard'), ARRAY[]::int[]);
    _discard_arr := ARRAY(SELECT x FROM unnest(_discard_arr) x WHERE x IS NOT NULL);
    IF _state ? 'discard_by' AND _state->'discard_by' IS NOT NULL THEN
      _discard_by := ARRAY(SELECT elem::text FROM jsonb_array_elements_text(_state->'discard_by') elem WHERE elem IS NOT NULL);
    ELSE
      _discard_by := ARRAY[]::text[];
    END IF;

    IF g.turn_phase = 'draw' THEN
      _deck := COALESCE(public._rami_jarr(_state->'deck'), ARRAY[]::int[]);
      _hand := COALESCE(public._rami_jarr(_state->'hands'->_key), ARRAY[]::int[]);
      _card := NULL;
      _matched := false;

      -- ═══ Bot pioche sur défausse si la carte match (only 50% of the time to weaken) ═══
      _rnd := public._crypto_rand_int(100);
      IF _intel >= 70 AND _rnd < 50 AND array_length(_discard_arr, 1) IS NOT NULL AND array_length(_discard_arr, 1) > 0 THEN
        _top := _discard_arr[array_length(_discard_arr, 1)];
        IF (_top % 56) < 52 AND EXISTS (
          SELECT 1 FROM unnest(_hand) c
          WHERE (c % 56) < 52 AND c%13 = _top%13
        ) THEN
          _matched := true;
          _card := _top;
          _discard_arr := _discard_arr[1:array_length(_discard_arr, 1)-1];
          IF array_length(_discard_by, 1) > 0 THEN
            _discard_by := _discard_by[1:array_length(_discard_by, 1)-1];
          END IF;
        END IF;
      END IF;

      IF NOT _matched THEN
        -- Piocher depuis le deck
        IF COALESCE(array_length(_deck, 1), 0) = 0 THEN
          IF array_length(_discard_arr, 1) IS NOT NULL AND array_length(_discard_arr, 1) > 1 THEN
            _all := _discard_arr[1:array_length(_discard_arr, 1)-1];
            _discard_arr := ARRAY[_discard_arr[array_length(_discard_arr, 1)]];
            _discard_by := ARRAY[_discard_by[array_length(_discard_by, 1)]];
            _deck := (SELECT array_agg(c ORDER BY gen_random_uuid()) FROM unnest(_all) c);
          ELSE
            EXIT;
          END IF;
        END IF;
        IF COALESCE(array_length(_deck, 1), 0) = 0 THEN EXIT; END IF;
        _card := _deck[1];
        _deck := _deck[2:array_length(_deck, 1)];
      END IF;

      _hand := array_append(_hand, _card);
      _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_hand));
      _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
      _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
      _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);
      _state := jsonb_set(_state, '{hands}', _hands);
      _state := public._rami_normalize_state(_state);

      UPDATE public.rami_games SET state = _state, turn_phase = 'play', updated_at = now() WHERE id = _game_id;
      UPDATE public.rami_participants SET hand_count = COALESCE(array_length(_hand, 1), 0)
       WHERE game_id = _game_id AND slot = part.slot;
      CONTINUE;
    END IF;

    -- ═══ Phase 'play' ═══
    _hand := COALESCE(public._rami_jarr(_state->'hands'->_key), ARRAY[]::int[]);
    _melds := COALESCE(_state->'melds', '[]'::jsonb);
    _melded := NULL;

    -- ═══ WEAKENED BOT: Only meld 55% of the time even when a combo exists ═══
    _skip_meld := (public._crypto_rand_int(100) >= 55);

    IF _intel >= 50 AND NOT _skip_meld AND COALESCE(array_length(_hand, 1), 0) >= 4 THEN
      -- Try 4-card meld first (only 40% of the time to weaken)
      _rnd := public._crypto_rand_int(100);
      IF _rnd < 40 THEN
        SELECT ARRAY[_hand[ai], _hand[aj], _hand[ak], _hand[al]] INTO _melded
          FROM generate_subscripts(_hand, 1) ai, generate_subscripts(_hand, 1) aj,
               generate_subscripts(_hand, 1) ak, generate_subscripts(_hand, 1) al
         WHERE ai < aj AND aj < ak AND ak < al
           AND public._rami_meld_type(ARRAY[_hand[ai], _hand[aj], _hand[ak], _hand[al]], g.joker_mode, g.random_joker) IS NOT NULL
         LIMIT 1;
      END IF;

      IF _melded IS NULL THEN
        SELECT ARRAY[_hand[bi], _hand[bj], _hand[bk]] INTO _melded
          FROM generate_subscripts(_hand, 1) bi, generate_subscripts(_hand, 1) bj, generate_subscripts(_hand, 1) bk
         WHERE bi < bj AND bj < bk
           AND public._rami_meld_type(ARRAY[_hand[bi], _hand[bj], _hand[bk]], g.joker_mode, g.random_joker) IS NOT NULL
         LIMIT 1;
      END IF;

      IF _melded IS NOT NULL THEN
        _type := public._rami_meld_type(_melded, g.joker_mode, g.random_joker);
        _new_hand := _hand;
        FOREACH _card IN ARRAY _melded LOOP
          _new_hand := public._rami_remove_one(_new_hand, _card);
        END LOOP;
        _melds := _melds || jsonb_build_array(jsonb_build_object(
          'player', _key, 'cards', to_jsonb(_melded), 'type', _type
        ));
        _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_new_hand));
        _state := jsonb_set(_state, '{hands}', _hands);
        _state := jsonb_set(_state, '{melds}', _melds);
        UPDATE public.rami_games SET state = _state, updated_at = now() WHERE id = _game_id;
        UPDATE public.rami_participants SET hand_count = COALESCE(array_length(_new_hand, 1), 0)
          WHERE game_id = _game_id AND slot = part.slot;
        CONTINUE;
      END IF;
    END IF;

    IF COALESCE(array_length(_hand, 1), 0) = 0 THEN EXIT; END IF;

    -- Choisir une carte à défausser
    IF _intel < 50 THEN
      _card := _hand[1 + public._crypto_rand_int(array_length(_hand, 1))];
    ELSE
      -- Weakened: 35% chance to discard randomly instead of highest
      _rnd := public._crypto_rand_int(100);
      IF _rnd < 35 THEN
        _card := _hand[1 + public._crypto_rand_int(array_length(_hand, 1))];
      ELSE
        SELECT c INTO _card FROM unnest(_hand) c
          ORDER BY (CASE WHEN (c % 56) < 52 THEN c%13 ELSE -1 END) DESC, gen_random_uuid()::text
          LIMIT 1;
      END IF;
    END IF;

    _new_hand := public._rami_remove_one(_hand, _card);

    -- ═══ Gérer le cas où _new_hand est vide (dernière carte) ═══
    IF COALESCE(array_length(_new_hand, 1), 0) = 0 THEN
      -- Ajouter à la défausse
      _discard_arr := array_append(_discard_arr, _card);
      _discard_by := array_append(_discard_by, _key);
      _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_new_hand));
      _state := jsonb_set(_state, '{hands}', _hands);
      _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
      _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);
      _state := public._rami_normalize_state(_state);

      IF public._rami_check_win(_state, _key, _seven) THEN
        SELECT COALESCE(pseudo, 'Bot') INTO _winner_name FROM public.profiles WHERE id = part.user_id;
        IF part.user_id IS NOT NULL THEN
          _comm := round(g.pot * (g.commission_pct / 2.0) / 100.0, 0);
          _payout := g.pot - _comm;
          UPDATE public.profiles SET balance_ar = balance_ar + _payout WHERE id = part.user_id;
          INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
            VALUES (part.user_id, 'rami_win', _payout, _game_id, 'Win rami (bot)');
        END IF;
        UPDATE public.rami_games
           SET status='finished', winner_id=part.user_id, winner_name=COALESCE(_winner_name, part.display_name), finished_at=now(), state=_state
         WHERE id = _game_id;
        UPDATE public.rami_participants SET hand_count = 0
         WHERE game_id = _game_id AND slot = part.slot;
        EXIT;
      ELSE
        -- Remettre la carte dans la main
        _new_hand := ARRAY[_card];
        _discard_arr := _discard_arr[1:array_length(_discard_arr, 1)-1];
        _discard_by := _discard_by[1:array_length(_discard_by, 1)-1];
        _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_new_hand));
        _state := jsonb_set(_state, '{hands}', _hands);
        _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
        _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);
        _state := public._rami_normalize_state(_state);
        UPDATE public.rami_games SET state = _state, updated_at = now() WHERE id = _game_id;
        UPDATE public.rami_participants SET hand_count = 1
         WHERE game_id = _game_id AND slot = part.slot;
        CONTINUE;
      END IF;
    END IF;

    -- Défausser normalement
    _discard_arr := array_append(_discard_arr, _card);
    _discard_by := array_append(_discard_by, _key);
    _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_new_hand));
    _state := jsonb_set(_state, '{hands}', _hands);
    _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
    _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);

    -- Action log
    _action_log := COALESCE(_state->'action_log', '[]'::jsonb) ||
      jsonb_build_object('t', 'discard', 'p', _key, 'card', _card, 'ts', extract(epoch from now())::bigint);
    _state := jsonb_set(_state, '{action_log}', _action_log);

    -- Passer au suivant
    SELECT array_agg(slot ORDER BY slot) INTO _parts
      FROM public.rami_participants WHERE game_id = _game_id AND NOT forfeited;
    _next := g.current_turn;
    LOOP
      _next := (_next + 1) % g.max_players;
      EXIT WHEN _next = ANY(_parts);
    END LOOP;

    _state := public._rami_normalize_state(_state);
    UPDATE public.rami_games SET state = _state, current_turn = _next, turn_phase = 'draw', updated_at = now()
     WHERE id = _game_id;
    UPDATE public.rami_participants SET hand_count = COALESCE(array_length(_new_hand, 1), 0)
     WHERE game_id = _game_id AND slot = part.slot;
  END LOOP;
END $function$;

GRANT EXECUTE ON FUNCTION public._rami_autoplay_bots(uuid) TO authenticated;
