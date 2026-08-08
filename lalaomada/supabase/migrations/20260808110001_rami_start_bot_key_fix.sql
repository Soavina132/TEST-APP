CREATE OR REPLACE FUNCTION public.rami_start(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _g public.rami_games; _deck int[]; _i int; _j int; _tmp int;
  _hands jsonb := '{}'::jsonb; _hand int[]; _state jsonb; _key text;
  _first_discard int; _cfg record; _joker_mode text; _random_joker int;
  _discards jsonb; _action_log jsonb;
  _slot int; _uid uuid; _is_bot boolean;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status NOT IN ('waiting','open') THEN RETURN; END IF;
  
  IF (SELECT count(*) FROM public.rami_participants WHERE game_id=_game_id) < 2 THEN 
    RAISE EXCEPTION 'pas assez de joueurs'; 
  END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');

  _deck := ARRAY(SELECT generate_series(0, 111));

  FOR _i IN REVERSE 112..2 LOOP
    _j := 1 + floor(random()*_i)::int;
    _tmp := _deck[_i]; _deck[_i] := _deck[_j]; _deck[_j] := _tmp;
  END LOOP;

  -- Deal 13 cards to each participant
  FOR _slot, _uid, _is_bot IN 
    SELECT slot, user_id, is_bot FROM public.rami_participants 
    WHERE game_id=_game_id ORDER BY slot
  LOOP
    _hand := _deck[1:13];
    _deck := _deck[14:array_length(_deck,1)];
    _key := CASE WHEN COALESCE(_is_bot, false) THEN 'bot:' || _slot::text ELSE _uid::text END;
    _hands := _hands || jsonb_build_object(_key, to_jsonb(_hand));
    UPDATE public.rami_participants SET hand_count = 13 
      WHERE game_id=_game_id AND slot=_slot;
  END LOOP;

  _first_discard := _deck[1];
  _deck := _deck[2:array_length(_deck,1)];

  _joker_mode := _g.joker_mode;
  _random_joker := NULL;
  IF _joker_mode IN ('aleatoire','double') THEN
    _random_joker := floor(random()*52)::int;
  END IF;

  _discards := jsonb_build_object('_seed', jsonb_build_array(_first_discard));

  _action_log := jsonb_build_array(
    jsonb_build_object('t', 'start', 'ts', extract(epoch from now())::bigint)
  );

  _state := jsonb_build_object(
    'deck', to_jsonb(_deck),
    'discards', _discards,
    'last_discard_by', '_seed',
    'hands', _hands,
    'melds', '[]'::jsonb,
    'action_log', _action_log,
    'refunded', '{}'::jsonb
  );

  UPDATE public.rami_games SET
    status='playing', state=_state, started_at=now(),
    current_turn=0, turn_phase='draw',
    random_joker=_random_joker,
    turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval
    WHERE id=_game_id;
END $function$;
