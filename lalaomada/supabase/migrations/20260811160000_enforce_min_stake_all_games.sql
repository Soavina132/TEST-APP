-- ─────────────────────────────────────────────────────────────────────────────
-- Applique _validate_stake (min 200 Ar) sur tous les jeux
-- Avant: seul ludo_create et rami_create validaient la mise minimum
-- Après: chess, domino, fanorona, poker, ludo, rami — tous valident
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.chess_create(_stake numeric, _private boolean DEFAULT true, _commission numeric DEFAULT 10)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid := auth.uid(); v_bal numeric; v_code text; v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  PERFORM public._validate_stake(_stake);
  SELECT balance_ar INTO v_bal FROM profiles WHERE id = v_uid;
  IF v_bal < _stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;
  IF _private THEN v_code := upper(substring(md5(random()::text||clock_timestamp()::text) from 1 for 6)); END IF;
  INSERT INTO chess_games(host_id, white_id, stake, pot, commission_pct, is_private, room_code)
  VALUES (v_uid, v_uid, _stake, _stake, _commission, _private, v_code)
  RETURNING id INTO v_id;
  UPDATE profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO transactions(user_id, type, amount, ref_id, note) VALUES (v_uid, 'chess_stake', -_stake, v_id, 'Create chess');
  RETURN v_id;
END $function$;


CREATE OR REPLACE FUNCTION public.chess_create_stake(_stake numeric, _color text DEFAULT 'white'::text, _time_min integer DEFAULT 10)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_id  uuid;
  v_human_w boolean := (lower(coalesce(_color,'white')) <> 'black');
  v_ms int := greatest(60000, coalesce(_time_min,10) * 60000);
  v_bal numeric;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _stake <= 0 THEN RAISE EXCEPTION 'stake must be positive'; END IF;
  PERFORM public._validate_stake(_stake);
  SELECT balance_ar INTO v_bal FROM profiles WHERE id = v_uid FOR UPDATE;
  IF coalesce(v_bal,0) < _stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;
  UPDATE profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO transactions(user_id, type, amount, meta) VALUES (v_uid, 'chess_stake', -_stake, jsonb_build_object('kind','hold'));

  INSERT INTO public.chess_games(
    host_id, white_id, black_id, status, mode,
    stake, pot, commission_pct, is_private, room_code,
    time_control_min, white_time_ms, black_time_ms,
    fen, turn, ply
  ) VALUES (
    v_uid,
    CASE WHEN v_human_w THEN v_uid ELSE NULL END,
    CASE WHEN v_human_w THEN NULL ELSE v_uid END,
    'open', 'stake',
    _stake, _stake, 10, false, public._chess_gen_code(),
    coalesce(_time_min,10), v_ms, v_ms,
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 'w', 0
  ) RETURNING id INTO v_id;
  RETURN v_id;
END $function$;


