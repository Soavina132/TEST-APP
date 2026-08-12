-- ═══════════════════════════════════════════════════════════
-- FIX COMPLET DOMINO: 3 bugs critiques
-- ═══════════════════════════════════════════════════════════
-- Bug 1: "Tuile non trouvée" — domino_play ne rejette pas les
--         humains quand c'est le tour du bot (user_id IS NULL)
-- Bug 2: "could not determine polymorphic type" — to_jsonb() avec
--         une valeur NULL (quand required_slot ou _next est NULL)
-- Bug 3: Chargement infini — _domino_bot_loop trop lent avec
--         pg_sleep(0.5) entre chaque itération
-- ═══════════════════════════════════════════════════════════

-- ── Bug 1: domino_play — rejeter si c'est un bot ──
CREATE OR REPLACE FUNCTION public.domino_play(_game_id uuid, _move jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  g public.domino_games%ROWTYPE;
  st jsonb;
  v_slot INT;
  v_uid UUID := auth.uid();
  v_part record;
  v_action TEXT;
  v_tile_idx INT;
  v_side TEXT;
  v_playable jsonb;
  hand jsonb;
  tile jsonb;
  a INT; b INT;
  left_end INT; right_end INT;
  board jsonb;
  first_move_double INT;
  first_tile_rule TEXT;
  v_new_left INT; v_new_right INT;
  v_board_entry jsonb;
  v_passes INT;
  v_last_pass INT;
  v_next_slot INT;
  v_stock_len INT;
  v_draw_mode TEXT;
  i INT;
  v_active_count INT;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;

  st := g.state;
  v_slot := g.current_turn;
  SELECT * INTO v_part FROM public.domino_participants
    WHERE game_id=_game_id AND slot=v_slot;

  -- FIX Bug 1: Rejeter si c'est un bot ou si ce n'est pas le joueur humain
  IF v_part.user_id IS NULL OR v_part.user_id <> v_uid THEN
    RAISE EXCEPTION 'Pas votre tour';
  END IF;

  v_action := _move->>'action';

  -- ─── PLAY action ──────────────────────────────────────────────
  IF v_action = 'play' THEN
    v_side := COALESCE(_move->>'side', 'auto');
    hand := st->'hands'->v_slot::text;

    IF _move ? 'tile_idx' AND (_move->>'tile_idx') IS NOT NULL THEN
      v_tile_idx := (_move->>'tile_idx')::INT;
    ELSIF _move ? 'tile' THEN
      tile := _move->'tile';
      v_tile_idx := -1;
      IF jsonb_array_length(hand) > 0 THEN
        FOR i IN 0..jsonb_array_length(hand)-1 LOOP
          IF ((hand->i->>0)::INT = (tile->>0)::INT AND (hand->i->>1)::INT = (tile->>1)::INT)
             OR ((hand->i->>0)::INT = (tile->>1)::INT AND (hand->i->>1)::INT = (tile->>0)::INT) THEN
            v_tile_idx := i;
            EXIT;
          END IF;
        END LOOP;
      END IF;
      IF v_tile_idx = -1 THEN
        RAISE EXCEPTION 'Tuile non trouvée dans la main: %', tile;
      END IF;
    ELSE
      RAISE EXCEPTION 'Move doit contenir tile ou tile_idx';
    END IF;

    v_playable := public._domino_playable_tiles(st, v_slot);
    IF NOT (v_playable @> to_jsonb(v_tile_idx)) THEN
      RAISE EXCEPTION 'Tuile non jouable';
    END IF;

    tile := hand->v_tile_idx;
    a := (tile->>0)::INT;
    b := (tile->>1)::INT;
    board := st->'board';
    left_end := NULLIF(st->>'left_end','')::INT;
    right_end := NULLIF(st->>'right_end','')::INT;
    first_move_double := NULLIF(st->>'first_move_double','')::INT;
    first_tile_rule := COALESCE(st->>'first_tile_rule', 'libre');

    IF jsonb_array_length(board) = 0 THEN
      IF first_move_double IS NOT NULL THEN
        IF NOT (a = first_move_double AND b = first_move_double) THEN
          RAISE EXCEPTION 'Doit jouer le double %', first_move_double;
        END IF;
      ELSIF first_tile_rule = 'under6' THEN
        IF a + b >= 6 THEN RAISE EXCEPTION 'Somme doit etre < 6'; END IF;
      END IF;
      v_new_left := a;
      v_new_right := b;
      v_board_entry := jsonb_build_array(jsonb_build_object('tile', jsonb_build_array(a,b), 'slot', v_slot));
      st := jsonb_set(st, ARRAY['board'], v_board_entry);
      st := jsonb_set(st, ARRAY['left_end'], to_jsonb(v_new_left));
      st := jsonb_set(st, ARRAY['right_end'], to_jsonb(v_new_right));
      st := st - 'first_move_double';
    ELSE
      IF v_side = 'left' OR (v_side = 'auto' AND (a = left_end OR b = left_end)) THEN
        IF b = left_end THEN
          v_board_entry := jsonb_build_array(jsonb_build_object('tile', jsonb_build_array(b,a), 'slot', v_slot)) || board;
        ELSIF a = left_end THEN
          v_board_entry := jsonb_build_array(jsonb_build_object('tile', jsonb_build_array(a,b), 'slot', v_slot)) || board;
        ELSE
          RAISE EXCEPTION 'Ne match pas le côté gauche';
        END IF;
        v_new_left := CASE WHEN b = left_end THEN a ELSE b END;
        v_new_right := right_end;
        st := jsonb_set(st, ARRAY['board'], v_board_entry);
        st := jsonb_set(st, ARRAY['left_end'], to_jsonb(v_new_left));
      ELSIF v_side = 'right' OR (v_side = 'auto' AND (a = right_end OR b = right_end)) THEN
        IF a = right_end THEN
          v_board_entry := board || jsonb_build_array(jsonb_build_object('tile', jsonb_build_array(a,b), 'slot', v_slot));
        ELSIF b = right_end THEN
          v_board_entry := board || jsonb_build_array(jsonb_build_object('tile', jsonb_build_array(b,a), 'slot', v_slot));
        ELSE
          RAISE EXCEPTION 'Ne match pas le côté droit';
        END IF;
        v_new_left := left_end;
        v_new_right := CASE WHEN a = right_end THEN b ELSE a END;
        st := jsonb_set(st, ARRAY['board'], v_board_entry);
        st := jsonb_set(st, ARRAY['right_end'], to_jsonb(v_new_right));
      ELSE
        RAISE EXCEPTION 'Tuile ne match ni gauche ni droite';
      END IF;
    END IF;

    -- Remove tile from hand
    hand := hand - v_tile_idx;
    st := jsonb_set(st, ARRAY['hands'], jsonb_set(st->'hands', ARRAY[v_slot::text], hand));

    -- Reset passes
    st := jsonb_set(st, ARRAY['passes'], '0'::jsonb);
    st := jsonb_set(st, ARRAY['last_pass_by'], 'null'::jsonb);

    -- Check if hand is empty (round winner)
    IF jsonb_array_length(hand) = 0 THEN
      st := jsonb_set(st, ARRAY['turn_slot'], to_jsonb(v_slot), true);
      UPDATE public.domino_games SET state=st WHERE id=_game_id;
      PERFORM public._domino_end_round(_game_id, v_slot);
      RETURN public._domino_visible(_game_id);
    END IF;

    -- Advance turn
    v_next_slot := public._domino_next_playable_slot(_game_id, v_slot, st);
    -- FIX Bug 2: guard against NULL
    IF v_next_slot IS NULL THEN
      v_next_slot := public._domino_lowest_pip_slot(_game_id, st);
      IF v_next_slot IS NOT NULL THEN
        st := jsonb_set(st, ARRAY['turn_slot'], to_jsonb(v_next_slot), true);
        UPDATE public.domino_games SET state=st WHERE id=_game_id;
        PERFORM public._domino_end_round(_game_id, v_next_slot);
        RETURN public._domino_visible(_game_id);
      END IF;
      -- All NULL — shouldn't happen, but guard
      RETURN public._domino_visible(_game_id);
    END IF;
    st := jsonb_set(st, ARRAY['turn_slot'], to_jsonb(v_next_slot), true);
    st := jsonb_set(st, ARRAY['turn_started_at'], to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    v_playable := public._domino_playable_tiles(st, v_next_slot);
    st := jsonb_set(st, ARRAY['playable_tiles'], v_playable, true);
    st := jsonb_set(st, ARRAY['last_event'], to_jsonb('play'));

    UPDATE public.domino_games SET state=st, current_turn=v_next_slot WHERE id=_game_id;
    RETURN public._domino_visible(_game_id);

  -- ─── DRAW action ──────────────────────────────────────────────
  ELSIF v_action = 'draw' THEN
    v_stock_len := COALESCE(jsonb_array_length(st->'stock'), 0);
    IF v_stock_len = 0 THEN RAISE EXCEPTION 'Stock vide'; END IF;
    hand := st->'hands'->v_slot::text;
    tile := st->'stock'->0;
    st := jsonb_set(st, ARRAY['stock'], st->'stock' - 0);
    hand := hand || tile;
    st := jsonb_set(st, ARRAY['hands'], jsonb_set(st->'hands', ARRAY[v_slot::text], hand));
    v_playable := public._domino_playable_tiles(st, v_slot);
    st := jsonb_set(st, ARRAY['playable_tiles'], v_playable, true);
    st := jsonb_set(st, ARRAY['turn_slot'], to_jsonb(v_slot), true);
    st := jsonb_set(st, ARRAY['last_event'], to_jsonb('draw'));
    UPDATE public.domino_games SET state=st WHERE id=_game_id;
    RETURN public._domino_visible(_game_id);

  -- ─── PASS action ───────────────────────────────────────────────
  ELSIF v_action = 'pass' THEN
    v_playable := public._domino_playable_tiles(st, v_slot);
    IF jsonb_array_length(v_playable) > 0 THEN
      RAISE EXCEPTION 'Vous avez un domino jouable';
    END IF;
    v_draw_mode := COALESCE(st->>'draw_mode', 'with');
    v_stock_len := COALESCE(jsonb_array_length(st->'stock'), 0);
    IF v_draw_mode = 'with' AND v_stock_len > 0 THEN
      RAISE EXCEPTION 'Vous devez piocher avant de passer';
    END IF;

    v_passes := COALESCE((st->>'passes')::INT, 0) + 1;
    v_last_pass := v_slot;
    st := jsonb_set(st, ARRAY['passes'], to_jsonb(v_passes));
    st := jsonb_set(st, ARRAY['last_pass_by'], to_jsonb(v_last_pass));

    SELECT count(*) INTO v_active_count FROM public.domino_participants
      WHERE game_id=_game_id AND NOT forfeited;
    IF v_passes >= v_active_count THEN
      st := jsonb_set(st, ARRAY['turn_slot'], to_jsonb(v_slot), true);
      UPDATE public.domino_games SET state=st WHERE id=_game_id;
      PERFORM public._domino_end_round(_game_id, public._domino_lowest_pip_slot(_game_id, st));
      RETURN public._domino_visible(_game_id);
    END IF;

    v_next_slot := public._domino_next_playable_slot(_game_id, v_slot, st);
    -- FIX Bug 2: guard against NULL
    IF v_next_slot IS NULL THEN
      v_next_slot := public._domino_lowest_pip_slot(_game_id, st);
      IF v_next_slot IS NOT NULL THEN
        st := jsonb_set(st, ARRAY['turn_slot'], to_jsonb(v_next_slot), true);
        UPDATE public.domino_games SET state=st WHERE id=_game_id;
        PERFORM public._domino_end_round(_game_id, v_next_slot);
        RETURN public._domino_visible(_game_id);
      END IF;
      RETURN public._domino_visible(_game_id);
    END IF;
    st := jsonb_set(st, ARRAY['turn_slot'], to_jsonb(v_next_slot), true);
    st := jsonb_set(st, ARRAY['turn_started_at'], to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    v_playable := public._domino_playable_tiles(st, v_next_slot);
    st := jsonb_set(st, ARRAY['playable_tiles'], v_playable, true);
    st := jsonb_set(st, ARRAY['last_event'], to_jsonb('pass'));
    UPDATE public.domino_games SET state=st, current_turn=v_next_slot WHERE id=_game_id;
    RETURN public._domino_visible(_game_id);

  ELSE
    RAISE EXCEPTION 'Action inconnue: %', v_action;
  END IF;
END
$function$;

-- ── Bug 2: domino_tick — guard to_jsonb(NULL) ──
CREATE OR REPLACE FUNCTION public.domino_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  g record; cur_uid uuid; _cfg record; _skips int; _next int;
  remaining int; last_slot int;
  _break_until timestamptz; _reveal_until timestamptz; _deal_until timestamptz;
  required_slot int; board_empty boolean;
  v_is_bot boolean := false;
  v_think_until timestamptz;
  v_draw_mode text;
  v_stock_len int;
  v_drew_playable boolean;
  v_state jsonb;
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
    g.state := public._domino_arm_bot_think(_game_id, required_slot, g.state);
    v_state := jsonb_set(g.state, ARRAY['turn_slot'], to_jsonb(required_slot), true);
    UPDATE public.domino_games
       SET state = v_state, current_turn = required_slot,
           turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
     WHERE id = _game_id;
    RETURN;
  END IF;

  SELECT COALESCE(dp.is_bot, false), dp.user_id
    INTO v_is_bot, cur_uid
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id
     AND dp.slot = g.current_turn
     AND dp.forfeited = false;

  IF COALESCE(v_is_bot, false) THEN
    v_think_until := NULLIF(g.state->>'bot_think_until','')::timestamptz;
    IF v_think_until IS NOT NULL AND v_think_until <= now() THEN
      PERFORM public._domino_bot_step(_game_id);
    ELSIF v_think_until IS NULL THEN
      PERFORM public._domino_bot_step(_game_id);
    END IF;
    RETURN;
  END IF;

  IF g.turn_deadline IS NULL OR g.turn_deadline > now() THEN RETURN; END IF;

  IF cur_uid IS NULL THEN
    _next := public._domino_next_playable_slot(_game_id, g.current_turn, g.state);
    IF _next IS NOT NULL THEN
      g.state := public._domino_arm_bot_think(_game_id, _next, g.state);
      v_state := jsonb_set(g.state, ARRAY['turn_slot'], to_jsonb(_next), true);
      UPDATE public.domino_games SET state = v_state, current_turn = _next,
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;

  IF NOT public._domino_slot_has_playable(g.state, g.current_turn) THEN
    v_draw_mode := COALESCE(g.state->>'draw_mode', 'with');
    v_stock_len := jsonb_array_length(COALESCE(g.state->'stock', '[]'::jsonb));
    v_drew_playable := false;

    IF v_draw_mode = 'with' AND v_stock_len > 0 THEN
      v_drew_playable := public._domino_auto_draw(_game_id);
    END IF;

    IF v_drew_playable THEN
      RETURN;
    END IF;

    PERFORM public._domino_force_pass(_game_id, g.current_turn);
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
      g.state := public._domino_arm_bot_think(_game_id, required_slot, g.state);
      v_state := jsonb_set(g.state, ARRAY['turn_slot'], to_jsonb(required_slot), true);
      UPDATE public.domino_games SET state = v_state, turn_skips = g.turn_skips,
        current_turn = required_slot,
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
      RETURN;
    END IF;
  ELSE
    g.turn_skips := jsonb_set(COALESCE(g.turn_skips,'{}'::jsonb), ARRAY[cur_uid::text], to_jsonb(_skips), true);
    IF board_empty AND required_slot IS NOT NULL THEN
      g.state := public._domino_arm_bot_think(_game_id, required_slot, g.state);
      v_state := jsonb_set(g.state, ARRAY['turn_slot'], to_jsonb(required_slot), true);
      UPDATE public.domino_games SET state = v_state, turn_skips = g.turn_skips,
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

  g.state := public._domino_arm_bot_think(_game_id, _next, g.state);
  v_state := jsonb_set(g.state, ARRAY['turn_slot'], to_jsonb(_next), true);
  UPDATE public.domino_games SET state = v_state, current_turn = _next,
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
END
$function$;

-- ── Bug 3: _domino_bot_loop — réduire pg_sleep à 0.1s ──
CREATE OR REPLACE FUNCTION public._domino_bot_loop(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  v_is_bot boolean;
  v_max_loops int := 60;
  g_status text;
  g_phase text;
  v_turn int;
  v_until timestamptz;
  v_sleep_sec numeric;
BEGIN
  LOOP
    EXIT WHEN v_max_loops <= 0;
    v_max_loops := v_max_loops - 1;

    SELECT status::text, state->>'phase' INTO g_status, g_phase
      FROM public.domino_games WHERE id = _game_id;
    EXIT WHEN g_status IS NULL OR g_status <> 'playing';

    IF g_phase = 'reveal' THEN
      SELECT NULLIF(state->>'reveal_until', '')::timestamptz INTO v_until
        FROM public.domino_games WHERE id = _game_id;
      IF v_until IS NOT NULL AND v_until > now() THEN
        v_sleep_sec := EXTRACT(epoch FROM (v_until - now()));
        IF v_sleep_sec > 0 AND v_sleep_sec < 15 THEN
          PERFORM pg_sleep(v_sleep_sec);
        END IF;
      END IF;
      PERFORM public.domino_tick(_game_id);
      CONTINUE;
    END IF;

    IF g_phase = 'break' THEN
      SELECT NULLIF(state->>'break_until', '')::timestamptz INTO v_until
        FROM public.domino_games WHERE id = _game_id;
      IF v_until IS NOT NULL AND v_until > now() THEN
        v_sleep_sec := EXTRACT(epoch FROM (v_until - now()));
        IF v_sleep_sec > 0 AND v_sleep_sec < 15 THEN
          PERFORM pg_sleep(v_sleep_sec);
        END IF;
      END IF;
      PERFORM public.domino_tick(_game_id);
      CONTINUE;
    END IF;

    IF g_phase = 'dealing' THEN
      SELECT NULLIF(state->>'deal_until', '')::timestamptz INTO v_until
        FROM public.domino_games WHERE id = _game_id;
      IF v_until IS NOT NULL AND v_until > now() THEN
        v_sleep_sec := EXTRACT(epoch FROM (v_until - now()));
        IF v_sleep_sec > 0 AND v_sleep_sec < 10 THEN
          PERFORM pg_sleep(v_sleep_sec);
        END IF;
      END IF;
      PERFORM public.domino_tick(_game_id);
      CONTINUE;
    END IF;

    EXIT WHEN g_phase NOT IN ('play', 'playing');

    SELECT COALESCE(dp.is_bot, false), g.current_turn INTO v_is_bot, v_turn
      FROM public.domino_participants dp
      JOIN public.domino_games g ON g.id = dp.game_id
     WHERE dp.game_id = _game_id
       AND dp.slot = g.current_turn
       AND dp.forfeited = false;

    EXIT WHEN NOT COALESCE(v_is_bot, false);

    -- Forcer bot_think_until dans le passe
    UPDATE public.domino_games
       SET state = jsonb_set(
             jsonb_set(state, '{bot_think_until}',
               to_jsonb((now() - interval '10 seconds')::timestamptz::text), true),
             '{bot_locked_slot}', to_jsonb(v_turn), true)
     WHERE id = _game_id;

    PERFORM public.domino_tick(_game_id);
    -- FIX Bug 3: réduit de 0.5s à 0.1s pour accélérer le bot
    PERFORM pg_sleep(0.1);
  END LOOP;
END
$function$;
