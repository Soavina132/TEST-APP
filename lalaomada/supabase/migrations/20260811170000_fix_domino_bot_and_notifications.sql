-- ============================================================
-- Fix: Bot domino automatique + suppression notifications inutiles
-- ============================================================

-- 1. Accélérer le cron domino_tick_all: 1 minute → 5 secondes
DO $$
DECLARE j int;
BEGIN
  SELECT jobid INTO j FROM cron.job WHERE jobname = 'domino_tick_all';
  IF j IS NOT NULL THEN PERFORM cron.unschedule(j); END IF;
END $$;

SELECT cron.schedule('domino_tick_all', '5 seconds',
  $$SELECT CASE WHEN public._has_active_games() THEN public.domino_tick_all() END$$);

-- 2. Fix domino_set_ready: déclencher le bot après le démarrage
CREATE OR REPLACE FUNCTION public.domino_set_ready(_game_id uuid, _ready boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_status text;
  v_count int;
  v_max int;
  v_ready_count int;
  v_has_bot boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  UPDATE public.domino_participants
     SET ready = COALESCE(_ready, false)
   WHERE game_id = _game_id AND user_id = v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not a participant';
  END IF;

  SELECT status::text, max_players
    INTO v_status, v_max
    FROM public.domino_games
   WHERE id = _game_id
   FOR UPDATE;

  IF v_status <> 'open' THEN
    RETURN;
  END IF;

  SELECT count(*), count(*) FILTER (WHERE ready)
    INTO v_count, v_ready_count
    FROM public.domino_participants
   WHERE game_id = _game_id;

  IF v_count = v_max AND v_ready_count = v_max THEN
    PERFORM public._domino_start(_game_id);

    -- Vérifier s'il y a des bots dans la partie
    SELECT EXISTS(SELECT 1 FROM public.domino_participants
      WHERE game_id = _game_id AND is_bot = true AND forfeited = false)
    INTO v_has_bot;

    IF v_has_bot THEN
      -- Attendre la fin du dealing phase (3s) puis déclencher le bot
      PERFORM pg_sleep(3.5);
      PERFORM public.domino_tick(_game_id);
      PERFORM public._domino_bot_loop(_game_id);
    END IF;
  END IF;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.domino_set_ready(uuid, boolean) TO authenticated;

-- 3. Fix _domino_bot_step: supprimer la notification "Bot passe son tour"
CREATE OR REPLACE FUNCTION public._domino_bot_step(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  g record; st jsonb; v_slot int; hand jsonb; le int; re int;
  draw_mode text; is_first_move boolean; first_dbl int; v_rule text;
  i int; j int; a int; b int; tile jsonb; placed jsonb;
  found boolean; found_i int; new_hand jsonb; new_left int; new_right int;
  next_turn int; winner_slot int; stock jsonb; drawn jsonb;
  _cfg record; v_is_bot boolean; phase text; v_think_until timestamptz;
  v_locked_slot int; v_delay_ms int; v_name text;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

  st := g.state;
  phase := COALESCE(st->>'phase', 'play');
  IF phase NOT IN ('play','playing') THEN RETURN; END IF;

  v_slot := g.current_turn;
  SELECT COALESCE(dp.is_bot, false), COALESCE(dp.display_name, 'Bot') INTO v_is_bot, v_name
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id AND dp.slot = v_slot AND dp.forfeited = false;

  IF NOT COALESCE(v_is_bot, false) THEN RETURN; END IF;

  v_think_until := NULLIF(st->>'bot_think_until','')::timestamptz;
  v_locked_slot := NULLIF(st->>'bot_locked_slot','null')::int;

  IF v_think_until IS NULL OR v_locked_slot IS DISTINCT FROM v_slot THEN
    -- 400ms-1000ms think delay
    v_delay_ms := 400 + (floor(random() * 600))::int;
    st := jsonb_set(st, '{bot_locked_slot}', to_jsonb(v_slot), true);
    st := jsonb_set(st, '{bot_think_until}',
                    to_jsonb((now() + make_interval(secs => v_delay_ms / 1000.0))::text), true);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    RETURN;
  END IF;

  IF v_think_until > now() THEN RETURN; END IF;

  st := st - 'bot_think_until' - 'bot_locked_slot';

  hand := COALESCE(st->'hands'->v_slot::text, '[]'::jsonb);
  le := NULLIF(st->>'left_end', 'null')::int;
  re := NULLIF(st->>'right_end', 'null')::int;
  draw_mode := COALESCE(st->>'draw_mode', 'with');
  v_rule := COALESCE(st->>'first_tile_rule', 'libre');
  is_first_move := jsonb_array_length(COALESCE(st->'board', '[]'::jsonb)) = 0;
  first_dbl := NULLIF(st->>'first_move_double', 'null')::int;
  SELECT * INTO _cfg FROM public._game_cfg('domino');

  found := false; found_i := -1;

  IF jsonb_array_length(hand) > 0 THEN
    FOR i IN 0..jsonb_array_length(hand)-1 LOOP
      a := (hand->i->>0)::int; b := (hand->i->>1)::int;
      IF is_first_move THEN
        IF first_dbl IS NOT NULL THEN
          IF a = first_dbl AND b = first_dbl THEN found := true; found_i := i; EXIT; END IF;
        ELSIF v_rule = 'under6' THEN
          IF (a + b) < 6 THEN found := true; found_i := i; EXIT; END IF;
        ELSE
          found := true; found_i := i; EXIT;
        END IF;
      ELSE
        IF a = le OR b = le OR a = re OR b = re THEN found := true; found_i := i; EXIT; END IF;
      END IF;
    END LOOP;
  END IF;

  IF found THEN
    tile := hand->found_i; a := (tile->>0)::int; b := (tile->>1)::int;
    new_hand := '[]'::jsonb;
    FOR j IN 0..jsonb_array_length(hand)-1 LOOP
      IF j <> found_i THEN new_hand := new_hand || jsonb_build_array(hand->j); END IF;
    END LOOP;

    IF is_first_move THEN
      placed := jsonb_build_object('tile', jsonb_build_array(a, b), 'flipped', false);
      st := jsonb_set(st, '{board}', jsonb_build_array(placed), true);
      new_left := a; new_right := b;
    ELSE
      IF a = re OR b = re THEN
        IF a = re THEN
          placed := jsonb_build_object('tile', jsonb_build_array(a, b), 'flipped', false); new_right := b;
        ELSE
          placed := jsonb_build_object('tile', jsonb_build_array(b, a), 'flipped', false); new_right := a;
        END IF;
        new_left := le;
        st := jsonb_set(st, '{board}', COALESCE(st->'board','[]'::jsonb) || jsonb_build_array(placed), true);
      ELSE
        IF a = le THEN
          placed := jsonb_build_object('tile', jsonb_build_array(b, a), 'flipped', false); new_left := b;
        ELSE
          placed := jsonb_build_object('tile', jsonb_build_array(a, b), 'flipped', false); new_left := a;
        END IF;
        new_right := re;
        st := jsonb_set(st, '{board}', jsonb_build_array(placed) || COALESCE(st->'board','[]'::jsonb), true);
      END IF;
    END IF;

    st := jsonb_set(st, ARRAY['hands', v_slot::text], new_hand, true);
    st := jsonb_set(st, '{left_end}', to_jsonb(new_left), true);
    st := jsonb_set(st, '{right_end}', to_jsonb(new_right), true);
    st := jsonb_set(st, '{passes}', to_jsonb(0), true);
    st := jsonb_set(st, '{first_move_double}', 'null'::jsonb, true);
    st := jsonb_set(st, '{phase}', '"play"'::jsonb, true);
    st := st - 'last_pass_by';

    IF jsonb_array_length(new_hand) = 0 THEN
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
      PERFORM public._domino_end_round(_game_id, v_slot);
      RETURN;
    END IF;

    next_turn := public._domino_next_playable_slot(_game_id, v_slot, st);
    IF next_turn IS NULL THEN
      winner_slot := public._domino_lowest_pip_slot(_game_id, st);
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
      PERFORM public._domino_end_round(_game_id, winner_slot);
      RETURN;
    END IF;

    st := public._domino_arm_bot_think(_game_id, next_turn, st);
    UPDATE public.domino_games SET state = st, current_turn = next_turn,
           turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
     WHERE id = _game_id;
    RETURN;
  END IF;

  -- Bot has no playable tile — SANS notification (silencieux)
  stock := COALESCE(st->'stock', '[]'::jsonb);
  IF draw_mode = 'with' AND jsonb_array_length(stock) > 0 THEN
    drawn := stock -> 0; stock := stock - 0;
    hand := hand || jsonb_build_array(drawn);
    st := jsonb_set(st, ARRAY['hands', v_slot::text], hand, true);
    st := jsonb_set(st, '{stock}', stock, true);
    v_delay_ms := 400 + (floor(random() * 600))::int;
    st := jsonb_set(st, '{bot_locked_slot}', to_jsonb(v_slot), true);
    st := jsonb_set(st, '{bot_think_until}',
                    to_jsonb((now() + make_interval(secs => v_delay_ms / 1000.0))::text), true);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    RETURN;
  END IF;

  -- Bot must pass (silencieux, pas de notification)
  st := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1), true);
  st := jsonb_set(st, '{last_pass_by}', to_jsonb(v_slot), true);

  next_turn := public._domino_next_playable_slot(_game_id, v_slot, st);
  IF next_turn IS NULL THEN
    winner_slot := public._domino_lowest_pip_slot(_game_id, st);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_end_round(_game_id, winner_slot);
    RETURN;
  END IF;

  st := public._domino_arm_bot_think(_game_id, next_turn, st);
  UPDATE public.domino_games SET state = st, current_turn = next_turn,
         turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
   WHERE id = _game_id;
