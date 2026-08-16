-- ═══════════════════════════════════════════════════════════════
-- Fix 1: rami_draw normalise l'état avant de traiter la défausse
-- Bug: si state n'a pas la clé 'discards' (vieilles parties), 
-- _rami_discards_map peut retourner {} et la défausse est invisible.
-- Solution: normaliser l'état au début de rami_draw.
--
-- Fix 2: rami_draw accepte aussi turn_phase='play' pour _from='discard'
-- quand c'est le tout premier tour (le 1er joueur a 14 cartes et
-- peut choisir de piocher sur la défausse au lieu de jouer direct).
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.rami_draw(_game_id uuid, _from text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _deck int[]; _discards jsonb; _hand int[]; _card int; _hands jsonb;
  _pile int[]; _cfg record; _action_log jsonb;
  _last_by text; _k text; _v jsonb; _all int[]; _new_discards jsonb; _flat int[];
  _melds_count int;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  -- Normaliser l'état pour garantir que 'discards' et 'discard' existent
  _state := public._rami_normalize_state(_g.state);
  _melds_count := COALESCE(jsonb_array_length(COALESCE(_state->'melds','[]'::jsonb)), 0);

  -- Accepter draw en phase 'play' SEULEMENT si c'est le 1er tour (0 melds, 0 action_log)
  -- et _from='discard' (le 1er joueur peut prendre la carte visible)
  IF _g.turn_phase = 'play' THEN
    IF _from = 'discard' AND _melds_count = 0 
       AND COALESCE(jsonb_array_length(COALESCE(_state->'action_log','[]'::jsonb)), 0) <= 1 THEN
      NULL; -- autorisé: 1er joueur prend la défausse
    ELSE
      RAISE EXCEPTION 'deja pioché ou phase de jeu';
    END IF;
  ELSIF _g.turn_phase <> 'draw' THEN
    RAISE EXCEPTION 'deja pioché';
  END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _deck := COALESCE(public._rami_jarr(_state->'deck'), ARRAY[]::int[]);
  _discards := public._rami_discards_map(_state);
  _hand := COALESCE(public._rami_jarr(_state->'hands'->_uid::text), ARRAY[]::int[]);

  IF _from = 'discard' THEN
    _last_by := COALESCE(_state->>'last_discard_by', '_seed');
    _pile := COALESCE(public._rami_jarr(_discards->_last_by), ARRAY[]::int[]);
    -- Fallback: si last_discard_by n'existe pas, chercher n'importe quelle pile non-vide
    IF array_length(_pile,1) IS NULL THEN
      FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
        _pile := public._rami_jarr(_v);
        IF array_length(_pile,1) IS NOT NULL THEN
          _last_by := _k;
          EXIT;
        END IF;
      END LOOP;
    END IF;
    IF array_length(_pile,1) IS NULL THEN RAISE EXCEPTION 'défausse vide'; END IF;
    _card := _pile[array_length(_pile,1)];
    _pile := _pile[1:array_length(_pile,1)-1];
    IF array_length(_pile,1) IS NULL THEN
      _discards := _discards - _last_by;
    ELSE
      _discards := jsonb_set(_discards, ARRAY[_last_by], to_jsonb(_pile));
    END IF;
    _state := jsonb_set(_state, '{last_discard_by}', to_jsonb(_last_by), true);
  ELSE
    IF COALESCE(array_length(_deck,1),0) = 0 THEN
      _all := ARRAY[]::int[];
      _new_discards := '{}'::jsonb;
      FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
        _pile := public._rami_jarr(_v);
        IF array_length(_pile,1) > 1 THEN
          _all := _all || _pile[1:array_length(_pile,1)-1];
          _new_discards := _new_discards || jsonb_build_object(_k, jsonb_build_array(_pile[array_length(_pile,1)]));
        ELSIF array_length(_pile,1) = 1 THEN
          _new_discards := _new_discards || jsonb_build_object(_k, jsonb_build_array(_pile[1]));
        END IF;
      END LOOP;
      IF array_length(_all,1) IS NULL THEN RAISE EXCEPTION 'plus de cartes'; END IF;
      _deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_all) c);
      _discards := _new_discards;
    END IF;
    _card := _deck[1];
    _deck := _deck[2:array_length(_deck,1)];
  END IF;

  _hand := array_append(_hand, _card);
  _hands := jsonb_set(_state->'hands', ARRAY[_uid::text], to_jsonb(_hand));

  _action_log := COALESCE(_state->'action_log', '[]'::jsonb) ||
    jsonb_build_object('t', 'draw', 'p', _uid::text, 'from', _from, 'card', _card, 'ts', extract(epoch from now())::bigint);

  _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
  _state := jsonb_set(_state, '{discards}', _discards);
  _state := jsonb_set(_state, '{hands}', _hands);
  _state := jsonb_set(_state, '{action_log}', _action_log);
  _flat := ARRAY[]::int[];
  FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
    _flat := _flat || public._rami_jarr(_v);
  END LOOP;
  _state := jsonb_set(_state, '{discard}', to_jsonb(_flat), true);

  UPDATE public.rami_games
    SET state=_state, turn_phase='play',
        turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval,
        updated_at=now()
    WHERE id=_game_id;
  UPDATE public.rami_participants SET hand_count=array_length(_hand,1)
    WHERE game_id=_game_id AND user_id=_uid;
END $$;
REVOKE ALL ON FUNCTION public.rami_draw(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_draw(uuid,text) TO authenticated;
