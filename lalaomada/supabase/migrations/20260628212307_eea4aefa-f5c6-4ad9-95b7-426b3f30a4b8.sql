CREATE OR REPLACE FUNCTION public._domino_start(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','extensions'
AS $function$
DECLARE
  g record; n int; tiles jsonb; hands jsonb := '{}'::jsonb; stock jsonb;
  per_hand int := 7; p record; idx int := 0; hand jsonb;
  starter int := 0; best int := -1; cur_best int; t jsonb;
  starter_double int := -1;
  prev_draw_mode text;
  new_state jsonb;
  _cfg record;
  deal_until timestamptz;
  v_rule text;
  a int; b int; sum2 int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'open' THEN RETURN; END IF;
  SELECT count(*) INTO n FROM public.domino_participants WHERE game_id = _game_id;
  IF n < g.max_players THEN RETURN; END IF;

  tiles := public._domino_deal(n);

  FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id ORDER BY slot LOOP
    SELECT jsonb_agg(value) INTO hand FROM jsonb_array_elements(tiles) WITH ORDINALITY t(value, ord)
      WHERE ord > idx*per_hand AND ord <= (idx+1)*per_hand;
    hands := hands || jsonb_build_object(p.slot::text, COALESCE(hand,'[]'::jsonb));
    idx := idx + 1;
  END LOOP;

  SELECT jsonb_agg(value) INTO stock FROM jsonb_array_elements(tiles) WITH ORDINALITY t(value, ord)
    WHERE ord > n*per_hand;
  stock := COALESCE(stock, '[]'::jsonb);

  v_rule := COALESCE(g.state->>'first_tile_rule', g.first_tile_rule, 'libre');

  IF v_rule = 'under6' THEN
    -- Highest qualifying double first (sum < 6)
    best := -1; starter := 0; starter_double := -1;
    FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id ORDER BY slot LOOP
      cur_best := -1;
      FOR t IN SELECT * FROM jsonb_array_elements(hands -> p.slot::text) LOOP
        a := (t->>0)::int; b := (t->>1)::int; sum2 := a + b;
        IF a = b AND sum2 < 6 AND sum2 > cur_best THEN cur_best := sum2; END IF;
      END LOOP;
      IF cur_best > best THEN best := cur_best; starter := p.slot; END IF;
    END LOOP;
    IF best < 0 THEN
      -- Fallback: highest tile total strictly < 6
      FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id ORDER BY slot LOOP
        cur_best := -1;
        FOR t IN SELECT * FROM jsonb_array_elements(hands -> p.slot::text) LOOP
          a := (t->>0)::int; b := (t->>1)::int; sum2 := a + b;
          IF sum2 < 6 AND sum2 > cur_best THEN cur_best := sum2; END IF;
        END LOOP;
        IF cur_best > best THEN best := cur_best; starter := p.slot; END IF;
      END LOOP;
    END IF;
    -- starter_double stays -1 so no auto-placement happens.
  ELSE
    -- libre: highest double anywhere; auto-placed by _domino_place_first
    FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id ORDER BY slot LOOP
      cur_best := -1;
      FOR t IN SELECT * FROM jsonb_array_elements(hands -> p.slot::text) LOOP
        IF (t->>0)::int = (t->>1)::int AND (t->>0)::int > cur_best THEN cur_best := (t->>0)::int; END IF;
      END LOOP;
      IF cur_best > best THEN best := cur_best; starter := p.slot; starter_double := cur_best; END IF;
    END LOOP;
  END IF;

  prev_draw_mode := COALESCE(g.state->>'draw_mode','with');
  IF jsonb_array_length(stock) = 0 THEN prev_draw_mode := 'without'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('domino');
  deal_until := now() + interval '3 seconds';

  new_state := jsonb_build_object(
    'hands', hands,
    'stock', stock,
    'board', '[]'::jsonb,
    'left_end', 'null'::jsonb,
    'right_end', 'null'::jsonb,
    'passes', 0,
    'scores', '{}'::jsonb,
    'round', 1,
    'draw_mode', prev_draw_mode,
    'first_tile_rule', v_rule,
    'phase', 'dealing',
    'deal_until', deal_until::text,
    'starter_slot', starter,
    'starter_double', starter_double,
    'first_move_double', CASE WHEN starter_double >= 0 THEN to_jsonb(starter_double) ELSE 'null'::jsonb END
  );

  UPDATE public.domino_games
     SET status='playing',
         state=new_state,
         current_turn=starter,
         turn_deadline=deal_until,
         started_at=now(),
         turn_skips='{}'::jsonb,
         scores=COALESCE(scores,'{}'::jsonb)
   WHERE id = _game_id;
END $function$;