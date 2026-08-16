-- ═══ Fix 1: Le 1er joueur est toujours l'humain (slot 0) ═══
-- Fix 2: Le bot ajoute ses actions à action_log
-- Fix 3: La pioche sur défausse utilise toujours le bon tas

CREATE OR REPLACE FUNCTION public.rami_start_solo_bot(
  _max_players integer DEFAULT 2,
  _difficulty  text DEFAULT 'medium',
  _joker_mode  text DEFAULT 'classique',
  _game_mode   text DEFAULT 'bordel'
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
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
  v_size     int;
  v_hands    jsonb := '{}'::jsonb;
  v_hand     int[];
  v_key      text;
  v_rj       int := NULL;
  v_top      int;
  v_state    jsonb;
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

  -- ═══ DEUX PAQUETS : 0..v_max-1 et 56..56+v_max-1 (104 ou 112 cartes) ═══
  IF _joker_mode IN ('classique','double') THEN v_max := 56; ELSE v_max := 52; END IF;
  v_deck := ARRAY(SELECT generate_series(0, v_max - 1))
         || ARRAY(SELECT 56 + generate_series(0, v_max - 1));
  v_size := array_length(v_deck, 1);

  -- Mélange Fisher-Yates
  FOR v_i IN REVERSE v_size..2 LOOP
    v_j := 1 + floor(random() * v_i)::int;
    v_tmp := v_deck[v_i]; v_deck[v_i] := v_deck[v_j]; v_deck[v_j] := v_tmp;
  END LOOP;

  -- Distribution : 13 cartes par joueur
  FOR v_slot IN 0.._max_players - 1 LOOP
    v_hand := v_deck[1:13];
    v_deck := v_deck[14:array_length(v_deck,1)];
    v_key := CASE WHEN v_slot = 0 THEN v_uid::text ELSE 'bot:' || v_slot::text END;
    v_hands := v_hands || jsonb_build_object(v_key, to_jsonb(v_hand));
    UPDATE public.rami_participants SET hand_count = 13
      WHERE game_id = v_game_id AND slot = v_slot;
  END LOOP;

  -- Joker couleur opposée
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

  v_top   := v_deck[1];
  v_deck  := v_deck[2:array_length(v_deck,1)];

  -- ═══ L'HUMAIN EST TOUJOURS LE 1ER JOUEUR ═══
  v_state := jsonb_build_object(
    'deck',           to_jsonb(v_deck),
    'discard',        jsonb_build_array(v_top),
    'discards',       jsonb_build_object('_seed', jsonb_build_array(v_top)),
    'last_discard_by', '_seed',
    'hands',          v_hands,
    'melds',          '[]'::jsonb,
    'first_player',   0,
    'action_log',     '[]'::jsonb
  );

  UPDATE public.rami_games SET
    status = 'playing', state = v_state, started_at = now(),
    current_turn = 0, turn_phase = 'draw',
    random_joker = v_rj,
    turn_deadline = now() + interval '60 seconds'
  WHERE id = v_game_id;

  -- Pas de bots à déclencher : l'humain joue en 1er
  RETURN v_game_id;
END $function$;

-- ═══ Fix: rami_draw — pioche sur défausse toujours fiable ═══
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
    -- Trouver la bonne défausse : d'abord last_discard_by, sinon n'importe quelle pile
    _last_by := COALESCE(_state->>'last_discard_by', '_seed');
    _pile := COALESCE(public._rami_jarr(_discards->_last_by), ARRAY[]::int[]);
    IF array_length(_pile,1) IS NULL THEN
      -- last_discard_by pointe vers une pile vide, chercher une autre pile
      FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
        _pile := public._rami_jarr(_v);
        IF array_length(_pile,1) IS NOT NULL THEN
          _last_by := _k;
          EXIT;
        END IF;
      END LOOP;
    END IF;
    IF array_length(_pile,1) IS NULL THEN RAISE EXCEPTION 'défausse vide'; END IF;

    -- Prendre la carte du dessus
    _card := _pile[array_length(_pile,1)];
    _pile := _pile[1:array_length(_pile,1)-1];
    IF array_length(_pile,1) IS NULL THEN
      _discards := _discards - _last_by;
    ELSE
      _discards := jsonb_set(_discards, ARRAY[_last_by], to_jsonb(_pile));
    END IF;
    -- Mettre à jour last_discard_by vers la pile qui reste
    _state := jsonb_set(_state, '{last_discard_by}', to_jsonb(_last_by), true);
  ELSE
    -- Pioche depuis le deck
    IF COALESCE(array_length(_deck,1),0) = 0 THEN
      -- Reshuffle: prendre toutes les défausses sauf le dessus
      _all := ARRAY[]::int[];
      _new_discards := '{}'::jsonb;
      FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
        _pile := public._rami_jarr(_v);
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
    _deck := _deck[2:array_length(_deck,1)];
  END IF;

  -- Ajouter la carte à la main
  _hand := array_append(_hand, _card);
  _hands := jsonb_set(_state->'hands', ARRAY[_uid::text], to_jsonb(_hand));

  -- Action log
  _action_log := COALESCE(_state->'action_log', '[]'::jsonb) ||
    jsonb_build_object('t', 'draw', 'p', _uid::text, 'from', _from, 'card', _card, 'ts', extract(epoch from now())::bigint);

  -- Sauvegarder l'état
  _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
  _state := jsonb_set(_state, '{discards}', _discards);
  _state := jsonb_set(_state, '{hands}', _hands);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  -- Reconstruire le flat discard array pour compat
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
