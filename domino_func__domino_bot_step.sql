CREATE OR REPLACE FUNCTION public._domino_bot_step(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  g record;
  st jsonb;
  v_slot int;
  v_is_bot boolean;
  phase text;
  v_think_until timestamptz;
  v_locked_slot int;
  v_delay_ms int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

  st := g.state;
  phase := COALESCE(st->>'phase', 'play');
  IF phase NOT IN ('play','playing') THEN RETURN; END IF;

  v_slot := g.current_turn;
  SELECT COALESCE(dp.is_bot, false) INTO v_is_bot
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id
     AND dp.slot = v_slot
     AND dp.forfeited = false;

  IF NOT COALESCE(v_is_bot, false) THEN RETURN; END IF;

  v_think_until := NULLIF(st->>'bot_think_until','')::timestamptz;
  v_locked_slot := NULLIF(st->>'bot_locked_slot','null')::int;

  IF v_think_until IS NOT NULL AND v_locked_slot = v_slot AND v_think_until > now() THEN
    RETURN;
  END IF;

  IF v_think_until IS NULL OR v_locked_slot IS DISTINCT FROM v_slot THEN
    v_delay_ms := 1500 + (floor(random() * 2000))::int;
    st := jsonb_set(st - 'bot_think_until' - 'bot_locked_slot',
                    '{bot_locked_slot}', to_jsonb(v_slot), true);
    st := jsonb_set(st, '{bot_think_until}',
                    to_jsonb((now() + make_interval(secs => v_delay_ms / 1000.0))::text), true);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    RETURN;
  END IF;

  -- Le délai est écoulé : retirer le verrou et laisser le bot jouer.
  st := st - 'bot_think_until' - 'bot_locked_slot';
  UPDATE public.domino_games SET state = st WHERE id = _game_id;
  PERFORM public._domino_autoplay_bots(_game_id);
END;
$function$
