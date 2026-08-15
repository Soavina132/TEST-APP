-- ============================================================
-- Fix RAMI bugs:
--   13) rami_tick: sync discard field instead of removing it
--   14) rami_claim_seven: reduce pot on refund + fix balance column
--   15) rami_tick: filter forfeited players in turn check
-- ============================================================

-- ── Bug 13 + 15: Rewrite rami_tick ─────────────────────────────────────

CREATE OR REPLACE FUNCTION public.rami_tick(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _g public.rami_games; _state jsonb; _uid uuid; _hand int[]; _new_hand int[];
  _deck int[]; _card int; _next int; _cfg record; _skips int;
  _best_card int; _best_pts int := -1; _pts int; _rank int; _c int;
  _is_bot boolean; _key text;
  _discards jsonb; _pile int[]; _reshuffle jsonb;
  _all_discard int[]; _k text; _v jsonb;
  _parts int[]; _win uuid;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RETURN; END IF;

  -- Bug 15: filter forfeited players — don't auto-play for someone who left
  SELECT COALESCE(is_bot,false), user_id INTO _is_bot, _uid
    FROM public.rami_participants WHERE game_id=_game_id AND slot=_g.current_turn AND NOT forfeited;

  IF NOT FOUND THEN
    -- Current player forfeited: advance turn
    SELECT array_agg(slot ORDER BY slot) INTO _parts FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited;
    IF COALESCE(array_length(_parts,1),0) <= 1 THEN
      SELECT user_id INTO _win FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited LIMIT 1;
      UPDATE public.rami_games SET status='finished', winner_id=_win, finished_at=now() WHERE id=_game_id;
      IF _win IS NOT NULL THEN
        UPDATE public.profiles SET balance_ar = balance_ar + (_g.pot * (100 - _g.commission_pct) / 100) WHERE id=_win;
        INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
          VALUES (_win,'rami_win', _g.pot * (100 - _g.commission_pct) / 100, _game_id, 'Rami win (forfait)');
      END IF;
      RETURN;
    END IF;
    SELECT * INTO _cfg FROM public._game_cfg('rami');
    _next := _g.current_turn;
    LOOP
      _next := (_next + 1) % _g.max_players;
      EXIT WHEN _next = ANY(_parts);
    END LOOP;
    UPDATE public.rami_games
       SET current_turn = _next, turn_phase = 'draw',
           turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
           updated_at = now()
     WHERE id = _game_id;
    PERFORM public._rami_autoplay_bots(_game_id);
    RETURN;
  END IF;

  IF _is_bot THEN
    PERFORM public._rami_autoplay_bots(_game_id);
    RETURN;
  END IF;

  IF _g.turn_deadline IS NULL OR _g.turn_deadline > now() THEN RETURN; END IF;
  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _skips := COALESCE((_g.turn_skips->>_uid::text)::int, 0) + 1;

  IF _skips >= COALESCE(_cfg.max_turn_skips,3) THEN
    UPDATE public.rami_participants SET forfeited = true WHERE game_id=_game_id AND user_id=_uid;
    IF (SELECT count(*) FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited) <= 1 THEN
      SELECT user_id INTO _win FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited LIMIT 1;
      UPDATE public.rami_games SET status='finished', winner_id=_win, finished_at=now() WHERE id=_game_id;
      IF _win IS NOT NULL THEN
        UPDATE public.profiles SET balance_ar = balance_ar + (_g.pot * (100 - _g.commission_pct) / 100) WHERE id=_win;
        INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
          VALUES (_win,'rami_win', _g.pot * (100 - _g.commission_pct) / 100, _game_id, 'Rami win (forfait)');
      END IF;
      RETURN;
    END IF;
  END IF;

  _state := public._rami_normalize_state(_g.state);
  _key := _uid::text;
  _deck := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'deck'))::int[], ARRAY[]::int[]);
  _discards := public._rami_discards_map(_state);
  _hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_key))::int[], ARRAY[]::int[]);

  IF _g.turn_phase = 'draw' THEN
    IF COALESCE(array_length(_deck,1),0) = 0 THEN
      _reshuffle := public._rami_reshuffle(_state);
      _deck := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_reshuffle->'deck'))::int[], ARRAY[]::int[]);
      _discards := _reshuffle->'discards';
      IF COALESCE(array_length(_deck,1),0) = 0 THEN
        UPDATE public.rami_games SET status='finished', finished_at=now(),
          state = jsonb_set(_state,'{end_reason}', to_jsonb('deck exhausted'::text))
          WHERE id=_game_id;
        RETURN;
      END IF;
    END IF;
    _card := _deck[1]; _deck := _deck[2:array_length(_deck,1)];
    _hand := array_append(_hand, _card);
  END IF;

  FOREACH _c IN ARRAY _hand LOOP
    IF public._rami_is_joker(_c, _g.joker_mode, _g.random_joker) THEN CONTINUE; END IF;
    _rank := _c % 13;
    _pts := CASE WHEN _rank = 0 THEN 11
                 WHEN _rank >= 10 THEN 10
                 ELSE _rank + 1 END;
    IF _pts > _best_pts THEN _best_pts := _pts; _best_card := _c; END IF;
  END LOOP;
  IF _best_card IS NULL THEN
    _best_card := _hand[1 + floor(random()*array_length(_hand,1))::int];
  END IF;
  _card := _best_card;

  _new_hand := public._rami_remove_one(_hand, _card);
  _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_key))::int[], ARRAY[]::int[]);
  _pile := array_append(_pile, _card);
  _discards := jsonb_set(_discards, ARRAY[_key], to_jsonb(_pile), true);

  _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
  _state := jsonb_set(_state, '{discards}', _discards);
  _state := jsonb_set(_state, '{last_discard_by}', to_jsonb(_key));
  _state := jsonb_set(_state, ARRAY['hands',_key], to_jsonb(_new_hand));

  -- Bug 13: sync discard field instead of removing it
  _all_discard := ARRAY[]::int[];
  FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
    _all_discard := _all_discard || ARRAY(SELECT jsonb_array_elements_text(_v))::int[];
  END LOOP;
  _state := jsonb_set(_state, '{discard}', to_jsonb(_all_discard), true);

  UPDATE public.rami_participants SET hand_count=array_length(_new_hand,1) WHERE game_id=_game_id AND user_id=_uid;

  _next := _g.current_turn;
  LOOP
    _next := (_next + 1) % _g.max_players;
    EXIT WHEN _next IN (SELECT slot FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited);
  END LOOP;

  UPDATE public.rami_games SET state=_state, current_turn=_next, turn_phase='draw',
    turn_skips = jsonb_set(COALESCE(_g.turn_skips,'{}'::jsonb), ARRAY[_uid::text], to_jsonb(_skips)),
    turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval,
    updated_at=now()
    WHERE id=_game_id;

  PERFORM public._rami_autoplay_bots(_game_id);
