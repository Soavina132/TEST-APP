-- ─────────────────────────────────────────────────────────────────────
-- Migration: Replace random() with crypto-grade randomness (pgcrypto)
-- for all card shuffling in the rami game.
--
-- random() is a simple LCG (linear congruential generator) — not
-- cryptographically secure. extensions.gen_random_bytes() from pgcrypto uses
-- the OS CSPRNG, giving true unpredictable shuffles.
-- ─────────────────────────────────────────────────────────────────────

-- Ensure pgcrypto is available
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ── Helper: crypto-grade random integer in [0, _max) ──
CREATE OR REPLACE FUNCTION public._crypto_rand_int(_max int)
RETURNS int
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  _b bytea;
  _val bigint;
BEGIN
  IF _max <= 0 THEN RETURN 0; END IF;
  IF _max = 1 THEN RETURN 0; END IF;
  _b := extensions.gen_random_bytes(4);
  _val := get_byte(_b, 0)::bigint
        + get_byte(_b, 1)::bigint * 256
        + get_byte(_b, 2)::bigint * 65536
        + get_byte(_b, 3)::bigint * 16777216;
  RETURN (_val % _max)::int;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════
-- rami_start: uses _crypto_rand_int for Fisher-Yates + joker selection
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.rami_start(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  _g public.rami_games; _deck int[]; _i int; _j int; _tmp int;
  _hands jsonb := '{}'::jsonb; _hand int[]; _state jsonb; _key text;
  _cfg record; _joker_mode text; _random_joker int;
  _discards jsonb; _action_log jsonb;
  _slot int; _uid uuid; _is_bot boolean;
  _is_first boolean := true;
  _card_count int;
  _deck_size int;
  _max_players int;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status NOT IN ('waiting','open') THEN RETURN; END IF;

  IF (SELECT count(*) FROM public.rami_participants WHERE game_id=_game_id) < 2 THEN
    RAISE EXCEPTION 'pas assez de joueurs';
  END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');

  _joker_mode := _g.joker_mode;
  _random_joker := NULL;

  IF _joker_mode = 'aucun' THEN
    _deck_size := 52;
  ELSIF _joker_mode = 'fixe' THEN
    _deck_size := 54;
  ELSE
    _deck_size := 56;
    _random_joker := public._crypto_rand_int(52);
  END IF;

  _max_players := _g.max_players;
  IF _max_players <= 2 THEN
    _deck := ARRAY(SELECT generate_series(0, _deck_size-1)) ||
             ARRAY(SELECT generate_series(56, _deck_size-1+56));
  ELSE
    _deck := ARRAY(SELECT generate_series(0, _deck_size-1)) ||
             ARRAY(SELECT generate_series(56, _deck_size-1+56)) ||
             ARRAY(SELECT generate_series(112, _deck_size-1+112));
  END IF;

  -- Fisher-Yates shuffle with crypto-grade randomness
  FOR _i IN REVERSE array_length(_deck,1)..2 LOOP
    _j := 1 + public._crypto_rand_int(_i);
    _tmp := _deck[_i]; _deck[_i] := _deck[_j]; _deck[_j] := _tmp;
  END LOOP;

  -- Deal: first player gets 14, others get 13
  FOR _slot, _uid, _is_bot IN
    SELECT slot, user_id, is_bot FROM public.rami_participants
    WHERE game_id=_game_id ORDER BY slot
  LOOP
    IF _is_first THEN
      _card_count := 14;
      _is_first := false;
    ELSE
      _card_count := 13;
    END IF;

    _hand := _deck[1:_card_count];
    _deck := _deck[_card_count+1:array_length(_deck,1)];
    _key := CASE WHEN COALESCE(_is_bot, false) THEN 'bot:' || _slot::text ELSE _uid::text END;
    _hands := _hands || jsonb_build_object(_key, to_jsonb(_hand));
    UPDATE public.rami_participants SET hand_count = _card_count
      WHERE game_id=_game_id AND slot=_slot;
  END LOOP;

  -- PAS de carte seed sur la défausse — la défausse commence vide
  _discards := '{}'::jsonb;

  _action_log := jsonb_build_array(
    jsonb_build_object('t', 'start', 'ts', extract(epoch from now())::bigint)
  );

  _state := jsonb_build_object(
    'deck', to_jsonb(_deck),
    'discards', _discards,
    'discard', '[]'::jsonb,
    'last_discard_by', null::jsonb,
    'hands', _hands,
    'melds', '[]'::jsonb,
    'action_log', _action_log,
    'refunded', '{}'::jsonb
  );

  UPDATE public.rami_games SET
    status='playing', state=_state, started_at=now(),
    current_turn=0, turn_phase='play',
    random_joker=_random_joker,
    turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval
    WHERE id=_game_id;

  PERFORM public._rami_autoplay_bots(_game_id);
END $function$;

REVOKE ALL ON FUNCTION public.rami_start(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_start(uuid) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════
-- rami_start_solo_bot: same crypto Fisher-Yates
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.rami_start_solo_bot(_max_players integer DEFAULT 2, _difficulty text DEFAULT 'medium'::text, _joker_mode text DEFAULT 'classique'::text, _game_mode text DEFAULT 'bordel'::text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid      uuid := auth.uid();
  v_game_id  uuid;
  v_code     text;
  v_name     text;
  v_intel    int;
  v_paused   boolean;
  v_banned   boolean;
  v_slot     int;
  v_bot_names text[] := ARRAY['Bot Rija','Bot Naina','Bot Hery','Bot Voara'];
  v_max      int;
  v_deck     int[];
  v_i        int;
  v_j        int;
  v_tmp      int;
  v_hands    jsonb := '{}'::jsonb;
  v_hand     int[];
  v_key      text;
  v_rj       int := NULL;
  v_state    jsonb;
  v_card_count int;
  v_is_first boolean := true;
BEGIN
  PERFORM public._assert_solo_bot_enabled();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _max_players < 2 OR _max_players > 4 THEN RAISE EXCEPTION 'Joueurs invalides (2-4)'; END IF;
  IF _joker_mode NOT IN ('sans','aleatoire','classique','double') THEN _joker_mode := 'classique'; END IF;
  IF _game_mode NOT IN ('bordel','naturel') THEN _game_mode := 'bordel'; END IF;

  SELECT paused INTO v_paused FROM public.app_settings WHERE id = 1;
  IF COALESCE(v_paused, false) THEN RAISE EXCEPTION 'Application en pause'; END IF;

  SELECT banned, COALESCE(pseudo,'Joueur') INTO v_banned, v_name
    FROM public.profiles WHERE id = v_uid;
  IF COALESCE(v_banned, false) THEN RAISE EXCEPTION 'Compte banni'; END IF;

  CASE lower(_difficulty)
    WHEN 'easy' THEN v_intel := 30;
    WHEN 'hard' THEN v_intel := 95;
    ELSE v_intel := 70;
  END CASE;

  v_code := public._rami_gen_code();

  INSERT INTO public.rami_games (
    room_code, is_private, stake, max_players, commission_pct,
    created_by, pot, joker_mode, game_mode, status
  ) VALUES (
    v_code, true, 0, _max_players, 0, v_uid, 0, _joker_mode, _game_mode, 'waiting'
  ) RETURNING id INTO v_game_id;

  INSERT INTO public.rami_participants(game_id, user_id, slot, display_name, ready, is_bot)
    VALUES (v_game_id, v_uid, 0, v_name, true, false);

  FOR v_slot IN 1.._max_players - 1 LOOP
    INSERT INTO public.rami_participants(
      game_id, user_id, slot, display_name, ready, is_bot, bot_name, bot_intelligence
    ) VALUES (
      v_game_id, NULL, v_slot, v_bot_names[v_slot], true, true, v_bot_names[v_slot], v_intel
    );
  END LOOP;

  IF _joker_mode IN ('classique','double') THEN v_max := 56; ELSE v_max := 52; END IF;
  v_deck := ARRAY(SELECT generate_series(0, v_max - 1));
  -- Fisher-Yates shuffle with crypto-grade randomness
  FOR v_i IN REVERSE v_max..2 LOOP
    v_j := 1 + public._crypto_rand_int(v_i);
    v_tmp := v_deck[v_i]; v_deck[v_i] := v_deck[v_j]; v_deck[v_j] := v_tmp;
  END LOOP;

  -- Deal: 1er joueur (humain, slot 0) a 14 cartes, les autres 13
  v_is_first := true;
  FOR v_slot IN 0.._max_players - 1 LOOP
    IF v_is_first THEN
      v_card_count := 14;
      v_is_first := false;
    ELSE
      v_card_count := 13;
    END IF;

    v_hand := v_deck[1:v_card_count];
    v_deck := v_deck[v_card_count+1:array_length(v_deck,1)];
    v_key := CASE WHEN v_slot = 0 THEN v_uid::text ELSE 'bot:' || v_slot::text END;
    v_hands := v_hands || jsonb_build_object(v_key, to_jsonb(v_hand));
    UPDATE public.rami_participants SET hand_count = v_card_count
      WHERE game_id = v_game_id AND slot = v_slot;
  END LOOP;

  -- Joker aléatoire si mode aleatoire/double
  IF _joker_mode IN ('aleatoire','double') THEN
    v_i := 1;
    WHILE v_i <= array_length(v_deck,1) AND v_deck[v_i] >= 52 LOOP
      v_i := v_i + 1;
    END LOOP;
    IF v_i <= array_length(v_deck,1) THEN
      v_rj := v_deck[v_i];
      v_deck := v_deck[1:v_i-1] || v_deck[v_i+1:array_length(v_deck,1)];
    END IF;
  END IF;

  -- PAS de carte _seed sur la défausse (aligné avec rami_start)
  v_state := jsonb_build_object(
    'deck',           to_jsonb(v_deck),
    'discards',       '{}'::jsonb,
    'discard',        '[]'::jsonb,
    'last_discard_by', null::jsonb,
    'hands',          v_hands,
    'melds',          '[]'::jsonb,
    'first_player',   0
  );

  UPDATE public.rami_games SET
    status        = 'playing',
    state         = v_state,
    started_at    = now(),
    current_turn  = 0,
    turn_phase    = 'play',
    random_joker  = v_rj,
    turn_deadline = now() + interval '60 seconds'
  WHERE id = v_game_id;

  RETURN v_game_id;
END $function$;

REVOKE ALL ON FUNCTION public.rami_start_solo_bot(integer, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_start_solo_bot(integer, text, text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════
-- _rami_reshuffle: replace ORDER BY random() with ORDER BY gen_random_uuid()
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._rami_reshuffle(_state jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  _discard_arr int[];
  _discard_by text[];
  _all int[];
  _top_card int;
  _top_by text;
  _deck int[];
  _discards jsonb;
BEGIN
  _discard_arr := COALESCE(public._rami_jarr(_state->'discard'), ARRAY[]::int[]);
  _discard_arr := ARRAY(SELECT x FROM unnest(_discard_arr) x WHERE x IS NOT NULL);

  IF _state ? 'discard_by' AND _state->'discard_by' IS NOT NULL THEN
    _discard_by := ARRAY(SELECT elem::text FROM jsonb_array_elements_text(_state->'discard_by') elem WHERE elem IS NOT NULL);
  ELSE
    _discard_by := ARRAY[]::text[];
  END IF;

  IF array_length(_discard_arr, 1) IS NULL OR array_length(_discard_arr, 1) <= 1 THEN
    RETURN jsonb_build_object(
      'deck', '[]'::jsonb,
      'discard', to_jsonb(_discard_arr),
      'discard_by', to_jsonb(_discard_by),
      'discards', '{}'::jsonb
    );
  END IF;

  _top_card := _discard_arr[array_length(_discard_arr, 1)];
  _top_by := COALESCE(_discard_by[array_length(_discard_by, 1)], '_seed');
  _all := _discard_arr[1:array_length(_discard_arr, 1)-1];
  -- Crypto-grade shuffle using gen_random_uuid()
  _deck := (SELECT array_agg(c ORDER BY gen_random_uuid()) FROM unnest(_all) c);
  _discard_arr := ARRAY[_top_card];
  _discard_by := ARRAY[_top_by];
  _discards := jsonb_build_object(_top_by, to_jsonb(_discard_arr));

  RETURN jsonb_build_object(
    'deck', to_jsonb(_deck),
    'discard', to_jsonb(_discard_arr),
    'discard_by', to_jsonb(_discard_by),
    'discards', _discards
  );
END $function$;


-- ═══ Additional functions patched with crypto randomness ═══

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

      -- ═══ Bot pioche sur défausse si la carte match ═══
      IF _intel >= 70 AND array_length(_discard_arr, 1) IS NOT NULL AND array_length(_discard_arr, 1) > 0 THEN
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

    IF _intel >= 50 AND COALESCE(array_length(_hand, 1), 0) >= 4 THEN
      SELECT ARRAY[_hand[ai], _hand[aj], _hand[ak], _hand[al]] INTO _melded
        FROM generate_subscripts(_hand, 1) ai, generate_subscripts(_hand, 1) aj,
             generate_subscripts(_hand, 1) ak, generate_subscripts(_hand, 1) al
       WHERE ai < aj AND aj < ak AND ak < al
         AND public._rami_meld_type(ARRAY[_hand[ai], _hand[aj], _hand[ak], _hand[al]], g.joker_mode, g.random_joker) IS NOT NULL
       LIMIT 1;

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
      SELECT c INTO _card FROM unnest(_hand) c
        ORDER BY (CASE WHEN (c % 56) < 52 THEN c%13 ELSE -1 END) DESC, gen_random_uuid()::text
        LIMIT 1;
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
END $function$


REVOKE ALL ON FUNCTION public._rami_autoplay_bots(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._rami_autoplay_bots(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.rami_draw(_game_id uuid, _from text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _uid uuid := auth.uid();
  _g public.rami_games;
  _slot int;
  _state jsonb;
  _deck int[];
  _discard_arr int[];
  _discard_by text[];
  _hand int[];
  _card int;
  _hands jsonb;
  _cfg record;
  _action_log jsonb;
  _last_by text;
  _discards jsonb;
  _pile int[];
  _k text;
  _i int;
  _all int[];
  _melds_count int;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  _state := public._rami_normalize_state(_g.state);
  _melds_count := COALESCE(jsonb_array_length(COALESCE(_state->'melds','[]'::jsonb)), 0);

  -- Accepter draw en phase 'play' au 1er tour (1er joueur, 0 melds)
  IF _g.turn_phase = 'play' THEN
    IF _from = 'discard' AND _melds_count = 0
       AND COALESCE(jsonb_array_length(COALESCE(_state->'action_log','[]'::jsonb)), 0) <= 1 THEN
      NULL;
    ELSE
      RAISE EXCEPTION 'deja pioché ou phase de jeu';
    END IF;
  ELSIF _g.turn_phase <> 'draw' THEN
    RAISE EXCEPTION 'deja pioché';
  END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _deck := COALESCE(public._rami_jarr(_state->'deck'), ARRAY[]::int[]);
  _discard_arr := COALESCE(public._rami_jarr(_state->'discard'), ARRAY[]::int[]);
  _discard_arr := ARRAY(SELECT x FROM unnest(_discard_arr) x WHERE x IS NOT NULL);

  IF _state ? 'discard_by' AND _state->'discard_by' IS NOT NULL THEN
    _discard_by := ARRAY(SELECT elem::text FROM jsonb_array_elements_text(_state->'discard_by') elem WHERE elem IS NOT NULL);
  ELSE
    _last_by := COALESCE(_state->>'last_discard_by', '_seed');
    _discard_by := ARRAY(SELECT _last_by FROM generate_series(1, COALESCE(array_length(_discard_arr,1),0)));
  END IF;

  _hand := COALESCE(public._rami_jarr(_state->'hands'->_uid::text), ARRAY[]::int[]);

  IF _from = 'discard' THEN
    IF array_length(_discard_arr, 1) IS NULL THEN
      RAISE EXCEPTION 'défausse vide';
    END IF;
    _card := _discard_arr[array_length(_discard_arr, 1)];
    _discard_arr := _discard_arr[1:array_length(_discard_arr, 1)-1];
    IF array_length(_discard_by, 1) > 0 THEN
      _last_by := _discard_by[array_length(_discard_by, 1)];
      _discard_by := _discard_by[1:array_length(_discard_by, 1)-1];
    ELSE
      _last_by := COALESCE(_state->>'last_discard_by', '_seed');
    END IF;
  ELSE
    IF COALESCE(array_length(_deck, 1), 0) = 0 THEN
      IF array_length(_discard_arr, 1) IS NULL OR array_length(_discard_arr, 1) <= 1 THEN
        RAISE EXCEPTION 'plus de cartes';
      END IF;
      _all := _discard_arr[1:array_length(_discard_arr, 1)-1];
      _card := _discard_arr[array_length(_discard_arr, 1)];
      _discard_arr := ARRAY[_card];
      IF array_length(_discard_by, 1) > 0 THEN
        _last_by := _discard_by[array_length(_discard_by, 1)];
        _discard_by := ARRAY[_last_by];
      ELSE
        _last_by := COALESCE(_state->>'last_discard_by', '_seed');
        _discard_by := ARRAY[_last_by];
      END IF;
      _deck := (SELECT array_agg(c ORDER BY gen_random_uuid()) FROM unnest(_all) c);
    END IF;
    _card := _deck[1];
    _deck := _deck[2:array_length(_deck, 1)];
  END IF;

  _hand := array_append(_hand, _card);
  _hands := jsonb_set(_state->'hands', ARRAY[_uid::text], to_jsonb(_hand));

  _action_log := COALESCE(_state->'action_log', '[]'::jsonb) ||
    jsonb_build_object('t', 'draw', 'p', _uid::text, 'from', _from, 'card', _card, 'ts', extract(epoch from now())::bigint);

  -- Reconstruire discards multi-pile depuis discard + discard_by
  _discards := '{}'::jsonb;
  IF array_length(_discard_arr, 1) IS NOT NULL THEN
    FOR _k IN SELECT DISTINCT unnest(_discard_by) LOOP
      _pile := ARRAY[]::int[];
      FOR _i IN 1..array_length(_discard_arr, 1) LOOP
        IF _i <= array_length(_discard_by, 1) AND _discard_by[_i] = _k THEN
          _pile := array_append(_pile, _discard_arr[_i]);
        END IF;
      END LOOP;
      IF array_length(_pile, 1) IS NOT NULL THEN
        _discards := _discards || jsonb_build_object(_k, to_jsonb(_pile));
      END IF;
    END LOOP;
  END IF;

  IF array_length(_discard_by, 1) IS NOT NULL THEN
    _last_by := _discard_by[array_length(_discard_by, 1)];
  END IF;

  _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
  _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);
  _state := jsonb_set(_state, '{discards}', _discards, true);
  IF _last_by IS NOT NULL THEN
    _state := jsonb_set(_state, '{last_discard_by}', to_jsonb(_last_by), true);
  END IF;
  _state := jsonb_set(_state, '{hands}', _hands);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  UPDATE public.rami_games
    SET state=_state, turn_phase='play',
        turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
        updated_at=now()
    WHERE id=_game_id;

  UPDATE public.rami_participants SET hand_count=array_length(_hand, 1)
    WHERE game_id=_game_id AND user_id=_uid;
END $function$


REVOKE ALL ON FUNCTION public.rami_draw(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_draw(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.rami_tick(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _g rami_games; _state jsonb; _uid uuid; _is_bot boolean; _slot int;
  _hand int[]; _new_hand int[];
  _deck int[]; _card int; _next int; _cfg record;
  _skips int; _pkey text;
  _discard_arr int[];
  _discard_by text[];
  _think text;
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RETURN; END IF;

  SELECT user_id, is_bot, slot INTO _uid, _is_bot, _slot
    FROM rami_participants WHERE game_id=_game_id AND slot=_g.current_turn;

  IF COALESCE(_is_bot, false) THEN
    -- Respecter bot_think_until
    _think := _g.state->>'bot_think_until';
    IF _think IS NOT NULL THEN
      IF _think > to_char(now(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') THEN
        RETURN;
      END IF;
      _state := _g.state - 'bot_think_until';
      UPDATE rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
    END IF;
    PERFORM public._rami_autoplay_bots(_game_id);
    RETURN;
  END IF;

  IF _g.turn_deadline IS NULL OR _g.turn_deadline > now() THEN RETURN; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _state := public._rami_normalize_state(_g.state);
  _pkey := _uid::text;
  _hand := COALESCE(public._rami_jarr(_state->'hands'->_pkey), ARRAY[]::int[]);
  _discard_arr := COALESCE(public._rami_jarr(_state->'discard'), ARRAY[]::int[]);
  _discard_arr := ARRAY(SELECT x FROM unnest(_discard_arr) x WHERE x IS NOT NULL);
  IF _state ? 'discard_by' AND _state->'discard_by' IS NOT NULL THEN
    _discard_by := ARRAY(SELECT elem::text FROM jsonb_array_elements_text(_state->'discard_by') elem WHERE elem IS NOT NULL);
  ELSE
    _discard_by := ARRAY[]::text[];
  END IF;

  IF _g.turn_phase = 'draw' THEN
    _deck := COALESCE(public._rami_jarr(_state->'deck'), ARRAY[]::int[]);
    IF array_length(_deck,1) IS NULL AND array_length(_discard_arr,1) IS NOT NULL AND array_length(_discard_arr,1) > 1 THEN
      DECLARE _all int[]; BEGIN
        _all := _discard_arr[1:array_length(_discard_arr, 1)-1];
        _discard_arr := ARRAY[_discard_arr[array_length(_discard_arr, 1)]];
        _discard_by := ARRAY[_discard_by[array_length(_discard_by, 1)]];
        _deck := (SELECT array_agg(c ORDER BY gen_random_uuid()) FROM unnest(_all) c);
      END;
    END IF;

    IF array_length(_deck,1) IS NULL THEN
      IF array_length(_hand, 1) IS NULL THEN RETURN; END IF;
      _card := _hand[1 + public._crypto_rand_int(array_length(_hand,1))];
      _new_hand := public._rami_remove_one(_hand, _card);
      _discard_arr := array_append(_discard_arr, _card);
      _discard_by := array_append(_discard_by, _pkey);
      _state := jsonb_set(_state, ARRAY['hands',_pkey], to_jsonb(_new_hand));
      _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
      _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);
      UPDATE rami_participants SET hand_count=array_length(_new_hand,1) WHERE game_id=_game_id AND user_id=_uid;
      _next := _g.current_turn;
      LOOP
        _next := (_next + 1) % _g.max_players;
        EXIT WHEN _next IN (SELECT slot FROM rami_participants WHERE game_id=_game_id AND NOT forfeited);
      END LOOP;
      _state := public._rami_normalize_state(_state);
      UPDATE rami_games SET state=_state, current_turn=_next, turn_phase='draw',
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
        updated_at=now() WHERE id=_game_id;
      PERFORM public._rami_autoplay_bots(_game_id);
      RETURN;
    END IF;

    _card := _deck[1];
    _deck := _deck[2:array_length(_deck,1)];
    _hand := array_append(_hand, _card);
    _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
    _state := jsonb_set(_state, ARRAY['hands',_pkey], to_jsonb(_hand));
    _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
    _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);
    _state := public._rami_normalize_state(_state);
    UPDATE rami_participants SET hand_count=COALESCE(array_length(_hand,1),0)
      WHERE game_id=_game_id AND user_id=_uid;
    UPDATE rami_games SET state=_state, turn_phase='play',
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
        updated_at=now() WHERE id=_game_id;
    RETURN;
  END IF;

  _skips := COALESCE((_g.turn_skips->>_uid::text)::int, 0) + 1;
  IF _skips >= COALESCE(_cfg.max_turn_skips, 3) THEN
    UPDATE rami_participants SET forfeited = true WHERE game_id=_game_id AND user_id=_uid;
    IF (SELECT count(*) FROM rami_participants WHERE game_id=_game_id AND NOT forfeited) <= 1 THEN
      DECLARE _win uuid; _payout numeric; BEGIN
        SELECT user_id INTO _win FROM rami_participants WHERE game_id=_game_id AND NOT forfeited LIMIT 1;
        UPDATE rami_games SET status='finished', winner_id=_win, finished_at=now() WHERE id=_game_id;
        IF _win IS NOT NULL THEN
          _payout := _g.pot * (100 - _g.commission_pct) / 100;
          UPDATE profiles SET balance_ar = COALESCE(balance_ar, balance) + _payout WHERE id=_win;
          INSERT INTO transactions(user_id,type,amount,ref_id,note)
            VALUES (_win,'rami_win', _payout, _game_id, 'Rami win (forfait)');
        END IF;
        RETURN;
      END;
    END IF;
  END IF;

  IF array_length(_hand, 1) IS NULL THEN RETURN; END IF;
  _card := _hand[1 + public._crypto_rand_int(array_length(_hand,1))];
  _new_hand := public._rami_remove_one(_hand, _card);
  _discard_arr := array_append(_discard_arr, _card);
  _discard_by := array_append(_discard_by, _pkey);
  _state := jsonb_set(_state, ARRAY['hands',_pkey], to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
  _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);
  UPDATE rami_participants SET hand_count=array_length(_new_hand,1) WHERE game_id=_game_id AND user_id=_uid;

  _next := _g.current_turn;
  LOOP
    _next := (_next + 1) % _g.max_players;
    EXIT WHEN _next IN (SELECT slot FROM rami_participants WHERE game_id=_game_id AND NOT forfeited);
  END LOOP;

  _state := public._rami_normalize_state(_state);
  UPDATE rami_games SET state=_state, current_turn=_next, turn_phase='draw',
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
    updated_at=now() WHERE id=_game_id;
  PERFORM public._rami_autoplay_bots(_game_id);
END $function$


REVOKE ALL ON FUNCTION public.rami_tick(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_tick(uuid) TO authenticated;

