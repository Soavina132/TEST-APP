-- ============================================================
-- 1. Remove lucky deal (revert to normal distribution)
-- 2. Fix rami_discard: accept turn_phase='play' (was 'draw')
-- 3. Add lives system: 3 lives, 90s timer, auto-forfeit
-- 4. Create rami_process_expired_turns() for timer enforcement
-- ============================================================

-- ═══ Add lives column ═══
ALTER TABLE public.rami_participants ADD COLUMN IF NOT EXISTS lives integer DEFAULT 3;

-- Set lives=3 for existing participants in active games
UPDATE public.rami_participants SET lives = 3 WHERE lives IS NULL;

-- ═══ 1. rami_start — remove lucky deal, set lives=3, normal distribution ═══
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

  -- Mélange cryptographique
  _deck := ARRAY(SELECT c FROM (SELECT unnest(_deck) AS c, gen_random_uuid() AS r ORDER BY r) x);
  _deck := ARRAY(SELECT c FROM (SELECT unnest(_deck) AS c, gen_random_uuid() AS r ORDER BY r) x);
  FOR _i IN REVERSE array_length(_deck,1)..2 LOOP
    _j := 1 + public._crypto_rand_int(_i);
    _tmp := _deck[_i]; _deck[_i] := _deck[_j]; _deck[_j] := _tmp;
  END LOOP;

  SELECT array_agg(slot ORDER BY slot) INTO _slots FROM public.rami_participants WHERE game_id=_game_id;
  _first_slot := _slots[1 + public._crypto_rand_int(array_length(_slots,1))];

  -- Distribution normale (pas de lucky deal)
  FOR _slot, _uid, _is_bot IN
    SELECT slot, user_id, is_bot FROM public.rami_participants WHERE game_id=_game_id ORDER BY slot
  LOOP
    IF _slot = _first_slot THEN _card_count := 14; ELSE _card_count := 13; END IF;
    _hand := _deck[1:_card_count];
    _deck := _deck[_card_count+1:array_length(_deck,1)];
    _key := CASE WHEN COALESCE(_is_bot,false) THEN 'bot:'||_slot::text ELSE _uid::text END;
    _hands := _hands || jsonb_build_object(_key, to_jsonb(_hand));
    UPDATE public.rami_participants SET hand_count = _card_count, lives = 3
      WHERE game_id=_game_id AND slot=_slot;
  END LOOP;

  -- Joker aléatoire
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
    turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 90) || ' seconds')::interval
    WHERE id=_game_id;

  PERFORM public._rami_autoplay_bots(_game_id);
