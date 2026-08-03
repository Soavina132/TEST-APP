ALTER TABLE public.domino_games
  ADD COLUMN IF NOT EXISTS first_tile_rule text NOT NULL DEFAULT 'libre';

UPDATE public.app_settings SET game_invite_timeout_minutes = 6 WHERE id = 1 AND COALESCE(game_invite_timeout_minutes,0) < 6;
ALTER TABLE public.app_settings ALTER COLUMN game_invite_timeout_minutes SET DEFAULT 6;

CREATE OR REPLACE FUNCTION public._auto_cancel_open_games()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  r record;
  v_min int;
  v_iv interval;
BEGIN
  SELECT COALESCE(game_invite_timeout_minutes, 6) INTO v_min FROM public.app_settings WHERE id = 1;
  IF v_min IS NULL OR v_min <= 0 THEN v_min := 6; END IF;
  v_iv := (v_min || ' minutes')::interval;

  FOR r IN SELECT id, stake FROM public.fanorona_games WHERE status='open' AND created_at < now() - v_iv
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      FROM public.fanorona_participants pp
      WHERE pp.game_id = r.id AND pp.user_id = p.id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT user_id, 'fanorona_refund', r.stake, r.id, 'Auto-cancelled'
      FROM public.fanorona_participants WHERE game_id = r.id;
    UPDATE public.fanorona_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;

  FOR r IN SELECT id, stake FROM public.chess_games WHERE status='open' AND created_at < now() - v_iv
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      WHERE p.id IN (SELECT host_id FROM public.chess_games WHERE id=r.id);
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT host_id, 'chess_refund', r.stake, r.id, 'Auto-cancelled'
      FROM public.chess_games WHERE id=r.id;
    UPDATE public.chess_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;

  FOR r IN SELECT id, stake FROM public.domino_games WHERE status='open' AND created_at < now() - v_iv
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      FROM public.domino_participants pp
      WHERE pp.game_id = r.id AND pp.user_id = p.id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT user_id, 'domino_refund', r.stake, r.id, 'Auto-cancelled'
      FROM public.domino_participants WHERE game_id = r.id;
    UPDATE public.domino_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;

  FOR r IN SELECT id, stake FROM public.rami_games WHERE status='waiting' AND created_at < now() - v_iv
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      FROM public.rami_participants pp
      WHERE pp.game_id = r.id AND pp.user_id = p.id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT user_id, 'rami_refund', r.stake, r.id, 'Auto-cancelled'
      FROM public.rami_participants WHERE game_id = r.id;
    UPDATE public.rami_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;

  FOR r IN SELECT id, stake FROM public.ludo_games WHERE status='open' AND created_at < now() - v_iv
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      FROM public.ludo_participants pp
      WHERE pp.game_id = r.id AND pp.user_id = p.id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT user_id, 'ludo_refund', r.stake, r.id, 'Auto-cancelled'
      FROM public.ludo_participants WHERE game_id = r.id;
    UPDATE public.ludo_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;
END $function$;

CREATE OR REPLACE FUNCTION public.domino_create(
  _stake numeric, _max integer, _private boolean,
  _mode text DEFAULT 'classic', _commission numeric DEFAULT 10,
  _target_score integer DEFAULT 0, _draw_mode text DEFAULT 'with',
  _first_tile_rule text DEFAULT 'libre'
)
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
END $function$;