CREATE OR REPLACE FUNCTION public.domino_create(_stake numeric, _max integer, _private boolean, _mode text DEFAULT 'classic'::text, _commission numeric DEFAULT 10, _target_score integer DEFAULT 0, _draw_mode text DEFAULT 'with'::text, _first_tile_rule text DEFAULT 'libre'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_balance numeric; v_code text; v_id uuid; v_name text; v_state jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _max NOT BETWEEN 2 AND 3 THEN RAISE EXCEPTION 'invalid max_players (2-3)'; END IF;
  PERFORM public._validate_stake(_stake);
  IF _target_score < 0 OR _target_score > 1000 THEN RAISE EXCEPTION 'invalid target_score'; END IF;
  IF _draw_mode NOT IN ('with','without') THEN RAISE EXCEPTION 'invalid draw_mode'; END IF;
  IF _first_tile_rule NOT IN ('libre','under6') THEN RAISE EXCEPTION 'invalid first_tile_rule'; END IF;

  SELECT balance_ar, pseudo INTO v_balance, v_name FROM public.profiles WHERE id = v_uid;
  IF v_balance IS NULL OR v_balance < _stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;

  IF _private THEN
    v_code := upper(substring(md5(random()::text||clock_timestamp()::text) from 1 for 6));
  END IF;

  v_state := public._domino_init_state();
  v_state := jsonb_set(v_state, '{draw_mode}', to_jsonb(_draw_mode), true);
  v_state := jsonb_set(v_state, '{first_tile_rule}', to_jsonb(_first_tile_rule), true);

  INSERT INTO public.domino_games(host_id, max_players, stake, pot, commission_pct, is_private, room_code, mode, target_score, state, first_tile_rule)
  VALUES (v_uid, _max, _stake, _stake, _commission, _private, v_code, _mode, _target_score, v_state, _first_tile_rule)
  RETURNING id INTO v_id;

  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
    VALUES (v_uid, 'domino_stake', -_stake, v_id, 'Create domino game');
  INSERT INTO public.domino_participants(game_id, user_id, slot, display_name)
    VALUES (v_id, v_uid, 0, COALESCE(v_name,'Player'));
  RETURN v_id;
END $function$;


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
  v_is_bot boolean;
  v_think_until timestamptz;
  v_sleep_sec numeric;
  v_max_loops int := 15;
  g_status text;
  g_phase text;
BEGIN
  PERFORM public._validate_stake(_stake);
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

  -- FIX: was _domino_tick (doesn't exist) → domino_tick
  PERFORM public.domino_tick(v_game_id);

  -- Faire jouer les bots via _domino_bot_loop (force-play)
  PERFORM public._domino_bot_loop(v_game_id);

  RETURN v_game_id;
END;
$function$;


CREATE OR REPLACE FUNCTION public.fanorona_create(_stake numeric, _private boolean, _commission numeric DEFAULT 10, _variant text DEFAULT 'tsivy'::text, _mandatory_capture boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_balance numeric;
  v_code text;
  v_id uuid;
  v_name text;
  v_cols int; v_rows int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  PERFORM public._validate_stake(_stake);

  CASE _variant
    WHEN 'telo'  THEN v_cols := 3; v_rows := 3;
    WHEN 'dimy'  THEN v_cols := 5; v_rows := 5;
    WHEN 'tsivy' THEN v_cols := 9; v_rows := 5;
    ELSE v_cols := 9; v_rows := 5; _variant := 'tsivy';
  END CASE;

  SELECT balance_ar, pseudo INTO v_balance, v_name FROM public.profiles WHERE id = v_uid;
  IF v_balance < _stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;
  IF _private THEN v_code := upper(substring(md5(random()::text||clock_timestamp()::text) from 1 for 6)); END IF;

  INSERT INTO public.fanorona_games(host_id, max_players, stake, pot, commission_pct, is_private, room_code, state, cols, rows, variant, mandatory_capture)
  VALUES (v_uid, 2, _stake, _stake, _commission, _private, v_code,
    jsonb_build_object('phase','waiting','board', public._fanorona_init_board(v_cols, v_rows), 'chain_from', null, 'chain_dirs', '[]'::jsonb),
    v_cols, v_rows, _variant, COALESCE(_mandatory_capture, true))
  RETURNING id INTO v_id;

  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note) VALUES (v_uid, 'fanorona_stake', -_stake, v_id, 'Create fanorona');
  INSERT INTO public.fanorona_participants(game_id, user_id, slot, color, display_name) VALUES (v_id, v_uid, 0, 'white', COALESCE(v_name,'Player'));
  RETURN v_id;
END $function$;


CREATE OR REPLACE FUNCTION public.fanorona_create_solo(_stake numeric DEFAULT 0, _variant text DEFAULT 'tsivy'::text, _mandatory_capture boolean DEFAULT true, _bot_intelligence integer DEFAULT 3)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
  v_name text;
  v_cols int; v_rows int;
  v_bot_name text;
  v_time_ms int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  PERFORM public._validate_stake(_stake);

  CASE _variant
    WHEN 'telo'  THEN v_cols := 3; v_rows := 3;
    WHEN 'dimy'  THEN v_cols := 5; v_rows := 5;
    WHEN 'tsivy' THEN v_cols := 9; v_rows := 5;
    ELSE v_cols := 9; v_rows := 5; _variant := 'tsivy';
  END CASE;

  SELECT pseudo INTO v_name FROM public.profiles WHERE id = v_uid;
  v_bot_name := CASE _bot_intelligence WHEN 1 THEN 'Debutant' WHEN 2 THEN 'Amateur' WHEN 3 THEN 'Confirme' WHEN 4 THEN 'Expert' ELSE 'Maitre' END;
  v_time_ms := 10 * 60 * 1000;

  INSERT INTO public.fanorona_games(
    host_id, max_players, stake, pot, commission_pct, is_private, room_code,
    state, cols, rows, variant, mandatory_capture, bot_intelligence, status, started_at, last_move_at,
    white_time_ms, black_time_ms
  )
  VALUES (
    v_uid, 2, 0, 0, 0, true, null,
    jsonb_build_object('phase','playing', 'board', public._fanorona_init_board(v_cols, v_rows), 'chain_from',null,'chain_dirs','[]'::jsonb,'move_count',0,'visited','[]'::jsonb,'last_axis',null),
    v_cols, v_rows, _variant, COALESCE(_mandatory_capture, true), COALESCE(_bot_intelligence, 3), 'playing', now(), now(),
    v_time_ms, v_time_ms
  ) RETURNING id INTO v_id;

  INSERT INTO public.fanorona_participants(game_id, user_id, slot, color, display_name, is_bot)
  VALUES (v_id, v_uid, 0, 'white', COALESCE(v_name, 'Joueur'), false);

  INSERT INTO public.fanorona_participants(game_id, user_id, slot, color, display_name, is_bot, bot_intelligence)
  VALUES (v_id, NULL, 1, 'black', 'Bot ' || v_bot_name, true, COALESCE(_bot_intelligence, 3));

  UPDATE public.fanorona_games
    SET current_turn = 0,
        turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')), 60) || ' seconds')::interval
    WHERE id = v_id;

  RETURN v_id;
END $function$;


CREATE OR REPLACE FUNCTION public.ludo_quick_start(_max_players integer DEFAULT 2, _stake numeric DEFAULT 0, _mode text DEFAULT 'classic'::text, _match_type text DEFAULT 'solo'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid;
  v_game_id uuid;
  v_code text;
  v_name text;
  v_balance numeric;
  v_paused boolean;
  v_banned boolean;
  v_commission numeric;
  v_slot int;
  v_colors text[];
  v_color text;
  v_team int;
  v_bot_names text[] := ARRAY['Bot Rija','Bot Naina','Bot Hery','Bot Voara'];
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _max_players NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'Joueurs invalides (2-4)'; END IF;
  PERFORM public._validate_stake(_stake);

  SELECT paused INTO v_paused FROM public.app_settings WHERE id = 1;
  IF COALESCE(v_paused, false) THEN RAISE EXCEPTION 'Application en pause'; END IF;

  SELECT banned, COALESCE(pseudo, 'Joueur'), balance_ar
    INTO v_banned, v_name, v_balance
    FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF COALESCE(v_banned, false) THEN RAISE EXCEPTION 'Compte banni'; END IF;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  v_colors := CASE _max_players
    WHEN 2 THEN ARRAY['red', 'yellow']
    WHEN 3 THEN ARRAY['red', 'yellow', 'blue']
    ELSE ARRAY['red', 'green', 'yellow', 'blue']
  END;

  SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id = 1;
  v_code := public._gen_room_code();

  INSERT INTO public.ludo_games(
    host_id, max_players, stake, pot, commission_pct, room_code, is_private, mode, match_type
  ) VALUES (
    v_uid, _max_players, _stake, _stake, COALESCE(v_commission, 10), v_code, TRUE, COALESCE(_mode, 'classic'), COALESCE(_match_type, 'solo')
  ) RETURNING id INTO v_game_id;

  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'stake', -_stake, v_game_id, 'Mise creation partie solo bot');
  END IF;

  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name, ready, is_bot)
    VALUES (v_game_id, v_uid, 0, v_colors[1], v_name, TRUE, FALSE);

  FOR v_slot IN 1.._max_players - 1 LOOP
    v_color := v_colors[v_slot + 1];
    IF _match_type = 'groupe' THEN
      v_team := CASE WHEN v_slot % 2 = 0 THEN 1 ELSE 2 END;
    ELSE
      v_team := NULL;
    END IF;
    INSERT INTO public.ludo_participants(
      game_id, user_id, slot, color, is_bot, bot_name, display_name,
      bot_intelligence, bot_win_bias, ready, team
    ) VALUES (
      v_game_id, NULL, v_slot, v_color, TRUE,
      v_bot_names[v_slot], v_bot_names[v_slot],
      70, 0, TRUE, v_team
    );
  END LOOP;

  UPDATE public.ludo_games
    SET status = 'playing'::game_status, started_at = now(),
        state = public._ludo_init_state(_max_players),
        current_turn = 0
    WHERE id = v_game_id;

  RETURN v_game_id;
END $function$;


CREATE OR REPLACE FUNCTION public.ludo_start_solo_bot(_max_players integer DEFAULT 2, _stake numeric DEFAULT 0, _mode text DEFAULT 'classic'::text, _match_type text DEFAULT 'solo'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_game_id uuid;
  v_name text;
  v_intel int := 70;
  v_colors4 text[] := ARRAY['red','blue','green','yellow'];
  v_colors3 text[] := ARRAY['red','green','yellow'];
  v_colors2 text[] := ARRAY['red','yellow'];
  v_color text;
  i int;
  v_bot_names text[] := ARRAY['Bot Rina','Bot Naina','Bot Toky','Bot Sanda'];
  v_balance numeric;
  v_commission numeric;
  v_team int;
BEGIN
  PERFORM public._validate_stake(_stake);
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _max_players < 2 OR _max_players > 4 THEN
    RAISE EXCEPTION 'max_players doit être entre 2 et 4';
  END IF;
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id=1;

  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct,
                                is_private, mode, match_type, status, is_solo)
  VALUES (v_uid, _max_players, _stake, _stake, COALESCE(v_commission,0),
          TRUE, COALESCE(_mode,'classic'), COALESCE(_match_type,'solo'), 'open', TRUE)
  RETURNING id INTO v_game_id;

  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_uid,'stake',-_stake,v_game_id,'Mise création partie solo bot');
  END IF;

  SELECT COALESCE(NULLIF(trim(pseudo),''),'Joueur') INTO v_name
    FROM public.profiles WHERE id = v_uid;

  IF _match_type = 'groupe' THEN v_team := 1; ELSE v_team := NULL; END IF;

  IF _max_players = 2 THEN v_color := v_colors2[1];
  ELSIF _max_players = 3 THEN v_color := v_colors3[1];
  ELSE v_color := v_colors4[1];
  END IF;

  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name, ready, team)
  VALUES (v_game_id, v_uid, 0, v_color, COALESCE(v_name,'Joueur'), TRUE, v_team);

  FOR i IN 1..(_max_players-1) LOOP
    IF _max_players = 2 THEN v_color := v_colors2[i+1];
    ELSIF _max_players = 3 THEN v_color := v_colors3[i+1];
    ELSE v_color := v_colors4[i+1];
    END IF;
    IF _match_type = 'groupe' THEN
      v_team := CASE WHEN i % 2 = 0 THEN 1 ELSE 2 END;
    ELSE
      v_team := NULL;
    END IF;
    INSERT INTO public.ludo_participants(
      game_id, user_id, slot, color, is_bot, bot_name, display_name,
      bot_intelligence, bot_win_bias, ready, team
    ) VALUES (
      v_game_id, NULL, i, v_color, TRUE,
      v_bot_names[i], v_bot_names[i], v_intel, 0, TRUE, v_team
    );
  END LOOP;

  -- ═══ AUTO-START: tous les participants sont prêts → démarrer immédiatement
  UPDATE public.ludo_games
    SET status = 'playing',
        started_at = now(),
        state = public._ludo_init_state(_max_players, COALESCE(_mode, 'classic')),
        current_turn = 0
    WHERE id = v_game_id;

  RETURN v_game_id;
