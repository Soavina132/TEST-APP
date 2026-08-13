================================================================================
-- _domino_active_humans
================================================================================
CREATE OR REPLACE FUNCTION public._domino_active_humans(_gid uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT count(*)::int FROM public.domino_participants
  WHERE game_id = _gid AND forfeited = false AND is_bot = false
$function$


================================================================================
-- _domino_apply_turn_timer
================================================================================
CREATE OR REPLACE FUNCTION public._domino_apply_turn_timer()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  seconds_left integer;
BEGIN
  IF NEW.turn_deadline IS NULL THEN
    NEW.state := COALESCE(NEW.state, '{}'::jsonb) - 'turn_started_at' - 'turn_duration_seconds';
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' OR OLD.turn_deadline IS DISTINCT FROM NEW.turn_deadline THEN
    seconds_left := GREATEST(1, CEIL(EXTRACT(EPOCH FROM (NEW.turn_deadline - now())))::integer);
    NEW.state := jsonb_set(COALESCE(NEW.state, '{}'::jsonb), '{turn_started_at}', to_jsonb(now()::text), true);
    NEW.state := jsonb_set(NEW.state, '{turn_duration_seconds}', to_jsonb(seconds_left), true);
  END IF;
  RETURN NEW;
END;
$function$


================================================================================
-- _domino_arm_bot_think
================================================================================
CREATE OR REPLACE FUNCTION public._domino_arm_bot_think(_game_id uuid, _slot integer, _state jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_isbot boolean;
  v_state jsonb := COALESCE(_state, '{}'::jsonb);
BEGIN
  SELECT is_bot INTO v_isbot
    FROM public.domino_participants
   WHERE game_id = _game_id AND slot = _slot AND forfeited = false;

  IF NOT COALESCE(v_isbot, false) THEN
    RETURN (v_state - 'bot_think_until') - 'bot_locked_slot';
  END IF;

  -- Fenêtre de réflexion max 2s (auparavant 5s).
  v_state := jsonb_set(v_state - 'bot_think_until' - 'bot_locked_slot', '{bot_locked_slot}', to_jsonb(_slot), true);
  v_state := jsonb_set(v_state, '{bot_think_until}', to_jsonb((now() + interval '2 seconds')::text), true);
  RETURN v_state;
END;
$function$


================================================================================
-- _domino_auto_draw
================================================================================
CREATE OR REPLACE FUNCTION public._domino_auto_draw(_game_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  g record; st jsonb; stock jsonb; hand jsonb; drawn jsonb;
  slot int; guard int := 0; did boolean := false;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id;
  IF g.id IS NULL OR g.status <> 'playing' THEN RETURN false; END IF;
  st := g.state;
  IF COALESCE(st->>'draw_mode','with') <> 'with' THEN RETURN false; END IF;
  slot := g.current_turn;
  IF public._domino_slot_has_playable(st, slot) THEN RETURN false; END IF;

  stock := COALESCE(st->'stock','[]'::jsonb);
  hand  := COALESCE(st->'hands'->slot::text,'[]'::jsonb);

  WHILE jsonb_array_length(stock) > 0 AND guard < 30 LOOP
    guard := guard + 1;
    drawn := stock -> 0;
    stock := stock - 0;
    hand  := hand || jsonb_build_array(drawn);
    did   := true;
    st := jsonb_set(st, ARRAY['hands', slot::text], hand);
    st := jsonb_set(st, '{stock}', stock);
    EXIT WHEN public._domino_slot_has_playable(st, slot);
  END LOOP;

  IF NOT did THEN RETURN false; END IF;

  UPDATE public.domino_games
     SET state = st,
         turn_deadline = now() + interval '30 seconds'
   WHERE id = _game_id;
  RETURN public._domino_slot_has_playable(st, slot);
END $function$


================================================================================
-- _domino_autoplay_bots
================================================================================
CREATE OR REPLACE FUNCTION public._domino_autoplay_bots(_game_id uuid)
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
  _cfg record; v_is_bot boolean; phase text;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;
  st := g.state;
  phase := COALESCE(st->>'phase', 'play');
  IF phase NOT IN ('play','playing') THEN RETURN; END IF;
  v_slot := g.current_turn;
  SELECT COALESCE(dp.is_bot, false) INTO v_is_bot
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id AND dp.slot = v_slot AND dp.forfeited = false;
  IF NOT COALESCE(v_is_bot, false) THEN RETURN; END IF;

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
    tile := hand->found_i;
    a := (tile->>0)::int; b := (tile->>1)::int;
    new_hand := '[]'::jsonb;
    FOR j IN 0..jsonb_array_length(hand)-1 LOOP
      IF j <> found_i THEN new_hand := new_hand || jsonb_build_array(hand->j); END IF;
    END LOOP;

    IF is_first_move THEN
      placed := jsonb_build_array(a, b);
      st := jsonb_set(st, '{board}', jsonb_build_array(jsonb_build_object('tile', placed, 'flipped', false)), true);
      new_left := a; new_right := b;
    ELSE
      IF a = re OR b = re THEN
        IF a = re THEN placed := jsonb_build_array(a, b); new_right := b;
        ELSE placed := jsonb_build_array(b, a); new_right := a; END IF;
        new_left := le;
        st := jsonb_set(st, '{board}', COALESCE(st->'board','[]'::jsonb) || jsonb_build_array(jsonb_build_object('tile', placed, 'flipped', false)), true);
      ELSE
        IF a = le THEN placed := jsonb_build_array(b, a); new_left := b;
        ELSE placed := jsonb_build_array(a, b); new_left := a; END IF;
        new_right := re;
        st := jsonb_set(st, '{board}', jsonb_build_array(jsonb_build_object('tile', placed, 'flipped', false)) || COALESCE(st->'board','[]'::jsonb), true);
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

    UPDATE public.domino_games
       SET state = st, current_turn = next_turn,
           turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
     WHERE id = _game_id;
    RETURN;
  END IF;

  stock := COALESCE(st->'stock', '[]'::jsonb);
  IF draw_mode = 'with' AND jsonb_array_length(stock) > 0 THEN
    drawn := stock -> 0;
    hand := hand || jsonb_build_array(drawn);
    stock := stock - 0;
    st := jsonb_set(st, ARRAY['hands', v_slot::text], hand, true);
    st := jsonb_set(st, '{stock}', stock, true);
    UPDATE public.domino_games
       SET state = st,
           turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
     WHERE id = _game_id;
    RETURN;
  END IF;

  st := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1), true);
  st := jsonb_set(st, '{last_pass_by}', to_jsonb(v_slot), true);
  next_turn := public._domino_next_playable_slot(_game_id, v_slot, st);
  IF next_turn IS NULL THEN
    winner_slot := public._domino_lowest_pip_slot(_game_id, st);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_end_round(_game_id, winner_slot);
    RETURN;
  END IF;

  UPDATE public.domino_games
     SET state = st, current_turn = next_turn,
         turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
   WHERE id = _game_id;
END;
$function$


================================================================================
-- _domino_bot_pick_move
================================================================================
CREATE OR REPLACE FUNCTION public._domino_bot_pick_move(_state jsonb, _slot integer, _intel integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  hand jsonb := COALESCE(_state -> 'hands' -> _slot::text, '[]'::jsonb);
  board_len int := jsonb_array_length(COALESCE(_state->'board','[]'::jsonb));
  le int := NULLIF(_state->>'left_end','null')::int;
  re int := NULLIF(_state->>'right_end','null')::int;
  first_dbl int := NULLIF(_state->>'first_move_double','null')::int;
  v_rule text := COALESCE(_state->>'first_tile_rule','libre');
  draw_mode text := COALESCE(_state->>'draw_mode','with');
  stock_len int := jsonb_array_length(COALESCE(_state->'stock','[]'::jsonb));
  n_players int := 0;
  playable jsonb := '[]'::jsonb;
  scored jsonb := '[]'::jsonb;
  t jsonb;
  a int;
  b int;
  ml boolean;
  mr boolean;
  i int;
  n int;
  pick_idx int;
  best_score numeric := -1000000000;
  cur_score numeric;
  new_le int;
  new_re int;
  other_end int;
  hand_size int := jsonb_array_length(hand);
  min_opp_hand int := 999;
  opp_slot int;
  opp_hand jsonb;
  suit_count int[] := ARRAY[0,0,0,0,0,0,0];
  follow_le int;
  follow_re int;
  is_double boolean;
  difficulty text;
  quality_gate numeric;
BEGIN
  IF hand_size = 0 THEN
    RETURN jsonb_build_object('action','pass');
  END IF;

  SELECT count(*) INTO n_players
    FROM jsonb_object_keys(COALESCE(_state->'hands', '{}'::jsonb));

  IF _intel < 40 THEN
    difficulty := 'easy';
  ELSIF _intel < 75 THEN
    difficulty := 'medium';
  ELSE
    difficulty := 'hard';
  END IF;

  FOR t IN SELECT * FROM jsonb_array_elements(hand) LOOP
    a := (t->>0)::int;
    b := (t->>1)::int;
    IF a BETWEEN 0 AND 6 THEN suit_count[a+1] := suit_count[a+1] + 1; END IF;
    IF b BETWEEN 0 AND 6 AND b <> a THEN suit_count[b+1] := suit_count[b+1] + 1; END IF;
  END LOOP;

  IF n_players > 0 THEN
    FOR opp_slot IN 0..(n_players - 1) LOOP
      IF opp_slot <> _slot THEN
        opp_hand := _state->'hands'->opp_slot::text;
        IF opp_hand IS NOT NULL AND jsonb_typeof(opp_hand) = 'array' THEN
          min_opp_hand := LEAST(min_opp_hand, jsonb_array_length(opp_hand));
        END IF;
      END IF;
    END LOOP;
  END IF;

  IF board_len = 0 THEN
    IF first_dbl IS NOT NULL THEN
      FOR t IN SELECT * FROM jsonb_array_elements(hand) LOOP
        a := (t->>0)::int;
        b := (t->>1)::int;
        IF a = first_dbl AND b = first_dbl THEN
          RETURN jsonb_build_object('action','play','tile', t, 'side','right');
        END IF;
      END LOOP;
      IF draw_mode = 'with' AND stock_len > 0 THEN
        RETURN jsonb_build_object('action','draw');
      END IF;
      RETURN jsonb_build_object('action','pass');
    END IF;

    FOR t IN SELECT * FROM jsonb_array_elements(hand) LOOP
      a := (t->>0)::int;
      b := (t->>1)::int;
      IF v_rule <> 'under6' OR (a + b) < 6 THEN
        playable := playable || jsonb_build_array(jsonb_build_object('tile', t, 'side', 'right'));
      END IF;
    END LOOP;
  ELSE
    FOR t IN SELECT * FROM jsonb_array_elements(hand) LOOP
      a := (t->>0)::int;
      b := (t->>1)::int;
      ml := (a = le OR b = le);
      mr := (a = re OR b = re);
      IF mr THEN
        playable := playable || jsonb_build_array(jsonb_build_object('tile', t, 'side', 'right'));
      END IF;
      IF ml AND NOT (mr AND le = re) THEN
        playable := playable || jsonb_build_array(jsonb_build_object('tile', t, 'side', 'left'));
      END IF;
    END LOOP;
  END IF;

  n := jsonb_array_length(playable);
  IF n = 0 THEN
    IF draw_mode = 'with' AND stock_len > 0 THEN
      RETURN jsonb_build_object('action','draw');
    END IF;
    RETURN jsonb_build_object('action','pass');
  END IF;

  IF difficulty = 'easy' THEN
    pick_idx := floor(random() * n)::int;
    RETURN jsonb_build_object('action','play','tile', playable->pick_idx->'tile','side', playable->pick_idx->>'side');
  END IF;

  FOR i IN 0..(n - 1) LOOP
    a := (playable->i->'tile'->>0)::int;
    b := (playable->i->'tile'->>1)::int;
    is_double := a = b;

    IF board_len = 0 THEN
      new_le := a;
      new_re := b;
    ELSIF playable->i->>'side' = 'right' THEN
      new_le := le;
      other_end := CASE WHEN a = re THEN b ELSE a END;
      new_re := other_end;
    ELSE
      other_end := CASE WHEN a = le THEN b ELSE a END;
      new_le := other_end;
      new_re := re;
    END IF;

    follow_le := CASE WHEN new_le BETWEEN 0 AND 6 THEN suit_count[new_le + 1] ELSE 0 END;
    follow_re := CASE WHEN new_re BETWEEN 0 AND 6 THEN suit_count[new_re + 1] ELSE 0 END;
    IF a = new_le OR b = new_le THEN follow_le := GREATEST(0, follow_le - 1); END IF;
    IF a = new_re OR b = new_re THEN follow_re := GREATEST(0, follow_re - 1); END IF;

    -- Professional-style priorities:
    -- 1) empty the hand quickly, 2) keep follow-up numbers, 3) dump high pips
    -- when opponents are close, 4) avoid creating a dead end for ourselves.
    cur_score := 0;
    cur_score := cur_score + (a + b) * CASE WHEN min_opp_hand <= 2 OR hand_size <= 4 THEN 7 ELSE 3 END;
    cur_score := cur_score + (follow_le + follow_re) * CASE WHEN hand_size <= 4 THEN 18 ELSE 8 END;
    cur_score := cur_score + CASE WHEN is_double THEN 16 + (a * 2) ELSE 0 END;
    cur_score := cur_score + CASE WHEN new_le = new_re AND (follow_le + follow_re) > 0 THEN 12 ELSE 0 END;

    IF hand_size <= 3 AND (follow_le + follow_re) = 0 AND hand_size > 1 THEN
      cur_score := cur_score - 45;
    END IF;

    IF min_opp_hand <= 2 THEN
      -- Defensive endgame: prefer ends we still control and high-pip dumping.
      cur_score := cur_score + (follow_le + follow_re) * 14 + (a + b) * 4;
    END IF;

    IF hand_size = 1 THEN
      cur_score := cur_score + 100000;
    END IF;

    IF difficulty = 'medium' THEN
      cur_score := cur_score + (random() * 30) - 10;
    END IF;

    scored := scored || jsonb_build_array(jsonb_build_object(
      'idx', i,
      'score', cur_score,
      'tile', playable->i->'tile',
      'side', playable->i->>'side'
    ));

    IF cur_score > best_score THEN
      best_score := cur_score;
      pick_idx := i;
    END IF;
  END LOOP;

  IF difficulty = 'medium' AND n > 1 THEN
    quality_gate := best_score - 20;
    SELECT COALESCE((x->>'idx')::int, pick_idx) INTO pick_idx
      FROM jsonb_array_elements(scored) AS x
      WHERE (x->>'score')::numeric >= quality_gate
      ORDER BY random()
      LIMIT 1;
  END IF;

  IF pick_idx IS NULL OR pick_idx < 0 THEN pick_idx := 0; END IF;
  RETURN jsonb_build_object('action','play','tile', playable->pick_idx->'tile','side', playable->pick_idx->>'side');
