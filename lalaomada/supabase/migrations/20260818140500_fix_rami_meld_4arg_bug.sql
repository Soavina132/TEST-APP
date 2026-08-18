-- Fix: rami_meld was calling _rami_meld_type with 4 args (integer[], text, integer, boolean)
-- but the deployed function only accepts 3 args. Same bug as rami_validate_hand, missed this caller.
CREATE OR REPLACE FUNCTION public.rami_meld(_game_id uuid, _cards integer[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _uid uuid := auth.uid();
  _g public.rami_games;
  _slot int;
  _state jsonb;
  _hand int[];
  _c int;
  _new_hand int[];
  _melds jsonb;
  _type text;
  _action_log jsonb;
  _first_melds jsonb;
  _is_pure boolean;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour de jouer'; END IF;

  -- FIX: 3 args only (no _seven_cards boolean)
  _type := public._rami_meld_type(_cards, _g.joker_mode, _g.random_joker);
  IF _type IS NULL THEN RAISE EXCEPTION 'combinaison invalide'; END IF;

  _state := _g.state;
  _hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[], ARRAY[]::int[]);
  _new_hand := _hand;
  FOREACH _c IN ARRAY _cards LOOP
    IF NOT (_c = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte absente de la main'; END IF;
    _new_hand := public._rami_remove_one(_new_hand, _c);
  END LOOP;

  _is_pure := true;
  FOREACH _c IN ARRAY _cards LOOP
    IF public._rami_is_joker(_c, _g.joker_mode, _g.random_joker) THEN
      _is_pure := false;
    END IF;
  END LOOP;

  _melds := COALESCE(_state->'melds', '[]'::jsonb) || jsonb_build_array(
    jsonb_build_object(
      'player', _uid::text,
      'cards', to_jsonb(_cards),
      'type', _type,
      'pure', _is_pure
    )
  );

  _first_melds := COALESCE(_state->'first_melds', '{}'::jsonb);
  IF _first_melds ? _uid::text = false OR _first_melds->_uid::text IS NULL THEN
    _first_melds := jsonb_set(_first_melds, ARRAY[_uid::text], to_jsonb(extract(epoch from now())::bigint), true);
  END IF;

  _action_log := COALESCE(_state->'action_log', '[]'::jsonb) ||
    jsonb_build_object('t', 'meld', 'p', _uid::text, 'type', _type, 'n', array_length(_cards, 1), 'pure', _is_pure, 'ts', extract(epoch from now())::bigint);

  _state := jsonb_set(_state, ARRAY['hands', _uid::text], to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{melds}', _melds);
  _state := jsonb_set(_state, '{first_melds}', _first_melds, true);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand, 1), 0)
    WHERE game_id=_game_id AND user_id=_uid;
END $function$;
REVOKE ALL ON FUNCTION public.rami_meld(uuid, integer[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_meld(uuid, integer[]) TO authenticated;
