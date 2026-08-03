-- ============================================================
-- Migration: Add push notifications for Domino game events
--
-- Sends push notifications to offline players via the existing
-- push notification system (trigger → Edge Function send-push).
--
-- Events notified:
-- 1. "À vous de jouer" — when it becomes a human player's turn
-- 2. "X passe son tour" — when a player passes
-- 3. "Domino bloqué !" — when all players pass (game blocked)
-- 4. "Manche terminée" — when a round ends
-- ============================================================

-- ═══════════════════════════════════════════════════════════
-- Helper: notify a specific player by slot (real users only)
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._domino_notify(
  _game_id uuid,
  _slot int,
  _kind text,
  _title text,
  _body text,
  _link text DEFAULT '/jeux/domino'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid;
  v_is_bot boolean;
BEGIN
  SELECT user_id, is_bot INTO v_uid, v_is_bot
    FROM public.domino_participants
    WHERE game_id = _game_id AND slot = _slot;
  
  IF v_uid IS NULL OR v_is_bot THEN RETURN; END IF;
  
  INSERT INTO public.notifications(user_id, kind, title, body, link, ref_id)
  VALUES (v_uid, _kind, _title, _body, _link, _game_id);
END $$;

-- ═══════════════════════════════════════════════════════════
-- Helper: notify all human players except one slot
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._domino_notify_all(
  _game_id uuid,
  _exclude_slot int DEFAULT -1,
  _kind text DEFAULT 'domino',
  _title text DEFAULT '',
  _body text DEFAULT '',
  _link text DEFAULT '/jeux/domino'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  p record;
BEGIN
  FOR p IN SELECT slot, user_id, is_bot FROM public.domino_participants
            WHERE game_id = _game_id AND slot <> _exclude_slot LOOP
    IF p.user_id IS NULL OR p.is_bot THEN CONTINUE; END IF;
    INSERT INTO public.notifications(user_id, kind, title, body, link, ref_id)
    VALUES (p.user_id, _kind, _title, _body, _link, _game_id);
  END LOOP;
END $$;

-- ═══════════════════════════════════════════════════════════
-- Rewrite domino_play with notifications at key points
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.domino_play(_game_id uuid, _move jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  g           record;
  my_slot     int;
  st          jsonb;
  hand        jsonb;
  tile        jsonb;
  a int; b int;
  le int; re int;
  side        text;
  new_left    int; new_right int;
  action      text;
  n_players   int;
  next_turn   int;
  drawn       jsonb;
  stock       jsonb;
  found       boolean := false;
  new_hand    jsonb;
  i           int;
  winner_slot int;
  draw_mode   text;
  first_dbl   int;
  stock_len   int;
  stored_tile jsonb;
  v_name      text;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  SELECT slot INTO my_slot FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid;
  IF my_slot IS NULL OR my_slot <> g.current_turn THEN RAISE EXCEPTION 'not your turn'; END IF;

  st        := g.state;
  action    := _move->>'action';
  hand      := st -> 'hands' -> my_slot::text;
  stock     := st -> 'stock';
  le        := NULLIF(st->>'left_end',  'null')::int;
  re        := NULLIF(st->>'right_end', 'null')::int;
  draw_mode := COALESCE(st->>'draw_mode', 'with');
  stock_len := jsonb_array_length(COALESCE(stock, '[]'::jsonb));
  SELECT count(*) INTO n_players FROM public.domino_participants WHERE game_id = _game_id;

  IF action = 'draw' THEN
    IF draw_mode = 'without' THEN RAISE EXCEPTION 'draw disabled in this game'; END IF;
    IF stock_len = 0 THEN RAISE EXCEPTION 'stock empty'; END IF;
    drawn := stock -> 0; stock := stock - 0;
    hand  := hand || jsonb_build_array(drawn);
    st := jsonb_set(st, ARRAY['hands', my_slot::text], hand);
    st := jsonb_set(st, '{stock}', stock);
    UPDATE public.domino_games
       SET state = st,
           turn_deadline = now() + interval '30 seconds'
     WHERE id = _game_id;
    RETURN;
  END IF;

  IF action = 'pass' THEN
    IF draw_mode = 'with' AND stock_len > 0 THEN RAISE EXCEPTION 'you must draw first'; END IF;
    st := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1));
    st := jsonb_set(st, '{last_pass_by}', to_jsonb(my_slot));
    next_turn := public._domino_next_playable_slot(_game_id, my_slot, st);

    SELECT display_name INTO v_name FROM public.domino_participants
      WHERE game_id = _game_id AND slot = my_slot;

    -- Notify other players: "X passe son tour"
    PERFORM public._domino_notify_all(_game_id, my_slot, 'domino_pass',
      v_name || ' passe son tour',
      v_name || ' n''a pas de tuile jouable',
      '/domino/' || _game_id::text);

    IF (st->>'passes')::int >= n_players THEN
      -- Domino bloqué ! All players passed
      PERFORM public._domino_notify_all(_game_id, -1, 'domino_blocked',
        '🚫 Domino bloqué !',
        'Personne ne peut jouer — la manche se termine',
        '/domino/' || _game_id::text);
      winner_slot := public._domino_lowest_pip_slot(_game_id, st);
      PERFORM public._domino_end_round(_game_id, winner_slot);
      RETURN;
    END IF;
    IF next_turn IS NULL THEN
      PERFORM public._domino_notify_all(_game_id, -1, 'domino_blocked',
        '🚫 Domino bloqué !',
        'Personne ne peut jouer — la manche se termine',
        '/domino/' || _game_id::text);
      winner_slot := public._domino_lowest_pip_slot(_game_id, st);
      PERFORM public._domino_end_round(_game_id, winner_slot);
      RETURN;
    END IF;
    st := public._domino_arm_bot_think(_game_id, next_turn, st);
    st := jsonb_set(st, '{current_turn}', to_jsonb(next_turn));
    UPDATE public.domino_games
       SET state = st, current_turn = next_turn,
           turn_deadline = now() + interval '30 seconds'
     WHERE id = _game_id;
    -- Notify next player: "À vous de jouer"
    PERFORM public._domino_notify(_game_id, next_turn, 'domino_turn',
      'À vous de jouer — Domino',
      'C''est votre tour de jouer',
      '/domino/' || _game_id::text);
    RETURN;
  END IF;

  IF action <> 'play' THEN RAISE EXCEPTION 'unknown action'; END IF;

  tile := _move -> 'tile';
  IF tile IS NULL THEN RAISE EXCEPTION 'tile required'; END IF;
  a := (tile->>0)::int; b := (tile->>1)::int;
  side := _move->>'side';

  FOR i IN 0 .. jsonb_array_length(hand) - 1 LOOP
    IF (hand->i->>0)::int = a AND (hand->i->>1)::int = b THEN
      found := true;
      new_hand := hand - i;
      EXIT;
    END IF;
    IF (hand->i->>0)::int = b AND (hand->i->>1)::int = a THEN
      found := true;
      a := b; b := (hand->i->>0)::int;
      new_hand := hand - i;
      EXIT;
    END IF;
  END LOOP;
  IF NOT found THEN RAISE EXCEPTION 'tile not in hand'; END IF;

  first_dbl := NULLIF(st->>'first_move_double', 'null')::int;
  IF le IS NULL THEN
    IF first_dbl IS NOT NULL AND a <> b THEN RAISE EXCEPTION 'first move must be the highest double'; END IF;
    IF first_dbl IS NOT NULL AND a <> first_dbl THEN RAISE EXCEPTION 'first move must be the highest double'; END IF;
    new_left  := a; new_right := b;
    st := jsonb_set(st, '{board}', jsonb_build_array(
      jsonb_build_object('tile', jsonb_build_array(a, b), 'flipped', false)
    ));
  ELSE
    DECLARE
      touch int; expose int;
      matches_left  boolean := (a = le OR b = le);
      matches_right boolean := (a = re OR b = re);
    BEGIN
      IF side IS NULL THEN
        IF matches_left THEN side := 'left';
        ELSIF matches_right THEN side := 'right';
        ELSE RAISE EXCEPTION 'tile does not fit'; END IF;
      END IF;

      IF side = 'left' THEN
        IF a = le THEN touch := a; expose := b;
        ELSIF b = le THEN touch := b; expose := a;
        ELSE RAISE EXCEPTION 'tile does not fit left'; END IF;
        new_left  := expose;
        new_right := re;
        stored_tile := jsonb_build_object('tile', jsonb_build_array(expose, touch), 'flipped', false);
        st := jsonb_set(st, '{board}', jsonb_build_array(stored_tile) || (st->'board'));
      ELSE
        IF a = re THEN touch := a; expose := b;
        ELSIF b = re THEN touch := b; expose := a;
        ELSE RAISE EXCEPTION 'tile does not fit right'; END IF;
        new_left  := le;
        new_right := expose;
        stored_tile := jsonb_build_object('tile', jsonb_build_array(touch, expose), 'flipped', false);
        st := jsonb_set(st, '{board}', (st->'board') || jsonb_build_array(stored_tile));
      END IF;
    END;
  END IF;

  st := jsonb_set(st, ARRAY['hands', my_slot::text], new_hand);
  st := jsonb_set(st, '{left_end}',  to_jsonb(new_left));
  st := jsonb_set(st, '{right_end}', to_jsonb(new_right));
  st := jsonb_set(st, '{passes}',    to_jsonb(0));
  st := jsonb_set(st, '{first_move_double}', 'null'::jsonb);
  st := st - 'last_pass_by';

  IF jsonb_array_length(new_hand) = 0 THEN
    -- Player played their last tile → round won
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    SELECT display_name INTO v_name FROM public.domino_participants
      WHERE game_id = _game_id AND slot = my_slot;
    -- Notify all other players
    PERFORM public._domino_notify_all(_game_id, my_slot, 'domino_round_end',
      v_name || ' a gagné la manche !',
      v_name || ' a posé tous ses dominos',
      '/domino/' || _game_id::text);
    -- Notify winner
    PERFORM public._domino_notify(_game_id, my_slot, 'domino_round_won',
      'Vous avez gagné la manche ! 🎉',
      'Vous avez posé tous vos dominos',
      '/domino/' || _game_id::text);
    PERFORM public._domino_end_round(_game_id, my_slot);
    RETURN;
  END IF;

  next_turn := public._domino_next_playable_slot(_game_id, my_slot, st);
  IF next_turn IS NULL THEN
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    -- Game blocked
    PERFORM public._domino_notify_all(_game_id, -1, 'domino_blocked',
      '🚫 Domino bloqué !',
      'Personne ne peut jouer — la manche se termine',
      '/domino/' || _game_id::text);
    winner_slot := public._domino_lowest_pip_slot(_game_id, st);
    PERFORM public._domino_end_round(_game_id, winner_slot);
    RETURN;
  END IF;

  st := public._domino_arm_bot_think(_game_id, next_turn, st);
  st := jsonb_set(st, '{current_turn}', to_jsonb(next_turn));
  UPDATE public.domino_games
    SET state = st, current_turn = next_turn,
        turn_deadline = now() + interval '30 seconds'
    WHERE id = _game_id;
  -- Notify next player: "À vous de jouer"
  PERFORM public._domino_notify(_game_id, next_turn, 'domino_turn',
    'À vous de jouer — Domino',
    'C''est votre tour de jouer',
    '/domino/' || _game_id::text);
END $$;

REVOKE EXECUTE ON FUNCTION public.domino_play(uuid, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.domino_play(uuid, jsonb) TO authenticated;
