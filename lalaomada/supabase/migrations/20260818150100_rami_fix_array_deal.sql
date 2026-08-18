-- ============================================================
-- Fix: utilise jsonb[] au lieu de int[][] pour les mains
-- (PostgreSQL ne supporte pas les tableaux 2D non-rectangulaires)
-- ============================================================

CREATE OR REPLACE FUNCTION public.rami_start(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _g public.rami_games; _deck int[]; _i int; _j int; _tmp int;
  _hands jsonb := '{}'::jsonb; _state jsonb; _key text;
  _cfg record; _joker_mode text; _random_joker int;
  _discards jsonb; _action_log jsonb;
  _max int; _max_players int;
  _first_slot int; _slots int[];
  _n int;
  _p_slot int[]; _p_uid uuid[]; _p_isbot boolean[]; _p_key text[];
  _hand_list jsonb[];
  _round int; _p_idx int;
  _drawn_card int;
  _cur_hand int[];
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
    _deck := ARRAY(SELECT generate_series(0, _max-1))
          || ARRAY(SELECT generate_series(56, _max-1+56));
  ELSE
    _deck := ARRAY(SELECT generate_series(0, _max-1))
          || ARRAY(SELECT generate_series(56, _max-1+56))
          || ARRAY(SELECT generate_series(112, _max-1+112));
  END IF;

  FOR _i IN REVERSE array_length(_deck,1)..2 LOOP
    _j := 1 + public._crypto_rand_int(_i);
    _tmp := _deck[_i]; _deck[_i] := _deck[_j]; _deck[_j] := _tmp;
  END LOOP;

  SELECT array_agg(slot ORDER BY slot) INTO _slots FROM public.rami_participants WHERE game_id=_game_id;
  _first_slot := _slots[1 + public._crypto_rand_int(array_length(_slots,1))];

  SELECT array_agg(slot ORDER BY slot),
         array_agg(user_id ORDER BY slot),
         array_agg(COALESCE(is_bot,false) ORDER BY slot)
    INTO _p_slot, _p_uid, _p_isbot
    FROM public.rami_participants WHERE game_id=_game_id;
  _n := array_length(_p_slot, 1);

  _p_key := array_fill(NULL::text, ARRAY[_n]);
  _hand_list := array_fill('[]'::jsonb, ARRAY[_n]);
  FOR _i IN 1.._n LOOP
    _p_key[_i] := CASE WHEN _p_isbot[_i] THEN 'bot:'||_p_slot[_i]::text ELSE _p_uid[_i]::text END;
  END LOOP;

  FOR _round IN 1..13 LOOP
    FOR _p_idx IN 1.._n LOOP
      _drawn_card := _deck[1];
      _deck := _deck[2:array_length(_deck,1)];
      _cur_hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_hand_list[_p_idx]))::int[], ARRAY[]::int[]);
      _cur_hand := array_append(_cur_hand, _drawn_card);
      _hand_list[_p_idx] := to_jsonb(_cur_hand);
    END LOOP;
  END LOOP;

  FOR _p_idx IN 1.._n LOOP
    IF _p_slot[_p_idx] = _first_slot THEN
      _drawn_card := _deck[1];
      _deck := _deck[2:array_length(_deck,1)];
      _cur_hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_hand_list[_p_idx]))::int[], ARRAY[]::int[]);
      _cur_hand := array_append(_cur_hand, _drawn_card);
      _hand_list[_p_idx] := to_jsonb(_cur_hand);
      EXIT;
    END IF;
  END LOOP;

  FOR _i IN 1.._n LOOP
    _hands := _hands || jsonb_build_object(_p_key[_i], _hand_list[_i]);
    UPDATE public.rami_participants
      SET hand_count = jsonb_array_length(_hand_list[_i])
      WHERE game_id=_game_id AND slot=_p_slot[_i];
  END LOOP;

  IF _joker_mode IN ('aleatoire','double') THEN
    _i := 1;
    WHILE _i <= array_length(_deck,1) AND (_deck[_i] % 56) >= 52 LOOP
      _i := _i + 1;
    END LOOP;
    IF _i <= array_length(_deck,1) THEN
      _random_joker := _deck[_i];
      _deck := _deck[1:_i-1] || _deck[_i+1:array_length(_deck,1)];
    END IF;
  END IF;

  _discards := '{}'::jsonb;
  _action_log := jsonb_build_array(
    jsonb_build_object('t','start','ts',extract(epoch from now())::bigint)
  );

  _state := jsonb_build_object(
    'deck', to_jsonb(_deck),
    'discards', _discards,
    'discard', '[]'::jsonb,
    'last_discard_by', null::jsonb,
    'hands', _hands,
    'melds', '[]'::jsonb,
    'action_log', _action_log,
    'refunded', '{}'::jsonb,
    'joker_mode', _joker_mode,
    'first_player', _first_slot,
    'random_joker', CASE WHEN _random_joker IS NULL THEN 'null'::jsonb ELSE to_jsonb(_random_joker) END
  );

  UPDATE public.rami_games SET
    status='playing', state=_state, started_at=now(),
    current_turn=_first_slot, turn_phase='play',
    random_joker=_random_joker,
    turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 90) || ' seconds')::interval
    WHERE id=_game_id;

  PERFORM public._rami_autoplay_bots(_game_id);
