-- ═══════════════════════════════════════════════════════════════════
-- FIX: rami_tick supprimait le tableau plat discard (_state - 'discard')
-- à 3 endroits, ce qui empêchait le joueur suivant de piocher sur la
-- défausse (discard devenait NULL alors que discards avait des cartes).
--
-- Solution: au lieu de supprimer discard, on le met à jour correctement:
-- - Pour les auto-défaites: ajouter la carte au tableau plat
-- - Pour l'auto-pioche du deck: garder le tableau plat tel quel
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.rami_tick(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  _g rami_games; _state jsonb; _uid uuid; _is_bot boolean; _slot int;
  _hand int[]; _new_hand int[];
  _deck int[]; _discards jsonb; _pile int[]; _card int; _next int; _cfg record;
  _skips int; _pkey text;
  _discard_arr int[];  -- tableau plat = source de vérité
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RETURN; END IF;

  SELECT user_id, is_bot, slot INTO _uid, _is_bot, _slot
    FROM rami_participants WHERE game_id=_game_id AND slot=_g.current_turn;

  IF COALESCE(_is_bot, false) THEN
    PERFORM public._rami_autoplay_bots(_game_id);
    RETURN;
  END IF;

  IF _g.turn_deadline IS NULL OR _g.turn_deadline > now() THEN RETURN; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _state := public._rami_normalize_state(_g.state);
  _pkey := _uid::text;
  _hand := COALESCE(public._rami_jarr(_state->'hands'->_pkey), ARRAY[]::int[]);
  _discard_arr := COALESCE(public._rami_jarr(_state->'discard'), ARRAY[]::int[]);
  _discard_arr := ARRAY(SELECT x FROM unnest(_discard_arr) x WHERE x IS NOT NULL);

  IF _g.turn_phase = 'draw' THEN
    _deck := COALESCE(public._rami_jarr(_state->'deck'), ARRAY[]::int[]);
    IF array_length(_deck,1) IS NULL THEN
      DECLARE _reshuffle jsonb;
      BEGIN
        _reshuffle := public._rami_reshuffle(_state);
        _deck := public._rami_jarr(_reshuffle->'deck');
        _discards := COALESCE(_reshuffle->'discards','{}'::jsonb);
        _state := jsonb_set(_state, '{discards}', _discards, true);
        -- Reconstruire le tableau plat depuis discards
        _discard_arr := ARRAY[]::int[];
        DECLARE _k text; _v jsonb; BEGIN
          FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
            _discard_arr := _discard_arr || public._rami_jarr(_v);
          END LOOP;
        END;
      END;
    END IF;

    IF array_length(_deck,1) IS NULL THEN
      -- ═══ Timeout en draw + deck vide: forcer défausse d'une carte ═══
      _card := _hand[1 + floor(random()*array_length(_hand,1))::int];
      _new_hand := public._rami_remove_one(_hand, _card);
      _discards := public._rami_discards_map(_state);
      _pile := public._rami_jarr(_discards->_pkey);
      _pile := array_append(_pile, _card);
      _discards := jsonb_set(_discards, ARRAY[_pkey], public._rami_jset(_pile), true);
      -- FIX: mettre à jour le tableau plat au lieu de le supprimer
      _discard_arr := array_append(_discard_arr, _card);
      _state := jsonb_set(_state, '{discards}', _discards, true);
      _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
      _state := jsonb_set(_state, ARRAY['hands',_pkey], to_jsonb(_new_hand));
      _state := jsonb_set(_state, '{last_discard_by}', to_jsonb(_pkey), true);
      UPDATE rami_participants SET hand_count=array_length(_new_hand,1) WHERE game_id=_game_id AND user_id=_uid;
      _next := _g.current_turn;
      LOOP
        _next := (_next + 1) % _g.max_players;
        EXIT WHEN _next IN (SELECT slot FROM rami_participants WHERE game_id=_game_id AND NOT forfeited);
      END LOOP;
      UPDATE rami_games SET state=_state, current_turn=_next, turn_phase='draw',
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
        updated_at=now() WHERE id=_game_id;
      PERFORM public._rami_autoplay_bots(_game_id);
      RETURN;
    END IF;

    -- ═══ Timeout en draw + deck non vide: auto-piocher du deck ═══
    _card := _deck[1];
    _deck := _deck[2:array_length(_deck,1)];
    _hand := array_append(_hand, _card);
    _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
    _state := jsonb_set(_state, ARRAY['hands',_pkey], to_jsonb(_hand));
    -- FIX: garder le tableau plat discard tel quel (la défausse n'a pas changé)
    _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
    UPDATE rami_participants SET hand_count=COALESCE(array_length(_hand,1),0)
      WHERE game_id=_game_id AND user_id=_uid;
    UPDATE rami_games
       SET state = _state, turn_phase = 'play',
           turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
           updated_at = now()
     WHERE id = _game_id;
    RETURN;
  END IF;

  -- ═══ Timeout en play phase ═══
  _skips := COALESCE((_g.turn_skips->>_uid::text)::int, 0) + 1;
  IF _skips >= COALESCE(_cfg.max_turn_skips, 3) THEN
    UPDATE rami_participants SET forfeited = true WHERE game_id=_game_id AND user_id=_uid;
    IF (SELECT count(*) FROM rami_participants WHERE game_id=_game_id AND NOT forfeited) <= 1 THEN
      DECLARE _win uuid; _payout numeric;
      BEGIN
        SELECT user_id INTO _win FROM rami_participants WHERE game_id=_game_id AND NOT forfeited LIMIT 1;
        UPDATE rami_games SET status='finished', winner_id=_win, finished_at=now() WHERE id=_game_id;
        IF _win IS NOT NULL THEN
          _payout := _g.pot * (100 - _g.commission_pct) / 100;
          UPDATE profiles SET balance_ar = COALESCE(balance_ar, balance) + _payout WHERE id=_win;
          INSERT INTO transactions(user_id,type,amount,ref_id,note)
            VALUES (_win,'rami_win', _payout, _game_id, 'Rami win (forfait)');
        END IF;
        RETURN;
      END;
    END IF;
  END IF;

  -- ═══ Auto-défausser une carte aléatoire ═══
  _discards := public._rami_discards_map(_state);
  _card := _hand[1 + floor(random()*array_length(_hand,1))::int];
  _new_hand := public._rami_remove_one(_hand, _card);
  _pile := public._rami_jarr(_discards->_pkey);
  _pile := array_append(_pile, _card);
  _discards := jsonb_set(_discards, ARRAY[_pkey], public._rami_jset(_pile), true);
  -- FIX: mettre à jour le tableau plat au lieu de le supprimer
  _discard_arr := array_append(_discard_arr, _card);
  _state := jsonb_set(_state, '{discards}', COALESCE(_discards,'{}'::jsonb), true);
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
  _state := jsonb_set(_state, '{last_discard_by}', to_jsonb(_pkey), true);
  _state := jsonb_set(_state, ARRAY['hands',_pkey], to_jsonb(_new_hand));
  UPDATE rami_participants SET hand_count=array_length(_new_hand,1) WHERE game_id=_game_id AND user_id=_uid;

  _next := _g.current_turn;
  LOOP
    _next := (_next + 1) % _g.max_players;
    EXIT WHEN _next IN (SELECT slot FROM rami_participants WHERE game_id=_game_id AND NOT forfeited);
  END LOOP;

  UPDATE rami_games SET state=_state, current_turn=_next, turn_phase='draw',
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
    updated_at=now() WHERE id=_game_id;

  PERFORM public._rami_autoplay_bots(_game_id);
END $function$;