END $function$;

-- ── Bug 14: Fix rami_claim_seven — reduce pot + fix balance column ──────

CREATE OR REPLACE FUNCTION public.rami_claim_seven(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _melds jsonb; _m jsonb; _total_cards int := 0; _found boolean := false;
  _refunded jsonb; _action_log jsonb;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;

  _state := _g.state;
  _refunded := COALESCE(_state->'refunded','{}'::jsonb);
  IF _refunded ? _uid::text THEN RAISE EXCEPTION 'deja remboursé'; END IF;

  -- Check if player has melds totaling exactly 7 cards
  _melds := COALESCE(_state->'melds','[]'::jsonb);
  FOR _m IN SELECT * FROM jsonb_array_elements(_melds) LOOP
    IF _m->>'player' = _uid::text THEN
      _total_cards := _total_cards + COALESCE(jsonb_array_length(_m->'cards'), 0);
      IF _m->>'type' = 'seven' THEN _found := true; END IF;
    END IF;
  END LOOP;

  IF NOT _found AND _total_cards < 7 THEN
    RAISE EXCEPTION 'tu dois poser 7 cartes valides';
  END IF;

  -- Refund stake AND reduce pot
  IF _g.stake > 0 THEN
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, 0) + _g.stake WHERE id=_uid;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (_uid,'rami_seven_refund',_g.stake,_game_id,'7 Cartes refund');
    UPDATE public.rami_games SET pot = GREATEST(pot - _g.stake, 0) WHERE id=_game_id;
  END IF;

  _refunded := _refunded || jsonb_build_object(_uid::text, true);
  _state := jsonb_set(_state, '{refunded}', _refunded);
  _action_log := COALESCE(_state->'action_log','[]'::jsonb) ||
    jsonb_build_object('t','seven','p',_uid::text,'ts',extract(epoch from now())::bigint);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
END $function$;