END
$function$;
REVOKE ALL ON FUNCTION public.rami_start(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_start(uuid) TO authenticated;


-- ═══ 2. Fix rami_discard: accept turn_phase='play' ═══
CREATE OR REPLACE FUNCTION public.rami_discard(_game_id uuid, _card integer)
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
  _new_hand int[];
  _c int;
  _discard_arr int[];
  _discard_by text[];
  _key text;
  _action_log jsonb;
  _won boolean;
  _payout numeric;
  _comm numeric;
  _winner_name text;
  _seven boolean;
  _cfg record;
  _parts int[];
  _next int;
  _next_is_bot boolean;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  -- FIX: accept 'play' phase (after drawing), not 'draw'
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _seven := COALESCE(_g.seven_cards, false);
  _key := _uid::text;
  _state := public._rami_normalize_state(_g.state);
  _hand := COALESCE(public._rami_jarr(_state->'hands'->_key), ARRAY[]::int[]);
  _new_hand := _hand;

  IF NOT (_card = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte absente de la main'; END IF;
  _new_hand := public._rami_remove_one(_new_hand, _card);

  _discard_arr := COALESCE(public._rami_jarr(_state->'discard'), ARRAY[]::int[]);
  _discard_arr := ARRAY(SELECT x FROM unnest(_discard_arr) x WHERE x IS NOT NULL);
  _discard_arr := array_append(_discard_arr, _card);

  IF _state ? 'discard_by' AND _state->'discard_by' IS NOT NULL THEN
    _discard_by := ARRAY(SELECT elem::text FROM jsonb_array_elements_text(_state->'discard_by') elem WHERE elem IS NOT NULL);
  ELSE
    _discard_by := ARRAY[]::text[];
  END IF;
  _discard_by := array_append(_discard_by, _key);

  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
  _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);

  _action_log := COALESCE(_state->'action_log', '[]'::jsonb) ||
    jsonb_build_object('t', 'discard', 'p', _key, 'card', _card, 'ts', extract(epoch from now())::bigint);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  UPDATE public.rami_participants
     SET hand_count=COALESCE(array_length(_new_hand, 1), 0)
   WHERE game_id=_game_id AND user_id=_uid;

  IF COALESCE(array_length(_new_hand, 1), 0) = 0 THEN
    _won := public._rami_check_win(_state, _key, _seven);
    IF _won THEN
      SELECT COALESCE(pseudo, 'Joueur') INTO _winner_name FROM public.profiles WHERE id=_uid;
      _comm := round(_g.pot * (_g.commission_pct / 2.0) / 100.0, 0);
      _payout := _g.pot - _comm;
      UPDATE public.profiles SET balance_ar=COALESCE(balance_ar, balance)+_payout WHERE id=_uid;
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
           turn_deadline=now() + (COALESCE(_cfg.turn_timer_seconds, 90) || ' seconds')::interval,
           updated_at=now()
     WHERE id=_game_id;
    RETURN jsonb_build_object('won', false);
  END IF;
END
$function$;
REVOKE ALL ON FUNCTION public.rami_discard(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_discard(uuid, integer) TO authenticated;


-- ═══ 3. rami_start_solo_bot — remove lucky deal, set lives=3 ═══
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

  INSERT INTO public.rami_participants(game_id, user_id, slot, display_name, ready, is_bot, lives)
    VALUES (v_game_id, v_uid, 0, v_name, true, false, 3);

  FOR v_slot IN 1.._max_players - 1 LOOP
    INSERT INTO public.rami_participants(
      game_id, user_id, slot, display_name, ready, is_bot, bot_name, bot_intelligence, lives
    ) VALUES (
      v_game_id, NULL, v_slot, v_bot_names[v_slot], true, true, v_bot_names[v_slot], v_intel, 3
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
    v_hand := v_deck[1:v_card_count];
    v_deck := v_deck[v_card_count+1:array_length(v_deck,1)];
    v_key := CASE WHEN v_slot = 0 THEN v_uid::text ELSE 'bot:' || v_slot::text END;
    v_hands := v_hands || jsonb_build_object(v_key, to_jsonb(v_hand));
    UPDATE public.rami_participants SET hand_count = v_card_count
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
    random_joker = v_rj, turn_deadline = now() + interval '90 seconds'
  WHERE id = v_game_id;

  RETURN v_game_id;
END
$function$;
REVOKE ALL ON FUNCTION public.rami_start_solo_bot(integer, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_start_solo_bot(integer, text, text, text) TO authenticated;


-- ═══ 4. rami_process_expired_turns — timer enforcement with lives ═══
CREATE OR REPLACE FUNCTION public.rami_process_expired_turns()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _g record;
  _state jsonb;
  _slot int;
  _uid uuid;
  _is_bot boolean;
  _key text;
  _lives int;
  _hand int[];
  _card int;
  _discard_arr int[];
  _discard_by text[];
  _action_log jsonb;
  _parts int[];
  _next int;
  _next_is_bot boolean;
  _cfg record;
  _active_count int;
  _winner_slot int;
  _winner_uid uuid;
  _winner_name text;
  _payout numeric;
  _comm numeric;
  _seven boolean;
BEGIN
  SELECT * INTO _cfg FROM public._game_cfg('rami');

  FOR _g IN
    SELECT * FROM public.rami_games
    WHERE status = 'playing'
      AND turn_deadline IS NOT NULL
      AND turn_deadline < now()
  LOOP
    BEGIN
      -- Get current player info
      SELECT slot, user_id, is_bot, lives
        INTO _slot, _uid, _is_bot, _lives
        FROM public.rami_participants
        WHERE game_id = _g.id AND slot = _g.current_turn AND NOT forfeited;

      IF _slot IS NULL THEN
        -- Current player already forfeited, just advance turn
        SELECT array_agg(slot ORDER BY slot) INTO _parts
          FROM public.rami_participants WHERE game_id = _g.id AND NOT forfeited;
        IF COALESCE(array_length(_parts,1),0) <= 1 THEN
          -- Game over
          UPDATE public.rami_games SET status='finished', finished_at=now() WHERE id=_g.id;
          CONTINUE;
        END IF;
        _next := _g.current_turn;
        LOOP
          _next := (_next + 1) % _g.max_players;
          EXIT WHEN _next = ANY(_parts);
        END LOOP;
        UPDATE public.rami_games SET current_turn=_next, turn_phase='draw',
          turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 90) || ' seconds')::interval,
          updated_at=now()
          WHERE id = _g.id;
        CONTINUE;
      END IF;

      -- Decrement life
      _lives := _lives - 1;
      _key := CASE WHEN COALESCE(_is_bot, false) THEN 'bot:' || _slot::text ELSE _uid::text END;
      _state := public._rami_normalize_state(_g.state);
      _seven := COALESCE(_g.seven_cards, false);

      -- Log the timeout
      _action_log := COALESCE(_state->'action_log', '[]'::jsonb) ||
        jsonb_build_object('t', 'timeout', 'p', _key, 'lives', _lives, 'ts', extract(epoch from now())::bigint);

      IF _lives <= 0 THEN
        -- ═══ Auto-forfeit ═══
        UPDATE public.rami_participants SET lives = 0, forfeited = true
          WHERE game_id = _g.id AND slot = _slot;

        _action_log := _action_log || jsonb_build_object('t', 'forfeit', 'p', _key, 'ts', extract(epoch from now())::bigint);
        _state := jsonb_set(_state, '{action_log}', _action_log);

        -- Check remaining players
        SELECT count(*) INTO _active_count
          FROM public.rami_participants WHERE game_id = _g.id AND NOT forfeited;

        IF _active_count <= 1 THEN
          -- Last player wins
          SELECT slot, user_id INTO _winner_slot, _winner_uid
            FROM public.rami_participants WHERE game_id = _g.id AND NOT forfeited LIMIT 1;

          IF _winner_uid IS NOT NULL THEN
            SELECT COALESCE(pseudo, 'Joueur') INTO _winner_name FROM public.profiles WHERE id = _winner_uid;
            _comm := round(_g.pot * (_g.commission_pct / 2.0) / 100.0, 0);
            _payout := _g.pot - _comm;
            UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, 0) + _payout WHERE id = _winner_uid;
            INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
              VALUES (_winner_uid, 'rami_win', _payout, _g.id, 'Win rami (forfeit)');
            UPDATE public.rami_games SET status='finished', winner_id=_winner_uid, winner_name=_winner_name,
              finished_at=now(), state=_state WHERE id=_g.id;
          ELSE
            UPDATE public.rami_games SET status='finished', finished_at=now(), state=_state WHERE id=_g.id;
          END IF;
          CONTINUE;
        END IF;

        -- Advance to next player
        SELECT array_agg(slot ORDER BY slot) INTO _parts
          FROM public.rami_participants WHERE game_id = _g.id AND NOT forfeited;
        _next := _slot;
        LOOP
          _next := (_next + 1) % _g.max_players;
          EXIT WHEN _next = ANY(_parts);
        END LOOP;

        SELECT COALESCE(is_bot, false) INTO _next_is_bot
          FROM public.rami_participants WHERE game_id = _g.id AND slot = _next;

        IF _next_is_bot THEN
          _state := jsonb_set(_state, '{bot_think_until}',
            to_jsonb(to_char(now() + interval '5 seconds', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')), true);
        ELSE
          _state := _state - 'bot_think_until';
        END IF;

        UPDATE public.rami_games SET state=_state, current_turn=_next, turn_phase='draw',
          turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 90) || ' seconds')::interval,
          updated_at=now()
          WHERE id = _g.id;
        CONTINUE;
      END IF;

      -- ═══ Life lost but still alive ═══
      UPDATE public.rami_participants SET lives = _lives
        WHERE game_id = _g.id AND slot = _slot;

      IF _g.turn_phase = 'play' THEN
        -- Player has drawn (14 cards) → auto-discard last card in hand
        _hand := COALESCE(public._rami_jarr(_state->'hands'->_key), ARRAY[]::int[]);
        IF COALESCE(array_length(_hand,1),0) > 0 THEN
          _card := _hand[array_length(_hand,1)]; -- last card = last drawn
          _hand := _hand[1:array_length(_hand,1)-1];

          -- Add to discard pile
          _discard_arr := COALESCE(public._rami_jarr(_state->'discard'), ARRAY[]::int[]);
          _discard_arr := ARRAY(SELECT x FROM unnest(_discard_arr) x WHERE x IS NOT NULL);
          _discard_arr := array_append(_discard_arr, _card);

          IF _state ? 'discard_by' AND _state->'discard_by' IS NOT NULL THEN
            _discard_by := ARRAY(SELECT elem::text FROM jsonb_array_elements_text(_state->'discard_by') elem WHERE elem IS NOT NULL);
          ELSE
            _discard_by := ARRAY[]::text[];
          END IF;
          _discard_by := array_append(_discard_by, _key);

          _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
          _state := jsonb_set(_state, '{discard_by}', to_jsonb(_discard_by), true);
          _state := jsonb_set(_state, ARRAY['hands', _key], to_jsonb(_hand));

          UPDATE public.rami_participants SET hand_count = COALESCE(array_length(_hand,1),0)
            WHERE game_id = _g.id AND slot = _slot;

          _action_log := _action_log || jsonb_build_object('t', 'auto_discard', 'p', _key, 'card', _card, 'ts', extract(epoch from now())::bigint);
        END IF;
      ELSE
        -- Player hasn't drawn → just skip (no draw, no discard)
        _action_log := _action_log || jsonb_build_object('t', 'auto_skip', 'p', _key, 'ts', extract(epoch from now())::bigint);
      END IF;

      -- Advance to next player
      SELECT array_agg(slot ORDER BY slot) INTO _parts
        FROM public.rami_participants WHERE game_id = _g.id AND NOT forfeited;
      _next := _slot;
      LOOP
        _next := (_next + 1) % _g.max_players;
        EXIT WHEN _next = ANY(_parts);
      END LOOP;

      SELECT COALESCE(is_bot, false) INTO _next_is_bot
        FROM public.rami_participants WHERE game_id = _g.id AND slot = _next;

      IF _next_is_bot THEN
        _state := jsonb_set(_state, '{bot_think_until}',
          to_jsonb(to_char(now() + interval '5 seconds', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')), true);
      ELSE
        _state := _state - 'bot_think_until';
      END IF;

      _state := jsonb_set(_state, '{action_log}', _action_log);
      _state := public._rami_normalize_state(_state);

      UPDATE public.rami_games SET state=_state, current_turn=_next, turn_phase='draw',
        turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 90) || ' seconds')::interval,
        updated_at=now()
        WHERE id = _g.id;

    EXCEPTION WHEN OTHERS THEN
      -- Skip this game on error, continue to next
      NULL;
    END;
  END LOOP;
END
$function$;
REVOKE ALL ON FUNCTION public.rami_process_expired_turns() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_process_expired_turns() TO authenticated;
