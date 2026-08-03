CREATE OR REPLACE FUNCTION public._domino_end_round(_game_id uuid, _winner_slot integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  g              record;
  st             jsonb;
  winner_uid     uuid;
  winner_key     text;
  round_score    int   := 0;
  hand_pips      jsonb := '{}'::jsonb;
  v_final_hands  jsonb := '{}'::jsonb;
  p              record;
  p_key          text;
  pips           int;
  v_scores       jsonb;
  new_total      int;
  v_blocked      boolean := false;
  winner_hand    jsonb;
  v_reveal       interval := interval '3 seconds';
  v_break_total  interval := interval '13 seconds';
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN; END IF;

  -- Protection idempotente : une manche déjà en écran résultat / pause
  -- ne doit jamais être recalculée ni ajouter ses points une 2e fois.
  IF COALESCE(g.state->>'phase', 'play') IN ('reveal', 'break') THEN
    RETURN;
  END IF;

  -- ── Match nul (aucun gagnant) : nouvelle manche, aucun point ─────────────
  IF _winner_slot IS NULL THEN
    st := g.state;
    FOR p IN SELECT slot, user_id FROM public.domino_participants WHERE game_id = _game_id LOOP
      p_key         := COALESCE(p.user_id::text, 'bot_' || p.slot::text);
      pips          := public._domino_hand_pips(st->'hands'->p.slot::text);
      hand_pips     := hand_pips     || jsonb_build_object(p_key, pips);
      v_final_hands := v_final_hands || jsonb_build_object(p_key, COALESCE(st->'hands'->p.slot::text, '[]'::jsonb));
    END LOOP;

    st := jsonb_set(st, '{phase}',        '"reveal"'::jsonb);
    st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text));
    st := jsonb_set(st, '{break_until}',  to_jsonb((now() + v_break_total)::text));
    st := jsonb_set(st, '{last_round}', jsonb_build_object(
      'winner_uid',  NULL::text,
      'round_score', 0,
      'hand_pips',   hand_pips,
      'final_hands', v_final_hands,
      'blocked',     true,
      'draw',        true,
      'final',       false
    ));
    st := jsonb_set(st, '{scores}', COALESCE(g.scores, g.state->'scores', '{}'::jsonb));
    UPDATE public.domino_games SET state = st, turn_deadline = NULL WHERE id = _game_id;
    RETURN;
  END IF;

  -- ── Victoire d'une manche ────────────────────────────────────────────────
  SELECT user_id INTO winner_uid
    FROM public.domino_participants
   WHERE game_id = _game_id AND slot = _winner_slot;
  winner_key := COALESCE(winner_uid::text, 'bot_' || _winner_slot::text);

  st := g.state;
  winner_hand := st->'hands'->_winner_slot::text;
  v_blocked   := COALESCE(jsonb_array_length(winner_hand), 0) > 0;

  FOR p IN SELECT slot, user_id FROM public.domino_participants WHERE game_id = _game_id LOOP
    p_key         := COALESCE(p.user_id::text, 'bot_' || p.slot::text);
    pips          := public._domino_hand_pips(st->'hands'->p.slot::text);
    hand_pips     := hand_pips     || jsonb_build_object(p_key, pips);
    v_final_hands := v_final_hands || jsonb_build_object(p_key, COALESCE(st->'hands'->p.slot::text, '[]'::jsonb));
    IF p.slot <> _winner_slot THEN round_score := round_score + pips; END IF;
  END LOOP;

  -- Mode « Victoire directe » : la partie se termine immédiatement
  IF COALESCE(g.target_score, 0) <= 0 THEN
    PERFORM public._domino_finalize(_game_id, _winner_slot);
    RETURN;
  END IF;

  -- Mode « Par points » : cumul du score de la manche pour le gagnant
  v_scores  := COALESCE(g.scores, g.state->'scores', '{}'::jsonb);
  new_total := COALESCE((v_scores->>winner_key)::int, 0) + round_score;
  v_scores  := jsonb_set(v_scores, ARRAY[winner_key], to_jsonb(new_total), true);

  -- Objectif atteint → fin de partie
  IF new_total >= g.target_score THEN
    st := jsonb_set(st, '{last_round}', jsonb_build_object(
      'winner_uid',  winner_key,
      'round_score', round_score,
      'hand_pips',   hand_pips,
      'final_hands', v_final_hands,
      'blocked',     v_blocked,
      'final',       true
    ));
    UPDATE public.domino_games SET scores = v_scores, state = st WHERE id = _game_id;
    PERFORM public._domino_finalize(_game_id, _winner_slot);
    RETURN;
  END IF;

  -- Objectif pas encore atteint → nouvelle manche automatique
  st := jsonb_set(st, '{phase}',        '"reveal"'::jsonb);
  st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text));
  st := jsonb_set(st, '{break_until}',  to_jsonb((now() + v_break_total)::text));
  st := jsonb_set(st, '{last_round}', jsonb_build_object(
    'winner_uid',  winner_key,
    'round_score', round_score,
    'hand_pips',   hand_pips,
    'final_hands', v_final_hands,
    'blocked',     v_blocked,
    'final',       false
  ));
  st := jsonb_set(st, '{scores}', v_scores);
  UPDATE public.domino_games SET scores = v_scores, state = st, turn_deadline = NULL WHERE id = _game_id;
END;
$function$;

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
$function$;

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
$function$;