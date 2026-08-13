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
