-- ═══ Fix: pioche sur défausse fiable + bot 2 paquets + cleanup null cards ═══

-- 1. rami_draw: sécurité contre les cartes NULL dans la défausse + filtrage NULL au reshuffle
-- 2. _rami_autoplay_bots: le bot peut matcher les cartes des 2 paquets (0-111) + fix bug re-défausse
-- 3. Cleanup: nettoyer les cartes NULL dans les défausses des parties existantes

CREATE OR REPLACE FUNCTION public.rami_draw(_game_id uuid, _from text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  _uid uuid := auth.uid();
  _g public.rami_games;
  _slot int;
  _state jsonb;
  _deck int[];
  _discards jsonb;
  _hand int[];
  _card int;
  _hands jsonb;
  _pile int[];
  _cfg record;
  _action_log jsonb;
  _last_by text;
  _k text;
  _v jsonb;
  _all int[];
  _new_discards jsonb;
  _flat int[];
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn THEN RAISE EXCEPTION 'pas ton tour'; END IF;
  IF _g.turn_phase <> 'draw' THEN RAISE EXCEPTION 'deja pioché ou phase de jeu'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _state := public._rami_normalize_state(_g.state);
  _deck := COALESCE(public._rami_jarr(_state->'deck'), ARRAY[]::int[]);
  _discards := public._rami_discards_map(_state);
  _hand := COALESCE(public._rami_jarr(_state->'hands'->_uid::text), ARRAY[]::int[]);

  IF _from = 'discard' THEN
    _last_by := COALESCE(_state->>'last_discard_by', '_seed');
    _pile := COALESCE(public._rami_jarr(_discards->_last_by), ARRAY[]::int[]);
    IF array_length(_pile,1) IS NULL THEN
      FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
        _pile := public._rami_jarr(_v);
        IF array_length(_pile,1) IS NOT NULL THEN
          _last_by := _k;
          EXIT;
        END IF;
      END LOOP;
    END IF;
    IF array_length(_pile,1) IS NULL THEN RAISE EXCEPTION 'défausse vide'; END IF;

    _card := _pile[array_length(_pile,1)];
    IF _card IS NULL THEN RAISE EXCEPTION 'carte invalide dans la défausse'; END IF;
    _pile := _pile[1:array_length(_pile,1)-1];
    IF array_length(_pile,1) IS NULL THEN
      _discards := _discards - _last_by;
    ELSE
      _discards := jsonb_set(_discards, ARRAY[_last_by], to_jsonb(_pile));
    END IF;
    _state := jsonb_set(_state, '{last_discard_by}', to_jsonb(_last_by), true);
  ELSE
    IF COALESCE(array_length(_deck,1),0) = 0 THEN
      _all := ARRAY[]::int[];
      _new_discards := '{}'::jsonb;
      FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
        _pile := public._rami_jarr(_v);
        _pile := ARRAY(SELECT x FROM unnest(_pile) x WHERE x IS NOT NULL);
        IF array_length(_pile,1) > 1 THEN
          _all := _all || _pile[1:array_length(_pile,1)-1];
          _new_discards := _new_discards || jsonb_build_object(_k, jsonb_build_array(_pile[array_length(_pile,1)]));
        ELSIF array_length(_pile,1) = 1 THEN
          _new_discards := _new_discards || jsonb_build_object(_k, jsonb_build_array(_pile[1]));
        END IF;
      END LOOP;
      IF array_length(_all,1) IS NULL THEN RAISE EXCEPTION 'plus de cartes'; END IF;
      _deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_all) c);
      _discards := _new_discards;
    END IF;
    _card := _deck[1];
    IF _card IS NULL THEN RAISE EXCEPTION 'carte invalide dans le deck'; END IF;
    _deck := _deck[2:array_length(_deck,1)];
  END IF;

  _hand := array_append(_hand, _card);
  _hands := jsonb_set(_state->'hands', ARRAY[_uid::text], to_jsonb(_hand));

  _action_log := COALESCE(_state->'action_log', '[]'::jsonb) ||
    jsonb_build_object('t', 'draw', 'p', _uid::text, 'from', _from, 'card', _card, 'ts', extract(epoch from now())::bigint);

  _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
  _state := jsonb_set(_state, '{discards}', _discards);
  _state := jsonb_set(_state, '{hands}', _hands);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  _flat := ARRAY[]::int[];
  FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
    _flat := _flat || public._rami_jarr(_v);
  END LOOP;
  _state := jsonb_set(_state, '{discard}', to_jsonb(_flat), true);

  UPDATE public.rami_games
    SET state=_state, turn_phase='play',
        turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
        updated_at=now()
    WHERE id=_game_id;
  UPDATE public.rami_participants SET hand_count=array_length(_hand,1)
    WHERE game_id=_game_id AND user_id=_uid;
END $function$;

-- ═══ Fix _rami_autoplay_bots: bot 2 paquets + bug re-défausse ═══