END $function$;


CREATE OR REPLACE FUNCTION public.poker_create(_stake numeric, _max integer DEFAULT 6, _private boolean DEFAULT false, _commission numeric DEFAULT 10, _small_blind numeric DEFAULT 10, _big_blind numeric DEFAULT 20, _buy_in numeric DEFAULT 10000)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_gid uuid;
  v_code text;
  v_chips numeric;
BEGIN
  PERFORM public._validate_stake(_stake);
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _max < 2 OR _max > 9 THEN RAISE EXCEPTION 'Nombre de joueurs invalide (2-9)'; END IF;
  IF _small_blind <= 0 THEN RAISE EXCEPTION 'Petite blinde invalide'; END IF;
  IF _big_blind < _small_blind THEN RAISE EXCEPTION 'Grosse blinde invalide'; END IF;
  IF _buy_in < _big_blind * 2 THEN RAISE EXCEPTION 'Cave trop faible'; END IF;

  -- Check balance
  IF _stake > 0 AND (SELECT balance_ar FROM public.profiles WHERE id=v_uid) < _stake THEN
    RAISE EXCEPTION 'Solde insuffisant';
  END IF;

  -- Deduct stake
  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar=balance_ar-_stake WHERE id=v_uid;
    INSERT INTO public.transactions(user_id,type,amount,note)
      VALUES(v_uid,'stake',-_stake,'Mise Poker');
  END IF;

  -- Generate code
  IF _private THEN v_code := upper(substring(md5(random()::text),1,6)); END IF;

  -- Create game with blinds & buy-in
  INSERT INTO public.poker_games(
    host_id, stake, commission_pct, max_players, is_private, room_code,
    created_by, state, small_blind, big_blind, buy_in_chips
  )
  VALUES(
    v_uid, _stake, _commission, _max, _private, v_code,
    v_uid, '{}', _small_blind, _big_blind, _buy_in
  )
  RETURNING id INTO v_gid;

  -- Add creator as player (seat 0) with configured buy-in
  v_chips := _buy_in;
  INSERT INTO public.poker_players(game_id, user_id, seat, chips, status, is_ready)
  VALUES(v_gid, v_uid, 0, v_chips, 'waiting', false);

  RETURN v_gid;
END;
$function$;


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
  PERFORM public._validate_stake(_stake);
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

  -- ═══ DEUX PAQUETS : 0.._max-1 et 56..56+_max-1 ═══
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

  -- ═══ Joker couleur opposée : tirer une carte non-joker restante ═══
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


