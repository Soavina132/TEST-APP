-- ════════════════════════════════════════════════════════════════════
-- Règle "7 Cartes" + Victoire "Mode Sans Jokers" (7 PUR + 3 + 3 = 13)
--
-- A. 7 CARTES — PUR conditionnel :
--    • seven_cards = true  → 7 cartes PUR (pas de Joker), tout mode confondu
--    • seven_cards = false + mode 'sans'  → 7 cartes PUR (pas de Joker dans le mode)
--    • seven_cards = false + autre mode  → Jokers autorisés sur les 7 cartes
--
-- B. VICTOIRE MODE SANS JOKERS :
--    13 cartes = 1 combinaison PUR de 7 + 2 groupes de 3 (Tri ou Escalier)
--    Toutes les partitions possibles sont testées.
-- ════════════════════════════════════════════════════════════════════

-- ── 1. Stocker joker_mode + random_joker dans le state JSON ──────────
UPDATE public.rami_games
   SET state = jsonb_set(
        jsonb_set(COALESCE(state, '{}'::jsonb), '{joker_mode}', to_jsonb(joker_mode), true),
        '{random_joker}',
        CASE WHEN random_joker IS NULL THEN 'null'::jsonb ELSE to_jsonb(random_joker) END,
        true
       )
 WHERE status = 'playing';

-- ── 2. _rami_is_seven : paramètre _seven_cards pour PUR conditionnel ─
DROP FUNCTION IF EXISTS public._rami_is_seven(integer[], text, integer);

