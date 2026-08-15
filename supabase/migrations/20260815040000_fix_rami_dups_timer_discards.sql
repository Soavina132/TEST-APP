-- ============================================================
-- Fix RAMI bugs:
--   3) Drop old duplicate function signatures (rami_create 5-arg, rami_start_solo_bot 3-arg)
--   4) rami_discard: use _cfg.turn_timer_seconds instead of hardcoded 60s
--   5) rami_discard / rami_draw: sync per-player discards map so bots see human discards
-- ============================================================

-- ── Bug 3: Drop old duplicate functions ──────────────────────────────────

DROP FUNCTION IF EXISTS public.rami_create(numeric, integer, boolean, integer, text);
DROP FUNCTION IF EXISTS public.rami_start_solo_bot(integer, text, text);

-- ── Bug 4 + 5: Rewrite rami_discard ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.rami_discard(_game_id uuid, _card integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE _uid uuid := auth.uid(); _g rami_games; _slot int; _state jsonb;
  _hand int[]; _new_hand int[]; _discard int[]; _hands jsonb;
  _parts int[]; _next int; _payout numeric; _comm numeric; _won boolean;
  _cfg record; _discards jsonb; _pile int[]; _key text;
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _key := _uid::text;
  _state := _g.state;
  _hand := ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_key))::int[];
  IF NOT (_card = ANY(_hand)) THEN RAISE EXCEPTION 'carte absente'; END IF;
  _new_hand := public._rami_remove_one(_hand,_card);

  -- Flat discard array (legacy compat — top of pile)
  _discard := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'discard'))::int[], ARRAY[]::int[]);
  _discard := array_append(_discard,_card);

  -- Per-player discards map (used by bots to find cards to draw)
  _discards := public._rami_discards_map(_state);
  _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_key))::int[], ARRAY[]::int[]);
  _pile := array_append(_pile, _card);
  _discards := jsonb_set(_discards, ARRAY[_key], to_jsonb(_pile), true);

  _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_new_hand));
  _state := jsonb_set(_state,'{hands}',_hands);
  _state := jsonb_set(_state,'{discard}',to_jsonb(_discard));
  _state := jsonb_set(_state,'{discards}',_discards);
  _state := jsonb_set(_state,'{last_discard_by}',to_jsonb(_key));

  UPDATE public.rami_participants
     SET hand_count=COALESCE(array_length(_new_hand,1),0)
   WHERE game_id=_game_id AND user_id=_uid;

  -- Victory: hand empty AND combo set valid (1 carré + 2 trio + 1 escalier)
  IF COALESCE(array_length(_new_hand,1),0) = 0 THEN
    _won := public._rami_check_win(_state, _uid);
    IF _won THEN
      _comm := round(_g.pot * _g.commission_pct / 100.0, 0);
      _payout := _g.pot - _comm;
      UPDATE public.profiles SET balance_ar=balance_ar+_payout WHERE id=_uid;
      INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (_uid,'rami_win',_payout,_game_id,'Win rami');
      UPDATE public.rami_games SET status='finished', winner_id=_uid, finished_at=now(), state=_state WHERE id=_game_id;
      RETURN;
    ELSE
      RAISE EXCEPTION 'combinaisons incomplètes: il faut 1 carré + 2 trios + 1 escalier';
    END IF;
  END IF;

  -- Next turn
  SELECT array_agg(slot ORDER BY slot) INTO _parts
    FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited;
  _next := _g.current_turn;
  LOOP
    _next := (_next + 1) % _g.max_players;
    EXIT WHEN _next = ANY(_parts);
  END LOOP;

  UPDATE public.rami_games
     SET state=_state, current_turn=_next, turn_phase='draw',
         turn_deadline=now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
         updated_at=now()
   WHERE id=_game_id;
END $function$;

-- ── Bug 5: Rewrite rami_draw to sync discards map ────────────────────────

CREATE OR REPLACE FUNCTION public.rami_draw(_game_id uuid, _from text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _deck int[]; _discard int[]; _hand int[]; _card int; _hands jsonb; _cfg record;
  _discards jsonb := NULL; _pile int[]; _last text;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL OR _slot <> _g.current_turn THEN RAISE EXCEPTION 'pas ton tour'; END IF;
  IF _g.turn_phase <> 'draw' THEN RAISE EXCEPTION 'déjà pioché'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _state := _g.state;
  _deck := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'deck'))::int[], ARRAY[]::int[]);
  _discard := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'discard'))::int[], ARRAY[]::int[]);
  _hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[], ARRAY[]::int[]);

  IF _from = 'discard' THEN
    IF array_length(_discard,1) IS NULL THEN RAISE EXCEPTION 'défausse vide'; END IF;
    _card := _discard[array_length(_discard,1)];
    _discard := _discard[1:array_length(_discard,1)-1];

    -- Sync per-player discards map: remove top card from last discarder's pile
    _discards := public._rami_discards_map(_state);
    _last := public._rami_last_discarder(_state);
    IF _last IS NOT NULL AND _discards ? _last THEN
      _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_last))::int[], ARRAY[]::int[]);
      IF array_length(_pile,1) IS NOT NULL AND array_length(_pile,1) > 0 AND _pile[array_length(_pile,1)] = _card THEN
        _pile := _pile[1:array_length(_pile,1)-1];
        IF array_length(_pile,1) IS NULL THEN
          _discards := _discards - _last;
        ELSE
          _discards := jsonb_set(_discards, ARRAY[_last], to_jsonb(_pile));
        END IF;
      END IF;
    END IF;
  ELSE
    IF array_length(_deck,1) IS NULL THEN
      IF array_length(_discard,1) <= 1 THEN RAISE EXCEPTION 'plus de cartes'; END IF;
      _deck := _discard[1:array_length(_discard,1)-1];
      _discard := ARRAY[_discard[array_length(_discard,1)]];
      _deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_deck) c);
      -- Reset discards map to just the remaining top card under last discarder
      _discards := public._rami_discards_map(_state);
      _last := public._rami_last_discarder(_state);
      IF _last IS NOT NULL THEN
        _discards := jsonb_build_object(_last, to_jsonb(_discard));
      END IF;
    END IF;
    _card := _deck[1];
    _deck := _deck[2:array_length(_deck,1)];
  END IF;

  _hand := array_append(_hand, _card);
  _hands := jsonb_set(_state->'hands', ARRAY[_uid::text], to_jsonb(_hand));
  _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard));
  _state := jsonb_set(_state, '{hands}', _hands);

  -- Only set discards map when it was actually modified (discard draw or reshuffle)
  IF _discards IS NOT NULL THEN
    _state := jsonb_set(_state, '{discards}', _discards);
  END IF;

  UPDATE public.rami_games
     SET state = _state,
         turn_phase = 'play',
         turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
         updated_at = now()
   WHERE id = _game_id;

  UPDATE public.rami_participants SET hand_count=array_length(_hand,1)
   WHERE game_id=_game_id AND user_id=_uid;
END $function$;
