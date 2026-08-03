
-- Fix Rami timer:
-- 1) Reset per-turn timer to 60s (was 500s, which felt like "no timer")
UPDATE public.game_configs SET turn_timer_seconds = 60 WHERE slug = 'rami';

-- 2) rami_draw must reset turn_deadline so the player has a full turn to play after drawing
CREATE OR REPLACE FUNCTION public.rami_draw(_game_id uuid, _from text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _deck int[]; _discard int[]; _hand int[]; _card int; _hands jsonb; _cfg record;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL OR _slot <> _g.current_turn THEN RAISE EXCEPTION 'pas ton tour'; END IF;
  IF _g.turn_phase <> 'draw' THEN RAISE EXCEPTION 'déjà pioché'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');

  _state := _g.state;
  _deck := ARRAY(SELECT jsonb_array_elements_text(_state->'deck'))::int[];
  _discard := ARRAY(SELECT jsonb_array_elements_text(_state->'discard'))::int[];
  _hand := ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[];
  IF _from = 'discard' THEN
    IF array_length(_discard,1) IS NULL THEN RAISE EXCEPTION 'défausse vide'; END IF;
    _card := _discard[array_length(_discard,1)];
    _discard := _discard[1:array_length(_discard,1)-1];
  ELSE
    IF array_length(_deck,1) IS NULL THEN
      IF array_length(_discard,1) <= 1 THEN RAISE EXCEPTION 'plus de cartes'; END IF;
      _deck := _discard[1:array_length(_discard,1)-1];
      _discard := ARRAY[_discard[array_length(_discard,1)]];
      _deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_deck) c);
    END IF;
    _card := _deck[1];
    _deck := _deck[2:array_length(_deck,1)];
  END IF;
  _hand := array_append(_hand, _card);
  _hands := jsonb_set(_state->'hands', ARRAY[_uid::text], to_jsonb(_hand));
  _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard));
  _state := jsonb_set(_state, '{hands}', _hands);

  UPDATE public.rami_games
     SET state = _state,
         turn_phase = 'play',
         turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
         updated_at = now()
   WHERE id = _game_id;

  UPDATE public.rami_participants SET hand_count=array_length(_hand,1)
   WHERE game_id=_game_id AND user_id=_uid;
END $$;

GRANT EXECUTE ON FUNCTION public.rami_draw(uuid,text) TO authenticated;
