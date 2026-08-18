-- ═══ Fix: rami_start_solo_bot doit utiliser 2 paquets (104 cartes) ═══
-- La migration 20260815042000 a écrasé le fix 20260810210000 qui utilisait 2 paquets.
-- Sans 2 paquets, avec 4 joueurs × 13 cartes = 52, la pioche est vide dès le départ.

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
  v_first    int;
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
  v_first := floor(random() * _max_players)::int;

  v_state := jsonb_build_object(
    'deck',           to_jsonb(v_deck),
    'discard',        jsonb_build_array(v_top),
    'discards',       jsonb_build_object('_seed', jsonb_build_array(v_top)),
    'last_discard_by', '_seed',
    'hands',          v_hands,
    'melds',          '[]'::jsonb,
    'first_player',   v_first
  );

  UPDATE public.rami_games SET
    status = 'playing', state = v_state, started_at = now(),
    current_turn = v_first, turn_phase = 'draw',
    random_joker = v_rj,
    turn_deadline = now() + interval '60 seconds'
  WHERE id = v_game_id;

  -- Si le premier joueur est un bot, déclencher le bot
  IF v_first > 0 THEN
    PERFORM public._rami_autoplay_bots(v_game_id);
  END IF;

  RETURN v_game_id;
END $function$;
