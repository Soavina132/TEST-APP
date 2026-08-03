-- Randomize the first player in Ludo
-- Previously _ludo_init_state always set turn_slot=0 (red always starts)
-- Now it picks a random slot between 0 and max_players-1

CREATE OR REPLACE FUNCTION public._ludo_init_state(_max_players int)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE p jsonb := '{}'::jsonb; i INT; v_start INT;
BEGIN
  FOR i IN 0.._max_players-1 LOOP
    p := p || jsonb_build_object(i::text,
      jsonb_build_array(
        jsonb_build_object('s','yard','k',-1),
        jsonb_build_object('s','yard','k',-1),
        jsonb_build_object('s','yard','k',-1),
        jsonb_build_object('s','yard','k',-1)
      ));
  END LOOP;
  -- Random starting player
  v_start := floor(random() * _max_players)::INT;
  RETURN jsonb_build_object(
    'pawns', p, 'turn_slot', v_start, 'dice', NULL, 'must_move', false,
    'turn_started_at', to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'last_event', 'start');
END $function$;

-- Fix _ludo_ensure_state to use the random turn_slot from init_state
CREATE OR REPLACE FUNCTION public._ludo_ensure_state(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE g public.ludo_games%ROWTYPE; st jsonb;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.id IS NULL OR g.status IS NULL OR g.status <> 'playing' THEN
    RAISE EXCEPTION 'Partie pas en cours';
  END IF;
  IF (g.state ? 'pawns') IS NOT TRUE OR g.state->'pawns' = '{}'::jsonb THEN
    st := public._ludo_init_state(g.max_players);
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
    RETURN st;
  END IF;
  RETURN g.state;
END $function$;
