-- ============================================================
-- 1. Cleanup: remove the redundant lives-tracking system (rami_process_expired_turns
--    duplicated the already-working turn_skips/rami_tick system + rami_bot_tick_all cron)
-- 2. Fix rami_tick to match exact spec:
--    - draw phase (not yet drawn) → skip turn immediately, NO auto-draw
--    - play phase (already drawn, 14 cards) → auto-discard the LAST DRAWN card (not random)
-- 3. Add joker distribution rule to rami_start / rami_start_solo_bot:
--    - Never deal 3+ jokers to one player
--    - Only 3% chance a player keeps 2 jokers — otherwise redistribute to players with 0/1
-- ============================================================

DROP FUNCTION IF EXISTS public.rami_process_expired_turns();
ALTER TABLE public.rami_participants DROP COLUMN IF EXISTS lives;

-- ═══ 1. Fix rami_tick ═══
CREATE OR REPLACE FUNCTION public.rami_tick(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _g rami_games; _state jsonb; _uid uuid; _is_bot boolean; _slot int;
  _hand int[]; _new_hand int[];
  _card int; _next int; _cfg record;
  _skips int; _pkey text;
  _discard_arr int[];
  _discard_by text[];
  _think text;
  _max_lives int;
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RETURN; END IF;

  SELECT user_id, is_bot, slot INTO _uid, _is_bot, _slot
    FROM rami_participants WHERE game_id=_game_id AND slot=_g.current_turn;

  IF COALESCE(_is_bot, false) THEN
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
  _max_lives := COALESCE(_cfg.max_turn_skips, 3);

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

  -- ── Règle absolue : chaque expiration de 90s = 1 vie perdue ──
  _skips := COALESCE((_g.turn_skips->>_pkey)::int, 0) + 1;
  UPDATE rami_games
    SET turn_skips = jsonb_set(COALESCE(turn_skips, '{}'::jsonb), ARRAY[_pkey], to_jsonb(_skips))
    WHERE id = _game_id;

  -- Vérifier élimination (3 vies perdues = forfait auto)
  IF _skips >= _max_lives THEN
    UPDATE rami_participants SET forfeited = true WHERE game_id=_game_id AND user_id=_uid;
    _state := jsonb_set(_state, '{action_log}',
      COALESCE(_state->'action_log','[]'::jsonb) ||
      jsonb_build_object('t','eliminated','p',_pkey,'ts',extract(epoch from now())::bigint));
    UPDATE rami_games SET state=_state, updated_at=now() WHERE id=_game_id;

    IF (SELECT count(*) FROM rami_participants WHERE game_id=_game_id AND NOT forfeited) <= 1 THEN
      DECLARE _win uuid; _winner_name text; _payout numeric; BEGIN
        SELECT user_id INTO _win FROM rami_participants WHERE game_id=_game_id AND NOT forfeited LIMIT 1;
        IF _win IS NOT NULL THEN
          SELECT COALESCE(pseudo, 'Joueur') INTO _winner_name FROM public.profiles WHERE id=_win;
          _payout := _g.pot * (100 - _g.commission_pct) / 100;
          UPDATE profiles SET balance_ar = COALESCE(balance_ar, 0) + _payout WHERE id=_win;
          INSERT INTO transactions(user_id,type,amount,ref_id,note)
            VALUES (_win,'rami_win', _payout, _game_id, 'Rami win (adversaire éliminé)');
        END IF;
        UPDATE rami_games SET status='finished', winner_id=_win, winner_name=_winner_name, finished_at=now(), state=_state WHERE id=_game_id;
        RETURN;
      END;
    ELSE
      _next := _g.current_turn;
      LOOP
        _next := (_next + 1) % _g.max_players;
        EXIT WHEN _next IN (SELECT slot FROM rami_participants WHERE game_id=_game_id AND NOT forfeited);
      END LOOP;
      DECLARE _next_is_bot boolean; BEGIN
        SELECT COALESCE(is_bot, false) INTO _next_is_bot
          FROM rami_participants WHERE game_id=_game_id AND slot=_next;
        IF _next_is_bot THEN
          _state := jsonb_set(_state, '{bot_think_until}',
            to_jsonb(to_char(now() + interval '5 seconds', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')), true);
        ELSE
          _state := _state - 'bot_think_until';
        END IF;
      END;
      _state := public._rami_normalize_state(_state);
      UPDATE rami_games SET state=_state, current_turn=_next, turn_phase='draw',
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
        updated_at=now() WHERE id=_game_id;
      PERFORM public._rami_autoplay_bots(_game_id);
      RETURN;
    END IF;
  END IF;

  -- ── Phase DRAW : le joueur n'a pas encore pioché → tour passé automatiquement, SANS piocher ──
  IF _g.turn_phase = 'draw' THEN
    _next := _g.current_turn;
    LOOP
      _next := (_next + 1) % _g.max_players;
      EXIT WHEN _next IN (SELECT slot FROM rami_participants WHERE game_id=_game_id AND NOT forfeited);
    END LOOP;
    DECLARE _next_is_bot2 boolean; BEGIN
      SELECT COALESCE(is_bot, false) INTO _next_is_bot2
        FROM rami_participants WHERE game_id=_game_id AND slot=_next;
      IF _next_is_bot2 THEN
        _state := jsonb_set(_state, '{bot_think_until}',
          to_jsonb(to_char(now() + interval '5 seconds', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')), true);
      ELSE
        _state := _state - 'bot_think_until';
      END IF;
    END;
    _state := public._rami_normalize_state(_state);
    UPDATE rami_games SET state=_state, current_turn=_next, turn_phase='draw',
      turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
      updated_at=now() WHERE id=_game_id;
    PERFORM public._rami_autoplay_bots(_game_id);
    RETURN;
  END IF;

  -- ── Phase PLAY : le joueur a déjà pioché (14 cartes) → défausse auto de la DERNIÈRE carte tirée ──
  IF array_length(_hand, 1) IS NULL THEN RETURN; END IF;
  _card := _hand[array_length(_hand, 1)]; -- dernière carte en main = dernière carte tirée
  _new_hand := _hand[1:array_length(_hand,1)-1];
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
END
$function$;
REVOKE ALL ON FUNCTION public.rami_tick(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_tick(uuid) TO authenticated;


-- ═══ 2. rami_start with joker distribution rule ═══
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
  -- joker distribution rule
  _n int;
  _p_slot int[]; _p_uid uuid[]; _p_isbot boolean[]; _p_key text[];
  _hand_list jsonb[];
  _joker_ct int[]; _allowed int[]; _excess int[];
  _roll int; _best_j int; _best_score int;
  _hand_i int[]; _hand_j int[]; _joker_card int; _plain_card int; _c int;
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

  -- Collecter les participants dans l'ordre des slots
  SELECT array_agg(slot ORDER BY slot), array_agg(user_id ORDER BY slot), array_agg(COALESCE(is_bot,false) ORDER BY slot)
    INTO _p_slot, _p_uid, _p_isbot
    FROM public.rami_participants WHERE game_id=_game_id;
  _n := array_length(_p_slot, 1);
  _hand_list := array_fill(NULL::jsonb, ARRAY[_n]);
  _p_key := array_fill(NULL::text, ARRAY[_n]);
  _joker_ct := array_fill(0, ARRAY[_n]);
  _allowed := array_fill(0, ARRAY[_n]);

  -- Distribution normale (aléatoire, sans favoritisme)
  FOR _i IN 1.._n LOOP
    _p_key[_i] := CASE WHEN _p_isbot[_i] THEN 'bot:'||_p_slot[_i]::text ELSE _p_uid[_i]::text END;
    IF _p_slot[_i] = _first_slot THEN _card_count := 14; ELSE _card_count := 13; END IF;
    _hand := _deck[1:_card_count];
    _deck := _deck[_card_count+1:array_length(_deck,1)];
    _hand_list[_i] := to_jsonb(_hand);
  END LOOP;

  -- ── Règle jokers : jamais 3+ jokers pour un joueur, 3% de chance pour en garder 2 ──
  IF _joker_mode IN ('classique','double') THEN
    FOR _i IN 1.._n LOOP
      _hand := ARRAY(SELECT jsonb_array_elements_text(_hand_list[_i]))::int[];
      _joker_ct[_i] := 0;
      FOREACH _c IN ARRAY _hand LOOP
        IF (_c % 56) >= 52 THEN _joker_ct[_i] := _joker_ct[_i] + 1; END IF;
      END LOOP;
    END LOOP;

    _allowed := array_fill(0, ARRAY[_n]);
    _excess := array_fill(0, ARRAY[_n]);
    FOR _i IN 1.._n LOOP
      IF _joker_ct[_i] >= 2 THEN
        _roll := public._crypto_rand_int(100);
        IF _roll < 3 THEN _allowed[_i] := 2; ELSE _allowed[_i] := 1; END IF;
      ELSE
        _allowed[_i] := _joker_ct[_i];
      END IF;
      _excess[_i] := greatest(0, _joker_ct[_i] - _allowed[_i]);
    END LOOP;

    -- FIX: use a fixed excess counter (snapshot), not a live recheck against
    -- allowed[j] — otherwise players who just RECEIVED a redistributed joker
    -- (whose original allowed=0) get it stripped away again in a cascade.
    FOR _i IN 1.._n LOOP
      WHILE _excess[_i] > 0 LOOP
        _best_j := NULL; _best_score := 99;
        FOR _j IN 1.._n LOOP
          IF _j <> _i AND _joker_ct[_j] < 2 THEN
            IF _joker_ct[_j] < _best_score THEN _best_score := _joker_ct[_j]; _best_j := _j; END IF;
          END IF;
        END LOOP;
        IF _best_j IS NULL THEN EXIT; END IF;

        _hand_i := ARRAY(SELECT jsonb_array_elements_text(_hand_list[_i]))::int[];
        _hand_j := ARRAY(SELECT jsonb_array_elements_text(_hand_list[_best_j]))::int[];

        _joker_card := NULL;
        FOREACH _c IN ARRAY _hand_i LOOP
          IF (_c % 56) >= 52 THEN _joker_card := _c; EXIT; END IF;
        END LOOP;
        _plain_card := NULL;
        FOREACH _c IN ARRAY _hand_j LOOP
          IF (_c % 56) < 52 THEN _plain_card := _c; EXIT; END IF;
        END LOOP;
        IF _joker_card IS NULL OR _plain_card IS NULL THEN EXIT; END IF;

        _hand_i := public._rami_remove_one(_hand_i, _joker_card);
        _hand_i := array_append(_hand_i, _plain_card);
        _hand_j := public._rami_remove_one(_hand_j, _plain_card);
        _hand_j := array_append(_hand_j, _joker_card);
        _hand_list[_i] := to_jsonb(_hand_i);
        _hand_list[_best_j] := to_jsonb(_hand_j);
        _joker_ct[_i] := _joker_ct[_i] - 1;
        _joker_ct[_best_j] := _joker_ct[_best_j] + 1;
        _excess[_i] := _excess[_i] - 1;
      END LOOP;
    END LOOP;
  END IF;

  -- Finaliser _hands jsonb + mettre à jour hand_count
  FOR _i IN 1.._n LOOP
    _hands := _hands || jsonb_build_object(_p_key[_i], _hand_list[_i]);
    UPDATE public.rami_participants
      SET hand_count = jsonb_array_length(_hand_list[_i])
      WHERE game_id=_game_id AND slot=_p_slot[_i];
  END LOOP;

  -- Joker aléatoire (mode 'aleatoire'/'double')
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


-- ═══ 3. rami_start_solo_bot with joker distribution rule ═══
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
  -- joker distribution rule
  v_n int;
  v_hand_list jsonb[];
  v_p_key text[];
  v_joker_ct int[]; v_allowed int[]; v_excess int[];
  v_roll int; v_best_j int; v_best_score int;
  v_hand_i int[]; v_hand_j int[]; v_joker_card int; v_plain_card int; v_c int;
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

  v_n := v_max_players;
  v_hand_list := array_fill(NULL::jsonb, ARRAY[v_n]);
  v_p_key := array_fill(NULL::text, ARRAY[v_n]);
  v_joker_ct := array_fill(0, ARRAY[v_n]);
  v_allowed := array_fill(0, ARRAY[v_n]);

  -- Distribution normale (slot 0..n-1 → index 1..n)
  FOR v_slot IN 0..v_max_players - 1 LOOP
    v_i := v_slot + 1;
    v_p_key[v_i] := CASE WHEN v_slot = 0 THEN v_uid::text ELSE 'bot:' || v_slot::text END;
    IF v_slot = v_first_slot THEN v_card_count := 14; ELSE v_card_count := 13; END IF;
    v_hand := v_deck[1:v_card_count];
    v_deck := v_deck[v_card_count+1:array_length(v_deck,1)];
    v_hand_list[v_i] := to_jsonb(v_hand);
  END LOOP;

  -- ── Règle jokers : jamais 3+ jokers pour un joueur, 3% de chance pour en garder 2 ──
  IF _joker_mode IN ('classique','double') THEN
    FOR v_i IN 1..v_n LOOP
      v_hand := ARRAY(SELECT jsonb_array_elements_text(v_hand_list[v_i]))::int[];
      v_joker_ct[v_i] := 0;
      FOREACH v_c IN ARRAY v_hand LOOP
        IF (v_c % 56) >= 52 THEN v_joker_ct[v_i] := v_joker_ct[v_i] + 1; END IF;
      END LOOP;
    END LOOP;

    v_allowed := array_fill(0, ARRAY[v_n]);
    v_excess := array_fill(0, ARRAY[v_n]);
    FOR v_i IN 1..v_n LOOP
      IF v_joker_ct[v_i] >= 2 THEN
        v_roll := public._crypto_rand_int(100);
        IF v_roll < 3 THEN v_allowed[v_i] := 2; ELSE v_allowed[v_i] := 1; END IF;
      ELSE
        v_allowed[v_i] := v_joker_ct[v_i];
      END IF;
      v_excess[v_i] := greatest(0, v_joker_ct[v_i] - v_allowed[v_i]);
    END LOOP;

    FOR v_i IN 1..v_n LOOP
      WHILE v_excess[v_i] > 0 LOOP
        v_best_j := NULL; v_best_score := 99;
        FOR v_j IN 1..v_n LOOP
          IF v_j <> v_i AND v_joker_ct[v_j] < 2 THEN
            IF v_joker_ct[v_j] < v_best_score THEN v_best_score := v_joker_ct[v_j]; v_best_j := v_j; END IF;
          END IF;
        END LOOP;
        IF v_best_j IS NULL THEN EXIT; END IF;

        v_hand_i := ARRAY(SELECT jsonb_array_elements_text(v_hand_list[v_i]))::int[];
        v_hand_j := ARRAY(SELECT jsonb_array_elements_text(v_hand_list[v_best_j]))::int[];

        v_joker_card := NULL;
        FOREACH v_c IN ARRAY v_hand_i LOOP
          IF (v_c % 56) >= 52 THEN v_joker_card := v_c; EXIT; END IF;
        END LOOP;
        v_plain_card := NULL;
        FOREACH v_c IN ARRAY v_hand_j LOOP
          IF (v_c % 56) < 52 THEN v_plain_card := v_c; EXIT; END IF;
        END LOOP;
        IF v_joker_card IS NULL OR v_plain_card IS NULL THEN EXIT; END IF;

        v_hand_i := public._rami_remove_one(v_hand_i, v_joker_card);
        v_hand_i := array_append(v_hand_i, v_plain_card);
        v_hand_j := public._rami_remove_one(v_hand_j, v_plain_card);
        v_hand_j := array_append(v_hand_j, v_joker_card);
        v_hand_list[v_i] := to_jsonb(v_hand_i);
        v_hand_list[v_best_j] := to_jsonb(v_hand_j);
        v_joker_ct[v_i] := v_joker_ct[v_i] - 1;
        v_joker_ct[v_best_j] := v_joker_ct[v_best_j] + 1;
        v_excess[v_i] := v_excess[v_i] - 1;
      END LOOP;
    END LOOP;
  END IF;

  -- Finaliser v_hands + hand_count
  FOR v_i IN 1..v_n LOOP
    v_hands := v_hands || jsonb_build_object(v_p_key[v_i], v_hand_list[v_i]);
    UPDATE public.rami_participants SET hand_count = jsonb_array_length(v_hand_list[v_i])
      WHERE game_id = v_game_id AND slot = v_i - 1;
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