CREATE OR REPLACE FUNCTION public._domino_next_round(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  g record; n int; tiles jsonb; hands jsonb := '{}'::jsonb;
  stock jsonb; per_hand int := 7; p record; idx int := 0; hand jsonb;
  starter int := 0; best int := -1; cur_dbl int; t jsonb;
  starter_double int := -1;
  _cfg record;
  v_round int;
  v_rule text;
  v_prev_starter int;
  slots int[];
  i int;
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
  ELSIF v_rule = 'libre' THEN
    FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
      cur_dbl := -1;
      FOR t IN SELECT * FROM jsonb_array_elements(hands -> p.slot::text) LOOP
        IF (t->>0)::int = (t->>1)::int AND (t->>0)::int > cur_dbl THEN cur_dbl := (t->>0)::int; END IF;
      END LOOP;
      IF cur_dbl > best THEN best := cur_dbl; starter := p.slot; starter_double := cur_dbl; END IF;
    END LOOP;
  ELSE
    starter := slots[1];
    starter_double := -1;
  END IF;

  SELECT * INTO _cfg FROM public._game_cfg('domino');

  UPDATE public.domino_games SET
    current_turn = starter,
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
    state = jsonb_build_object(
      'phase','playing',
      'hands', hands,
      'stock', stock,
      'board', '[]'::jsonb,
      'left_end', 'null'::jsonb,
      'right_end', 'null'::jsonb,
      'passes', 0,
      'scores', COALESCE(g.state->'scores','{}'::jsonb),
      'round', v_round,
      'last_round', g.state->'last_round',
      'draw_mode', COALESCE(g.state->>'draw_mode','with'),
      'first_tile_rule', v_rule,
      'starter_slot', to_jsonb(starter),
      'first_move_double', CASE WHEN starter_double >= 0 THEN to_jsonb(starter_double) ELSE 'null'::jsonb END
    )
  WHERE id = _game_id;
END $function$;

CREATE OR REPLACE FUNCTION public.domino_play(_game_id uuid, _move jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  g record; my_slot int; st jsonb; hand jsonb; tile jsonb;
  a int; b int; le int; re int; side text;
  new_left int; new_right int; action text; next_turn int;
  drawn jsonb; stock jsonb; found boolean := false; new_hand jsonb; i int;
  _cfg record;
  has_playable boolean := false;
  draw_mode text;
  is_first_move boolean;
  first_dbl int;
  matches_left boolean;
  matches_right boolean;
  winner_slot int;
  v_rule text;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  IF (g.state->>'phase') IN ('break','reveal') THEN RAISE EXCEPTION 'round break'; END IF;

  SELECT slot INTO my_slot FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid AND forfeited = false;
  IF my_slot IS NULL OR my_slot <> g.current_turn THEN RAISE EXCEPTION 'not your turn'; END IF;

  st := g.state;
  action := _move->>'action';
  hand := COALESCE(st -> 'hands' -> my_slot::text, '[]'::jsonb);
  stock := COALESCE(st -> 'stock','[]'::jsonb);
  le := NULLIF(st->>'left_end','null')::int;
  re := NULLIF(st->>'right_end','null')::int;
  draw_mode := COALESCE(st->>'draw_mode','with');
  v_rule := COALESCE(st->>'first_tile_rule','libre');
  SELECT * INTO _cfg FROM public._game_cfg('domino');
  is_first_move := jsonb_array_length(COALESCE(st->'board','[]'::jsonb)) = 0;
  has_playable := public._domino_slot_has_playable(st, my_slot);

  IF action = 'draw' THEN
    IF draw_mode = 'without' THEN RAISE EXCEPTION 'draw disabled in this game'; END IF;
    IF has_playable THEN RAISE EXCEPTION 'you have a playable tile'; END IF;
    IF jsonb_array_length(stock) = 0 THEN RAISE EXCEPTION 'stock empty'; END IF;
    drawn := stock -> 0; stock := stock - 0;
    hand := hand || jsonb_build_array(drawn);
    st := jsonb_set(st, ARRAY['hands', my_slot::text], hand);
    st := jsonb_set(st, '{stock}', stock);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    RETURN;
  END IF;

  IF action = 'pass' THEN
    IF has_playable THEN RAISE EXCEPTION 'you must play'; END IF;
    IF draw_mode = 'with' AND jsonb_array_length(stock) > 0 THEN RAISE EXCEPTION 'you must draw first'; END IF;

    st := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1));
    next_turn := public._domino_next_playable_slot(_game_id, my_slot, st);

    IF next_turn IS NULL THEN
      winner_slot := public._domino_lowest_pip_slot(_game_id, st);
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
      IF winner_slot IS NOT NULL THEN
        PERFORM public._domino_end_round(_game_id, winner_slot);
      END IF;
      RETURN;
    END IF;

    UPDATE public.domino_games SET state = st, current_turn = next_turn,
      turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
    RETURN;
  END IF;

  tile := _move -> 'tile';
  side := _move->>'side';
  a := (tile->>0)::int; b := (tile->>1)::int;

  new_hand := '[]'::jsonb;
  FOR i IN 0..jsonb_array_length(hand)-1 LOOP
    IF NOT found AND ((hand->i->>0)::int = a AND (hand->i->>1)::int = b) THEN found := true;
    ELSE new_hand := new_hand || jsonb_build_array(hand->i); END IF;
  END LOOP;
  IF NOT found THEN RAISE EXCEPTION 'tile not in hand'; END IF;

  IF is_first_move THEN
    first_dbl := NULLIF(st->>'first_move_double','null')::int;
    IF first_dbl IS NOT NULL THEN
      IF NOT (a = first_dbl AND b = first_dbl) THEN
        RAISE EXCEPTION 'first move must be the highest double (%-%)', first_dbl, first_dbl;
      END IF;
    ELSIF v_rule = 'under6' THEN
      IF (a + b) >= 6 THEN
        RAISE EXCEPTION '1er domino doit avoir un total < 6';
      END IF;
    END IF;
    st := jsonb_set(st, '{board}', jsonb_build_array(jsonb_build_object('tile', tile, 'flipped', false)));
    new_left := a; new_right := b;
  ELSE
    matches_left := (a = le OR b = le);
    matches_right := (a = re OR b = re);
    IF side IS NULL OR side NOT IN ('left','right')
       OR (side = 'left' AND NOT matches_left)
       OR (side = 'right' AND NOT matches_right) THEN
      IF matches_right THEN side := 'right';
      ELSIF matches_left THEN side := 'left';
      ELSE RAISE EXCEPTION 'tile does not match either end'; END IF;
    END IF;

    IF side = 'left' THEN
      IF a = le THEN new_left := b; ELSE new_left := a; END IF;
      st := jsonb_set(st, '{board}', jsonb_build_array(jsonb_build_object('tile', tile, 'flipped', a<>le)) || (st->'board'));
      new_right := re;
    ELSE
      IF a = re THEN new_right := b; ELSE new_right := a; END IF;
      st := jsonb_set(st, '{board}', (st->'board') || jsonb_build_array(jsonb_build_object('tile', tile, 'flipped', a=re AND a<>b)));
      new_left := le;
    END IF;
  END IF;

  st := jsonb_set(st, ARRAY['hands', my_slot::text], new_hand);
  st := jsonb_set(st, '{left_end}', to_jsonb(new_left));
  st := jsonb_set(st, '{right_end}', to_jsonb(new_right));
  st := jsonb_set(st, '{passes}', to_jsonb(0));
  st := jsonb_set(st, '{first_move_double}', 'null'::jsonb);

  IF jsonb_array_length(new_hand) = 0 THEN
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_end_round(_game_id, my_slot);
    RETURN;
  END IF;

  next_turn := public._domino_next_playable_slot(_game_id, my_slot, st);
  IF next_turn IS NULL THEN
    winner_slot := public._domino_lowest_pip_slot(_game_id, st);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    IF winner_slot IS NOT NULL THEN
      PERFORM public._domino_end_round(_game_id, winner_slot);
    END IF;
    RETURN;
  END IF;

  UPDATE public.domino_games SET state = st, current_turn = next_turn,
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
END $function$;

