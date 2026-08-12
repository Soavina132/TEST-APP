-- Fix _ludo_ensure_state: pass mode to _ludo_init_state + handle NULL state
-- Previously: called _ludo_init_state(g.max_players) without mode, didn't handle g.state IS NULL
-- Now: calls _ludo_init_state(g.max_players, COALESCE(g.mode, 'classic')) and handles NULL state

CREATE OR REPLACE FUNCTION public._ludo_ensure_state(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE g public.ludo_games%ROWTYPE; st jsonb;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  IF g.state IS NULL OR (g.state ? 'pawns') IS NOT TRUE OR g.state->'pawns' = '{}'::jsonb THEN
    st := public._ludo_init_state(g.max_players, COALESCE(g.mode, 'classic'));
    UPDATE public.ludo_games SET state=st, current_turn=0 WHERE id=_game_id;
    RETURN st;
  END IF;
  RETURN g.state;
END
$function$;
