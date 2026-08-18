-- ============================================================
-- 1. Fix: rami_validate_hand calls _rami_meld_type with 4 args (bug)
-- 2. Fix: rami_validate_hand calls _rami_check_win with uuid instead of text
-- 3. Feature: Lucky deal probabilities in rami_start AND rami_start_solo_bot
--    - 35% chance: 2 trios at start
--    - 20% chance: 2 jokers at start
--    - 10% chance: 7-card valid combo (carré + tri) at start
-- ============================================================

-- ════════════════════════════════════════════════════════════
-- 1. Fix rami_validate_hand
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.rami_validate_hand(_game_id uuid, _layout jsonb, _discard_card integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _uid uuid := auth.uid();
  _g public.rami_games;
  _slot int;
  _state jsonb;
  _hand int[];
  _c int;
  _new_hand int[];
  _melds jsonb;
  _group jsonb;
  _cards int[];
  _type text;
  _is_pure boolean;
  _action_log jsonb;
  _won boolean;
  _payout numeric;
  _comm numeric;
  _first_melds jsonb;
  _winner_name text;
  _seven boolean;
  _cfg record;
  _parts int[];
  _next int;
  _discard_arr int[];
  _discard_by text[];
  _key text;
  _next_is_bot boolean;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _seven := COALESCE(_g.seven_cards, false);
  _key := _uid::text;
  _state := public._rami_normalize_state(_g.state);
  _hand := COALESCE(public._rami_jarr(_state->'hands'->_key), ARRAY[]::int[]);
  _new_hand := _hand;

  _first_melds := COALESCE(_state->'first_melds', '{}'::jsonb);
  _melds := COALESCE(_state->'melds', '[]'::jsonb);

  FOR _group IN SELECT * FROM jsonb_array_elements(_layout) LOOP
    _cards := ARRAY(SELECT jsonb_array_elements_text(_group))::int[];
    FOREACH _c IN ARRAY _cards LOOP
      IF NOT (_c = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte absente de la main'; END IF;
      _new_hand := public._rami_remove_one(_new_hand, _c);
    END LOOP;

    -- FIX: 3 args only (no _seven_cards boolean)
    _type := public._rami_meld_type(_cards, _g.joker_mode, _g.random_joker);
    IF _type IS NULL THEN RAISE EXCEPTION 'combinaison invalide dans le layout'; END IF;

    _is_pure := true;
    FOREACH _c IN ARRAY _cards LOOP
      IF public._rami_is_joker(_c, _g.joker_mode, _g.random_joker) THEN
        _is_pure := false;
      END IF;
    END LOOP;

    _melds := _melds || jsonb_build_array(
      jsonb_build_object(
        'player', _key,
        'cards', to_jsonb(_cards),
        'type', _type,
        'pure', _is_pure
      )
    );

    IF _first_melds ? _key = false OR _first_melds->_key IS NULL THEN
      _first_melds := jsonb_set(_first_melds, ARRAY[_key], to_jsonb(extract(epoch from now())::bigint), true);
    END IF;
  END LOOP;

  IF NOT (_discard_card = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte de défausse absente'; END IF;
  _new_hand := public._rami_remove_one(_new_hand, _discard_card);

  _state := jsonb_set(_state, '{melds}', _melds);
  _state := jsonb_set(_state, '{first_melds}', _first_melds, true);

  _discard_arr := COALESCE(public._rami_jarr(_state->'discard'), ARRAY[]::int[]);
  _discard_arr := ARRAY(SELECT x FROM unnest(_discard_arr) x WHERE x IS NOT NULL);
  _discard_arr := array_append(_discard_arr, _discard_card);

  IF _state ? 'discard_by' AND _state->'discard_by' IS NOT NULL THEN
    _discard_by := ARRAY(SELECT elem::text FROM jsonb_array_elements_text(_state->'discard_by') elem WHERE elem IS NOT NULL);
  ELSE
    _discard_by := ARRAY[]::text[];
  END IF;
  _discard_by := array_append(_discard_by, _key);

  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
  _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);

  _action_log := COALESCE(_state->'action_log', '[]'::jsonb) ||
    jsonb_build_object('t', 'validate_hand', 'p', _key, 'discard', _discard_card, 'ts', extract(epoch from now())::bigint);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand, 1), 0)
    WHERE game_id=_game_id AND user_id=_uid;

  IF COALESCE(array_length(_new_hand, 1), 0) = 0 THEN
    -- FIX: use _key (text) not _uid (uuid)
    _won := public._rami_check_win(_state, _key, _seven);
    IF _won THEN
      SELECT COALESCE(pseudo, 'Joueur') INTO _winner_name FROM public.profiles WHERE id=_uid;
      _comm := round(_g.pot * (_g.commission_pct / 2.0) / 100.0, 0);
      _payout := _g.pot - _comm;
      UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, 0) + _payout WHERE id = _uid;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (_uid, 'rami_win', _payout, _game_id, 'Win rami');
      _state := public._rami_normalize_state(_state);
      UPDATE public.rami_games SET status='finished', winner_id=_uid, winner_name=_winner_name, finished_at=now(), state=_state WHERE id=_game_id;
      RETURN jsonb_build_object('won', true, 'winner_name', _winner_name);
    ELSE
      _state := jsonb_set(_state, ARRAY['hands', _key], to_jsonb(_new_hand));
      _state := public._rami_normalize_state(_state);
      UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
      RETURN jsonb_build_object('won', false);
    END IF;
  ELSE
    _state := jsonb_set(_state, ARRAY['hands', _key], to_jsonb(_new_hand));

    SELECT array_agg(slot ORDER BY slot) INTO _parts
      FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited;
    _next := _g.current_turn;
    LOOP
      _next := (_next + 1) % _g.max_players;
      EXIT WHEN _next = ANY(_parts);
    END LOOP;

    SELECT COALESCE(is_bot, false) INTO _next_is_bot
      FROM public.rami_participants
      WHERE game_id=_game_id AND slot=_next;

    IF _next_is_bot THEN
      _state := jsonb_set(_state, '{bot_think_until}',
        to_jsonb(to_char(now() + interval '5 seconds', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')), true);
    ELSE
      _state := _state - 'bot_think_until';
    END IF;

    _state := public._rami_normalize_state(_state);

    UPDATE public.rami_games
       SET state=_state, current_turn=_next, turn_phase='draw',
           turn_deadline=now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
           updated_at=now()
     WHERE id=_game_id;
    RETURN jsonb_build_object('won', false);
  END IF;
END $function$;
REVOKE ALL ON FUNCTION public.rami_validate_hand(uuid, jsonb, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_validate_hand(uuid, jsonb, integer) TO authenticated;


-- ════════════════════════════════════════════════════════════
-- 2. rami_start with lucky deal
-- ════════════════════════════════════════════════════════════
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
  _card_count int; _max int; _max_players int;
  _first_slot int; _slots int[];
  _roll int; _special_cards int[]; _base_cards int[];
  _rank1 int; _rank2 int; _suits int[]; _deck_pos int; _remaining int;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status NOT IN ('waiting','open') THEN RETURN; END IF;
  IF (SELECT count(*) FROM public.rami_participants WHERE game_id=_game_id) < 2 THEN
    RAISE EXCEPTION 'pas assez de joueurs';
  END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _joker_mode := _g.joker_mode;
  _random_joker := NULL;
  IF _joker_mode IN ('classique','double') THEN _max := 56; ELSE _max := 52; END IF;

  _max_players := _g.max_players;
  IF _max_players <= 2 THEN
    _deck := ARRAY(SELECT generate_series(0, _max-1)) || ARRAY(SELECT generate_series(56, _max-1+56));
  ELSE
    _deck := ARRAY(SELECT generate_series(0, _max-1))
          || ARRAY(SELECT generate_series(56, _max-1+56))
          || ARRAY(SELECT generate_series(112, _max-1+112));
  END IF;

  _deck := ARRAY(SELECT c FROM (SELECT unnest(_deck) AS c, gen_random_uuid() AS r ORDER BY r) x);
  _deck := ARRAY(SELECT c FROM (SELECT unnest(_deck) AS c, gen_random_uuid() AS r ORDER BY r) x);
  FOR _i IN REVERSE array_length(_deck,1)..2 LOOP
    _j := 1 + public._crypto_rand_int(_i);
    _tmp := _deck[_i]; _deck[_i] := _deck[_j]; _deck[_j] := _tmp;
  END LOOP;

  SELECT array_agg(slot ORDER BY slot) INTO _slots FROM public.rami_participants WHERE game_id=_game_id;
  _first_slot := _slots[1 + public._crypto_rand_int(array_length(_slots,1))];

  FOR _slot, _uid, _is_bot IN
    SELECT slot, user_id, is_bot FROM public.rami_participants WHERE game_id=_game_id ORDER BY slot
  LOOP
    IF _slot = _first_slot THEN _card_count := 14; ELSE _card_count := 13; END IF;

    _special_cards := ARRAY[]::int[];
    _base_cards := ARRAY[]::int[];
    _roll := public._crypto_rand_int(100);

    IF _roll < 10 THEN
      -- 10% : 7-card valid combo (carré + tri)
      _rank1 := public._crypto_rand_int(13);
      _rank2 := public._crypto_rand_int(13);
      WHILE _rank2 = _rank1 LOOP _rank2 := public._crypto_rand_int(13); END LOOP;
      _base_cards := ARRAY[_rank1, _rank1+13, _rank1+26, _rank1+39];
      _suits := ARRAY[0,1,2,3];
      FOR _i IN REVERSE 4..2 LOOP _j := 1+public._crypto_rand_int(_i); _tmp:=_suits[_i]; _suits[_i]:=_suits[_j]; _suits[_j]:=_tmp; END LOOP;
      _base_cards := _base_cards || ARRAY[_rank2+_suits[1]*13, _rank2+_suits[2]*13, _rank2+_suits[3]*13];
    ELSIF _roll < 30 THEN
      -- 20% : 2 jokers
      IF _joker_mode IN ('classique','double') THEN _base_cards := ARRAY[52,53]; END IF;
    ELSIF _roll < 65 THEN
      -- 35% : 2 trios
      _rank1 := public._crypto_rand_int(13);
      _rank2 := public._crypto_rand_int(13);
      WHILE _rank2 = _rank1 LOOP _rank2 := public._crypto_rand_int(13); END LOOP;
      _suits := ARRAY[0,1,2,3];
      FOR _i IN REVERSE 4..2 LOOP _j := 1+public._crypto_rand_int(_i); _tmp:=_suits[_i]; _suits[_i]:=_suits[_j]; _suits[_j]:=_tmp; END LOOP;
      _base_cards := ARRAY[_rank1+_suits[1]*13, _rank1+_suits[2]*13, _rank1+_suits[3]*13];
      _suits := ARRAY[0,1,2,3];
      FOR _i IN REVERSE 4..2 LOOP _j := 1+public._crypto_rand_int(_i); _tmp:=_suits[_i]; _suits[_i]:=_suits[_j]; _suits[_j]:=_tmp; END LOOP;
      _base_cards := _base_cards || ARRAY[_rank2+_suits[1]*13, _rank2+_suits[2]*13, _rank2+_suits[3]*13];
    END IF;

    -- Extract special cards from deck
    IF array_length(_base_cards,1) > 0 THEN
      FOREACH _tmp IN ARRAY _base_cards LOOP
        _deck_pos := 0;
        FOR _i IN 1..array_length(_deck,1) LOOP
          IF _deck[_i] % 56 = _tmp THEN _deck_pos := _i; EXIT; END IF;
        END LOOP;
        IF _deck_pos > 0 THEN
          _special_cards := array_append(_special_cards, _deck[_deck_pos]);
          IF _deck_pos = 1 THEN _deck := _deck[2:array_length(_deck,1)];
          ELSIF _deck_pos = array_length(_deck,1) THEN _deck := _deck[1:array_length(_deck,1)-1];
          ELSE _deck := _deck[1:_deck_pos-1] || _deck[_deck_pos+1:array_length(_deck,1)]; END IF;
        END IF;
      END LOOP;
    END IF;

    _remaining := _card_count - COALESCE(array_length(_special_cards,1), 0);
    IF _remaining > 0 THEN
      _hand := _special_cards || _deck[1:_remaining];
      _deck := _deck[_remaining+1:array_length(_deck,1)];
    ELSE
      _hand := _special_cards;
    END IF;

    _key := CASE WHEN COALESCE(_is_bot,false) THEN 'bot:'||_slot::text ELSE _uid::text END;
    _hands := _hands || jsonb_build_object(_key, to_jsonb(_hand));
    UPDATE public.rami_participants SET hand_count = COALESCE(array_length(_hand,1),0)
      WHERE game_id=_game_id AND slot=_slot;
  END LOOP;

  IF _joker_mode IN ('aleatoire','double') THEN
    _i := 1;
    WHILE _i <= array_length(_deck,1) AND (_deck[_i] % 56) >= 52 LOOP _i := _i + 1; END LOOP;
    IF _i <= array_length(_deck,1) THEN
      _random_joker := _deck[_i];
      _deck := _deck[1:_i-1] || _deck[_i+1:array_length(_deck,1)];
    END IF;
  END IF;

  _discards := '{}'::jsonb;
  _action_log := jsonb_build_array(jsonb_build_object('t','start','ts',extract(epoch from now())::bigint));
  _state := jsonb_build_object(
    'deck', to_jsonb(_deck), 'discards', _discards, 'discard', '[]'::jsonb,
    'last_discard_by', null::jsonb, 'hands', _hands, 'melds', '[]'::jsonb,
    'action_log', _action_log, 'refunded', '{}'::jsonb, 'joker_mode', _joker_mode,
    'first_player', _first_slot,
    'random_joker', CASE WHEN _random_joker IS NULL THEN 'null'::jsonb ELSE to_jsonb(_random_joker) END
  );

  UPDATE public.rami_games SET status='playing', state=_state, started_at=now(),
    current_turn=_first_slot, turn_phase='play', random_joker=_random_joker,
    turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval
    WHERE id=_game_id;

  PERFORM public._rami_autoplay_bots(_game_id);
END
$function$;
REVOKE ALL ON FUNCTION public.rami_start(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_start(uuid) TO authenticated;


-- ════════════════════════════════════════════════════════════
-- 3. rami_start_solo_bot with lucky deal
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.rami_start_solo_bot(
  _max_players integer DEFAULT 2,
  _difficulty text DEFAULT 'medium'::text,
  _joker_mode text DEFAULT 'classique'::text,
  _game_mode text DEFAULT 'bordel'::text
)
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
  v_deck_size int;
  v_max_players int;
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
  v_first_slot int;
  -- Lucky deal vars
  v_roll int;
  v_special_cards int[] := ARRAY[]::int[];
  v_base_cards int[] := ARRAY[]::int[];
  v_rank1 int; v_rank2 int;
  v_suits int[];
  v_deck_pos int;
  v_remaining int;
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

  IF _joker_mode IN ('classique','double') THEN v_deck_size := 56; ELSE v_deck_size := 52; END IF;

  v_max_players := _max_players;
  IF v_max_players <= 2 THEN
    v_deck := ARRAY(SELECT generate_series(0, v_deck_size-1)) || ARRAY(SELECT generate_series(56, v_deck_size-1+56));
  ELSE
    v_deck := ARRAY(SELECT generate_series(0, v_deck_size-1))
           || ARRAY(SELECT generate_series(56, v_deck_size-1+56))
           || ARRAY(SELECT generate_series(112, v_deck_size-1+112));
  END IF;

  v_deck := ARRAY(SELECT c FROM (SELECT unnest(v_deck) AS c, gen_random_uuid() AS r ORDER BY r) x);
  v_deck := ARRAY(SELECT c FROM (SELECT unnest(v_deck) AS c, gen_random_uuid() AS r ORDER BY r) x);
  FOR v_i IN REVERSE array_length(v_deck,1)..2 LOOP
    v_j := 1 + public._crypto_rand_int(v_i);
    v_tmp := v_deck[v_i]; v_deck[v_i] := v_deck[v_j]; v_deck[v_j] := v_tmp;
  END LOOP;

  v_first_slot := public._crypto_rand_int(v_max_players);

  FOR v_slot IN 0..v_max_players - 1 LOOP
    IF v_slot = v_first_slot THEN v_card_count := 14; ELSE v_card_count := 13; END IF;

    v_special_cards := ARRAY[]::int[];
    v_base_cards := ARRAY[]::int[];
    v_roll := public._crypto_rand_int(100);

    IF v_roll < 10 THEN
      -- 10% : 7-card valid combo (carré + tri)
      v_rank1 := public._crypto_rand_int(13);
      v_rank2 := public._crypto_rand_int(13);
      WHILE v_rank2 = v_rank1 LOOP v_rank2 := public._crypto_rand_int(13); END LOOP;
      v_base_cards := ARRAY[v_rank1, v_rank1+13, v_rank1+26, v_rank1+39];
      v_suits := ARRAY[0,1,2,3];
      FOR v_i IN REVERSE 4..2 LOOP v_j := 1+public._crypto_rand_int(v_i); v_tmp:=v_suits[v_i]; v_suits[v_i]:=v_suits[v_j]; v_suits[v_j]:=v_tmp; END LOOP;
      v_base_cards := v_base_cards || ARRAY[v_rank2+v_suits[1]*13, v_rank2+v_suits[2]*13, v_rank2+v_suits[3]*13];
    ELSIF v_roll < 30 THEN
      -- 20% : 2 jokers
      IF _joker_mode IN ('classique','double') THEN v_base_cards := ARRAY[52,53]; END IF;
    ELSIF v_roll < 65 THEN
      -- 35% : 2 trios
      v_rank1 := public._crypto_rand_int(13);
      v_rank2 := public._crypto_rand_int(13);
      WHILE v_rank2 = v_rank1 LOOP v_rank2 := public._crypto_rand_int(13); END LOOP;
      v_suits := ARRAY[0,1,2,3];
      FOR v_i IN REVERSE 4..2 LOOP v_j := 1+public._crypto_rand_int(v_i); v_tmp:=v_suits[v_i]; v_suits[v_i]:=v_suits[v_j]; v_suits[v_j]:=v_tmp; END LOOP;
      v_base_cards := ARRAY[v_rank1+v_suits[1]*13, v_rank1+v_suits[2]*13, v_rank1+v_suits[3]*13];
      v_suits := ARRAY[0,1,2,3];
      FOR v_i IN REVERSE 4..2 LOOP v_j := 1+public._crypto_rand_int(v_i); v_tmp:=v_suits[v_i]; v_suits[v_i]:=v_suits[v_j]; v_suits[v_j]:=v_tmp; END LOOP;
      v_base_cards := v_base_cards || ARRAY[v_rank2+v_suits[1]*13, v_rank2+v_suits[2]*13, v_rank2+v_suits[3]*13];
    END IF;

    -- Extract special cards from deck
    IF array_length(v_base_cards,1) > 0 THEN
      FOREACH v_tmp IN ARRAY v_base_cards LOOP
        v_deck_pos := 0;
        FOR v_i IN 1..array_length(v_deck,1) LOOP
          IF v_deck[v_i] % 56 = v_tmp THEN v_deck_pos := v_i; EXIT; END IF;
        END LOOP;
        IF v_deck_pos > 0 THEN
          v_special_cards := array_append(v_special_cards, v_deck[v_deck_pos]);
          IF v_deck_pos = 1 THEN v_deck := v_deck[2:array_length(v_deck,1)];
          ELSIF v_deck_pos = array_length(v_deck,1) THEN v_deck := v_deck[1:array_length(v_deck,1)-1];
          ELSE v_deck := v_deck[1:v_deck_pos-1] || v_deck[v_deck_pos+1:array_length(v_deck,1)]; END IF;
        END IF;
      END LOOP;
    END IF;

    v_remaining := v_card_count - COALESCE(array_length(v_special_cards,1), 0);
    IF v_remaining > 0 THEN
      v_hand := v_special_cards || v_deck[1:v_remaining];
      v_deck := v_deck[v_remaining+1:array_length(v_deck,1)];
    ELSE
      v_hand := v_special_cards;
    END IF;

    v_key := CASE WHEN v_slot = 0 THEN v_uid::text ELSE 'bot:' || v_slot::text END;
    v_hands := v_hands || jsonb_build_object(v_key, to_jsonb(v_hand));
    UPDATE public.rami_participants SET hand_count = COALESCE(array_length(v_hand,1),0)
      WHERE game_id = v_game_id AND slot = v_slot;
  END LOOP;

  IF _joker_mode IN ('aleatoire','double') THEN
    v_rj := public._crypto_rand_int(52);
  END IF;

  v_state := jsonb_build_object(
    'deck', to_jsonb(v_deck), 'discards', '{}'::jsonb, 'discard', '[]'::jsonb,
    'last_discard_by', null::jsonb, 'hands', v_hands, 'melds', '[]'::jsonb,
    'first_player', v_first_slot, 'joker_mode', _joker_mode,
    'random_joker', CASE WHEN v_rj IS NULL THEN 'null'::jsonb ELSE to_jsonb(v_rj) END
  );

  UPDATE public.rami_games SET
    status = 'playing', state = v_state, started_at = now(),
    current_turn = v_first_slot, turn_phase = 'play',
    random_joker = v_rj, turn_deadline = now() + interval '60 seconds'
  WHERE id = v_game_id;

  RETURN v_game_id;
END
$function$;
REVOKE ALL ON FUNCTION public.rami_start_solo_bot(integer, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_start_solo_bot(integer, text, text, text) TO authenticated;