CREATE OR REPLACE FUNCTION public._rami_autoplay_bots(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $function$
DECLARE
  g public.rami_games; part public.rami_participants; guard int := 0;
  _key text; _hand int[]; _card int; _deck int[]; _new_hand int[]; _hands jsonb;
  _melds jsonb; _melded int[]; _type text; _intel int; _parts int[];
  _next int; _top int; _matched boolean;
  _cfg record;
  _state jsonb; _discards jsonb; _pile int[]; _last text; _reshuffle jsonb;
  _all_discard int[]; _k text; _v jsonb;
  _winner_name text; _payout numeric; _comm numeric;
  _seven boolean;
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
    _seven := COALESCE(g.seven_cards, false);
    SELECT * INTO _cfg FROM public._game_cfg('rami');
    _state := public._rami_normalize_state(g.state);
    _discards := public._rami_discards_map(_state);
    _last := public._rami_last_discarder(_state);

    IF g.turn_phase = 'draw' THEN
      _deck    := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'deck'))::int[], ARRAY[]::int[]);
      _hand    := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_key))::int[], ARRAY[]::int[]);
      _pile    := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_last))::int[], ARRAY[]::int[]);
      _pile := ARRAY(SELECT x FROM unnest(_pile) x WHERE x IS NOT NULL);
      _card    := NULL;
      _matched := false;

      -- ═══ Fix: bot peut matcher les cartes des 2 paquets (0-111) ═══
      -- Joker: (id % 56) >= 52, on exclut. Carte normale: (id % 56) < 52, rang = id % 13.
      IF _intel >= 70 AND array_length(_pile,1) IS NOT NULL AND array_length(_pile,1) > 0 THEN
        _top := _pile[array_length(_pile,1)];
        IF (_top % 56) < 52 AND EXISTS (
          SELECT 1 FROM unnest(_hand) c
          WHERE (c % 56) < 52 AND c%13 = _top%13
        ) THEN
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
        IF COALESCE(array_length(_deck,1),0) = 0 THEN
          _reshuffle := public._rami_reshuffle(_state);
          _deck := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_reshuffle->'deck'))::int[], ARRAY[]::int[]);
          _discards := _reshuffle->'discards';
        END IF;
        IF COALESCE(array_length(_deck,1),0) = 0 THEN EXIT; END IF;
        _card := _deck[1];
        _deck := _deck[2:array_length(_deck,1)];
      END IF;

      _hand := array_append(_hand, _card);
      _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_hand));
      _state := jsonb_set(_state,'{deck}',to_jsonb(_deck));
      _state := jsonb_set(_state,'{discards}',_discards);
      _state := jsonb_set(_state,'{hands}',_hands);
      _all_discard := ARRAY[]::int[];
      FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
        _all_discard := _all_discard || ARRAY(SELECT jsonb_array_elements_text(_v))::int[];
      END LOOP;
      _state := jsonb_set(_state, '{discard}', to_jsonb(_all_discard), true);

      UPDATE public.rami_games
         SET state = _state, turn_phase = 'play', updated_at = now()
       WHERE id = _game_id;
      UPDATE public.rami_participants
         SET hand_count = COALESCE(array_length(_hand,1),0)
       WHERE game_id = _game_id AND slot = part.slot;
      CONTINUE;
    END IF;

    _hand  := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_key))::int[], ARRAY[]::int[]);
    _melds := COALESCE(_state->'melds','[]'::jsonb);
    _melded := NULL;

    IF _intel >= 50 AND COALESCE(array_length(_hand,1),0) >= 4 THEN
      SELECT ARRAY[_hand[ai], _hand[aj], _hand[ak], _hand[al]] INTO _melded
        FROM generate_subscripts(_hand,1) ai, generate_subscripts(_hand,1) aj,
             generate_subscripts(_hand,1) ak, generate_subscripts(_hand,1) al
       WHERE ai < aj AND aj < ak AND ak < al
         AND public._rami_meld_type(ARRAY[_hand[ai],_hand[aj],_hand[ak],_hand[al]], g.joker_mode, g.random_joker) IS NOT NULL
       LIMIT 1;

      IF _melded IS NULL THEN
        SELECT ARRAY[_hand[bi], _hand[bj], _hand[bk]] INTO _melded
          FROM generate_subscripts(_hand,1) bi, generate_subscripts(_hand,1) bj, generate_subscripts(_hand,1) bk
         WHERE bi < bj AND bj < bk
           AND public._rami_meld_type(ARRAY[_hand[bi],_hand[bj],_hand[bk]], g.joker_mode, g.random_joker) IS NOT NULL
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
        ORDER BY (CASE WHEN (c % 56) < 52 THEN c%13 ELSE -1 END) DESC, random()
        LIMIT 1;
    END IF;

    _new_hand := public._rami_remove_one(_hand, _card);

    -- ═══ Fix: si _new_hand est vide, gérer proprement ═══
    IF COALESCE(array_length(_new_hand,1),0) = 0 THEN
      _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_key))::int[], ARRAY[]::int[]);
      _pile := array_append(_pile, _card);
      _discards := jsonb_set(_discards, ARRAY[_key], to_jsonb(_pile), true);
      _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_new_hand));
      _state := jsonb_set(_state,'{hands}',_hands);
      _state := jsonb_set(_state,'{discards}',_discards);
      _state := jsonb_set(_state,'{last_discard_by}',to_jsonb(_key));
      _all_discard := ARRAY[]::int[];
      FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
        _all_discard := _all_discard || ARRAY(SELECT jsonb_array_elements_text(_v))::int[];
      END LOOP;
      _state := jsonb_set(_state, '{discard}', to_jsonb(_all_discard), true);

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
         WHERE id=_game_id;
        UPDATE public.rami_participants SET hand_count=0
         WHERE game_id=_game_id AND slot=part.slot;
        EXIT;
      ELSE
        -- Remettre la carte dans la main (ne peut pas gagner avec 0 cartes)
        _new_hand := ARRAY[_card];
        _pile := _pile[1:array_length(_pile,1)-1];
        IF array_length(_pile,1) IS NULL THEN
          _discards := _discards - _key;
        ELSE
          _discards := jsonb_set(_discards, ARRAY[_key], to_jsonb(_pile));
        END IF;
        _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_new_hand));
        _state := jsonb_set(_state,'{hands}',_hands);
        _state := jsonb_set(_state,'{discards}',_discards);
        _all_discard := ARRAY[]::int[];
        FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
          _all_discard := _all_discard || ARRAY(SELECT jsonb_array_elements_text(_v))::int[];
        END LOOP;
        _state := jsonb_set(_state, '{discard}', to_jsonb(_all_discard), true);
        UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
        UPDATE public.rami_participants SET hand_count=1
          WHERE game_id=_game_id AND slot=part.slot;
        CONTINUE;
      END IF;
    END IF;

    -- Passer au joueur suivant
    SELECT array_agg(slot ORDER BY slot) INTO _parts
      FROM public.rami_participants WHERE game_id = _game_id AND NOT forfeited;
    _next := g.current_turn;
    LOOP
      _next := (_next + 1) % g.max_players;
      EXIT WHEN _next = ANY(_parts);
    END LOOP;

    _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_key))::int[], ARRAY[]::int[]);
    _pile := array_append(_pile, _card);
    _discards := jsonb_set(_discards, ARRAY[_key], to_jsonb(_pile), true);
    _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_new_hand));

    _state := jsonb_set(_state,'{hands}',_hands);
    _state := jsonb_set(_state,'{discards}',_discards);
    _state := jsonb_set(_state,'{last_discard_by}',to_jsonb(_key));
    _all_discard := ARRAY[]::int[];
    FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
      _all_discard := _all_discard || ARRAY(SELECT jsonb_array_elements_text(_v))::int[];
    END LOOP;
    _state := jsonb_set(_state, '{discard}', to_jsonb(_all_discard), true);

    UPDATE public.rami_games
       SET state = _state, current_turn = _next, turn_phase = 'draw',
           turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval,
           updated_at = now()
     WHERE id = _game_id;
    UPDATE public.rami_participants
       SET hand_count = COALESCE(array_length(_new_hand,1),0)
     WHERE game_id = _game_id AND slot = part.slot;
  END LOOP;
