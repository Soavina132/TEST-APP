CREATE OR REPLACE FUNCTION public.ludo_bot_play(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $$
DECLARE
  g public.ludo_games%ROWTYPE;
  st jsonb;
  v_slot INT;
  v_isbot BOOLEAN;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;

  SELECT is_bot INTO v_isbot
    FROM public.ludo_participants WHERE game_id = _game_id AND slot = v_slot;
  IF NOT v_isbot THEN RETURN st; END IF;

  -- Si déjà lancé, ne pas relancer
  IF (st->>'must_move')::BOOLEAN THEN RETURN st; END IF;

  -- Utiliser ludo_roll pour le lancer de dé.
  -- ludo_roll gère :
  --   - le dé équitable (1-6)
  --   - la règle des 3 six consécutifs (annulation du 3ème six)
  --   - le compteur consecutive_sixes
  --   - les pions jouables (movable_pawns)
  --   - le no_move_display quand aucun pion n'est jouable
  -- L'auth check de ludo_roll est skip pour les bots (IF NOT v_isbot AND ...).
  st := public.ludo_roll(_game_id);
  RETURN st;
END $$;

REVOKE ALL ON FUNCTION public.ludo_bot_play(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ludo_bot_play(uuid) TO service_role;