CREATE OR REPLACE FUNCTION public._domino_end_round(_game_id uuid, _winner_slot integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  g record; st jsonb; winner_uid uuid; round_score int := 0;
  hand_pips jsonb := '{}'::jsonb; p record; pips int;
  v_scores jsonb; new_total int;
  v_final_hands jsonb := '{}'::jsonb;
  v_blocked boolean := false;
  winner_hand jsonb;
  v_reveal interval := interval '3 seconds';
  v_break_total interval := interval '13 seconds';
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN; END IF;

  SELECT user_id INTO winner_uid FROM public.domino_participants WHERE game_id = _game_id AND slot = _winner_slot;
  st := g.state;

  winner_hand := st->'hands'->_winner_slot::text;
  v_blocked := COALESCE(jsonb_array_length(winner_hand), 0) > 0;

  FOR p IN SELECT slot, user_id FROM public.domino_participants WHERE game_id = _game_id LOOP
    pips := public._domino_hand_pips(st->'hands'->p.slot::text);
    hand_pips := hand_pips || jsonb_build_object(p.user_id::text, pips);
    v_final_hands := v_final_hands || jsonb_build_object(p.user_id::text, COALESCE(st->'hands'->p.slot::text, '[]'::jsonb));
    IF p.slot <> _winner_slot THEN round_score := round_score + pips; END IF;
  END LOOP;

  IF COALESCE(g.target_score,0) <= 0 THEN
    PERFORM public._domino_finalize(_game_id, _winner_slot);
    RETURN;
  END IF;

  v_scores := COALESCE(g.scores, '{}'::jsonb);
  new_total := COALESCE((v_scores->>winner_uid::text)::int, 0) + round_score;
  v_scores := jsonb_set(v_scores, ARRAY[winner_uid::text], to_jsonb(new_total), true);

  UPDATE public.domino_games SET scores = v_scores WHERE id = _game_id;

  IF new_total >= g.target_score THEN
    st := jsonb_set(st, '{last_round}', jsonb_build_object(
      'winner_uid', winner_uid, 'round_score', round_score, 'hand_pips', hand_pips,
      'final_hands', v_final_hands, 'blocked', v_blocked, 'final', true
    ));
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_finalize(_game_id, _winner_slot);
    RETURN;
  END IF;

  st := jsonb_set(st, '{phase}', '"reveal"'::jsonb);
  st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text));
  st := jsonb_set(st, '{break_until}', to_jsonb((now() + v_break_total)::text));
  st := jsonb_set(st, '{last_round}', jsonb_build_object(
    'winner_uid', winner_uid, 'round_score', round_score, 'hand_pips', hand_pips,
    'final_hands', v_final_hands, 'blocked', v_blocked, 'final', false
  ));
  st := jsonb_set(st, '{scores}', v_scores);
  UPDATE public.domino_games SET state = st, turn_deadline = NULL WHERE id = _game_id;
