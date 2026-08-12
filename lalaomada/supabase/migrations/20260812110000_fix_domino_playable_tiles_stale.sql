-- Bug majeur: quand un BOT joue/pioche/passe (_domino_bot_step), ou quand un
-- humain pioche/passe automatiquement au timeout (_domino_auto_draw,
-- _domino_force_pass), l'état 'playable_tiles' n'était JAMAIS recalculé pour
-- le NOUVEAU joueur courant. Le joueur suivant voyait donc les suggestions
-- de tuiles jouables calculées pour un AUTRE joueur (obsolètes) → suggestion
-- incorrecte affichée à l'écran.
--
-- Seules domino_play, _domino_next_round et _domino_place_first mettaient
-- correctement à jour playable_tiles. Ce fix l'ajoute partout où current_turn
-- change.

-- ── 1. _domino_bot_step ──
CREATE OR REPLACE FUNCTION public._domino_bot_step(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  g record; st jsonb; v_slot int; hand jsonb; le int; re int;
  draw_mode text; is_first_move boolean; first_dbl int; v_rule text;
  i int; j int; a int; b int; tile jsonb; placed jsonb;
  found boolean; found_i int; new_hand jsonb; new_left int; new_right int;
  next_turn int; winner_slot int; stock jsonb; drawn jsonb;
  _cfg record; v_is_bot boolean; phase text; v_think_until timestamptz;
  v_locked_slot int; v_delay_ms int; v_name text;
  v_playable jsonb;
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
    -- FIX: recalculer playable_tiles pour le nouveau joueur courant
    v_playable := public._domino_playable_tiles(st, next_turn);
    st := jsonb_set(st, ARRAY['playable_tiles'], v_playable, true);
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
    -- FIX: bot a pioché — recalculer sa propre playable_tiles (utile si un
    -- humain regarde le state pendant que le bot réfléchit encore)
    v_playable := public._domino_playable_tiles(st, v_slot);
    st := jsonb_set(st, ARRAY['playable_tiles'], v_playable, true);
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
  -- FIX: recalculer playable_tiles pour le nouveau joueur courant
  v_playable := public._domino_playable_tiles(st, next_turn);
  st := jsonb_set(st, ARRAY['playable_tiles'], v_playable, true);
  UPDATE public.domino_games SET state = st, current_turn = next_turn,
         turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
   WHERE id = _game_id;
END;
$function$;

-- ── 2. _domino_auto_draw ──
CREATE OR REPLACE FUNCTION public._domino_auto_draw(_game_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  g record; st jsonb; stock jsonb; hand jsonb; drawn jsonb;
  slot int; guard int := 0; did boolean := false;
  v_playable jsonb;
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

  -- FIX: recalculer playable_tiles après la pioche automatique (même slot)
  v_playable := public._domino_playable_tiles(st, slot);
  st := jsonb_set(st, ARRAY['playable_tiles'], v_playable, true);

  UPDATE public.domino_games
     SET state = st,
         turn_deadline = now() + interval '30 seconds'
   WHERE id = _game_id;
  RETURN public._domino_slot_has_playable(st, slot);
END $function$;

-- ── 3. _domino_force_pass ──
CREATE OR REPLACE FUNCTION public._domino_force_pass(_game_id uuid, _slot integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  g record; st jsonb; n_players int; next_turn int; winner_slot int; v_name text;
  v_playable jsonb;
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
  -- FIX: recalculer playable_tiles pour le nouveau joueur courant
  v_playable := public._domino_playable_tiles(st, next_turn);
  st := jsonb_set(st, ARRAY['playable_tiles'], v_playable, true);

  UPDATE public.domino_games
     SET state = st, current_turn = next_turn,
         turn_deadline = now() + interval '30 seconds'
   WHERE id = _game_id;
END;
$function$;

-- ── 4. Fix les parties en cours: recalculer playable_tiles pour le joueur courant ──
UPDATE public.domino_games
   SET state = jsonb_set(state, ARRAY['playable_tiles'],
                 public._domino_playable_tiles(state, current_turn))
 WHERE status = 'playing';
