
-- 1) Forfeit: when only one player remains, immediately award the pot.
--    Previously, in points mode, we kept the match running which left the
--    survivor stuck even though no opponent could keep playing.
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
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status NOT IN ('open','playing') THEN RETURN; END IF;
  SELECT slot INTO my_slot FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid;
  IF my_slot IS NULL THEN RETURN; END IF;
  UPDATE public.domino_participants SET forfeited = true WHERE game_id = _game_id AND user_id = v_uid;

  IF g.status = 'open' THEN
    UPDATE public.profiles p SET balance_ar = balance_ar + g.stake
      FROM public.domino_participants pp WHERE pp.game_id = _game_id AND pp.user_id = p.id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      SELECT user_id, 'domino_refund', g.stake, _game_id, 'Game cancelled' FROM public.domino_participants WHERE game_id = _game_id;
    UPDATE public.domino_games SET status = 'cancelled', finished_at = now() WHERE id = _game_id;
    RETURN;
  END IF;

  SELECT count(*) INTO remaining FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  IF remaining <= 1 THEN
    SELECT slot INTO last_slot FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false LIMIT 1;
    IF last_slot IS NOT NULL THEN
      PERFORM public._domino_finalize(_game_id, last_slot);
    ELSE
      UPDATE public.domino_games SET status='cancelled', finished_at=now() WHERE id = _game_id;
    END IF;
  END IF;
END $function$;

-- 2) Has-playable check must respect the under6 rule for the very first tile.
CREATE OR REPLACE FUNCTION public._domino_slot_has_playable(_state jsonb, _slot integer)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  hand jsonb := COALESCE(_state -> 'hands' -> _slot::text, '[]'::jsonb);
  board_len integer := jsonb_array_length(COALESCE(_state -> 'board', '[]'::jsonb));
  first_dbl integer;
  le integer; re integer;
  t jsonb; a integer; b integer;
  v_rule text;
BEGIN
  IF jsonb_array_length(hand) = 0 THEN RETURN false; END IF;

  IF board_len = 0 THEN
    first_dbl := NULLIF(_state->>'first_move_double', 'null')::integer;
    IF first_dbl IS NOT NULL THEN
      FOR t IN SELECT * FROM jsonb_array_elements(hand) LOOP
        IF (t->>0)::int = first_dbl AND (t->>1)::int = first_dbl THEN RETURN true; END IF;
      END LOOP;
      RETURN false;
    END IF;
    v_rule := COALESCE(_state->>'first_tile_rule','libre');
    IF v_rule = 'under6' THEN
      FOR t IN SELECT * FROM jsonb_array_elements(hand) LOOP
        IF ((t->>0)::int + (t->>1)::int) < 6 THEN RETURN true; END IF;
      END LOOP;
      RETURN false;
    END IF;
    RETURN true;
  END IF;

  le := NULLIF(_state->>'left_end', 'null')::integer;
  re := NULLIF(_state->>'right_end', 'null')::integer;
  FOR t IN SELECT * FROM jsonb_array_elements(hand) LOOP
    a := (t->>0)::integer; b := (t->>1)::integer;
    IF a = le OR b = le OR a = re OR b = re THEN RETURN true; END IF;
  END LOOP;
  RETURN false;
END $function$;

-- 3) Next round: for under6 mode round 1, pick the player holding the
--    highest qualifying first tile (highest double with total<6, else
--    highest non-double with total<6). Subsequent rounds rotate the
--    starter (already implemented).
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
    -- Rotate starter to the next active slot
    starter := slots[1];
    FOR i IN 1..array_length(slots,1) LOOP
      IF slots[i] = v_prev_starter THEN
        starter := slots[ ((i) % array_length(slots,1)) + 1 ];
        EXIT;
      END IF;
    END LOOP;
    starter_double := -1;
  ELSIF v_rule = 'under6' THEN
    -- First round under6: highest qualifying double first, then highest tile sum<6
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
      -- Fallback: highest tile total strictly <6
      FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
        cur_best := -1;
        FOR t IN SELECT * FROM jsonb_array_elements(hands -> p.slot::text) LOOP
          a := (t->>0)::int; b := (t->>1)::int; sum2 := a + b;
          IF sum2 < 6 AND sum2 > cur_best THEN cur_best := sum2; END IF;
        END LOOP;
        IF cur_best > best THEN best := cur_best; starter := p.slot; END IF;
      END LOOP;
    END IF;
    -- Never force a specific tile in under6 — the rule itself filters playability.
  ELSE
    -- libre: highest double anywhere; auto-placed
    FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
      cur_best := -1;
      FOR t IN SELECT * FROM jsonb_array_elements(hands -> p.slot::text) LOOP
        IF (t->>0)::int = (t->>1)::int AND (t->>0)::int > cur_best THEN cur_best := (t->>0)::int; END IF;
      END LOOP;
      IF cur_best > best THEN best := cur_best; starter := p.slot; starter_double := cur_best; END IF;
    END LOOP;
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