END;
$function$;

-- 4. Fix _domino_force_pass: supprimer notifications spam
CREATE OR REPLACE FUNCTION public._domino_force_pass(_game_id uuid, _slot integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  g record; st jsonb; n_players int; next_turn int; winner_slot int; v_name text;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL OR g.status <> 'playing' THEN RETURN; END IF;
  IF g.current_turn <> _slot THEN RETURN; END IF;

  st := g.state;
  SELECT count(*) INTO n_players FROM public.domino_participants WHERE game_id = _game_id;

  st := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1));
  st := jsonb_set(st, '{last_pass_by}', to_jsonb(_slot));

  next_turn := public._domino_next_playable_slot(_game_id, _slot, st);

  IF (st->>'passes')::int >= n_players OR next_turn IS NULL THEN
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    winner_slot := public._domino_lowest_pip_slot(_game_id, st);
    PERFORM public._domino_end_round(_game_id, winner_slot);
    RETURN;
  END IF;

  st := public._domino_arm_bot_think(_game_id, next_turn, st);
  UPDATE public.domino_games
     SET state = st, current_turn = next_turn,
         turn_deadline = now() + interval '30 seconds'
   WHERE id = _game_id;
END;
$function$;

-- 5. Fix domino_start_solo_bot: retirer _validate_stake (pas de param _stake)
CREATE OR REPLACE FUNCTION public.domino_start_solo_bot(_max_players integer DEFAULT 2, _difficulty text DEFAULT 'medium'::text, _target_score integer DEFAULT 100, _draw_mode text DEFAULT 'with'::text, _first_tile_rule text DEFAULT 'libre'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_game_id uuid;
  v_code text;
  v_name text;
  v_intel int;
  v_paused boolean;
  v_banned boolean;
  v_commission numeric;
  v_slot int;
  v_bot_names text[] := ARRAY['Bot Rija','Bot Naina','Bot Hery','Bot Voara'];
  v_init_state jsonb;
BEGIN
  PERFORM public._assert_solo_bot_enabled();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _max_players NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'Joueurs invalides (2-4)'; END IF;
  IF _draw_mode NOT IN ('with','without') THEN _draw_mode := 'with'; END IF;
  IF _first_tile_rule NOT IN ('libre','under6') THEN _first_tile_rule := 'libre'; END IF;

  SELECT paused INTO v_paused FROM public.app_settings WHERE id=1;
  IF COALESCE(v_paused,false) THEN RAISE EXCEPTION 'Application en pause'; END IF;

  SELECT banned, pseudo INTO v_banned, v_name FROM public.profiles WHERE id=v_uid;
  IF COALESCE(v_banned,false) THEN RAISE EXCEPTION 'Compte banni'; END IF;

  CASE lower(_difficulty)
    WHEN 'easy'   THEN v_intel := 30;
    WHEN 'hard'   THEN v_intel := 95;
    ELSE               v_intel := 70;
  END CASE;

  SELECT COALESCE(game_commission_pct,10) INTO v_commission FROM public.app_settings WHERE id=1;
  v_code := public._gen_room_code();

  v_init_state := jsonb_build_object(
    'phase','waiting',
    'draw_mode', _draw_mode,
    'first_tile_rule', _first_tile_rule,
    'round', 0,
    'scores', '{}'::jsonb
  );

  INSERT INTO public.domino_games(
    host_id, max_players, stake, pot, commission_pct, room_code, is_private, mode,
    status, started_at, target_score, first_tile_rule, state
  )
  VALUES (
    v_uid, _max_players, 0, 0, v_commission, v_code, true, 'classic',
    'playing', now(), COALESCE(_target_score, 100), _first_tile_rule, v_init_state
  )
  RETURNING id INTO v_game_id;

  INSERT INTO public.domino_participants(game_id, user_id, slot, display_name, ready, is_bot)
    VALUES (v_game_id, v_uid, 0, v_name, true, false);

  FOR v_slot IN 1.._max_players - 1 LOOP
    INSERT INTO public.domino_participants(
      game_id, user_id, slot, display_name, ready, is_bot, bot_name, bot_intelligence
    ) VALUES (
      v_game_id, NULL, v_slot, v_bot_names[v_slot], true, true, v_bot_names[v_slot], v_intel
    );
  END LOOP;

  PERFORM public._domino_next_round(v_game_id);
  PERFORM public.domino_tick(v_game_id);
  PERFORM public._domino_bot_loop(v_game_id);

  RETURN v_game_id;
END;
$function$;

-- 6. Nettoyer les anciennes notifications inutiles
DELETE FROM public.notifications WHERE kind IN ('domino_pass', 'domino_blocked', 'domino_turn');

-- 5. Fix rami_start_solo_bot: retirer _validate_stake (pas de param _stake)
CREATE OR REPLACE FUNCTION public.rami_start_solo_bot(_max_players integer DEFAULT 2, _difficulty text DEFAULT 'medium'::text, _joker_mode text DEFAULT 'classique'::text, _game_mode text DEFAULT 'bordel'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_game_id uuid; v_code text; v_name text; v_intel int;
  v_paused boolean; v_banned boolean; v_slot int;
  v_bot_names text[] := ARRAY['Bot Rija','Bot Naina','Bot Hery','Bot Voara'];
  v_max int; v_deck int[]; v_i int; v_j int; v_tmp int; v_size int;
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
  v_deck := ARRAY(SELECT generate_series(0, v_max-1)) || ARRAY(SELECT 56 + generate_series(0, v_max-1));
  v_size := array_length(v_deck,1);

  FOR v_i IN REVERSE v_size..2 LOOP
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
    WHILE v_i <= array_length(v_deck,1) AND (v_deck[v_i] % 56) >= 52 LOOP v_i := v_i + 1; END LOOP;
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
