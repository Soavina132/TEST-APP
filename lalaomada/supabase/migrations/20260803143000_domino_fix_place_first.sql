-- ─────────────────────────────────────────────────────────────────────────────
-- Fix : _domino_place_first utilisait l'ancien format objet {tile,flipped}
--        et n'armait pas le bot think timer pour le prochain joueur.
--
-- 1. Format board : {tile:[a,a],flipped:false} → [a,a] (tuple)
-- 2. Arm bot think : appeler _domino_arm_bot_think si le prochain joueur est un bot
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public._domino_place_first(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  g record; st jsonb; starter int; starter_double int;
  hands jsonb; starter_hand jsonb; filtered jsonb;
  board jsonb; next_slot int; _cfg record;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;
  st := g.state;
  IF (st->>'phase') <> 'dealing' THEN RETURN; END IF;

  starter := COALESCE((st->>'starter_slot')::int, g.current_turn);
  starter_double := COALESCE((st->>'starter_double')::int, -1);
  hands := st->'hands';

  IF starter_double >= 0 THEN
    starter_hand := hands -> starter::text;
    SELECT COALESCE(jsonb_agg(value), '[]'::jsonb) INTO filtered
      FROM jsonb_array_elements(starter_hand) value
      WHERE NOT ((value->>0)::int = starter_double AND (value->>1)::int = starter_double);
    hands := jsonb_set(hands, ARRAY[starter::text], filtered);
    -- FIX 1 : format tuple [a,a] au lieu de {tile:[a,a],flipped:false}
    board := jsonb_build_array(jsonb_build_array(starter_double, starter_double));
    st := jsonb_set(st, '{hands}', hands);
    st := jsonb_set(st, '{board}', board);
    st := jsonb_set(st, '{left_end}', to_jsonb(starter_double));
    st := jsonb_set(st, '{right_end}', to_jsonb(starter_double));

    SELECT slot INTO next_slot FROM public.domino_participants
      WHERE game_id=_game_id AND forfeited=false AND slot > starter ORDER BY slot LIMIT 1;
    IF next_slot IS NULL THEN
      SELECT slot INTO next_slot FROM public.domino_participants
        WHERE game_id=_game_id AND forfeited=false ORDER BY slot LIMIT 1;
    END IF;
  ELSE
    next_slot := starter;
  END IF;

  st := jsonb_set(st, '{phase}', '"play"'::jsonb);
  st := st - 'deal_until';

  SELECT * INTO _cfg FROM public._game_cfg('domino');

  -- FIX 2 : armer le bot think timer si le prochain joueur est un bot
  next_slot := COALESCE(next_slot, starter);
  st := public._domino_arm_bot_think(_game_id, next_slot, st);

  UPDATE public.domino_games
     SET state = st,
         current_turn = next_slot,
         turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
   WHERE id = _game_id;
END $function$;
