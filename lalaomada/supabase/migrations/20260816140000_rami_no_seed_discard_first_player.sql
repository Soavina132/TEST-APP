-- ═══════════════════════════════════════════════════════════════
-- Rami: 1er tour sans carte seed sur la défausse
--
-- Règles:
-- 1. Le 1er joueur reçoit 14 cartes, les autres 13
-- 2. AUCUNE carte sur la défausse au début (pas de _seed)
-- 3. Le 1er joueur ne peut PAS piocher (ni deck ni défausse)
--    Il organise sa main et défausse une carte
-- 4. Après sa défausse, la carte apparaît sur la défausse
-- 5. Le tour passe au joueur suivant (phase='draw') qui peut piocher
-- ═══════════════════════════════════════════════════════════════

-- ── 1. rami_start: pas de carte seed sur la défausse ──
CREATE OR REPLACE FUNCTION public.rami_start(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  _g public.rami_games; _deck int[]; _i int; _j int; _tmp int;
  _hands jsonb := '{}'::jsonb; _hand int[]; _state jsonb; _key text;
  _cfg record; _joker_mode text; _random_joker int;
  _discards jsonb; _action_log jsonb;
  _slot int; _uid uuid; _is_bot boolean;
  _is_first boolean := true;
  _card_count int;
  _deck_size int;
  _max_players int;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status NOT IN ('waiting','open') THEN RETURN; END IF;

  IF (SELECT count(*) FROM public.rami_participants WHERE game_id=_game_id) < 2 THEN
    RAISE EXCEPTION 'pas assez de joueurs';
  END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');

  _joker_mode := _g.joker_mode;
  _random_joker := NULL;

  IF _joker_mode = 'aucun' THEN
    _deck_size := 52;
  ELSIF _joker_mode = 'fixe' THEN
    _deck_size := 54;
  ELSE
    _deck_size := 56;
    _random_joker := floor(random()*52)::int;
  END IF;

  _max_players := _g.max_players;
  IF _max_players <= 2 THEN
    _deck := ARRAY(SELECT generate_series(0, _deck_size-1)) ||
             ARRAY(SELECT generate_series(56, _deck_size-1+56));
  ELSE
    _deck := ARRAY(SELECT generate_series(0, _deck_size-1)) ||
             ARRAY(SELECT generate_series(56, _deck_size-1+56)) ||
             ARRAY(SELECT generate_series(112, _deck_size-1+112));
  END IF;

  FOR _i IN REVERSE array_length(_deck,1)..2 LOOP
    _j := 1 + floor(random()*_i)::int;
    _tmp := _deck[_i]; _deck[_i] := _deck[_j]; _deck[_j] := _tmp;
  END LOOP;

  -- Deal: first player gets 14, others get 13
  FOR _slot, _uid, _is_bot IN
    SELECT slot, user_id, is_bot FROM public.rami_participants
    WHERE game_id=_game_id ORDER BY slot
  LOOP
    IF _is_first THEN
      _card_count := 14;
      _is_first := false;
    ELSE
      _card_count := 13;
    END IF;

    _hand := _deck[1:_card_count];
    _deck := _deck[_card_count+1:array_length(_deck,1)];
    _key := CASE WHEN COALESCE(_is_bot, false) THEN 'bot:' || _slot::text ELSE _uid::text END;
    _hands := _hands || jsonb_build_object(_key, to_jsonb(_hand));
    UPDATE public.rami_participants SET hand_count = _card_count
      WHERE game_id=_game_id AND slot=_slot;
  END LOOP;

  -- PAS de carte seed sur la défausse — la défausse commence vide
  _discards := '{}'::jsonb;

  _action_log := jsonb_build_array(
    jsonb_build_object('t', 'start', 'ts', extract(epoch from now())::bigint)
  );

  _state := jsonb_build_object(
    'deck', to_jsonb(_deck),
    'discards', _discards,
    'discard', '[]'::jsonb,
    'last_discard_by', null::jsonb,
    'hands', _hands,
    'melds', '[]'::jsonb,
    'action_log', _action_log,
    'refunded', '{}'::jsonb
  );

  UPDATE public.rami_games SET
    status='playing', state=_state, started_at=now(),
    current_turn=0, turn_phase='play',  -- 1er joueur en phase 'play' (il a déjà 14 cartes)
    random_joker=_random_joker,
    turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval
    WHERE id=_game_id;

  PERFORM public._rami_autoplay_bots(_game_id);
END $function$;

REVOKE ALL ON FUNCTION public.rami_start(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_start(uuid) TO authenticated;

-- ── 2. rami_draw: retirer l'exception du 1er tour ──
-- Le 1er joueur NE peut PAS piocher (ni deck ni défausse)
-- Il est en phase 'play' et doit simplement défausser
CREATE OR REPLACE FUNCTION public.rami_draw(_game_id uuid, _from text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _deck int[]; _discards jsonb; _hand int[]; _card int; _hands jsonb;
  _pile int[]; _cfg record; _action_log jsonb;
  _last_by text; _k text; _v jsonb; _all int[]; _new_discards jsonb; _flat int[];
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  -- Normaliser l'état
  _state := public._rami_normalize_state(_g.state);

  -- Le 1er joueur est en phase 'play' → il ne peut PAS piocher
  IF _g.turn_phase <> 'draw' THEN
    RAISE EXCEPTION 'deja pioché ou phase de jeu';
  END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _deck := COALESCE(public._rami_jarr(_state->'deck'), ARRAY[]::int[]);
  _discards := public._rami_discards_map(_state);
  _hand := COALESCE(public._rami_jarr(_state->'hands'->_uid::text), ARRAY[]::int[]);

  IF _from = 'discard' THEN
    _last_by := COALESCE(_state->>'last_discard_by', '_seed');
    -- Ne pas essayer _seed si la défausse est vide
    _pile := COALESCE(public._rami_jarr(_discards->_last_by), ARRAY[]::int[]);
    IF array_length(_pile,1) IS NULL THEN
      -- Chercher n'importe quelle pile non-vide
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
