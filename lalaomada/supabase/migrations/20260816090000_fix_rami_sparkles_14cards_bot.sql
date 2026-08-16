-- ═══════════════════════════════════════════════════════════════
-- Fix 3 bugs Rami :
-- 1. Helper functions manquantes (_rami_jarr, _rami_jset, _rami_discards_map,
--    _rami_normalize_state, _rami_last_discarder, _rami_reshuffle)
-- 2. rami_start : 14 cartes pour le 1er joueur + deck correct selon joker_mode
-- 3. rami_bot_tick_all + rami_tick → utilisent _rami_autoplay_bots (plus récent)
-- ═══════════════════════════════════════════════════════════════

-- ── 1. Helper functions ──

CREATE OR REPLACE FUNCTION public._rami_jarr(_v jsonb)
RETURNS int[] LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  IF _v IS NULL THEN RETURN ARRAY[]::int[]; END IF;
  IF jsonb_typeof(_v) <> 'array' THEN RETURN ARRAY[]::int[]; END IF;
  RETURN COALESCE(
    ARRAY(SELECT elem::int FROM jsonb_array_elements_text(_v) elem
          WHERE elem IS NOT NULL AND elem ~ '^[0-9]+$'),
    ARRAY[]::int[]);
END $$;

CREATE OR REPLACE FUNCTION public._rami_jset(_arr int[])
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  RETURN to_jsonb(COALESCE(_arr, ARRAY[]::int[]));
END $$;

