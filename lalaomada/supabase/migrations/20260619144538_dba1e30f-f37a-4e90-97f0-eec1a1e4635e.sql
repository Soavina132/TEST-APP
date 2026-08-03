
CREATE OR REPLACE FUNCTION public.domino_forfeit(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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
  IF remaining = 1 THEN
    SELECT slot INTO last_slot FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
    IF COALESCE(g.target_score,0) > 0 THEN
      -- Points mode: end the round, award the loser's remaining pips, continue match
      PERFORM public._domino_end_round(_game_id, last_slot);
    ELSE
      PERFORM public._domino_finalize(_game_id, last_slot);
    END IF;
  END IF;
END $function$;

CREATE OR REPLACE FUNCTION public._domino_next_round(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  g record; n int; tiles jsonb; hands jsonb := '{}'::jsonb;
  stock jsonb; per_hand int := 7; p record; idx int := 0; hand jsonb;
  starter int := 0; best int := -1; cur_dbl int; t jsonb;
  starter_double int := -1;
  _cfg record;
  deal_until timestamptz;
  new_state jsonb;
  prev_scores jsonb;
  last_slot int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN; END IF;
  SELECT count(*) INTO n FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  IF n < 2 THEN
    SELECT slot INTO last_slot FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false LIMIT 1;
    IF last_slot IS NOT NULL THEN
      PERFORM public._domino_finalize(_game_id, last_slot);
    ELSE
      UPDATE public.domino_games SET status='cancelled', finished_at=now() WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;

  tiles := public._domino_deal(n);

  FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
    SELECT jsonb_agg(value) INTO hand FROM jsonb_array_elements(tiles) WITH ORDINALITY t(value, ord)
      WHERE ord > idx*per_hand AND ord <= (idx+1)*per_hand;
    hands := hands || jsonb_build_object(p.slot::text, COALESCE(hand,'[]'::jsonb));
    idx := idx + 1;
  END LOOP;
  SELECT jsonb_agg(value) INTO stock FROM jsonb_array_elements(tiles) WITH ORDINALITY t(value, ord)
    WHERE ord > n*per_hand;
  stock := COALESCE(stock, '[]'::jsonb);

  FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
    cur_dbl := -1;
    FOR t IN SELECT * FROM jsonb_array_elements(hands -> p.slot::text) LOOP
      IF (t->>0)::int = (t->>1)::int AND (t->>0)::int > cur_dbl THEN cur_dbl := (t->>0)::int; END IF;
    END LOOP;
    IF cur_dbl > best THEN best := cur_dbl; starter := p.slot; starter_double := cur_dbl; END IF;
  END LOOP;

  SELECT * INTO _cfg FROM public._game_cfg('domino');
  deal_until := now() + interval '3 seconds';
  prev_scores := COALESCE(g.scores, '{}'::jsonb);

  new_state := jsonb_build_object(
    'hands', hands,
    'stock', stock,
    'board', '[]'::jsonb,
    'left_end', null,
    'right_end', null,
    'draw_mode', COALESCE(g.state->>'draw_mode','with'),
    'phase', 'dealing',
    'deal_until', deal_until::text,
    'starter_slot', starter,
    'starter_double', starter_double,
    'scores', prev_scores
  );

  UPDATE public.domino_games
     SET state=new_state,
         current_turn=starter,
         turn_deadline=deal_until,
         turn_skips='{}'::jsonb
   WHERE id = _game_id;
END $function$;
