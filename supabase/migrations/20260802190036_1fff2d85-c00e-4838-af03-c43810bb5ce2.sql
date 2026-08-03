-- 1) DISCARD : écrire dans la map "discards" + last_discard_by (au lieu du champ legacy)
CREATE OR REPLACE FUNCTION public.rami_discard(_game_id uuid, _card integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _hand int[]; _new_hand int[]; _pile int[]; _hands jsonb; _discards jsonb;
  _parts int[]; _next int; _cfg record;
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
  _hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[], ARRAY[]::int[]);
  IF NOT (_card = ANY(_hand)) THEN RAISE EXCEPTION 'carte absente'; END IF;
  _new_hand := public._rami_remove_one(_hand,_card);

  _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_uid::text))::int[], ARRAY[]::int[]);
  _pile := array_append(_pile, _card);
  _discards := jsonb_set(COALESCE(_discards,'{}'::jsonb), ARRAY[_uid::text], to_jsonb(_pile), true);

  _hands := jsonb_set(_state->'hands', ARRAY[_uid::text], to_jsonb(_new_hand));
  _state := jsonb_set(_state,'{hands}',_hands);
  _state := jsonb_set(_state,'{discards}',_discards, true);
  _state := jsonb_set(_state,'{last_discard_by}', to_jsonb(_uid::text), true);
  _state := _state - 'discard';

  UPDATE public.rami_participants
     SET hand_count=COALESCE(array_length(_new_hand,1),0)
   WHERE game_id=_game_id AND user_id=_uid;

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

  -- Laisse jouer les bots si c'est leur tour
  BEGIN
    PERFORM public._rami_autoplay_bots(_game_id);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END $function$;

-- 2) DRAW : piocher sur la pile de défausse courante (map normalisée)
CREATE OR REPLACE FUNCTION public.rami_draw(_game_id uuid, _from text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _deck int[]; _pile int[]; _hand int[]; _card int; _hands jsonb; _cfg record;
  _discards jsonb; _last text; _reshuffle jsonb;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL OR _slot <> _g.current_turn THEN RAISE EXCEPTION 'pas ton tour'; END IF;
  IF _g.turn_phase <> 'draw' THEN RAISE EXCEPTION 'déjà pioché'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');

  _state := public._rami_normalize_state(_g.state);
  _discards := public._rami_discards_map(_state);
  _last := public._rami_last_discarder(_state);
  _deck := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'deck'))::int[], ARRAY[]::int[]);
  _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_last))::int[], ARRAY[]::int[]);
  _hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[], ARRAY[]::int[]);

  IF _from = 'discard' THEN
    IF array_length(_pile,1) IS NULL THEN RAISE EXCEPTION 'défausse vide'; END IF;
    _card := _pile[array_length(_pile,1)];
    _pile := _pile[1:array_length(_pile,1)-1];
    IF array_length(_pile,1) IS NULL THEN
      _discards := _discards - _last;
    ELSE
      _discards := jsonb_set(_discards, ARRAY[_last], to_jsonb(_pile), true);
    END IF;
  ELSE
    IF array_length(_deck,1) IS NULL THEN
      _reshuffle := public._rami_reshuffle(_state);
      _deck := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_reshuffle->'deck'))::int[], ARRAY[]::int[]);
      _discards := COALESCE(_reshuffle->'discards','{}'::jsonb);
      IF array_length(_deck,1) IS NULL THEN RAISE EXCEPTION 'plus de cartes'; END IF;
    END IF;
    _card := _deck[1];
    _deck := _deck[2:array_length(_deck,1)];
  END IF;

  _hand := array_append(_hand, _card);
  _hands := jsonb_set(_state->'hands', ARRAY[_uid::text], to_jsonb(_hand));
  _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
  _state := jsonb_set(_state, '{discards}', COALESCE(_discards,'{}'::jsonb), true);
  _state := jsonb_set(_state, '{hands}', _hands);
  _state := _state - 'discard';

  UPDATE public.rami_games
     SET state = _state, turn_phase = 'play',
         turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
         updated_at = now()
   WHERE id = _game_id;

  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_hand,1),0)
   WHERE game_id=_game_id AND user_id=_uid;
END $function$;