CREATE OR REPLACE FUNCTION public._rami_discards_map(_state jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE _discards jsonb;
BEGIN
  _discards := _state->'discards';
  IF _discards IS NULL OR jsonb_typeof(_discards) = 'null' THEN
    _discards := jsonb_build_object('_seed', _state->'discard');
  END IF;
  IF _discards IS NULL OR jsonb_typeof(_discards) = 'null' THEN
    _discards := '{}'::jsonb;
  END IF;
  RETURN _discards;
END $$;

CREATE OR REPLACE FUNCTION public._rami_normalize_state(_state jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE _discards jsonb; _all_discard int[]; _k text; _v jsonb;
BEGIN
  IF _state IS NULL THEN RETURN '{}'::jsonb; END IF;
  _discards := public._rami_discards_map(_state);
  IF _state ? 'discard' = false OR _state->'discard' IS NULL THEN
    _all_discard := ARRAY[]::int[];
    FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
      _all_discard := _all_discard || public._rami_jarr(_v);
    END LOOP;
    _state := jsonb_set(_state, '{discard}', to_jsonb(_all_discard), true);
  END IF;
  IF _state ? 'discards' = false OR _state->'discards' IS NULL THEN
    _state := jsonb_set(_state, '{discards}', _discards, true);
  END IF;
  IF _state ? 'melds' = false THEN
    _state := jsonb_set(_state, '{melds}', '[]'::jsonb, true);
  END IF;
  IF _state ? 'action_log' = false THEN
    _state := jsonb_set(_state, '{action_log}', '[]'::jsonb, true);
  END IF;
  RETURN _state;
END $$;

CREATE OR REPLACE FUNCTION public._rami_last_discarder(_state jsonb)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  RETURN COALESCE(_state->>'last_discard_by', '_seed');
END $$;

CREATE OR REPLACE FUNCTION public._rami_reshuffle(_state jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  _discards jsonb; _deck int[]; _k text; _v jsonb;
  _pile int[]; _all int[]; _tops int[]; _new_discards jsonb;
  _i int;
BEGIN
  _discards := public._rami_discards_map(_state);
  _all := ARRAY[]::int[]; _tops := ARRAY[]::int[];
  FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
    _pile := public._rami_jarr(_v);
    IF array_length(_pile,1) > 1 THEN
      _all := _all || _pile[1:array_length(_pile,1)-1];
      _tops := array_append(_tops, _pile[array_length(_pile,1)]);
    ELSIF array_length(_pile,1) = 1 THEN
      _tops := array_append(_tops, _pile[1]);
    END IF;
  END LOOP;
  IF array_length(_all,1) IS NULL THEN
    RETURN jsonb_build_object('deck', '[]'::jsonb, 'discards', _discards);
  END IF;
  _deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_all) c);
  _new_discards := '{}'::jsonb;
  FOR _i IN 1..COALESCE(array_length(_tops,1),0) LOOP
    _new_discards := _new_discards || jsonb_build_object('_reshuffle_'||_i, jsonb_build_array(_tops[_i]));
  END LOOP;
  RETURN jsonb_build_object('deck', to_jsonb(_deck), 'discards', _new_discards);
END $$;

-- ── 2. rami_start : 14 cartes pour le 1er joueur + deck selon joker_mode ──

CREATE OR REPLACE FUNCTION public.rami_start(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  _g public.rami_games; _deck int[]; _i int; _j int; _tmp int;
  _hands jsonb := '{}'::jsonb; _hand int[]; _state jsonb; _key text;
  _first_discard int; _cfg record; _joker_mode text; _random_joker int;
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

  _first_discard := _deck[1];
  _deck := _deck[2:array_length(_deck,1)];

  _discards := jsonb_build_object('_seed', jsonb_build_array(_first_discard));

  _action_log := jsonb_build_array(
    jsonb_build_object('t', 'start', 'ts', extract(epoch from now())::bigint)
  );

  _state := jsonb_build_object(
    'deck', to_jsonb(_deck),
    'discards', _discards,
    'discard', jsonb_build_array(_first_discard),
    'last_discard_by', '_seed',
    'hands', _hands,
    'melds', '[]'::jsonb,
    'action_log', _action_log,
    'refunded', '{}'::jsonb
  );

  UPDATE public.rami_games SET
    status='playing', state=_state, started_at=now(),
    current_turn=0, turn_phase='play',
    random_joker=_random_joker,
    turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval
    WHERE id=_game_id;

  PERFORM public._rami_autoplay_bots(_game_id);
END $function$;

REVOKE ALL ON FUNCTION public.rami_start(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_start(uuid) TO authenticated;

-- ── 3. rami_bot_tick_all : utilise _rami_autoplay_bots ──

CREATE OR REPLACE FUNCTION public.rami_bot_tick_all()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _g_id uuid;
  _is_bot boolean;
  _updated timestamptz;
BEGIN
  FOR _g_id IN
    SELECT r.id FROM public.rami_games r
    WHERE r.status='playing'
  LOOP
    BEGIN
      SELECT p.is_bot, r.updated_at INTO _is_bot, _updated
        FROM public.rami_games r
        JOIN public.rami_participants p ON p.game_id=r.id AND p.slot=r.current_turn
        WHERE r.id=_g_id;

      IF _is_bot AND _updated IS NOT NULL AND now() - _updated >= interval '2 seconds' THEN
        PERFORM public._rami_autoplay_bots(_g_id);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
END $$;

REVOKE ALL ON FUNCTION public.rami_bot_tick_all() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_bot_tick_all() TO authenticated;

-- ── 4. rami_tick : utilise _rami_autoplay_bots pour les bots ──

CREATE OR REPLACE FUNCTION public.rami_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  _g rami_games; _state jsonb; _uid uuid; _is_bot boolean; _slot int;
  _hand int[]; _new_hand int[];
  _deck int[]; _discards jsonb; _pile int[]; _card int; _next int; _cfg record;
  _skips int; _pkey text;
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

  IF _g.turn_phase = 'draw' THEN
    _deck := COALESCE(public._rami_jarr(_state->'deck'), ARRAY[]::int[]);
    IF array_length(_deck,1) IS NULL THEN
      DECLARE _reshuffle jsonb;
      BEGIN
        _reshuffle := public._rami_reshuffle(_state);
        _deck := public._rami_jarr(_reshuffle->'deck');
        _discards := COALESCE(_reshuffle->'discards','{}'::jsonb);
        _state := jsonb_set(_state, '{discards}', _discards, true);
      END;
    END IF;

    IF array_length(_deck,1) IS NULL THEN
      _card := _hand[1 + floor(random()*array_length(_hand,1))::int];
      _new_hand := public._rami_remove_one(_hand, _card);
      _discards := public._rami_discards_map(_state);
      _pile := public._rami_jarr(_discards->_pkey);
      _pile := array_append(_pile, _card);
      _discards := jsonb_set(_discards, ARRAY[_pkey], public._rami_jset(_pile), true);
      _state := jsonb_set(_state, '{discards}', _discards, true);
      _state := jsonb_set(_state, ARRAY['hands',_pkey], to_jsonb(_new_hand));
      _state := _state - 'discard';
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

    _card := _deck[1];
    _deck := _deck[2:array_length(_deck,1)];
    _hand := array_append(_hand, _card);
    _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
    _state := jsonb_set(_state, ARRAY['hands',_pkey], to_jsonb(_hand));
    _state := _state - 'discard';
    UPDATE rami_participants SET hand_count=COALESCE(array_length(_hand,1),0)
      WHERE game_id=_game_id AND user_id=_uid;
    UPDATE rami_games
       SET state = _state, turn_phase = 'play',
           turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
           updated_at = now()
     WHERE id = _game_id;
    RETURN;
  END IF;

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

  _discards := public._rami_discards_map(_state);
  _card := _hand[1 + floor(random()*array_length(_hand,1))::int];
  _new_hand := public._rami_remove_one(_hand, _card);
  _pile := public._rami_jarr(_discards->_pkey);
  _pile := array_append(_pile, _card);
  _discards := jsonb_set(_discards, ARRAY[_pkey], public._rami_jset(_pile), true);
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

  UPDATE rami_games SET state=_state, current_turn=_next, turn_phase='draw',
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
    updated_at=now() WHERE id=_game_id;

  PERFORM public._rami_autoplay_bots(_game_id);
END $function$;

REVOKE ALL ON FUNCTION public.rami_tick(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_tick(uuid) TO authenticated;

-- Re-schedule cron
DO $$
DECLARE j bigint;
BEGIN
  SELECT jobid INTO j FROM cron.job WHERE jobname='rami_bot_tick_all';
  IF j IS NOT NULL THEN PERFORM cron.unschedule(j); END IF;
END $$;
SELECT cron.schedule('rami_bot_tick_all', '5 seconds', $$SELECT public.rami_bot_tick_all();$$);