END;
$function$


================================================================================
-- _domino_bot_step
================================================================================
CREATE OR REPLACE FUNCTION public._domino_bot_step(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  g record;
  st jsonb;
  v_slot int;
  v_is_bot boolean;
  phase text;
  v_think_until timestamptz;
  v_locked_slot int;
  v_delay_ms int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

  st := g.state;
  phase := COALESCE(st->>'phase', 'play');
  IF phase NOT IN ('play','playing') THEN RETURN; END IF;

  v_slot := g.current_turn;
  SELECT COALESCE(dp.is_bot, false) INTO v_is_bot
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id
     AND dp.slot = v_slot
     AND dp.forfeited = false;

  IF NOT COALESCE(v_is_bot, false) THEN RETURN; END IF;

  v_think_until := NULLIF(st->>'bot_think_until','')::timestamptz;
  v_locked_slot := NULLIF(st->>'bot_locked_slot','null')::int;

  IF v_think_until IS NOT NULL AND v_locked_slot = v_slot AND v_think_until > now() THEN
    RETURN;
  END IF;

  IF v_think_until IS NULL OR v_locked_slot IS DISTINCT FROM v_slot THEN
    v_delay_ms := 1500 + (floor(random() * 2000))::int;
    st := jsonb_set(st - 'bot_think_until' - 'bot_locked_slot',
                    '{bot_locked_slot}', to_jsonb(v_slot), true);
    st := jsonb_set(st, '{bot_think_until}',
                    to_jsonb((now() + make_interval(secs => v_delay_ms / 1000.0))::text), true);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    RETURN;
  END IF;

  -- Le délai est écoulé : retirer le verrou et laisser le bot jouer.
  st := st - 'bot_think_until' - 'bot_locked_slot';
  UPDATE public.domino_games SET state = st WHERE id = _game_id;
  PERFORM public._domino_autoplay_bots(_game_id);
END;
$function$


================================================================================
-- _domino_deal
================================================================================
CREATE OR REPLACE FUNCTION public._domino_deal(_n_players integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  tiles int[][] := ARRAY[]::int[][];
  a int; b int;
  shuffled jsonb;
  arr jsonb := '[]'::jsonb;
  i int;
BEGIN
  FOR a IN 0..6 LOOP
    FOR b IN a..6 LOOP
      arr := arr || jsonb_build_array(jsonb_build_array(a,b));
    END LOOP;
  END LOOP;
  -- shuffle in SQL
  SELECT jsonb_agg(value ORDER BY random()) INTO shuffled FROM jsonb_array_elements(arr);
  RETURN shuffled;
END $function$


================================================================================
-- _domino_end_round
================================================================================
CREATE OR REPLACE FUNCTION public._domino_end_round(_game_id uuid, _winner_slot integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  g record; st jsonb; winner_uid uuid; round_score int := 0;
  hand_pips jsonb := '{}'::jsonb; p record; pips int; p_key text;
  v_scores jsonb; new_total int; winner_key text;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN; END IF;

  SELECT user_id INTO winner_uid FROM public.domino_participants WHERE game_id = _game_id AND slot = _winner_slot;
  st := g.state;

  FOR p IN SELECT slot, user_id FROM public.domino_participants WHERE game_id = _game_id LOOP
    pips := public._domino_hand_pips(st->'hands'->p.slot::text);
    p_key := COALESCE(p.user_id::text, 'bot:'||p.slot);
    hand_pips := hand_pips || jsonb_build_object(p_key, pips);
    IF p.slot <> _winner_slot THEN round_score := round_score + pips; END IF;
  END LOOP;

  IF COALESCE(g.target_score,0) <= 0 THEN
    PERFORM public._domino_finalize(_game_id, _winner_slot);
    RETURN;
  END IF;

  winner_key := COALESCE(winner_uid::text, 'bot:'||_winner_slot);
  v_scores := COALESCE(g.scores, '{}'::jsonb);
  new_total := COALESCE((v_scores->>winner_key)::int, 0) + round_score;
  v_scores := jsonb_set(v_scores, ARRAY[winner_key], to_jsonb(new_total), true);

  UPDATE public.domino_games SET scores = v_scores WHERE id = _game_id;

  IF new_total >= g.target_score THEN
    st := jsonb_set(st, '{last_round}', jsonb_build_object(
      'winner_uid', winner_uid, 'round_score', round_score, 'hand_pips', hand_pips, 'final', true
    ));
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_finalize(_game_id, _winner_slot);
    RETURN;
  END IF;

  st := jsonb_set(st, '{phase}', '"break"'::jsonb);
  st := jsonb_set(st, '{break_until}', to_jsonb((now() + interval '10 seconds')::text));
  st := jsonb_set(st, '{last_round}', jsonb_build_object(
    'winner_uid', winner_uid, 'round_score', round_score, 'hand_pips', hand_pips, 'final', false
  ));
  st := jsonb_set(st, '{scores}', v_scores);
  UPDATE public.domino_games SET state = st, turn_deadline = NULL WHERE id = _game_id;
END $function$


================================================================================
-- _domino_finalize
================================================================================
CREATE OR REPLACE FUNCTION public._domino_finalize(_game_id uuid, _winner_slot integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  g record; winner_uid uuid; payout numeric; p record; n_active integer; refund_each numeric;
  st jsonb;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status = 'finished' THEN RETURN; END IF;

  IF _winner_slot IS NULL THEN
    SELECT count(*) INTO n_active FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
    IF n_active > 0 AND g.pot > 0 THEN
      refund_each := floor(g.pot / n_active);
      FOR p IN SELECT user_id FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false AND user_id IS NOT NULL LOOP
        UPDATE public.profiles SET balance_ar = balance_ar + refund_each WHERE id = p.user_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (p.user_id, 'domino_draw', refund_each, _game_id, 'Domino match nul – remboursement');
      END LOOP;
    END IF;
    st := jsonb_set(COALESCE(g.state,'{}'::jsonb), '{winner_slot}', 'null'::jsonb, true);
    UPDATE public.domino_games
       SET status='finished', winner_id=NULL, finished_at=now(), state=st
     WHERE id=_game_id;
    RETURN;
  END IF;

  SELECT user_id INTO winner_uid FROM public.domino_participants WHERE game_id = _game_id AND slot = _winner_slot;
  payout := g.pot * (100 - g.commission_pct) / 100;
  IF winner_uid IS NOT NULL THEN
    UPDATE public.profiles SET balance_ar = balance_ar + payout WHERE id = winner_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (winner_uid, 'domino_win', payout, _game_id, 'Domino win');
  END IF;
  st := jsonb_set(COALESCE(g.state,'{}'::jsonb), '{winner_slot}', to_jsonb(_winner_slot), true);
  UPDATE public.domino_games
     SET status='finished', winner_id=winner_uid, finished_at=now(), state=st
   WHERE id=_game_id;
END $function$


================================================================================
-- _domino_hand_pips
================================================================================
CREATE OR REPLACE FUNCTION public._domino_hand_pips(_hand jsonb)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(SUM(((t->>0)::int + (t->>1)::int)), 0)::int
  FROM jsonb_array_elements(COALESCE(_hand,'[]'::jsonb)) t
$function$


================================================================================
-- _domino_init_state
================================================================================
CREATE OR REPLACE FUNCTION public._domino_init_state()
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT '{"phase":"waiting","hands":{},"stock":[],"board":[],"left_end":null,"right_end":null,"passes":0,"scores":{}}'::jsonb
$function$


================================================================================
-- _domino_lock_game
================================================================================
CREATE OR REPLACE FUNCTION public._domino_lock_game(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(_game_id::text, 424242));
END $function$


================================================================================
-- _domino_lowest_pip_slot
================================================================================
CREATE OR REPLACE FUNCTION public._domino_lowest_pip_slot(_game_id uuid, _state jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE p record; cur_sum integer; best_sum integer := 2147483647; best_slot integer := NULL; tie_count integer := 0;
BEGIN
  FOR p IN SELECT slot FROM public.domino_participants WHERE game_id=_game_id AND forfeited=false ORDER BY slot LOOP
    cur_sum := public._domino_hand_pips(COALESCE(_state->'hands'->p.slot::text, '[]'::jsonb));
    IF cur_sum < best_sum THEN best_sum := cur_sum; best_slot := p.slot; tie_count := 1;
    ELSIF cur_sum = best_sum THEN tie_count := tie_count + 1; END IF;
  END LOOP;
  IF tie_count > 1 THEN RETURN NULL; END IF;
  RETURN best_slot;
END; $function$


================================================================================
-- _domino_next_playable_slot
================================================================================
CREATE OR REPLACE FUNCTION public._domino_next_playable_slot(_game_id uuid, _from_slot integer, _state jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  slots integer[];
  total integer;
  start_idx integer := 1;
  step integer;
  idx integer;
  candidate integer;
  draw_mode text := COALESCE(_state->>'draw_mode', 'with');
  stock_len integer := jsonb_array_length(COALESCE(_state -> 'stock', '[]'::jsonb));
BEGIN
  SELECT array_agg(slot ORDER BY slot)
    INTO slots
    FROM public.domino_participants
   WHERE game_id = _game_id AND forfeited = false;

  total := COALESCE(array_length(slots, 1), 0);
  IF total = 0 THEN
    RETURN NULL;
  END IF;

  FOR idx IN 1..total LOOP
    IF slots[idx] = _from_slot THEN
      start_idx := idx;
      EXIT;
    END IF;
  END LOOP;

  FOR step IN 1..total LOOP
    idx := ((start_idx - 1 + step) % total) + 1;
    candidate := slots[idx];

    IF public._domino_slot_has_playable(_state, candidate)
       OR (draw_mode = 'with' AND stock_len > 0) THEN
      RETURN candidate;
    END IF;
  END LOOP;

  RETURN NULL;
END;
$function$


================================================================================
-- _domino_next_round
================================================================================
CREATE OR REPLACE FUNCTION public._domino_next_round(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  g record; n int; tiles jsonb; hands jsonb := '{}'::jsonb;
  stock jsonb; per_hand int := 7; p record; idx int := 0; hand jsonb;
  starter int := 0; best int := -1; cur_best int; t jsonb;
  starter_double int := -1;
  _cfg record;
  v_round int;
  v_rule text;
  v_prev_starter int;
  slots int[];
  i int;
  a int; b int; sum2 int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN; END IF;
  SELECT count(*) INTO n FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  IF n < 2 THEN RETURN; END IF;

  tiles := public._domino_deal(n);

  SELECT array_agg(slot ORDER BY slot) INTO slots
    FROM public.domino_participants WHERE game_id=_game_id AND forfeited=false;

  FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
    SELECT jsonb_agg(value) INTO hand FROM jsonb_array_elements(tiles) WITH ORDINALITY t(value, ord)
      WHERE ord > idx*per_hand AND ord <= (idx+1)*per_hand;
    hands := hands || jsonb_build_object(p.slot::text, COALESCE(hand,'[]'::jsonb));
    idx := idx + 1;
  END LOOP;
  SELECT jsonb_agg(value) INTO stock FROM jsonb_array_elements(tiles) WITH ORDINALITY t(value, ord)
    WHERE ord > n*per_hand;
  stock := COALESCE(stock, '[]'::jsonb);

  v_round := COALESCE((g.state->>'round')::int, 1) + 1;
  v_rule := COALESCE(g.state->>'first_tile_rule', g.first_tile_rule, 'libre');
  v_prev_starter := NULLIF(g.state->>'starter_slot','null')::int;

  IF v_prev_starter IS NOT NULL THEN
    starter := slots[1];
    FOR i IN 1..array_length(slots,1) LOOP
      IF slots[i] = v_prev_starter THEN
        starter := slots[ ((i) % array_length(slots,1)) + 1 ];
        EXIT;
      END IF;
    END LOOP;
    starter_double := -1;
  ELSIF v_rule = 'under6' THEN
    best := -1; starter := slots[1]; starter_double := -1;
    FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
      cur_best := -1;
      FOR t IN SELECT * FROM jsonb_array_elements(hands -> p.slot::text) LOOP
        a := (t->>0)::int; b := (t->>1)::int; sum2 := a + b;
        IF a = b AND sum2 < 6 AND sum2 > cur_best THEN cur_best := sum2; END IF;
      END LOOP;
      IF cur_best > best THEN best := cur_best; starter := p.slot; END IF;
    END LOOP;
    IF best < 0 THEN
      FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
        cur_best := -1;
        FOR t IN SELECT * FROM jsonb_array_elements(hands -> p.slot::text) LOOP
          a := (t->>0)::int; b := (t->>1)::int; sum2 := a + b;
          IF sum2 < 6 AND sum2 > cur_best THEN cur_best := sum2; END IF;
        END LOOP;
        IF cur_best > best THEN best := cur_best; starter := p.slot; END IF;
      END LOOP;
    END IF;
  ELSE
    FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
      cur_best := -1;
      FOR t IN SELECT * FROM jsonb_array_elements(hands -> p.slot::text) LOOP
        IF (t->>0)::int = (t->>1)::int AND (t->>0)::int > cur_best THEN cur_best := (t->>0)::int; END IF;
      END LOOP;
      IF cur_best > best THEN best := cur_best; starter := p.slot; starter_double := cur_best; END IF;
    END LOOP;
  END IF;

  SELECT * INTO _cfg FROM public._game_cfg('domino');

  -- Reset "ready" côté participants pour repartir proprement
  UPDATE public.domino_participants
     SET ready = false
   WHERE game_id = _game_id;

  UPDATE public.domino_games SET
    current_turn = starter,
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
    turn_skips = '{}'::jsonb,
    state = jsonb_build_object(
      'phase','playing',
      'hands', hands,
      'stock', stock,
      'board', '[]'::jsonb,
      'left_end', 'null'::jsonb,
      'right_end', 'null'::jsonb,
      'passes', 0,
      'scores', COALESCE(g.scores, g.state->'scores', '{}'::jsonb),
      'round', v_round,
      'last_round', NULL,
      'reveal_until', NULL,
      'break_until', NULL,
      'draw_mode', COALESCE(g.state->>'draw_mode','with'),
      'first_tile_rule', v_rule,
      'starter_slot', to_jsonb(starter),
      'first_move_double', CASE WHEN starter_double >= 0 THEN to_jsonb(starter_double) ELSE 'null'::jsonb END
    )
  WHERE id = _game_id;
END;
$function$


================================================================================
-- _domino_normalize_board
================================================================================
CREATE OR REPLACE FUNCTION public._domino_normalize_board(_board jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  chain jsonb := '[]'::jsonb;
  entry jsonb;
  tile jsonb;
  placed jsonb;
  a int;
  b int;
  le int;
  re int;
  i int := 0;
BEGIN
  IF _board IS NULL OR jsonb_typeof(_board) <> 'array' OR jsonb_array_length(_board) = 0 THEN
    RETURN jsonb_build_object('board', '[]'::jsonb, 'left_end', NULL, 'right_end', NULL);
  END IF;

  FOR entry IN SELECT value FROM jsonb_array_elements(_board) AS value LOOP
    tile := CASE
      WHEN jsonb_typeof(entry) = 'array' THEN entry
      ELSE entry->'tile'
    END;

    IF tile IS NULL OR jsonb_typeof(tile) <> 'array' OR jsonb_array_length(tile) <> 2 THEN
      CONTINUE;
    END IF;

    a := (tile->>0)::int;
    b := (tile->>1)::int;

    IF i = 0 THEN
      chain := jsonb_build_array(jsonb_build_object('tile', jsonb_build_array(a, b), 'flipped', false));
      le := a;
      re := b;
    ELSE
      IF a = re THEN
        placed := jsonb_build_object('tile', jsonb_build_array(a, b), 'flipped', false);
        chain := chain || jsonb_build_array(placed);
        re := b;
      ELSIF b = re THEN
        placed := jsonb_build_object('tile', jsonb_build_array(b, a), 'flipped', false);
        chain := chain || jsonb_build_array(placed);
        re := a;
      ELSIF b = le THEN
        placed := jsonb_build_object('tile', jsonb_build_array(a, b), 'flipped', false);
        chain := jsonb_build_array(placed) || chain;
        le := a;
      ELSIF a = le THEN
        placed := jsonb_build_object('tile', jsonb_build_array(b, a), 'flipped', false);
        chain := jsonb_build_array(placed) || chain;
        le := b;
      ELSE
        -- Keep malformed legacy entries visible without changing endpoints.
        chain := chain || jsonb_build_array(jsonb_build_object('tile', jsonb_build_array(a, b), 'flipped', false));
      END IF;
    END IF;

    i := i + 1;
  END LOOP;

  IF jsonb_array_length(chain) = 0 THEN
    RETURN jsonb_build_object('board', '[]'::jsonb, 'left_end', NULL, 'right_end', NULL);
  END IF;

  RETURN jsonb_build_object('board', chain, 'left_end', le, 'right_end', re);
END;
$function$


================================================================================
-- _domino_place_first
================================================================================
CREATE OR REPLACE FUNCTION public._domino_place_first(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  g record; st jsonb; starter int; starter_double int;
  hands jsonb; starter_hand jsonb; filtered jsonb;
  board jsonb; next_slot int; v_playable jsonb; _delay interval;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;
  st := g.state;
  IF (st->>'phase') <> 'dealing' THEN RETURN; END IF;

  starter := COALESCE((st->>'starter_slot')::int, g.current_turn);
  starter_double := COALESCE((st->>'starter_double')::int, -1);
  hands := st->'hands';

  IF starter_double >= 0 THEN
    starter_hand := hands -> starter::text;
    SELECT COALESCE(jsonb_agg(value), '[]'::jsonb) INTO filtered
      FROM jsonb_array_elements(starter_hand) value
      WHERE NOT ((value->>0)::int = starter_double AND (value->>1)::int = starter_double);
    hands := jsonb_set(hands, ARRAY[starter::text], filtered);
    board := jsonb_build_array(
      jsonb_build_array(starter_double, starter_double)
    );
    st := jsonb_set(st, '{hands}', hands);
    st := jsonb_set(st, '{board}', board);
    st := jsonb_set(st, '{left_end}', to_jsonb(starter_double));
    st := jsonb_set(st, '{right_end}', to_jsonb(starter_double));
    st := jsonb_set(st, '{first_tile_idx}', '0'::jsonb);

    SELECT slot INTO next_slot FROM public.domino_participants
      WHERE game_id=_game_id AND forfeited=false AND slot > starter ORDER BY slot LIMIT 1;
    IF next_slot IS NULL THEN
      SELECT slot INTO next_slot FROM public.domino_participants
        WHERE game_id=_game_id AND forfeited=false ORDER BY slot LIMIT 1;
    END IF;
  ELSE
    next_slot := starter;
  END IF;

  st := jsonb_set(st, '{phase}', '"play"'::jsonb);
  st := st - 'deal_until' - 'bot_think_until' - 'bot_locked_slot';

  next_slot := COALESCE(next_slot, starter);
  st := jsonb_set(st, ARRAY['turn_slot'], to_jsonb(next_slot));
  v_playable := public._domino_playable_tiles(st, next_slot);
  st := jsonb_set(st, ARRAY['playable_tiles'], v_playable);

  _delay := public._domino_turn_delay(_game_id, next_slot);

  UPDATE public.domino_games
     SET state = st,
         current_turn = next_slot,
         turn_deadline = now() + _delay
   WHERE id = _game_id;
END;
$function$


================================================================================
-- _domino_play_as
================================================================================
CREATE OR REPLACE FUNCTION public._domino_play_as(_game_id uuid, _slot integer, _move jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  g             record;
  st            jsonb;
  hand          jsonb;
  tile          jsonb;
  placed_tile   jsonb;
  a int; b int;
  ha int; hb int;
  le int; re int;
  side          text;
  new_left      int;
  new_right     int;
  action        text;
  n_players     int;
  next_turn     int;
  drawn         jsonb;
  stock         jsonb;
  found         boolean := false;
  new_hand      jsonb;
  i             int;
  winner_slot   int;
  draw_mode     text;
  first_dbl     int;
  first_rule    text;
  stock_len     int;
  actor_is_bot  boolean;
  norm          jsonb;
  turn_secs     int;
BEGIN
  PERFORM public._domino_lock_game(_game_id);

  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  IF _slot <> g.current_turn THEN RAISE EXCEPTION 'not your turn (slot %, expected %)', _slot, g.current_turn; END IF;

  SELECT COALESCE(turn_timer_seconds, 60) INTO turn_secs
    FROM public.game_configs WHERE slug = 'domino';
  IF turn_secs IS NULL THEN turn_secs := 60; END IF;

  st := g.state;
  IF COALESCE(st->>'phase', 'play') NOT IN ('play', 'playing') THEN
    RAISE EXCEPTION 'round transition in progress';
  END IF;

  norm      := public._domino_normalize_board(COALESCE(st->'board', '[]'::jsonb));
  st        := jsonb_set(st, '{board}', COALESCE(norm->'board', '[]'::jsonb), true);
  st        := jsonb_set(st, '{left_end}', COALESCE(norm->'left_end', 'null'::jsonb), true);
  st        := jsonb_set(st, '{right_end}', COALESCE(norm->'right_end', 'null'::jsonb), true);

  action    := _move->>'action';
  hand      := COALESCE(st -> 'hands' -> _slot::text, '[]'::jsonb);
  stock     := COALESCE(st -> 'stock', '[]'::jsonb);
  le        := NULLIF(st->>'left_end',  'null')::int;
  re        := NULLIF(st->>'right_end', 'null')::int;
  draw_mode := COALESCE(st->>'draw_mode', 'with');
  first_rule := COALESCE(st->>'first_tile_rule', 'libre');
  stock_len := jsonb_array_length(stock);

  SELECT count(*) INTO n_players FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  SELECT is_bot INTO actor_is_bot
    FROM public.domino_participants WHERE game_id = _game_id AND slot = _slot;

  st := st - 'bot_think_until' - 'bot_locked_slot';

  IF COALESCE(actor_is_bot,false) AND action IN ('play','pass') THEN
    st := jsonb_set(st, '{bot_last_play_at}', to_jsonb(now()::text), true);
  END IF;

  IF action = 'draw' THEN
    IF draw_mode = 'without' THEN RAISE EXCEPTION 'draw disabled in this game'; END IF;
    IF public._domino_slot_has_playable(st, _slot) THEN RAISE EXCEPTION 'play your playable domino first'; END IF;
    IF stock_len = 0 THEN RAISE EXCEPTION 'stock empty'; END IF;
    drawn := stock -> 0;
    stock := stock - 0;
    hand  := hand || jsonb_build_array(drawn);
    st := jsonb_set(st, ARRAY['hands', _slot::text], hand, true);
    st := jsonb_set(st, '{stock}', stock, true);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    RETURN;
  END IF;

  IF action = 'pass' THEN
    IF public._domino_slot_has_playable(st, _slot) THEN RAISE EXCEPTION 'you have a playable domino'; END IF;
    IF draw_mode = 'with' AND stock_len > 0 THEN RAISE EXCEPTION 'you must draw first'; END IF;
    st        := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1), true);
    st        := jsonb_set(st, '{last_pass_by}', to_jsonb(_slot), true);
    next_turn := public._domino_next_playable_slot(_game_id, _slot, st);
    IF (st->>'passes')::int >= n_players THEN
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
      winner_slot := public._domino_lowest_pip_slot(_game_id, st);
      PERFORM public._domino_end_round(_game_id, winner_slot);
      RETURN;
    END IF;
    IF next_turn IS NULL THEN
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
      winner_slot := public._domino_lowest_pip_slot(_game_id, st);
      PERFORM public._domino_end_round(_game_id, winner_slot);
      RETURN;
    END IF;
    st := jsonb_set(st, '{current_turn}', to_jsonb(next_turn), true);
    st := public._domino_turn_state(st, turn_secs);
    st := public._domino_arm_bot_think(_game_id, next_turn, st);
    UPDATE public.domino_games
       SET state = st,
           current_turn = next_turn,
           turn_deadline = now() + (turn_secs || ' seconds')::interval
     WHERE id = _game_id;
    RETURN;
  END IF;

  IF action <> 'play' THEN RAISE EXCEPTION 'unknown action %', action; END IF;

  tile := _move -> 'tile';
  IF tile IS NULL OR jsonb_typeof(tile) <> 'array' OR jsonb_array_length(tile) <> 2 THEN
    RAISE EXCEPTION 'tile required';
  END IF;
  a := (tile->>0)::int;
  b := (tile->>1)::int;
  side := NULLIF(_move->>'side', 'auto');

  found := false;
  FOR i IN 0 .. jsonb_array_length(hand) - 1 LOOP
    ha := (hand->i->>0)::int;
    hb := (hand->i->>1)::int;
    IF (ha = a AND hb = b) OR (ha = b AND hb = a) THEN
      found := true;
      a := ha;
      b := hb;
      new_hand := hand - i;
      EXIT;
    END IF;
  END LOOP;
  IF NOT found THEN RAISE EXCEPTION 'tile [% %] not in hand of slot %', a, b, _slot; END IF;

  first_dbl := NULLIF(st->>'first_move_double', 'null')::int;
  IF le IS NULL THEN
    IF first_dbl IS NOT NULL AND (a <> first_dbl OR b <> first_dbl) THEN
      RAISE EXCEPTION 'first move must be the highest double';
    END IF;
    IF first_dbl IS NULL AND first_rule = 'under6' AND (a + b) >= 6 THEN
      RAISE EXCEPTION 'first domino must be under 6 points';
    END IF;
    new_left := a;
    new_right := b;
    placed_tile := jsonb_build_array(a, b);
    st := jsonb_set(st, '{board}', jsonb_build_array(jsonb_build_object('tile', placed_tile, 'flipped', false)), true);
  ELSE
    IF side IS NULL THEN
      IF a = re OR b = re THEN side := 'right';
      ELSIF a = le OR b = le THEN side := 'left';
      ELSE RAISE EXCEPTION 'tile does not fit';
      END IF;
    END IF;

    IF side = 'right' THEN
      IF a = re THEN placed_tile := jsonb_build_array(a, b); new_right := b;
      ELSIF b = re THEN placed_tile := jsonb_build_array(b, a); new_right := a;
      ELSE RAISE EXCEPTION 'tile does not fit right';
      END IF;
      new_left := le;
      st := jsonb_set(st, '{board}', COALESCE(st->'board', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('tile', placed_tile, 'flipped', false)), true);
    ELSIF side = 'left' THEN
      IF a = le THEN placed_tile := jsonb_build_array(b, a); new_left := b;
      ELSIF b = le THEN placed_tile := jsonb_build_array(a, b); new_left := a;
      ELSE RAISE EXCEPTION 'tile does not fit left';
      END IF;
      new_right := re;
      st := jsonb_set(st, '{board}', jsonb_build_array(jsonb_build_object('tile', placed_tile, 'flipped', false)) || COALESCE(st->'board', '[]'::jsonb), true);
    ELSE
      RAISE EXCEPTION 'invalid side';
    END IF;
  END IF;

  st := jsonb_set(st, ARRAY['hands', _slot::text], new_hand, true);
  st := jsonb_set(st, '{left_end}',  to_jsonb(new_left), true);
  st := jsonb_set(st, '{right_end}', to_jsonb(new_right), true);
  st := jsonb_set(st, '{passes}',    to_jsonb(0), true);
  st := jsonb_set(st, '{first_move_double}', 'null'::jsonb, true);
  st := st - 'last_pass_by';

  IF jsonb_array_length(new_hand) = 0 THEN
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_end_round(_game_id, _slot);
    RETURN;
  END IF;

  next_turn := public._domino_next_playable_slot(_game_id, _slot, st);
  IF next_turn IS NULL THEN
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    winner_slot := public._domino_lowest_pip_slot(_game_id, st);
    PERFORM public._domino_end_round(_game_id, winner_slot);
    RETURN;
  END IF;

  st := jsonb_set(st, '{current_turn}', to_jsonb(next_turn), true);
  st := public._domino_turn_state(st, turn_secs);
  st := public._domino_arm_bot_think(_game_id, next_turn, st);
  UPDATE public.domino_games
     SET state = st,
         current_turn = next_turn,
         turn_deadline = now() + (turn_secs || ' seconds')::interval
   WHERE id = _game_id;
END;
$function$


================================================================================
-- _domino_playable_tiles
================================================================================
CREATE OR REPLACE FUNCTION public._domino_playable_tiles(_state jsonb, _slot integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  hand jsonb;
  board jsonb;
  left_end INT;
  right_end INT;
  i INT;
  tile jsonb;
  a INT; b INT;
  result jsonb := '[]'::jsonb;
  first_move_double INT;
  first_tile_rule TEXT;
  board_len INT;
BEGIN
  hand := _state->'hands'->_slot::text;
  board := _state->'board';
  IF hand IS NULL THEN RETURN '[]'::jsonb; END IF;

  board_len := COALESCE(jsonb_array_length(board), 0);
  left_end := NULLIF(_state->>'left_end','')::INT;
  right_end := NULLIF(_state->>'right_end','')::INT;
  first_move_double := NULLIF(_state->>'first_move_double','')::INT;
  first_tile_rule := COALESCE(_state->>'first_tile_rule', 'libre');

  FOR i IN 0..jsonb_array_length(hand)-1 LOOP
    tile := hand->i;
    a := (tile->>0)::INT;
    b := (tile->>1)::INT;

    IF board_len = 0 THEN
      -- First tile rules
      IF first_move_double IS NOT NULL THEN
        IF a = first_move_double AND b = first_move_double THEN
          result := result || to_jsonb(i);
        END IF;
      ELSIF first_tile_rule = 'under6' THEN
        IF a + b < 6 THEN result := result || to_jsonb(i); END IF;
      ELSE
        result := result || to_jsonb(i);
      END IF;
    ELSE
      IF a = left_end OR b = left_end OR a = right_end OR b = right_end THEN
        result := result || to_jsonb(i);
      END IF;
    END IF;
  END LOOP;

  RETURN result;
END $function$


================================================================================
-- _domino_purge
================================================================================
CREATE OR REPLACE FUNCTION public._domino_purge(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  DELETE FROM public.chat_rooms WHERE game_id = _game_id;
  DELETE FROM public.game_spectators WHERE game_id = _game_id;
  DELETE FROM public.game_invitations WHERE game_id = _game_id;
  DELETE FROM public.domino_participants WHERE game_id = _game_id;
  DELETE FROM public.domino_games WHERE id = _game_id;
END $function$


================================================================================
-- _domino_required_starter_slot
================================================================================
CREATE OR REPLACE FUNCTION public._domino_required_starter_slot(_game_id uuid, _state jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  first_dbl integer;
  p record;
  t jsonb;
BEGIN
  IF jsonb_array_length(COALESCE(_state->'board', '[]'::jsonb)) > 0 THEN
    RETURN NULL;
  END IF;

  first_dbl := NULLIF(_state->>'first_move_double', 'null')::integer;
  IF first_dbl IS NULL THEN
    RETURN NULL;
  END IF;

  FOR p IN
    SELECT slot
    FROM public.domino_participants
    WHERE game_id = _game_id
      AND forfeited = false
    ORDER BY slot
  LOOP
    FOR t IN SELECT * FROM jsonb_array_elements(COALESCE(_state->'hands'->p.slot::text, '[]'::jsonb)) LOOP
      IF (t->>0)::integer = first_dbl AND (t->>1)::integer = first_dbl THEN
        RETURN p.slot;
      END IF;
    END LOOP;
  END LOOP;

  RETURN NULL;
END;
$function$


================================================================================
-- _domino_slot_has_playable
================================================================================
CREATE OR REPLACE FUNCTION public._domino_slot_has_playable(_state jsonb, _slot integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  hand jsonb := COALESCE(_state -> 'hands' -> _slot::text, '[]'::jsonb);
  board_len integer := jsonb_array_length(COALESCE(_state -> 'board', '[]'::jsonb));
  first_dbl integer;
  first_rule text;
  le integer;
  re integer;
  t jsonb;
  a integer;
  b integer;
BEGIN
  IF jsonb_array_length(hand) = 0 THEN
    RETURN false;
  END IF;

  IF board_len = 0 THEN
    first_dbl := NULLIF(_state->>'first_move_double', 'null')::integer;
    first_rule := COALESCE(_state->>'first_tile_rule', 'libre');

    IF first_dbl IS NOT NULL THEN
      FOR t IN SELECT * FROM jsonb_array_elements(hand) LOOP
        a := (t->>0)::integer; b := (t->>1)::integer;
        IF a = first_dbl AND b = first_dbl THEN RETURN true; END IF;
      END LOOP;
      RETURN false;
    END IF;

    IF first_rule = 'under6' THEN
      FOR t IN SELECT * FROM jsonb_array_elements(hand) LOOP
        a := (t->>0)::integer; b := (t->>1)::integer;
        IF (a + b) < 6 THEN RETURN true; END IF;
      END LOOP;
      RETURN false;
    END IF;

    RETURN true;
  END IF;

  le := NULLIF(_state->>'left_end', 'null')::integer;
  re := NULLIF(_state->>'right_end', 'null')::integer;

  FOR t IN SELECT * FROM jsonb_array_elements(hand) LOOP
    a := (t->>0)::integer;
    b := (t->>1)::integer;
    IF a = le OR b = le OR a = re OR b = re THEN RETURN true; END IF;
  END LOOP;

  RETURN false;
END;
$function$


================================================================================
-- _domino_start
================================================================================
CREATE OR REPLACE FUNCTION public._domino_start(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
  UPDATE public.domino_games
     SET status = 'playing',
         started_at = COALESCE(started_at, now()),
         turn_skips = '{}'::jsonb,
         scores = COALESCE(scores, '{}'::jsonb)
   WHERE id = _game_id
     AND status = 'open';

  IF NOT FOUND THEN RETURN; END IF;

  PERFORM public._domino_next_round(_game_id);
END;
$function$


================================================================================
-- _domino_turn_delay
================================================================================
CREATE OR REPLACE FUNCTION public._domino_turn_delay(_game_id uuid, _slot integer)
 RETURNS interval
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_is_bot boolean := false;
  v_cfg record;
BEGIN
  SELECT COALESCE(dp.is_bot, false) INTO v_is_bot
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id AND dp.slot = _slot AND dp.forfeited = false;
  IF v_is_bot THEN
    RETURN make_interval(secs => 3 + random() * 2);
  ELSE
    SELECT * INTO v_cfg FROM public._game_cfg('domino');
    RETURN (COALESCE(v_cfg.turn_timer_seconds, 30) || ' seconds')::interval;
  END IF;
END;
$function$


================================================================================
-- _domino_turn_state
================================================================================
CREATE OR REPLACE FUNCTION public._domino_turn_state(_state jsonb, _turn_seconds integer)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'public'
AS $function$
  SELECT jsonb_set(
           jsonb_set(
             COALESCE(_state, '{}'::jsonb),
             '{turn_started_at}',
             to_jsonb(now()::text),
             true
           ),
           '{turn_duration_seconds}',
           to_jsonb(GREATEST(1, COALESCE(_turn_seconds, 60))),
           true
         );
$function$


================================================================================
-- _domino_visible
================================================================================
CREATE OR REPLACE FUNCTION public._domino_visible(_game_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS(
    SELECT 1 FROM public.domino_games g
    WHERE g.id = _game_id
      AND (
        (g.status IN ('open','playing') AND g.is_private = false)
        OR g.host_id = auth.uid()
        OR EXISTS(SELECT 1 FROM public.domino_participants p WHERE p.game_id = g.id AND p.user_id = auth.uid())
        OR public.is_admin()
      )
  )
$function$


================================================================================
-- domino_add_bot
================================================================================
CREATE OR REPLACE FUNCTION public.domino_add_bot(_game_id uuid, _bot_name text DEFAULT 'Bot'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_is_admin boolean := public.is_admin();
  g public.domino_games%ROWTYPE;
  v_count int;
  v_slot int;
  v_bot_names text[] := ARRAY['Bot Rija','Bot Naina','Bot Hery','Bot Voara'];
  v_name text;
  v_ready_count int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status <> 'open' THEN RAISE EXCEPTION 'La partie a déjà commencé'; END IF;

  IF NOT v_is_admin THEN
    IF COALESCE(g.stake, 0) > 0 THEN
      RAISE EXCEPTION 'Bots réservés aux parties gratuites';
    END IF;
    IF g.host_id <> v_uid
       AND NOT EXISTS (SELECT 1 FROM public.domino_participants WHERE game_id=_game_id AND user_id=v_uid) THEN
      RAISE EXCEPTION 'Rejoignez la partie pour ajouter un bot';
    END IF;
  END IF;

  SELECT count(*) INTO v_count FROM public.domino_participants WHERE game_id=_game_id;
  IF v_count >= g.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;

  v_slot := v_count;
  v_name := COALESCE(NULLIF(trim(_bot_name), ''), v_bot_names[LEAST(v_slot + 1, array_length(v_bot_names, 1))]);

  INSERT INTO public.domino_participants(
    game_id, user_id, slot, display_name, ready, is_bot, bot_name, bot_intelligence
  ) VALUES (_game_id, NULL, v_slot, v_name, TRUE, TRUE, v_name, 70);

  SELECT count(*), count(*) FILTER (WHERE ready)
    INTO v_count, v_ready_count
    FROM public.domino_participants
   WHERE game_id = _game_id;

  IF v_count = g.max_players AND v_ready_count = g.max_players THEN
    PERFORM public._domino_start(_game_id);
  END IF;
END $function$


================================================================================
-- domino_advance_turn
================================================================================
CREATE OR REPLACE FUNCTION public.domino_advance_turn(_game_id uuid, _state jsonb, _turn_skips jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  _next int; _part record; _count int; _delay interval;
BEGIN
  -- Clear stale bot_think state
  _state := _state - 'bot_think_until' - 'bot_locked_slot';

  SELECT current_turn INTO _next FROM public.domino_games WHERE id = _game_id;
  SELECT count(*) INTO _count FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  LOOP
    _next := (_next + 1) % GREATEST(_count, 1);
    SELECT * INTO _part FROM public.domino_participants WHERE game_id = _game_id AND slot = _next AND forfeited = false;
    EXIT WHEN FOUND;
  END LOOP;

  _delay := public._domino_turn_delay(_game_id, _next);

  UPDATE public.domino_games SET
    state = _state,
    current_turn = _next,
    turn_skips = CASE WHEN _turn_skips != '{}'::jsonb THEN _turn_skips ELSE turn_skips END,
    turn_deadline = now() + _delay,
    updated_at = now()
  WHERE id = _game_id;
END;
$function$


================================================================================
-- domino_bot_execute
================================================================================
CREATE OR REPLACE FUNCTION public.domino_bot_execute(_game_id uuid, _bot record, _move jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  _game record; _state jsonb; _action text; _tile jsonb; _side text;
  _hand jsonb; _idx int; _ta int; _tb int; _le int; _re int;
  _board jsonb; _stock jsonb; _nt jsonb; _slot int; _ts jsonb; _count int;
  _key text; _fti int;
BEGIN
  SELECT * INTO _game FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND OR _game.status != 'playing' THEN RETURN; END IF;
  _state := _game.state;
  IF _state->>'phase' NOT IN ('playing', 'play') THEN RETURN; END IF;
  IF _game.current_turn != _bot.slot THEN RETURN; END IF;

  _state := _state - 'bot_think_until' - 'bot_locked_slot';

  _action := _move->>'action';
  _hand := _state->('hands')->(_bot.slot::text);
  _board := _state->'board';
  _le := NULLIF(_state->>'left_end','')::int;
  _re := NULLIF(_state->>'right_end','')::int;
  _stock := _state->'stock';
  _slot := _bot.slot;
  _key := COALESCE(_bot.user_id::text, 'bot_'||_slot);
  _fti := COALESCE((_state->>'first_tile_idx')::int, 0);

  IF _action = 'play' THEN
    _tile := _move->'tile'; _ta := (_tile->>0)::int; _tb := (_tile->>1)::int; _side := COALESCE(_move->>'side','auto');
    _idx := -1;
    FOR _i IN 0..jsonb_array_length(_hand)-1 LOOP
      IF (_hand->(_i))->>0 = _ta::text AND (_hand->(_i))->>1 = _tb::text THEN _idx := _i; EXIT; END IF;
      IF (_hand->(_i))->>0 = _tb::text AND (_hand->(_i))->>1 = _ta::text THEN
        _tile := jsonb_build_array(_tb, _ta); _ta := (_tile->>0)::int; _tb := (_tile->>1)::int; _idx := _i; EXIT;
      END IF;
    END LOOP;
    IF _idx < 0 THEN RETURN; END IF;

    IF jsonb_array_length(_board) = 0 THEN
      _board := jsonb_build_array(_tile); _le := _ta; _re := _tb;
      _fti := 0;
    ELSE
      IF _side = 'auto' THEN
        IF _ta = _re OR _tb = _re THEN _side := 'right';
        ELSIF _ta = _le OR _tb = _le THEN _side := 'left';
        ELSE RETURN; END IF;
      END IF;
      IF _side = 'left' THEN
        IF _tb = _le THEN _nt := jsonb_build_array(_ta, _tb); _le := _ta;
        ELSIF _ta = _le THEN _nt := jsonb_build_array(_tb, _ta); _le := _tb;
        ELSE RETURN; END IF;
        _board := jsonb_build_array(_nt) || _board;
        _fti := _fti + 1;
      ELSE
        IF _ta = _re THEN _nt := jsonb_build_array(_ta, _tb); _re := _tb;
        ELSIF _tb = _re THEN _nt := jsonb_build_array(_tb, _ta); _re := _ta;
        ELSE RETURN; END IF;
        _board := _board || jsonb_build_array(_nt);
      END IF;
    END IF;

    _hand := public.domino_remove_at(_hand, _idx);
    _state := _state || jsonb_build_object('board', _board, 'left_end', _le, 'right_end', _re, 'passes', 0, 'last_pass_by', null, 'first_move_double', null, 'first_tile_idx', _fti);
    _state := jsonb_set(_state, ARRAY['hands', _slot::text], _hand);
    _ts := jsonb_set(_game.turn_skips, ARRAY[_key], '0'::jsonb);

    IF jsonb_array_length(_hand) = 0 THEN
      PERFORM public.domino_end_round(_game_id, _slot);
      RETURN;
    END IF;
    PERFORM public.domino_advance_turn(_game_id, _state, _ts);

  ELSIF _action = 'draw' THEN
    IF jsonb_array_length(_stock) = 0 THEN RETURN; END IF;
    _nt := _stock->0;
    _stock := public.domino_pop_first(_stock);
    _hand := _hand || jsonb_build_array(_nt);
    _state := _state || jsonb_build_object('stock', _stock);
    _state := jsonb_set(_state, ARRAY['hands', _slot::text], _hand);
    _ta := (_nt->>0)::int; _tb := (_nt->>1)::int;
    IF _ta = _le OR _tb = _le OR _ta = _re OR _tb = _re THEN
      PERFORM public.domino_bot_execute(_game_id, _bot, jsonb_build_object('action','play','tile',_nt,'side','auto'));
    ELSIF jsonb_array_length(_stock) > 0 THEN
      UPDATE public.domino_games SET state = _state, turn_deadline = now() + make_interval(secs => 2), updated_at = now() WHERE id = _game_id;
    ELSE
      _state := _state || jsonb_build_object('passes', (_state->>'passes')::int + 1, 'last_pass_by', _slot);
      _ts := jsonb_set(_game.turn_skips, ARRAY[_key], to_jsonb((_game.turn_skips->>_key)::int + 1));
      SELECT count(*) INTO _count FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
      IF (_state->>'passes')::int >= _count THEN PERFORM public.domino_end_round(_game_id, null, true);
      ELSE PERFORM public.domino_advance_turn(_game_id, _state, _ts); END IF;
    END IF;

  ELSIF _action = 'pass' THEN
    _state := _state || jsonb_build_object('passes', (_state->>'passes')::int + 1, 'last_pass_by', _slot);
    _ts := jsonb_set(_game.turn_skips, ARRAY[_key], to_jsonb((_game.turn_skips->>_key)::int + 1));
    SELECT count(*) INTO _count FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
    IF (_state->>'passes')::int >= _count THEN PERFORM public.domino_end_round(_game_id, null, true);
    ELSE PERFORM public.domino_advance_turn(_game_id, _state, _ts); END IF;
  END IF;
END;
$function$


================================================================================
-- domino_create
================================================================================
CREATE OR REPLACE FUNCTION public.domino_create(_stake numeric, _max integer, _private boolean, _mode text DEFAULT 'classic'::text, _commission numeric DEFAULT 10)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_balance numeric;
  v_code text;
  v_id uuid;
  v_name text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _max NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'invalid max_players'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'invalid stake'; END IF;

  SELECT balance_ar, pseudo INTO v_balance, v_name FROM public.profiles WHERE id = v_uid;
  IF v_balance IS NULL OR v_balance < _stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;

  IF _private THEN
    v_code := upper(substring(md5(random()::text||clock_timestamp()::text) from 1 for 6));
  END IF;

  INSERT INTO public.domino_games(host_id, max_players, stake, pot, commission_pct, is_private, room_code, mode, state)
  VALUES (v_uid, _max, _stake, _stake, _commission, _private, v_code, _mode, public._domino_init_state())
  RETURNING id INTO v_id;

  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note) VALUES (v_uid, 'domino_stake', -_stake, v_id, 'Create domino game');

  INSERT INTO public.domino_participants(game_id, user_id, slot, display_name) VALUES (v_id, v_uid, 0, COALESCE(v_name,'Player'));
  RETURN v_id;
END $function$


================================================================================
-- domino_create
================================================================================
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
  IF _stake < 0 THEN RAISE EXCEPTION 'invalid stake'; END IF;
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
END $function$


================================================================================
-- domino_create
================================================================================
CREATE OR REPLACE FUNCTION public.domino_create(_stake numeric, _max integer, _private boolean, _mode text DEFAULT 'classic'::text, _commission numeric DEFAULT 10, _target_score integer DEFAULT 0, _draw_mode text DEFAULT 'with'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_balance numeric; v_code text; v_id uuid; v_name text; v_state jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _max NOT BETWEEN 2 AND 3 THEN RAISE EXCEPTION 'invalid max_players (2-3)'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'invalid stake'; END IF;
  IF _target_score < 0 OR _target_score > 1000 THEN RAISE EXCEPTION 'invalid target_score'; END IF;
  IF _draw_mode NOT IN ('with','without') THEN RAISE EXCEPTION 'invalid draw_mode'; END IF;

  SELECT balance_ar, pseudo INTO v_balance, v_name FROM public.profiles WHERE id = v_uid;
  IF v_balance IS NULL OR v_balance < _stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;

  IF _private THEN
    v_code := upper(substring(md5(random()::text||clock_timestamp()::text) from 1 for 6));
  END IF;

  v_state := public._domino_init_state();
  v_state := jsonb_set(v_state, '{draw_mode}', to_jsonb(_draw_mode), true);

  INSERT INTO public.domino_games(host_id, max_players, stake, pot, commission_pct, is_private, room_code, mode, target_score, state)
  VALUES (v_uid, _max, _stake, _stake, _commission, _private, v_code, _mode, _target_score, v_state)
  RETURNING id INTO v_id;

  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
    VALUES (v_uid, 'domino_stake', -_stake, v_id, 'Create domino game');
  INSERT INTO public.domino_participants(game_id, user_id, slot, display_name)
    VALUES (v_id, v_uid, 0, COALESCE(v_name,'Player'));
  RETURN v_id;
END $function$


================================================================================
-- domino_create
================================================================================
CREATE OR REPLACE FUNCTION public.domino_create(_stake numeric, _max integer, _private boolean, _mode text DEFAULT 'classic'::text, _commission numeric DEFAULT 10, _target_score integer DEFAULT 0)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_balance numeric;
  v_code text;
  v_id uuid;
  v_name text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _max NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'invalid max_players'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'invalid stake'; END IF;
  IF _target_score < 0 OR _target_score > 1000 THEN RAISE EXCEPTION 'invalid target_score'; END IF;

  SELECT balance_ar, pseudo INTO v_balance, v_name FROM public.profiles WHERE id = v_uid;
  IF v_balance IS NULL OR v_balance < _stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;

  IF _private THEN
    v_code := upper(substring(md5(random()::text||clock_timestamp()::text) from 1 for 6));
  END IF;

  INSERT INTO public.domino_games(host_id, max_players, stake, pot, commission_pct, is_private, room_code, mode, target_score, state)
  VALUES (v_uid, _max, _stake, _stake, _commission, _private, v_code, _mode, _target_score, public._domino_init_state())
  RETURNING id INTO v_id;

  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note) VALUES (v_uid, 'domino_stake', -_stake, v_id, 'Create domino game');
  INSERT INTO public.domino_participants(game_id, user_id, slot, display_name) VALUES (v_id, v_uid, 0, COALESCE(v_name,'Player'));
  RETURN v_id;
END $function$


================================================================================
-- domino_deal_tiles
================================================================================
CREATE OR REPLACE FUNCTION public.domino_deal_tiles(_game_id uuid, _tiles jsonb, _ppp integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  _hands jsonb := '{}'::jsonb; _stock jsonb; _p record; _count int; _offset int;
BEGIN
  SELECT count(*) INTO _count FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  FOR _p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
    _offset := _p.slot * _ppp;
    _hands := _hands || jsonb_build_object(_p.slot::text,
      (SELECT jsonb_agg(x) FROM (SELECT x FROM jsonb_array_elements(_tiles) WITH ORDINALITY AS ord(x, rn) WHERE rn > _offset AND rn <= _offset + _ppp ORDER BY rn) s));
  END LOOP;
  _stock := (SELECT jsonb_agg(x) FROM (SELECT x FROM jsonb_array_elements(_tiles) WITH ORDINALITY AS ord(x, rn) WHERE rn > _count * _ppp ORDER BY rn) s);
  RETURN jsonb_build_object('hands', _hands, 'stock', COALESCE(_stock, '[]'::jsonb));
END;
$function$


================================================================================
-- domino_end_round
================================================================================
CREATE OR REPLACE FUNCTION public.domino_end_round(_game_id uuid, _winner_slot integer DEFAULT NULL::integer, _blocked boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  _game record; _state jsonb; _p record; _pips int; _total int := 0;
  _hand_pips jsonb := '{}'::jsonb; _final_hands jsonb := '{}'::jsonb;
  _round_score int; _scores jsonb; _winner_uid text := null; _target int;
  _game_over boolean := false; _max int := -1; _ws int; _wu text;
  _now timestamp; _bu timestamp; _key text; _best int := 999; _tie int;
BEGIN
  SELECT * INTO _game FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND OR _game.status != 'playing' THEN RETURN; END IF;
  _state := _game.state; _scores := _game.scores;

  FOR _p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
    _key := COALESCE(_p.user_id::text, 'bot_'||_p.slot);
    _pips := public.domino_hand_pips(_state->('hands')->(_p.slot::text));
    _hand_pips := _hand_pips || jsonb_build_object(_key, _pips);
    _final_hands := _final_hands || jsonb_build_object(_key, _state->('hands')->(_p.slot::text));
    _total := _total + _pips;
  END LOOP;

  IF _blocked THEN
    _best := 999; _winner_slot := null;
    FOR _p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
      _key := COALESCE(_p.user_id::text, 'bot_'||_p.slot);
      _pips := (_hand_pips->>_key)::int;
      IF _pips < _best THEN _best := _pips; _winner_slot := _p.slot; _winner_uid := _key;
      ELSIF _pips = _best THEN _winner_uid := null; END IF;
    END LOOP;
    _round_score := GREATEST(0, _total - _best);
  ELSE
    SELECT COALESCE(user_id::text, 'bot_'||_winner_slot) INTO _winner_uid
    FROM public.domino_participants WHERE game_id = _game_id AND slot = _winner_slot AND forfeited = false;
    _round_score := GREATEST(0, _total - public.domino_hand_pips(_state->('hands')->(_winner_slot::text)));
  END IF;

  IF _winner_uid IS NOT NULL THEN
    _scores := jsonb_set(_scores, ARRAY[_winner_uid], to_jsonb((_scores->>_winner_uid)::int + _round_score));
  END IF;

  _target := _game.target_score;
  IF _target > 0 THEN
    FOR _p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
      _key := COALESCE(_p.user_id::text, 'bot_'||_p.slot);
      IF (_scores->>_key)::int >= _target THEN _game_over := true; END IF;
    END LOOP;
  ELSE
    _game_over := true;
  END IF;

  _now := now(); _bu := _now + interval '7 seconds';
  _state := _state || jsonb_build_object('phase', 'break', 'break_until', to_char(_bu, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'last_round', jsonb_build_object('winner_uid', _winner_uid, 'winner_slot', _winner_slot, 'round_score', _round_score,
    'hand_pips', _hand_pips, 'final_hands', _final_hands, 'blocked', _blocked, 'round', (_state->>'round')::int));

  IF _game_over THEN
    _max := -1; _wu := null; _ws := 0;
    FOR _p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
      _key := COALESCE(_p.user_id::text, 'bot_'||_p.slot);
      IF (_scores->>_key)::int > _max THEN _max := (_scores->>_key)::int; _wu := _p.user_id; _ws := _p.slot; END IF;
    END LOOP;
    _state := _state || jsonb_build_object('phase', 'finished', 'winner_slot', _ws);
    IF _wu IS NOT NULL AND _game.stake > 0 THEN
      UPDATE public.profiles SET balance = balance + (_game.pot * (100 - _game.commission_pct) / 100)::int WHERE id = _wu;
      INSERT INTO public.transactions(user_id, type, amount, description) VALUES (_wu, 'winnings', (_game.pot * (100 - _game.commission_pct) / 100)::int, 'Gain domino');
    END IF;
    UPDATE public.domino_games SET status = 'finished', state = _state, scores = _scores, winner_id = _wu, finished_at = _now, turn_deadline = null, updated_at = _now WHERE id = _game_id;
  ELSE
    UPDATE public.domino_games SET state = _state, scores = _scores, turn_deadline = null, updated_at = _now WHERE id = _game_id;
  END IF;
END;
$function$


================================================================================
-- domino_find_first_player
================================================================================
CREATE OR REPLACE FUNCTION public.domino_find_first_player(_game_id uuid, _hands jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE _p record; _i int; _ta int; _tb int; _best int := -1; _slot int := 0;
BEGIN
  FOR _p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
    FOR _i IN 0..jsonb_array_length(_hands->(_p.slot::text))-1 LOOP
      _ta := (_hands->(_p.slot::text)->(_i)->>0)::int;
      _tb := (_hands->(_p.slot::text)->(_i)->>1)::int;
      IF _ta = _tb AND _ta > _best THEN _best := _ta; _slot := _p.slot; END IF;
    END LOOP;
  END LOOP;
  RETURN jsonb_build_object('slot', _slot, 'double', CASE WHEN _best >= 0 THEN _best ELSE null END);
END;
$function$


================================================================================
-- domino_forfeit
================================================================================
CREATE OR REPLACE FUNCTION public.domino_forfeit(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  g record;
  my_slot int;
  remaining int;
  last_slot int;
  humans_left int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status NOT IN ('open','playing') THEN RETURN; END IF;
  SELECT slot INTO my_slot FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid;
  IF my_slot IS NULL THEN RETURN; END IF;
  UPDATE public.domino_participants SET forfeited = true WHERE game_id = _game_id AND user_id = v_uid;

  IF g.status = 'open' THEN
    UPDATE public.profiles p SET balance_ar = balance_ar + g.stake
      FROM public.domino_participants pp
     WHERE pp.game_id = _game_id AND pp.user_id = p.id AND COALESCE(pp.is_bot,false) = false;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      SELECT user_id, 'domino_refund', g.stake, _game_id, 'Game cancelled'
        FROM public.domino_participants
       WHERE game_id = _game_id AND COALESCE(is_bot,false) = false;
    UPDATE public.domino_games SET status = 'cancelled', finished_at = now() WHERE id = _game_id;
    humans_left := public._domino_active_humans(_game_id);
    IF humans_left = 0 THEN PERFORM public._domino_purge(_game_id); END IF;
    RETURN;
  END IF;

  humans_left := public._domino_active_humans(_game_id);
  IF humans_left = 0 THEN
    UPDATE public.domino_games SET status = 'cancelled', finished_at = now() WHERE id = _game_id;
    PERFORM public._domino_purge(_game_id);
    RETURN;
  END IF;

  SELECT count(*) INTO remaining FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  IF remaining <= 1 THEN
    SELECT slot INTO last_slot FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false LIMIT 1;
    IF last_slot IS NOT NULL THEN
      PERFORM public._domino_finalize(_game_id, last_slot);
    ELSE
      UPDATE public.domino_games SET status='cancelled', finished_at=now() WHERE id = _game_id;
      PERFORM public._domino_purge(_game_id);
    END IF;
  END IF;
END $function$


================================================================================
-- domino_generate_tiles
================================================================================
CREATE OR REPLACE FUNCTION public.domino_generate_tiles()
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE SECURITY DEFINER
AS $function$
DECLARE _tiles jsonb := '[]'::jsonb; _i int; _j int;
BEGIN
  FOR _i IN 0..6 LOOP
    FOR _j IN _i..6 LOOP
      _tiles := _tiles || jsonb_build_array(jsonb_build_array(_i, _j));
    END LOOP;
  END LOOP;
  SELECT jsonb_agg(x) INTO _tiles FROM (SELECT x FROM jsonb_array_elements(_tiles) AS x ORDER BY random()) s;
  RETURN _tiles;
END;
$function$


================================================================================
-- domino_hand_pips
================================================================================
CREATE OR REPLACE FUNCTION public.domino_hand_pips(_hand jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 IMMUTABLE SECURITY DEFINER
AS $function$
DECLARE _sum int := 0; _i int;
BEGIN
  IF _hand IS NULL THEN RETURN 0; END IF;
  FOR _i IN 0..jsonb_array_length(_hand)-1 LOOP
    _sum := _sum + (_hand->(_i)->>0)::int + (_hand->(_i)->>1)::int;
  END LOOP;
  RETURN _sum;
END;
$function$


================================================================================
-- domino_join
================================================================================
CREATE OR REPLACE FUNCTION public.domino_join(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  g record;
  v_balance numeric;
  v_name text;
  v_slot int;
  v_count int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL OR g.status <> 'open' THEN RAISE EXCEPTION 'game not joinable'; END IF;
  IF EXISTS(SELECT 1 FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid) THEN RETURN; END IF;
  SELECT balance_ar, pseudo INTO v_balance, v_name FROM public.profiles WHERE id = v_uid;
  IF v_balance < g.stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;

  SELECT count(*) INTO v_count FROM public.domino_participants WHERE game_id = _game_id;
  IF v_count >= g.max_players THEN RAISE EXCEPTION 'full'; END IF;
  v_slot := v_count;

  INSERT INTO public.domino_participants(game_id, user_id, slot, display_name) VALUES (_game_id, v_uid, v_slot, COALESCE(v_name,'Player'));
  UPDATE public.profiles SET balance_ar = balance_ar - g.stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note) VALUES (v_uid, 'domino_stake', -g.stake, _game_id, 'Join domino game');
  UPDATE public.domino_games SET pot = pot + g.stake WHERE id = _game_id;

  -- No auto-start: wait for all participants to mark themselves ready (domino_set_ready).
END $function$


================================================================================
-- domino_join_code
================================================================================
CREATE OR REPLACE FUNCTION public.domino_join_code(_code text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE g_id uuid;
BEGIN
  SELECT id INTO g_id FROM public.domino_games WHERE room_code = upper(_code) AND status = 'open';
  IF g_id IS NULL THEN RAISE EXCEPTION 'invalid code'; END IF;
  PERFORM public.domino_join(g_id);
  RETURN g_id;
END $function$


================================================================================
-- domino_play
================================================================================
CREATE OR REPLACE FUNCTION public.domino_play(_game_id uuid, _move jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  _g record; _state jsonb; _action text; _tile jsonb; _side text;
  _part record; _hand jsonb; _idx int; _ta int; _tb int; _le int; _re int;
  _board jsonb; _stock jsonb; _nt jsonb; _slot int; _ts jsonb; _count int; _key text; _draw text;
  _fti int;
BEGIN
  SELECT * INTO _g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND OR _g.status != 'playing' THEN RETURN; END IF;
  _state := _g.state;
  IF _state->>'phase' != 'playing' THEN RETURN; END IF;
  SELECT * INTO _part FROM public.domino_participants WHERE game_id = _game_id AND user_id = auth.uid() AND forfeited = false;
  IF NOT FOUND THEN RAISE EXCEPTION 'Vous ne participez pas'; END IF;
  IF _part.slot != _g.current_turn THEN RAISE EXCEPTION 'Ce n''est pas votre tour'; END IF;

  _action := _move->>'action';
  _hand := _state->('hands')->(_part.slot::text);
  _board := _state->'board';
  _le := NULLIF(_state->>'left_end','')::int;
  _re := NULLIF(_state->>'right_end','')::int;
  _stock := _state->'stock';
  _slot := _part.slot;
  _key := COALESCE(_part.user_id::text, 'bot_'||_slot);
  _draw := COALESCE(_state->>'draw_mode','with');
  _fti := COALESCE((_state->>'first_tile_idx')::int, 0);

  IF _action = 'play' THEN
    _tile := _move->'tile'; _ta := (_tile->>0)::int; _tb := (_tile->>1)::int; _side := COALESCE(_move->>'side','auto');
    _idx := -1;
    FOR _i IN 0..jsonb_array_length(_hand)-1 LOOP
      IF (_hand->>(_i))->>0 = _ta::text AND (_hand->>(_i))->>1 = _tb::text THEN _idx := _i; EXIT; END IF;
      IF (_hand->>(_i))->>0 = _tb::text AND (_hand->>(_i))->>1 = _ta::text THEN
        _tile := jsonb_build_array(_tb, _ta); _ta := (_tile->>0)::int; _tb := (_tile->>1)::int; _idx := _i; EXIT;
      END IF;
    END LOOP;
    IF _idx < 0 THEN RAISE EXCEPTION 'Tuile non valide'; END IF;

    IF jsonb_array_length(_board) = 0 THEN
      _board := jsonb_build_array(_tile); _le := _ta; _re := _tb;
      _fti := 0;
    ELSE
      IF _side = 'auto' THEN
        IF _ta = _re OR _tb = _re THEN _side := 'right';
        ELSIF _ta = _le OR _tb = _le THEN _side := 'left';
        ELSE RAISE EXCEPTION 'Tuile non jouable'; END IF;
      END IF;
      IF _side = 'left' THEN
        IF _tb = _le THEN _nt := jsonb_build_array(_ta, _tb); _le := _ta;
        ELSIF _ta = _le THEN _nt := jsonb_build_array(_tb, _ta); _le := _tb;
        ELSE RAISE EXCEPTION 'Tuile non jouable à gauche'; END IF;
        _board := jsonb_build_array(_nt) || _board;
        _fti := _fti + 1;
      ELSE
        IF _ta = _re THEN _nt := jsonb_build_array(_ta, _tb); _re := _tb;
        ELSIF _tb = _re THEN _nt := jsonb_build_array(_tb, _ta); _re := _ta;
        ELSE RAISE EXCEPTION 'Tuile non jouable à droite'; END IF;
        _board := _board || jsonb_build_array(_nt);
      END IF;
    END IF;

    _hand := public.domino_remove_at(_hand, _idx);
    _state := _state || jsonb_build_object('board',_board,'left_end',_le,'right_end',_re,'passes',0,'last_pass_by',null,'first_move_double',null,'first_tile_idx',_fti);
    _state := jsonb_set(_state, ARRAY['hands', _slot::text], _hand);
    _ts := jsonb_set(_g.turn_skips, ARRAY[_key], '0'::jsonb);

    IF jsonb_array_length(_hand) = 0 THEN PERFORM public.domino_end_round(_game_id, _slot); RETURN; END IF;
    PERFORM public.domino_advance_turn(_game_id, _state, _ts);

  ELSIF _action = 'draw' THEN
    IF jsonb_array_length(_stock) = 0 THEN RAISE EXCEPTION 'Pioche vide'; END IF;
    _nt := _stock->0;
    _stock := public.domino_pop_first(_stock);
    _hand := _hand || jsonb_build_array(_nt);
    _state := _state || jsonb_build_object('stock',_stock);
    _state := jsonb_set(_state, ARRAY['hands', _slot::text], _hand);
    _ta := (_nt->>0)::int; _tb := (_nt->>1)::int;
    IF _ta = _le OR _tb = _le OR _ta = _re OR _tb = _re THEN
      UPDATE public.domino_games SET state=_state, turn_deadline=now()+interval '30 seconds', updated_at=now() WHERE id=_game_id;
    ELSIF jsonb_array_length(_stock) > 0 THEN
      UPDATE public.domino_games SET state=_state, turn_deadline=now()+interval '30 seconds', updated_at=now() WHERE id=_game_id;
    ELSE
      _state := _state || jsonb_build_object('passes',(_state->>'passes')::int+1,'last_pass_by',_slot);
      _ts := jsonb_set(_g.turn_skips, ARRAY[_key], to_jsonb((_g.turn_skips->>_key)::int + 1));
      SELECT count(*) INTO _count FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
      IF (_state->>'passes')::int >= _count THEN PERFORM public.domino_end_round(_game_id, null, true);
      ELSE PERFORM public.domino_advance_turn(_game_id, _state, _ts); END IF;
    END IF;

  ELSIF _action = 'pass' THEN
    IF jsonb_array_length(_stock) > 0 AND _draw = 'with' THEN RAISE EXCEPTION 'Vous pouvez encore piocher'; END IF;
    _state := _state || jsonb_build_object('passes',(_state->>'passes')::int+1,'last_pass_by',_slot);
    _ts := jsonb_set(_g.turn_skips, ARRAY[_key], to_jsonb((_g.turn_skips->>_key)::int + 1));
    SELECT count(*) INTO _count FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
    IF (_state->>'passes')::int >= _count THEN PERFORM public.domino_end_round(_game_id, null, true);
    ELSE PERFORM public.domino_advance_turn(_game_id, _state, _ts); END IF;
  END IF;
END;
$function$


================================================================================
-- domino_play_and_bot
================================================================================
CREATE OR REPLACE FUNCTION public.domino_play_and_bot(_game_id uuid, _move jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
  PERFORM public.domino_play(_game_id, _move);
  PERFORM public._domino_bot_step(_game_id);
END $function$


================================================================================
-- domino_pop_first
================================================================================
CREATE OR REPLACE FUNCTION public.domino_pop_first(_arr jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE SECURITY DEFINER
AS $function$
DECLARE _result jsonb;
BEGIN
  SELECT jsonb_agg(x) INTO _result
  FROM (SELECT x FROM jsonb_array_elements(_arr) WITH ORDINALITY AS ord(x, rn) WHERE rn > 1 ORDER BY rn) s;
  RETURN COALESCE(_result, '[]'::jsonb);
END;
$function$


================================================================================
-- domino_remove_at
================================================================================
CREATE OR REPLACE FUNCTION public.domino_remove_at(_arr jsonb, _idx integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE SECURITY DEFINER
AS $function$
DECLARE _result jsonb;
BEGIN
  SELECT jsonb_agg(x) INTO _result
  FROM (SELECT x FROM jsonb_array_elements(_arr) WITH ORDINALITY AS ord(x, rn) WHERE rn - 1 != _idx ORDER BY rn) s;
  RETURN COALESCE(_result, '[]'::jsonb);
END;
$function$


================================================================================
-- domino_set_ready
================================================================================
CREATE OR REPLACE FUNCTION public.domino_set_ready(_game_id uuid, _ready boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  _g record; _all boolean; _count int; _tiles jsonb; _dealt jsonb; _info jsonb;
  _state jsonb; _scores jsonb := '{}'::jsonb; _ts jsonb := '{}'::jsonb; _p record;
  _key text; _draw text; _delay interval;
BEGIN
  SELECT * INTO _g FROM public.domino_games WHERE id = _game_id;
  IF NOT FOUND OR _g.status != 'open' THEN RETURN; END IF;
  UPDATE public.domino_participants SET ready = _ready WHERE game_id = _game_id AND user_id = auth.uid() AND forfeited = false;
  SELECT bool_and(ready), count(*) INTO _all, _count FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  IF _count < 2 THEN _all := false; END IF;

  IF _all THEN
    _tiles := public.domino_generate_tiles();
    _dealt := public.domino_deal_tiles(_game_id, _tiles);
    _info := public.domino_find_first_player(_game_id, _dealt->'hands');
    _draw := COALESCE(_g.state->>'draw_mode', 'with');
    FOR _p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
      _key := COALESCE(_p.user_id::text, 'bot_'||_p.slot);
      _scores := _scores || jsonb_build_object(COALESCE(_p.user_id::text, _key), 0);
      _ts := _ts || jsonb_build_object(_key, 0);
    END LOOP;
    _state := jsonb_build_object(
      'phase','playing','round',1,'board','[]'::jsonb,'left_end',null,'right_end',null,
      'first_tile_idx',0,
      'hands',_dealt->'hands','stock',CASE WHEN _draw='without' THEN '[]'::jsonb ELSE _dealt->'stock' END,
      'passes',0,'last_pass_by',null,'draw_mode',_draw,
      'first_tile_rule',COALESCE(_g.state->>'first_tile_rule','libre'),
      'first_move_double',_info->>'double',
      'last_round',null,'break_until',null,'reveal_until',null);

    _delay := public._domino_turn_delay(_game_id, (_info->>'slot')::int);

    UPDATE public.domino_games SET
      status='playing', state=_state, current_turn=(_info->>'slot')::int,
      scores=_scores, turn_skips=_ts, started_at=now(),
      turn_deadline=now() + _delay,
      pot=_g.stake*_count, updated_at=now()
    WHERE id=_game_id;
  END IF;
  UPDATE public.domino_games SET updated_at = now() WHERE id = _game_id;
END;
$function$


================================================================================
-- domino_start_new_round
================================================================================
CREATE OR REPLACE FUNCTION public.domino_start_new_round(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  _game record; _tiles jsonb; _dealt jsonb; _info jsonb; _state jsonb; _draw text;
  _delay interval;
BEGIN
  SELECT * INTO _game FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND OR _game.status != 'playing' THEN RETURN; END IF;
  _tiles := public.domino_generate_tiles();
  _dealt := public.domino_deal_tiles(_game_id, _tiles);
  _info := public.domino_find_first_player(_game_id, _dealt->'hands');
  _draw := COALESCE(_game.state->>'draw_mode', 'with');
  _state := jsonb_build_object(
    'phase', 'playing', 'round', (_game.state->>'round')::int + 1,
    'board', '[]'::jsonb, 'left_end', null, 'right_end', null,
    'first_tile_idx', 0,
    'hands', _dealt->'hands', 'stock', CASE WHEN _draw = 'without' THEN '[]'::jsonb ELSE _dealt->'stock' END,
    'passes', 0, 'last_pass_by', null, 'draw_mode', _draw,
    'first_tile_rule', COALESCE(_game.state->>'first_tile_rule', 'libre'),
    'first_move_double', _info->>'double',
    'last_round', _game.state->'last_round', 'break_until', null, 'reveal_until', null);

  _delay := public._domino_turn_delay(_game_id, (_info->>'slot')::int);

  UPDATE public.domino_games SET
    state = _state, current_turn = (_info->>'slot')::int,
    turn_deadline = now() + _delay, updated_at = now()
  WHERE id = _game_id;
END;
$function$


================================================================================
-- domino_start_solo_bot
================================================================================
CREATE OR REPLACE FUNCTION public.domino_start_solo_bot(_max_players integer DEFAULT 2, _difficulty text DEFAULT 'medium'::text, _target_score integer DEFAULT 100, _draw_mode text DEFAULT 'with'::text, _first_tile_rule text DEFAULT 'libre'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
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

  RETURN v_game_id;
END $function$


================================================================================
-- domino_tick
================================================================================
CREATE OR REPLACE FUNCTION public.domino_tick(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  g record;
  cur_uid uuid;
  _cfg record;
  _skips int;
  _next int;
  remaining int;
  last_slot int;
  _break_until timestamptz;
  _reveal_until timestamptz;
  _deal_until timestamptz;
  required_slot int;
  board_empty boolean;
  cur_is_bot boolean;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

  IF (g.state->>'phase') = 'dealing' THEN
    _deal_until := NULLIF(g.state->>'deal_until','')::timestamptz;
    IF _deal_until IS NULL OR _deal_until <= now() THEN
      PERFORM public._domino_place_first(_game_id);
      PERFORM public._domino_bot_step(_game_id);
    END IF;
    RETURN;
  END IF;

  IF (g.state->>'phase') = 'reveal' THEN
    _reveal_until := NULLIF(g.state->>'reveal_until','')::timestamptz;
    IF _reveal_until IS NOT NULL AND _reveal_until <= now() THEN
      UPDATE public.domino_games
         SET state = jsonb_set(g.state, '{phase}', '"break"'::jsonb)
       WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;

  IF (g.state->>'phase') = 'break' THEN
    _break_until := NULLIF(g.state->>'break_until','')::timestamptz;
    IF _break_until IS NOT NULL AND _break_until <= now() THEN
      PERFORM public._domino_next_round(_game_id);
      PERFORM public._domino_bot_step(_game_id);
    END IF;
    RETURN;
  END IF;

  SELECT * INTO _cfg FROM public._game_cfg('domino');
  board_empty := jsonb_array_length(COALESCE(g.state->'board', '[]'::jsonb)) = 0;
  required_slot := public._domino_required_starter_slot(_game_id, g.state);

  IF board_empty AND required_slot IS NOT NULL AND required_slot <> g.current_turn THEN
    UPDATE public.domino_games
       SET current_turn = required_slot,
           turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
     WHERE id = _game_id;
    PERFORM public._domino_bot_step(_game_id);
    RETURN;
  END IF;

  SELECT COALESCE(dp.is_bot, false) INTO cur_is_bot
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id
     AND dp.slot = g.current_turn
     AND dp.forfeited = false;

  IF COALESCE(cur_is_bot, false) THEN
    PERFORM public._domino_bot_step(_game_id);
    RETURN;
  END IF;

  IF g.turn_deadline IS NULL OR g.turn_deadline > now() THEN RETURN; END IF;

  SELECT user_id INTO cur_uid
    FROM public.domino_participants
   WHERE game_id = _game_id
     AND slot = g.current_turn
     AND forfeited = false;

  IF cur_uid IS NULL THEN
    _next := public._domino_next_playable_slot(_game_id, g.current_turn, g.state);
    IF _next IS NOT NULL THEN
      UPDATE public.domino_games
         SET current_turn = _next,
             turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
       WHERE id = _game_id;
      PERFORM public._domino_bot_step(_game_id);
    END IF;
    RETURN;
  END IF;

  -- Le joueur n'a rien joué : s'il devait piocher, on pioche à sa place
  -- jusqu'à obtenir une tuile jouable, et on lui rend son temps.
  IF public._domino_auto_draw(_game_id) THEN
    RETURN;
  END IF;
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id;

  _skips := COALESCE((g.turn_skips->>cur_uid::text)::int, 0) + 1;

  IF _skips >= _cfg.max_turn_skips THEN
    UPDATE public.domino_participants
       SET forfeited = true
     WHERE game_id = _game_id
       AND user_id = cur_uid;

    SELECT count(*) INTO remaining
      FROM public.domino_participants
     WHERE game_id = _game_id
       AND forfeited = false;

    IF remaining <= 1 THEN
      SELECT slot INTO last_slot
        FROM public.domino_participants
       WHERE game_id = _game_id
         AND forfeited = false
       LIMIT 1;

      IF last_slot IS NOT NULL THEN
        PERFORM public._domino_finalize(_game_id, last_slot);
      ELSE
        UPDATE public.domino_games SET status='cancelled', finished_at=now() WHERE id = _game_id;
      END IF;
      RETURN;
    END IF;

    g.turn_skips := jsonb_set(COALESCE(g.turn_skips,'{}'::jsonb), ARRAY[cur_uid::text], to_jsonb(_skips), true);
    g.state := jsonb_set(g.state, ARRAY['hands', g.current_turn::text], '[]'::jsonb, true);
    required_slot := public._domino_required_starter_slot(_game_id, g.state);

    IF board_empty AND required_slot IS NOT NULL THEN
      UPDATE public.domino_games
         SET state = g.state,
             turn_skips = g.turn_skips,
             current_turn = required_slot,
             turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
       WHERE id = _game_id;
      PERFORM public._domino_bot_step(_game_id);
      RETURN;
    END IF;
  ELSE
    g.turn_skips := jsonb_set(COALESCE(g.turn_skips,'{}'::jsonb), ARRAY[cur_uid::text], to_jsonb(_skips), true);

    IF board_empty AND required_slot IS NOT NULL THEN
      UPDATE public.domino_games
         SET turn_skips = g.turn_skips,
             current_turn = required_slot,
             turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
       WHERE id = _game_id;
      PERFORM public._domino_bot_step(_game_id);
      RETURN;
    END IF;

    UPDATE public.domino_games SET turn_skips = g.turn_skips WHERE id = _game_id;
  END IF;

  _next := public._domino_next_playable_slot(_game_id, g.current_turn, g.state);
  IF _next IS NULL THEN
    _next := public._domino_lowest_pip_slot(_game_id, g.state);
    PERFORM public._domino_end_round(_game_id, _next);
    RETURN;
  END IF;

  UPDATE public.domino_games
     SET current_turn = _next,
         turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
   WHERE id = _game_id;

  PERFORM public._domino_bot_step(_game_id);
END;
$function$


================================================================================
-- domino_tick_all
================================================================================
CREATE OR REPLACE FUNCTION public.domino_tick_all()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  g_id uuid;
BEGIN
  FOR g_id IN
    SELECT g.id
      FROM public.domino_games g
     WHERE g.status = 'playing'
       AND (
         (g.turn_deadline IS NOT NULL AND g.turn_deadline <= now())
         OR (g.state->>'phase' = 'dealing' AND COALESCE(NULLIF(g.state->>'deal_until','')::timestamptz, now()) <= now())
         OR (g.state->>'phase' = 'reveal'  AND NULLIF(g.state->>'reveal_until','')::timestamptz <= now())
         OR (g.state->>'phase' = 'break'   AND NULLIF(g.state->>'break_until','')::timestamptz <= now())
         OR (
           EXISTS (
             SELECT 1
               FROM public.domino_participants p
              WHERE p.game_id = g.id
                AND p.slot = g.current_turn
                AND p.forfeited = false
                AND p.is_bot = true
           )
           AND (
             NULLIF(g.state->>'bot_think_until','')::timestamptz IS NULL
             OR NULLIF(g.state->>'bot_think_until','')::timestamptz <= now()
             OR COALESCE(NULLIF(g.state->>'bot_locked_slot','null')::int, -1) IS DISTINCT FROM g.current_turn
           )
         )
       )
  LOOP
    BEGIN
      PERFORM public.domino_tick(g_id);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
END;
$function$