END
$function$;
REVOKE ALL ON FUNCTION public.rami_start(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_start(uuid) TO authenticated;


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
  v_max      int;
  v_max_players int;
  v_deck     int[];
  v_i        int;
  v_j        int;
  v_tmp      int;
  v_hands    jsonb := '{}'::jsonb;
  v_rj       int := NULL;
  v_state    jsonb;
  v_first_slot int;
  v_n int;
  v_p_key text[];
  v_hand_list jsonb[];
  v_round int;
  v_p_idx int;
  v_drawn_card int;
  v_cur_hand int[];
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

  v_max_players := _max_players;
  IF v_max_players <= 2 THEN
    v_deck := ARRAY(SELECT generate_series(0, v_max-1))
           || ARRAY(SELECT generate_series(56, v_max-1+56));
  ELSE
    v_deck := ARRAY(SELECT generate_series(0, v_max-1))
           || ARRAY(SELECT generate_series(56, v_max-1+56))
           || ARRAY(SELECT generate_series(112, v_max-1+112));
  END IF;

  FOR v_i IN REVERSE array_length(v_deck,1)..2 LOOP
    v_j := 1 + public._crypto_rand_int(v_i);
    v_tmp := v_deck[v_i]; v_deck[v_i] := v_deck[v_j]; v_deck[v_j] := v_tmp;
  END LOOP;

  v_first_slot := public._crypto_rand_int(v_max_players);

  v_n := v_max_players;
  v_p_key := array_fill(NULL::text, ARRAY[v_n]);
  v_hand_list := array_fill('[]'::jsonb, ARRAY[v_n]);
  FOR v_i IN 0..v_n - 1 LOOP
    v_p_key[v_i + 1] := CASE WHEN v_i = 0 THEN v_uid::text ELSE 'bot:' || v_i::text END;
  END LOOP;

  FOR v_round IN 1..13 LOOP
    FOR v_p_idx IN 1..v_n LOOP
      v_drawn_card := v_deck[1];
      v_deck := v_deck[2:array_length(v_deck,1)];
      v_cur_hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(v_hand_list[v_p_idx]))::int[], ARRAY[]::int[]);
      v_cur_hand := array_append(v_cur_hand, v_drawn_card);
      v_hand_list[v_p_idx] := to_jsonb(v_cur_hand);
    END LOOP;
  END LOOP;

  FOR v_p_idx IN 1..v_n LOOP
    IF (v_p_idx - 1) = v_first_slot THEN
      v_drawn_card := v_deck[1];
      v_deck := v_deck[2:array_length(v_deck,1)];
      v_cur_hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(v_hand_list[v_p_idx]))::int[], ARRAY[]::int[]);
      v_cur_hand := array_append(v_cur_hand, v_drawn_card);
      v_hand_list[v_p_idx] := to_jsonb(v_cur_hand);
      EXIT;
    END IF;
  END LOOP;

  FOR v_i IN 1..v_n LOOP
    v_hands := v_hands || jsonb_build_object(v_p_key[v_i], v_hand_list[v_i]);
    UPDATE public.rami_participants SET hand_count = jsonb_array_length(v_hand_list[v_i])
      WHERE game_id = v_game_id AND slot = v_i - 1;
  END LOOP;

  IF _joker_mode IN ('aleatoire','double') THEN
    v_i := 1;
    WHILE v_i <= array_length(v_deck,1) AND (v_deck[v_i] % 56) >= 52 LOOP
      v_i := v_i + 1;
    END LOOP;
    IF v_i <= array_length(v_deck,1) THEN
      v_rj := v_deck[v_i];
      v_deck := v_deck[1:v_i-1] || v_deck[v_i+1:array_length(v_deck,1)];
    END IF;
  END IF;

  v_state := jsonb_build_object(
    'deck',           to_jsonb(v_deck),
    'discards',       '{}'::jsonb,
    'discard',        '[]'::jsonb,
    'last_discard_by', null::jsonb,
    'hands',          v_hands,
    'melds',          '[]'::jsonb,
    'first_player',   v_first_slot,
    'joker_mode',     _joker_mode,
    'random_joker',   CASE WHEN v_rj IS NULL THEN 'null'::jsonb ELSE to_jsonb(v_rj) END
  );

  UPDATE public.rami_games SET
    status        = 'playing',
    state         = v_state,
    started_at    = now(),
    current_turn  = v_first_slot,
    turn_phase    = 'play',
    random_joker  = v_rj,
    turn_deadline = now() + interval '90 seconds'
  WHERE id = v_game_id;

  RETURN v_game_id;
END
$function$;
REVOKE ALL ON FUNCTION public.rami_start_solo_bot(integer, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_start_solo_bot(integer, text, text, text) TO authenticated;