-- 3) SOLO BOT : ajout du mode de jeu (bordel / naturel) + état normalisé
CREATE OR REPLACE FUNCTION public.rami_start_solo_bot(
  _max_players integer DEFAULT 2,
  _difficulty text DEFAULT 'medium',
  _joker_mode text DEFAULT 'classique',
  _game_mode text DEFAULT 'bordel'
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_game_id uuid; v_code text; v_name text; v_intel int;
  v_paused boolean; v_banned boolean; v_slot int;
  v_bot_names text[] := ARRAY['Bot Rija','Bot Naina','Bot Hery','Bot Voara'];
  v_max int; v_deck int[]; v_i int; v_j int; v_tmp int;
  v_hands jsonb := '{}'::jsonb; v_hand int[]; v_key text;
  v_rj int := NULL; v_top int; v_first int; v_state jsonb;
BEGIN
  PERFORM public._assert_solo_bot_enabled();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _max_players < 2 OR _max_players > 4 THEN RAISE EXCEPTION 'Joueurs invalides (2-4)'; END IF;
  IF _joker_mode NOT IN ('sans','aleatoire','classique','double') THEN _joker_mode := 'classique'; END IF;
  IF _game_mode NOT IN ('bordel','naturel') THEN _game_mode := 'bordel'; END IF;

  SELECT paused INTO v_paused FROM public.app_settings WHERE id=1;
  IF COALESCE(v_paused,false) THEN RAISE EXCEPTION 'Application en pause'; END IF;

  SELECT banned, COALESCE(pseudo,'Joueur') INTO v_banned, v_name FROM public.profiles WHERE id=v_uid;
  IF COALESCE(v_banned,false) THEN RAISE EXCEPTION 'Compte banni'; END IF;

  CASE lower(_difficulty)
    WHEN 'easy' THEN v_intel := 30;
    WHEN 'hard' THEN v_intel := 95;
    ELSE v_intel := 70;
  END CASE;

  v_code := public._rami_gen_code();

  INSERT INTO public.rami_games (
    room_code, is_private, stake, max_players, commission_pct, created_by, pot, joker_mode, game_mode, status
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
  v_deck := ARRAY(SELECT generate_series(0, v_max-1));
  FOR v_i IN REVERSE v_max..2 LOOP
    v_j := 1 + floor(random()*v_i)::int;
    v_tmp := v_deck[v_i]; v_deck[v_i] := v_deck[v_j]; v_deck[v_j] := v_tmp;
  END LOOP;

  FOR v_slot IN 0.._max_players - 1 LOOP
    v_hand := v_deck[1:13];
    v_deck := v_deck[14:array_length(v_deck,1)];
    v_key := CASE WHEN v_slot = 0 THEN v_uid::text ELSE 'bot:' || v_slot::text END;
    v_hands := v_hands || jsonb_build_object(v_key, to_jsonb(v_hand));
    UPDATE public.rami_participants SET hand_count = 13 WHERE game_id = v_game_id AND slot = v_slot;
  END LOOP;

  IF _joker_mode IN ('aleatoire','double') THEN
    v_i := 1;
    WHILE v_i <= array_length(v_deck,1) AND v_deck[v_i] >= 52 LOOP v_i := v_i + 1; END LOOP;
    IF v_i <= array_length(v_deck,1) THEN
      v_rj := v_deck[v_i];
      v_deck := v_deck[1:v_i-1] || v_deck[v_i+1:array_length(v_deck,1)];
    END IF;
  END IF;

  v_top := v_deck[1];
  v_deck := v_deck[2:array_length(v_deck,1)];
  v_first := floor(random() * _max_players)::int;

  v_state := jsonb_build_object(
    'deck', to_jsonb(v_deck),
    'discards', jsonb_build_object('_seed', jsonb_build_array(v_top)),
    'last_discard_by', '_seed',
    'hands', v_hands,
    'melds', '[]'::jsonb,
    'first_player', v_first
  );

  UPDATE public.rami_games SET
    status = 'playing', state = v_state, started_at = now(),
    current_turn = v_first, turn_phase = 'draw', random_joker = v_rj,
    turn_deadline = now() + interval '60 seconds'
  WHERE id = v_game_id;

  PERFORM public._rami_autoplay_bots(v_game_id);
  RETURN v_game_id;
END $function$;

REVOKE ALL ON FUNCTION public.rami_start_solo_bot(integer, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_start_solo_bot(integer, text, text, text) TO authenticated;

-- 4) rami_add_bot : difficulté paramétrable
CREATE OR REPLACE FUNCTION public.rami_add_bot(_game_id uuid, _bot_name text DEFAULT NULL, _difficulty text DEFAULT 'medium')
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_uid uuid := auth.uid(); g public.rami_games; v_is_admin boolean;
  v_slot int; v_count int; v_name text;
  v_bot_names text[] := ARRAY['Bot Rija','Bot Naina','Bot Hery','Bot Voara','Bot Miora','Bot Tahina'];
  v_intel int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO g FROM public.rami_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'partie introuvable'; END IF;
  IF g.status <> 'waiting' THEN RAISE EXCEPTION 'partie déjà commencée'; END IF;

  v_is_admin := public.has_role(v_uid, 'admin'::app_role);
  IF NOT v_is_admin AND g.created_by <> v_uid THEN
    RAISE EXCEPTION 'seul l''hôte peut ajouter un bot';
  END IF;
  IF NOT v_is_admin AND g.stake > 0 THEN
    RAISE EXCEPTION 'les bots ne sont autorisés qu''en partie gratuite';
  END IF;

  CASE lower(COALESCE(_difficulty,'medium'))
    WHEN 'easy' THEN v_intel := 30;
    WHEN 'hard' THEN v_intel := 95;
    ELSE v_intel := 70;
  END CASE;

  SELECT count(*) INTO v_count FROM public.rami_participants WHERE game_id = _game_id;
  IF v_count >= g.max_players THEN RAISE EXCEPTION 'partie pleine'; END IF;

  SELECT s.slot INTO v_slot
  FROM generate_series(0, g.max_players - 1) s(slot)
  WHERE s.slot NOT IN (SELECT slot FROM public.rami_participants WHERE game_id = _game_id)
  ORDER BY s.slot LIMIT 1;

  v_name := COALESCE(NULLIF(_bot_name,''), v_bot_names[1 + (v_slot % array_length(v_bot_names,1))]);

  INSERT INTO public.rami_participants(
    game_id, user_id, slot, display_name, ready, is_bot, bot_name, bot_intelligence, hand_count
  ) VALUES (_game_id, NULL, v_slot, v_name, true, true, v_name, v_intel, 0);

  IF (SELECT count(*) FROM public.rami_participants WHERE game_id = _game_id) = g.max_players
     AND (SELECT count(*) FROM public.rami_participants WHERE game_id = _game_id AND NOT ready) = 0 THEN
    PERFORM public.rami_start(_game_id);
  END IF;
END $function$;

REVOKE ALL ON FUNCTION public.rami_add_bot(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_add_bot(uuid, text, text) TO authenticated;