END;
$function$;

-- ═══ Cleanup: nettoyer les cartes NULL dans les défausses ═══
DO $$
DECLARE
  _g RECORD; _state jsonb; _discards jsonb; _k text; _v jsonb;
  _pile int[]; _new_discards jsonb; _flat int[]; _needs_update boolean;
BEGIN
  FOR _g IN SELECT id, state FROM public.rami_games WHERE status = 'playing' LOOP
    _state := _g.state;
    _discards := public._rami_discards_map(_state);
    _new_discards := '{}'::jsonb;
    _needs_update := false;

    FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
      _pile := public._rami_jarr(_v);
      IF _pile IS NOT NULL THEN
        _pile := ARRAY(SELECT x FROM unnest(_pile) x WHERE x IS NOT NULL);
      END IF;
      IF array_length(_pile,1) IS NOT NULL THEN
        _new_discards := _new_discards || jsonb_build_object(_k, to_jsonb(_pile));
      ELSE
        _needs_update := true;
      END IF;
    END LOOP;

    IF _needs_update THEN
      _state := jsonb_set(_state, '{discards}', _new_discards, true);
      _flat := ARRAY[]::int[];
      FOR _k, _v IN SELECT * FROM jsonb_each(_new_discards) LOOP
        _flat := _flat || public._rami_jarr(_v);
      END LOOP;
      _state := jsonb_set(_state, '{discard}', to_jsonb(_flat), true);
      UPDATE public.rami_games SET state = _state, updated_at = now() WHERE id = _g.id;
      RAISE NOTICE 'Nettoyage NULL dans jeu %', _g.id;
    END IF;
  END LOOP;
END $$;
