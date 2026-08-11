-- ─────────────────────────────────────────────────────────────────────────────
-- Rami: auto-pioche au timeout au lieu de draw+discard d'un coup
--
-- Avant: rami_tick au timeout faisait pioche + défausse aléatoire → tour perdu
-- Après: 
--   phase 'draw' + timeout → auto-pioche depuis le deck, passage en 'play'
--                          avec un NOUVEAU délai (le joueur choisit sa défausse)
--   phase 'play' + timeout → défausse auto aléatoire + tour suivant
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.rami_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  _g rami_games; _state jsonb; _uid uuid; _is_bot boolean; _slot int;
  _hand int[]; _new_hand int[];
  _deck int[]; _discards jsonb; _pile int[]; _card int; _next int; _cfg record;
  _skips int; _pkey text; _last text; v_think_until timestamptz; v_delay_ms int;
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RETURN; END IF;

  -- Check if current player is a bot
  SELECT user_id, is_bot, slot INTO _uid, _is_bot, _slot
    FROM rami_participants WHERE game_id=_game_id AND slot=_g.current_turn;

  -- ═══ BOT: use think timer (1-2s delay) instead of playing immediately ═══
  IF COALESCE(_is_bot, false) THEN
    _state := _g.state;
    v_think_until := NULLIF(_state->>'bot_think_until','')::timestamptz;
    IF v_think_until IS NULL THEN
      v_delay_ms := 800 + (floor(random() * 1200))::int;
      _state := jsonb_set(_state, '{bot_think_until}',
              to_jsonb((now() + make_interval(secs => v_delay_ms / 1000.0))::text), true);
      UPDATE rami_games SET state = _state WHERE id = _game_id;
      RETURN;
    ELSIF v_think_until > now() THEN
      RETURN;
    END IF;
    _state := _state - 'bot_think_until';
    UPDATE rami_games SET state = _state WHERE id = _game_id;
    PERFORM public.rami_bot_play(_game_id);
    RETURN;
  END IF;

  -- Human timeout
  IF _g.turn_deadline IS NULL OR _g.turn_deadline > now() THEN RETURN; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _state := public._rami_normalize_state(_g.state);
  _pkey := _uid::text;
  _hand := ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_pkey))::int[];

  -- ═══ Phase DRAW + timeout: AUTO-PIOCHE depuis le deck, puis phase 'play' ═══
  IF _g.turn_phase = 'draw' THEN
    _deck := ARRAY(SELECT jsonb_array_elements_text(_state->'deck'))::int[];

    -- Si deck vide, essayer reshuffle depuis la défausse
    IF array_length(_deck,1) IS NULL THEN
      DECLARE _reshuffle jsonb;
      BEGIN
        _reshuffle := public._rami_reshuffle(_state);
        _deck := public._rami_jarr(_reshuffle->'deck');
        _discards := COALESCE(_reshuffle->'discards','{}'::jsonb);
        _state := jsonb_set(_state, '{discards}', _discards, true);
      END;
    END IF;

    -- Si encore vide après reshuffle → passer au joueur suivant
    IF array_length(_deck,1) IS NULL THEN
      -- Aucune carte à piocher, on défausse une carte au hasard et on passe
      _card := _hand[1 + floor(random()*array_length(_hand,1))::int];
      _new_hand := public._rami_remove_one(_hand, _card);
      _pile := public._rami_jarr(public._rami_discards_map(_state)->_pkey);
      _pile := array_append(_pile, _card);
      _discards := public._rami_discards_map(_state);
      _discards := jsonb_set(_discards, ARRAY[_pkey], public._rami_jset(_pile), true);
      _state := jsonb_set(_state, '{discards}', _discards, true);
      _state := jsonb_set(_state, ARRAY['hands',_pkey], to_jsonb(_new_hand));
      _state := _state - 'discard';
      _state := jsonb_set(_state, '{last_discard_by}', to_jsonb(_pkey), true);
      UPDATE rami_participants SET hand_count=array_length(_new_hand,1) WHERE game_id=_game_id AND user_id=_uid;
      -- Avancer au suivant
      _next := _g.current_turn;
      LOOP
        _next := (_next + 1) % _g.max_players;
        EXIT WHEN _next IN (SELECT slot FROM rami_participants WHERE game_id=_game_id AND NOT forfeited);
      END LOOP;
      _state := _state - 'bot_think_until';
      PERFORM public._rami_arm_bot_think(_game_id, _next, _state);
      UPDATE rami_games SET state=_state, current_turn=_next, turn_phase='draw',
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
        updated_at=now() WHERE id=_game_id;
      RETURN;
    END IF;

    -- Piocher la carte du dessus du deck
    _card := _deck[1];
    _deck := _deck[2:array_length(_deck,1)];
    _hand := array_append(_hand, _card);

    _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
    _state := jsonb_set(_state, ARRAY['hands',_pkey], to_jsonb(_hand));
    _state := _state - 'discard';

    UPDATE rami_participants SET hand_count=COALESCE(array_length(_hand,1),0)
      WHERE game_id=_game_id AND user_id=_uid;

    -- Passage en phase 'play' avec un NOUVEAU délai pour la défausse
    UPDATE rami_games
       SET state = _state, turn_phase = 'play',
           turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
           updated_at = now()
     WHERE id = _game_id;
    RETURN;
  END IF;

  -- ═══ Phase PLAY + timeout: DÉFAUSSE AUTO d'une carte aléatoire ═══
  _skips := COALESCE((_g.turn_skips->>_uid::text)::int, 0) + 1;

  IF _skips >= _cfg.max_turn_skips THEN
    UPDATE rami_participants SET forfeited = true WHERE game_id=_game_id AND user_id=_uid;
    IF (SELECT count(*) FROM rami_participants WHERE game_id=_game_id AND NOT forfeited) <= 1 THEN
      DECLARE _win uuid;
      BEGIN
        SELECT user_id INTO _win FROM rami_participants WHERE game_id=_game_id AND NOT forfeited LIMIT 1;
        UPDATE rami_games SET status='finished', winner_id=_win, finished_at=now() WHERE id=_game_id;
        IF _win IS NOT NULL THEN
          UPDATE profiles SET balance_ar = balance_ar + (_g.pot * (100 - _g.commission_pct) / 100) WHERE id=_win;
          INSERT INTO transactions(user_id,type,amount,ref_id,note)
            VALUES (_win,'rami_win', _g.pot * (100 - _g.commission_pct) / 100, _game_id, 'Rami win (forfait)');
        END IF;
        RETURN;
      END;
    END IF;
  END IF;

  _discards := public._rami_discards_map(_state);
  _card := _hand[1 + floor(random()*array_length(_hand,1))::int];
  _new_hand := public._rami_remove_one(_hand, _card);
  _pile := public._rami_jarr(_discards->_pkey);
  _pile := array_append(_pile, _card);
  _discards := jsonb_set(_discards, ARRAY[_pkey], public._rami_jset(_pile), true);
  _state := jsonb_set(_state, '{deck}', to_jsonb(ARRAY(SELECT jsonb_array_elements_text(_state->'deck'))::int[]));
  _state := jsonb_set(_state, '{discards}', COALESCE(_discards,'{}'::jsonb), true);
  _state := _state - 'discard';
  _state := jsonb_set(_state, '{last_discard_by}', to_jsonb(_pkey), true);
  _state := jsonb_set(_state, ARRAY['hands',_pkey], to_jsonb(_new_hand));
  UPDATE rami_participants SET hand_count=array_length(_new_hand,1) WHERE game_id=_game_id AND user_id=_uid;

  _next := _g.current_turn;
  LOOP
    _next := (_next + 1) % _g.max_players;
    EXIT WHEN _next IN (SELECT slot FROM rami_participants WHERE game_id=_game_id AND NOT forfeited);
  END LOOP;

  _state := _state - 'bot_think_until';
  PERFORM public._rami_arm_bot_think(_game_id, _next, _state);

  UPDATE rami_games SET state=_state, current_turn=_next, turn_phase='draw',
    turn_skips = jsonb_set(_g.turn_skips, ARRAY[_uid::text], to_jsonb(_skips)),
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
    updated_at=now()
    WHERE id=_game_id;
END;
$function$;