END $function$;

CREATE OR REPLACE FUNCTION public.domino_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  g record; cur_uid uuid; _cfg record; _skips int; _next int;
  remaining int; last_slot int;
  _break_until timestamptz; _reveal_until timestamptz; _deal_until timestamptz;
  required_slot int; board_empty boolean;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

  IF (g.state->>'phase') = 'dealing' THEN
    _deal_until := NULLIF(g.state->>'deal_until','')::timestamptz;
    IF _deal_until IS NOT NULL AND _deal_until <= now() THEN
      PERFORM public._domino_place_first(_game_id);
    END IF;
    RETURN;
  END IF;

  IF (g.state->>'phase') = 'reveal' THEN
    _reveal_until := NULLIF(g.state->>'reveal_until','')::timestamptz;
    IF _reveal_until IS NOT NULL AND _reveal_until <= now() THEN
      UPDATE public.domino_games SET state = jsonb_set(g.state, '{phase}', '"break"'::jsonb) WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;

  IF (g.state->>'phase') = 'break' THEN
    _break_until := NULLIF(g.state->>'break_until','')::timestamptz;
    IF _break_until IS NOT NULL AND _break_until <= now() THEN
      PERFORM public._domino_next_round(_game_id);
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
    RETURN;
  END IF;

  IF g.turn_deadline IS NULL OR g.turn_deadline > now() THEN RETURN; END IF;

  SELECT user_id INTO cur_uid
    FROM public.domino_participants
   WHERE game_id = _game_id AND slot = g.current_turn AND forfeited = false;

  IF cur_uid IS NULL THEN
    _next := public._domino_next_playable_slot(_game_id, g.current_turn, g.state);
    IF _next IS NOT NULL THEN
      UPDATE public.domino_games SET current_turn = _next,
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;

  _skips := COALESCE((g.turn_skips->>cur_uid::text)::int, 0) + 1;

  IF _skips >= _cfg.max_turn_skips THEN
    UPDATE public.domino_participants SET forfeited = true WHERE game_id = _game_id AND user_id = cur_uid;
    SELECT count(*) INTO remaining FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
    IF remaining <= 1 THEN
      SELECT slot INTO last_slot FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false LIMIT 1;
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
      UPDATE public.domino_games SET state = g.state, turn_skips = g.turn_skips,
        current_turn = required_slot,
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
      RETURN;
    END IF;
  ELSE
    g.turn_skips := jsonb_set(COALESCE(g.turn_skips,'{}'::jsonb), ARRAY[cur_uid::text], to_jsonb(_skips), true);
    IF board_empty AND required_slot IS NOT NULL THEN
      UPDATE public.domino_games SET turn_skips = g.turn_skips,
        current_turn = required_slot,
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
      RETURN;
    END IF;
    UPDATE public.domino_games SET turn_skips = g.turn_skips WHERE id = _game_id;
  END IF;

  _next := public._domino_next_playable_slot(_game_id, g.current_turn, g.state);
  IF _next IS NULL THEN
    _next := public._domino_lowest_pip_slot(_game_id, g.state);
    IF _next IS NOT NULL THEN
      PERFORM public._domino_end_round(_game_id, _next);
    END IF;
    RETURN;
  END IF;

  UPDATE public.domino_games SET current_turn = _next,
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
END $function$;