CREATE OR REPLACE FUNCTION public._rami_is_seven(
  _cards integer[],
  _mode text,
  _rj integer,
  _seven_cards boolean DEFAULT false
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public'
AS $$
DECLARE
  _n int := COALESCE(array_length(_cards, 1), 0);
  i int; j int; k int; m int;
  _three int[]; _four int[]; _t3 text; _t4 text;
  _c int;
BEGIN
  IF _n <> 7 THEN RETURN false; END IF;

  -- PUR : rejeter les Jokers si seven_cards actif OU mode 'sans'
  IF _seven_cards OR _mode = 'sans' THEN
    FOREACH _c IN ARRAY _cards LOOP
      IF public._rami_is_joker(_c, _mode, _rj) THEN RETURN false; END IF;
    END LOOP;
  END IF;

  -- Toutes les partitions 3+4 des 7 cartes
  FOR i IN 1..5 LOOP
  FOR j IN i+1..6 LOOP
  FOR k IN j+1..7 LOOP
    _three := ARRAY[_cards[i], _cards[j], _cards[k]];
    _four  := ARRAY[]::int[];
    FOR m IN 1..7 LOOP
      IF m <> i AND m <> j AND m <> k THEN
        _four := _four || _cards[m];
      END IF;
    END LOOP;

    _t3 := public._rami_meld_type(_three, _mode, _rj);
    _t4 := public._rami_meld_type(_four,  _mode, _rj);

    -- Comp. 1 : Tri + Escalier de 4
    IF _t3 = 'trio' AND _t4 = 'run'   THEN RETURN true; END IF;
    -- Comp. 2 : Tri + Carré
    IF _t3 = 'trio' AND _t4 = 'carre' THEN RETURN true; END IF;
    -- Comp. 3 : Escalier de 3 + Carré
    IF _t3 = 'run'  AND _t4 = 'carre' THEN RETURN true; END IF;
  END LOOP; END LOOP; END LOOP;

  RETURN false;
END $$;

-- ── 3. _rami_meld_type : ajouter le support des 7 cartes + _seven_cards ─
DROP FUNCTION IF EXISTS public._rami_meld_type(integer[], text, integer);

CREATE OR REPLACE FUNCTION public._rami_meld_type(
  _cards integer[],
  _mode text,
  _rj integer,
  _seven_cards boolean DEFAULT false
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public'
AS $function$
DECLARE
  _n int := COALESCE(array_length(_cards,1),0);
  _c int; _cc int; _jokers int := 0; _reals int := 0;
  _rank int := -1; _suit int := -1; _r int; _s int;
  _ranks int[] := ARRAY[]::int[];
  _suits int[] := ARRAY[]::int[];
  _is_set boolean := true; _is_run boolean := true;
  _try_high int; _base int; _ok boolean; _used boolean[]; _idx int;
BEGIN
  IF _n < 3 THEN RETURN NULL; END IF;
  FOREACH _c IN ARRAY _cards LOOP
    IF _c < 0 THEN RETURN NULL; END IF;
    IF public._rami_is_joker(_c,_mode,_rj) THEN
      _jokers := _jokers + 1;
    ELSE
      _cc := _c % 56;
      IF _cc >= 52 THEN RETURN NULL; END IF;
      _reals := _reals + 1;
      _r := _cc % 13; _s := _cc / 13;
      IF _rank = -1 THEN _rank := _r; ELSIF _rank <> _r THEN _is_set := false; END IF;
      IF _suit = -1 THEN _suit := _s; ELSIF _suit <> _s THEN _is_run := false; END IF;
      _ranks := _ranks || _r;
      _suits := _suits || _s;
    END IF;
  END LOOP;
  IF _reals < 2 THEN RETURN NULL; END IF;
  IF _jokers > _reals THEN RETURN NULL; END IF;

  -- 7 cartes : vérifier si c'est une combinaison 'seven' valide
  IF _n = 7 AND public._rami_is_seven(_cards, _mode, _rj, _seven_cards) THEN
    RETURN 'seven';
  END IF;

  -- Deux paquets : un trio/carré ne peut pas contenir deux fois la même couleur
  IF _is_set AND (SELECT count(DISTINCT x) FROM unnest(_suits) x) <> array_length(_suits,1) THEN
    _is_set := false;
  END IF;

  IF _is_set AND _n IN (3,4) THEN
    IF _n = 4 THEN RETURN 'carre'; ELSE RETURN 'trio'; END IF;
  END IF;

  IF _is_run THEN
    FOR _try_high IN 0..1 LOOP
      DECLARE _rs int[] := _ranks; _i int; BEGIN
        IF _try_high = 1 THEN
          FOR _i IN 1..array_length(_rs,1) LOOP
            IF _rs[_i] = 0 THEN _rs[_i] := 13; END IF;
          END LOOP;
        END IF;
        IF (SELECT count(*) FROM (SELECT DISTINCT unnest(_rs)) x) <> array_length(_rs,1) THEN
          CONTINUE;
        END IF;
        FOR _base IN GREATEST(0,(SELECT min(x) FROM unnest(_rs) x) - _jokers)
                  .. LEAST(13 - _n + 1, (SELECT min(x) FROM unnest(_rs) x)) LOOP
          _used := array_fill(false, ARRAY[_n]); _ok := true;
          FOR _i IN 1..array_length(_rs,1) LOOP
            _idx := _rs[_i] - _base + 1;
            IF _idx < 1 OR _idx > _n OR _used[_idx] THEN _ok := false; EXIT; END IF;
            _used[_idx] := true;
          END LOOP;
          IF _ok THEN RETURN 'run'; END IF;
        END LOOP;
      END;
    END LOOP;
  END IF;
  RETURN NULL;
END $function$;

-- ── 4. rami_meld : passer _g.seven_cards à _rami_meld_type ────────────
CREATE OR REPLACE FUNCTION public.rami_meld(_game_id uuid, _cards integer[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  _uid uuid := auth.uid();
  _g public.rami_games;
  _slot int;
  _state jsonb;
  _hand int[];
  _c int;
  _new_hand int[];
  _melds jsonb;
  _type text;
  _action_log jsonb;
  _first_melds jsonb;
  _is_pure boolean;
  _seven_cards boolean;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour de jouer'; END IF;

  _seven_cards := COALESCE(_g.seven_cards, false);
  _type := public._rami_meld_type(_cards, _g.joker_mode, _g.random_joker, _seven_cards);
  IF _type IS NULL THEN RAISE EXCEPTION 'combinaison invalide'; END IF;

  _state := _g.state;
  _hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[], ARRAY[]::int[]);
  _new_hand := _hand;
  FOREACH _c IN ARRAY _cards LOOP
    IF NOT (_c = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte absente de la main'; END IF;
    _new_hand := public._rami_remove_one(_new_hand, _c);
  END LOOP;

  _is_pure := true;
  FOREACH _c IN ARRAY _cards LOOP
    IF public._rami_is_joker(_c, _g.joker_mode, _g.random_joker) THEN
      _is_pure := false;
    END IF;
  END LOOP;

  _melds := COALESCE(_state->'melds', '[]'::jsonb) || jsonb_build_array(
    jsonb_build_object(
      'player', _uid::text,
      'cards', to_jsonb(_cards),
      'type', _type,
      'pure', _is_pure
    )
  );

  _first_melds := COALESCE(_state->'first_melds', '{}'::jsonb);
  IF _first_melds ? _uid::text = false OR _first_melds->_uid::text IS NULL THEN
    _first_melds := jsonb_set(_first_melds, ARRAY[_uid::text], to_jsonb(extract(epoch from now())::bigint), true);
  END IF;

  _action_log := COALESCE(_state->'action_log', '[]'::jsonb) ||
    jsonb_build_object('t', 'meld', 'p', _uid::text, 'type', _type, 'n', array_length(_cards, 1), 'pure', _is_pure, 'ts', extract(epoch from now())::bigint);

  _state := jsonb_set(_state, ARRAY['hands', _uid::text], to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{melds}', _melds);
  _state := jsonb_set(_state, '{first_melds}', _first_melds, true);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand, 1), 0)
    WHERE game_id=_game_id AND user_id=_uid;
END $function$;

-- ── 5. rami_validate_hand : passer _g.seven_cards à _rami_meld_type ───
CREATE OR REPLACE FUNCTION public.rami_validate_hand(_game_id uuid, _layout jsonb, _discard_card integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
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
  _seven_cards boolean;
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
  _seven_cards := _seven;
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

    _type := public._rami_meld_type(_cards, _g.joker_mode, _g.random_joker, _seven_cards);
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
    _won := public._rami_check_win(_state, _uid, _seven);
    IF _won THEN
      SELECT COALESCE(pseudo, 'Joueur') INTO _winner_name FROM public.profiles WHERE id=_uid;
      _comm := round(_g.pot * (_g.commission_pct / 2.0) / 100.0, 0);
      _payout := _g.pot - _comm;
      UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) + _payout WHERE id = _uid;
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

-- ── 6. rami_start : inclure joker_mode + random_joker dans le state ───
CREATE OR REPLACE FUNCTION public.rami_start(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  _g public.rami_games; _deck int[]; _i int; _j int; _tmp int;
  _hands jsonb := '{}'::jsonb; _hand int[]; _state jsonb; _key text;
  _cfg record; _joker_mode text; _random_joker int;
  _discards jsonb; _action_log jsonb;
  _slot int; _uid uuid; _is_bot boolean;
  _is_first boolean := true;
  _card_count int;
  _max int;
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

  IF _joker_mode IN ('classique','double') THEN
    _max := 56;
  ELSE
    _max := 52;
  END IF;

  _max_players := _g.max_players;
  IF _max_players <= 2 THEN
    _deck := ARRAY(SELECT generate_series(0, _max - 1))
          || ARRAY(SELECT 56 + generate_series(0, _max - 1));
  ELSE
    _deck := ARRAY(SELECT generate_series(0, _max - 1))
          || ARRAY(SELECT 56 + generate_series(0, _max - 1))
          || ARRAY(SELECT 112 + generate_series(0, _max - 1));
  END IF;

  FOR _i IN REVERSE array_length(_deck,1)..2 LOOP
    _j := 1 + floor(random()*_i)::int;
    _tmp := _deck[_i]; _deck[_i] := _deck[_j]; _deck[_j] := _tmp;
  END LOOP;

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
    'refunded', '{}'::jsonb,
    'joker_mode', _joker_mode,
    'random_joker', CASE WHEN _random_joker IS NULL THEN 'null'::jsonb ELSE to_jsonb(_random_joker) END
  );

  UPDATE public.rami_games SET
    status='playing', state=_state, started_at=now(),
    current_turn=0, turn_phase='play',
    random_joker=_random_joker,
    turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval
    WHERE id=_game_id;

  PERFORM public._rami_autoplay_bots(_game_id);
END $function$;

-- ── 7. rami_start_solo_bot : inclure joker_mode dans le state ─────────
CREATE OR REPLACE FUNCTION public.rami_start_solo_bot(
  _max_players integer DEFAULT 2,
  _difficulty text DEFAULT 'medium'::text,
  _joker_mode text DEFAULT 'classique'::text,
  _game_mode text DEFAULT 'bordel'::text
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
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

  IF _joker_mode IN ('classique','double') THEN
    v_deck_size := 56;
  ELSE
    v_deck_size := 52;
  END IF;

  v_max_players := _max_players;
  IF v_max_players <= 2 THEN
    v_deck := ARRAY(SELECT generate_series(0, v_deck_size-1)) ||
             ARRAY(SELECT generate_series(56, v_deck_size-1+56));
  ELSE
    v_deck := ARRAY(SELECT generate_series(0, v_deck_size-1)) ||
             ARRAY(SELECT generate_series(56, v_deck_size-1+56)) ||
             ARRAY(SELECT generate_series(112, v_deck_size-1+112));
  END IF;

  FOR v_i IN REVERSE array_length(v_deck,1)..2 LOOP
    v_j := 1 + public._crypto_rand_int(v_i);
    v_tmp := v_deck[v_i]; v_deck[v_i] := v_deck[v_j]; v_deck[v_j] := v_tmp;
  END LOOP;

  v_is_first := true;
  FOR v_slot IN 0..v_max_players - 1 LOOP
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

  IF _joker_mode IN ('aleatoire','double') THEN
    v_rj := public._crypto_rand_int(52);
  END IF;

  v_state := jsonb_build_object(
    'deck',           to_jsonb(v_deck),
    'discards',       '{}'::jsonb,
    'discard',        '[]'::jsonb,
    'last_discard_by', null::jsonb,
    'hands',          v_hands,
    'melds',          '[]'::jsonb,
    'first_player',   0,
    'joker_mode',     _joker_mode,
    'random_joker',   CASE WHEN v_rj IS NULL THEN 'null'::jsonb ELSE to_jsonb(v_rj) END
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

-- ── 8. Helper : _rami_check_win_sans (partition 7+3+3) ───────────────
CREATE OR REPLACE FUNCTION public._rami_check_win_sans(
  _all_cards int[],
  _joker_mode text,
  _rj integer
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public'
AS $$
DECLARE
  _n int := COALESCE(array_length(_all_cards, 1), 0);
  i int; j int; k int; l int; m int; o int; p int;
  x int; a int; b int; c int;
  _seven int[]; _rest int[]; _g3a int[]; _g3b int[];
  _t3a text; _t3b text;
BEGIN
  IF _n < 13 THEN RETURN false; END IF;

  -- Toutes les selections de 7 cartes parmi _n
  FOR i IN 1.._n-6 LOOP
  FOR j IN i+1.._n-5 LOOP
  FOR k IN j+1.._n-4 LOOP
  FOR l IN k+1.._n-3 LOOP
  FOR m IN l+1.._n-2 LOOP
  FOR o IN m+1.._n-1 LOOP
  FOR p IN o+1.._n LOOP
    _seven := ARRAY[_all_cards[i],_all_cards[j],_all_cards[k],_all_cards[l],
                    _all_cards[m],_all_cards[o],_all_cards[p]];

    -- Les 7 cartes doivent former une combinaison 'seven' valide
    -- En mode 'sans', _rami_is_seven rejette toujours les Jokers
    IF NOT public._rami_is_seven(_seven, _joker_mode, _rj, true) THEN
      CONTINUE;
    END IF;

    -- Récupérer les 6 cartes restantes
    _rest := ARRAY[]::int[];
    FOR x IN 1.._n LOOP
      IF x <> i AND x <> j AND x <> k AND x <> l
         AND x <> m AND x <> o AND x <> p THEN
        _rest := _rest || _all_cards[x];
      END IF;
    END LOOP;

    -- Toutes les partitions 3+3 des 6 cartes restantes
    FOR a IN 1..4 LOOP
    FOR b IN a+1..5 LOOP
    FOR c IN b+1..6 LOOP
      _g3a := ARRAY[_rest[a], _rest[b], _rest[c]];
      _g3b := ARRAY[]::int[];
      FOR x IN 1..6 LOOP
        IF x <> a AND x <> b AND x <> c THEN
          _g3b := _g3b || _rest[x];
        END IF;
      END LOOP;

      _t3a := public._rami_meld_type(_g3a, _joker_mode, _rj);
      _t3b := public._rami_meld_type(_g3b, _joker_mode, _rj);

      -- Chaque groupe de 3 doit être un Trio ou un Escalier
      IF _t3a IN ('trio','run') AND _t3b IN ('trio','run') THEN
        RETURN true;
      END IF;
    END LOOP; END LOOP; END LOOP;

  END LOOP; END LOOP; END LOOP; END LOOP; END LOOP; END LOOP; END LOOP;

  RETURN false;
END $$;

-- ── 9. _rami_check_win (3 params) : lire joker_mode depuis le state ───
DROP FUNCTION IF EXISTS public._rami_check_win(jsonb, text, boolean);

CREATE OR REPLACE FUNCTION public._rami_check_win(
  _state jsonb,
  _key text,
  _seven_cards boolean DEFAULT false
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public'
AS $$
DECLARE
  _carre int := 0; _trio int := 0; _run int := 0; _total int := 0;
  _m jsonb; _t text; _cards int[]; _n int;
  _meld_count int := 0;
  _all_cards int[] := ARRAY[]::int[];
  _joker_mode text;
  _rj integer;
  i int;
BEGIN
  FOR _m IN SELECT * FROM jsonb_array_elements(COALESCE(_state->'melds','[]'::jsonb)) LOOP
    IF _m->>'player' = _key THEN
      _t := _m->>'type';
      _cards := ARRAY(SELECT jsonb_array_elements_text(_m->'cards'))::int[];
      _n := COALESCE(array_length(_cards,1),0);
      _total := _total + _n;
      _meld_count := _meld_count + 1;
      _all_cards := _all_cards || _cards;
      IF _t = 'carre' THEN _carre := _carre + 1;
      ELSIF _t = 'trio' THEN _trio := _trio + 1;
      ELSIF _t = 'run'  THEN _run  := _run + 1;
      ELSIF _t = 'seven' THEN _carre := _carre + 1; _trio := _trio + 1; _run := _run + 1;
      END IF;
    END IF;
  END LOOP;

  -- ═══ Mode SANS JOKERS : vérification stricte 7+3+3 ═══
  _joker_mode := COALESCE(_state->>'joker_mode', '');
  _rj := NULLIF(_state->>'random_joker', '')::int;

  IF _joker_mode = 'sans' THEN
    IF _total < 13 THEN RETURN false; END IF;
    -- Aucun Joker ne doit être présent dans les melds
    FOR i IN 1..COALESCE(array_length(_all_cards,1),0) LOOP
      IF public._rami_is_joker(_all_cards[i], _joker_mode, _rj) THEN
        RETURN false;
      END IF;
    END LOOP;
    RETURN public._rami_check_win_sans(_all_cards, _joker_mode, _rj);
  END IF;

  -- ═══ Autres modes : logique existante ═══
  IF _total >= 13 AND _meld_count >= 3 THEN
    RETURN true;
  END IF;
  RETURN false;
END $$;
