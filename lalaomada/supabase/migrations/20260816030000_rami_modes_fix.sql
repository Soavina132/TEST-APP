-- ============================================================
-- Rami: implement 7-card pure mode + 13-card alternative structure
--
-- Changes:
-- 1. _rami_check_win: rewritten to support both modes
--    - Mode A (seven_cards=true): 7 PURE cards, combos = 4-run+3-set or 3-run+4-set
--    - Mode B (seven_cards=false): 13 cards, standard (2trio+1run+1carre) OR alternative (no carre, run of 4+)
-- 2. rami_start: deal 7 cards if seven_cards=true, 13 if false
-- 3. rami_claim_seven: properly validate 7 pure cards in correct combo
-- 4. _rami_autoplay_bots: handle 7-card mode
-- 5. Fix rami_discard and rami_validate_hand to pass seven_cards to _rami_check_win
-- ============================================================

-- ═══ 1. _rami_check_win: support both 7-card and 13-card modes ═══
CREATE OR REPLACE FUNCTION public._rami_check_win(_state jsonb, _key text, _seven_cards boolean DEFAULT false)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public'
AS $function$
DECLARE
  _carre int := 0; _trio int := 0; _run int := 0; _total int := 0;
  _m jsonb; _t text; _cards int[]; _n int; _has_long_run boolean := false;
  _joker_mode text; _rj int; _all_pure boolean := true; _c int;
BEGIN
  _joker_mode := COALESCE(_state->>'joker_mode', 'classique');
  _rj := COALESCE((_state->'random_joker')::int, -1);

  FOR _m IN SELECT * FROM jsonb_array_elements(COALESCE(_state->'melds','[]'::jsonb)) LOOP
    IF _m->>'player' = _key THEN
      _t := _m->>'type';
      _cards := ARRAY(SELECT jsonb_array_elements_text(_m->'cards'))::int[];
      _n := COALESCE(array_length(_cards,1),0);
      _total := _total + _n;
      IF _t = 'carre' THEN _carre := _carre + 1;
      ELSIF _t = 'trio' THEN _trio := _trio + 1;
      ELSIF _t = 'run'  THEN
        _run  := _run  + 1;
        IF _n >= 4 THEN _has_long_run := true; END IF;
      END IF;
      IF _seven_cards THEN
        FOREACH _c IN ARRAY _cards LOOP
          IF public._rami_is_joker(_c, _joker_mode, _rj) THEN
            _all_pure := false;
          END IF;
        END LOOP;
      END IF;
    END IF;
  END LOOP;

  IF _seven_cards THEN
    -- Mode A: 7 pure cards, combos = 4-run+3-set or 3-run+4-set
    RETURN _all_pure AND _total = 7 AND _run >= 1
      AND ((_carre >= 1 AND _trio >= 0) OR (_trio >= 1 AND _carre >= 0));
  ELSE
    -- Mode B: 13 cards
    -- Standard: 2 trios + 1 run + 1 carre = 13
    IF _carre >= 1 AND _trio >= 2 AND _run >= 1 AND _total >= 13 THEN
      RETURN true;
    END IF;
    -- Alternative: no carre, at least one 4+ run, enough trios+runs to reach 13
    IF _carre = 0 AND _has_long_run AND _total >= 13 AND (_trio + _run) >= 2 THEN
      RETURN true;
    END IF;
    RETURN false;
  END IF;
END;
$function$;

-- ═══ 2. rami_start: deal 7 or 13 cards based on seven_cards flag ═══
CREATE OR REPLACE FUNCTION public.rami_start(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE _g rami_games; _parts uuid[]; _deck int[]; _i int; _j int; _tmp int;
  _hands jsonb := '{}'::jsonb; _p uuid; _hand int[]; _state jsonb;
  _max int; _rj int := NULL; _first int; _top int;
  _deal_count int; _seven boolean;
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'waiting' THEN RETURN; END IF;
  SELECT array_agg(user_id ORDER BY slot) INTO _parts FROM rami_participants WHERE game_id=_game_id;
  IF array_length(_parts,1) < 2 THEN RAISE EXCEPTION 'pas assez de joueurs'; END IF;

  _seven := COALESCE(_g.seven_cards, true);
  _deal_count := CASE WHEN _seven THEN 7 ELSE 13 END;

  IF _g.joker_mode IN ('classique','double') THEN _max := 56;
  ELSE _max := 52; END IF;
  _deck := ARRAY(SELECT generate_series(0,_max-1));

  FOR _i IN REVERSE _max..2 LOOP
    _j := 1 + floor(random()*_i)::int;
    _tmp := _deck[_i]; _deck[_i] := _deck[_j]; _deck[_j] := _tmp;
  END LOOP;

  FOREACH _p IN ARRAY _parts LOOP
    _hand := _deck[1:_deal_count];
    _deck := _deck[_deal_count+1:array_length(_deck,1)];
    _hands := _hands || jsonb_build_object(_p::text, to_jsonb(_hand));
    UPDATE rami_participants SET hand_count=_deal_count WHERE game_id=_game_id AND user_id=_p;
  END LOOP;

  IF _g.joker_mode IN ('aleatoire','double') THEN
    _i := 1;
    WHILE _i <= array_length(_deck,1) AND _deck[_i] >= 52 LOOP _i := _i + 1; END LOOP;
    IF _i <= array_length(_deck,1) THEN
      _rj := _deck[_i];
      _deck := _deck[1:_i-1] || _deck[_i+1:array_length(_deck,1)];
    END IF;
  END IF;

  _top := _deck[1];
  _deck := _deck[2:array_length(_deck,1)];

  _first := floor(random() * array_length(_parts,1))::int;

  _state := jsonb_build_object(
    'deck', to_jsonb(_deck),
    'discard', jsonb_build_array(_top),
    'discards', jsonb_build_object('_seed', jsonb_build_array(_top)),
    'last_discard_by', '_seed',
    'hands', _hands,
    'melds', '[]'::jsonb,
    'first_player', _first,
    'joker_mode', _g.joker_mode,
    'random_joker', COALESCE(_rj, -1),
    'seven_cards', _seven
  );

  UPDATE public.rami_games SET status='playing', state=_state, started_at=now(),
    current_turn=_first, turn_phase='draw',
    random_joker=_rj,
    turn_deadline=now() + interval '60 seconds'
  WHERE id=_game_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.rami_start(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_start(uuid) TO authenticated;

-- ═══ 3. rami_discard: pass seven_cards to _rami_check_win ═══
CREATE OR REPLACE FUNCTION public.rami_discard(_game_id uuid, _card integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $function$
DECLARE
  _uid uuid := auth.uid();
  _g rami_games;
  _slot int;
  _state jsonb;
  _hand int[];
  _new_hand int[];
  _discard int[];
  _hands jsonb;
  _parts int[];
  _next int;
  _payout numeric;
  _comm numeric;
  _won boolean;
  _cfg record;
  _discards jsonb;
  _pile int[];
  _key text;
  _winner_name text;
  _seven boolean;
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _key := _uid::text;
  _seven := COALESCE(_g.seven_cards, false);
  _state := _g.state;
  _hand := ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_key))::int[];
  IF NOT (_card = ANY(_hand)) THEN RAISE EXCEPTION 'carte absente'; END IF;
  _new_hand := public._rami_remove_one(_hand, _card);

  _discard := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'discard'))::int[], ARRAY[]::int[]);
  _discard := array_append(_discard, _card);

  _discards := public._rami_discards_map(_state);
  _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_key))::int[], ARRAY[]::int[]);
  _pile := array_append(_pile, _card);
  _discards := jsonb_set(_discards, ARRAY[_key], to_jsonb(_pile), true);

  _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{hands}', _hands);
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard));
  _state := jsonb_set(_state, '{discards}', _discards);
  _state := jsonb_set(_state, '{last_discard_by}', to_jsonb(_key));

  UPDATE public.rami_participants
     SET hand_count=COALESCE(array_length(_new_hand, 1), 0)
   WHERE game_id=_game_id AND user_id=_uid;

  IF COALESCE(array_length(_new_hand, 1), 0) = 0 THEN
    _won := public._rami_check_win(_state, _uid, _seven);
    IF _won THEN
      SELECT COALESCE(pseudo, 'Joueur') INTO _winner_name FROM public.profiles WHERE id=_uid;
      _comm := round(_g.pot * _g.commission_pct / 100.0, 0);
      _payout := _g.pot - _comm;
      UPDATE public.profiles SET balance_ar=balance_ar+_payout WHERE id=_uid;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (_uid, 'rami_win', _payout, _game_id, 'Win rami');
      UPDATE public.rami_games
        SET status='finished', winner_id=_uid, winner_name=_winner_name, finished_at=now(), state=_state
        WHERE id=_game_id;
      RETURN;
    ELSE
      RAISE EXCEPTION 'combinaisons incomplètes';
    END IF;
  END IF;

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
END;
$function$;
REVOKE ALL ON FUNCTION public.rami_discard(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_discard(uuid, integer) TO authenticated;

-- ═══ 4. rami_validate_hand: pass seven_cards to _rami_check_win ═══
CREATE OR REPLACE FUNCTION public.rami_validate_hand(_game_id uuid, _layout jsonb, _discard_card integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
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
  _group jsonb;
  _cards int[];
  _type text;
  _is_pure boolean;
  _action_log jsonb;
  _won boolean;
  _payout numeric;
  _comm numeric;
  _first_melds jsonb;
  _winner_name text;
  _seven boolean;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  _seven := COALESCE(_g.seven_cards, false);
  _state := _g.state;
  _hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[], ARRAY[]::int[]);
  _new_hand := _hand;

  _first_melds := COALESCE(_state->'first_melds', '{}'::jsonb);
  _melds := COALESCE(_state->'melds', '[]'::jsonb);

  FOR _group IN SELECT * FROM jsonb_array_elements(_layout) LOOP
    _cards := ARRAY(SELECT jsonb_array_elements_text(_group))::int[];
    FOREACH _c IN ARRAY _cards LOOP
      IF NOT (_c = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte absente de la main'; END IF;
      _new_hand := public._rami_remove_one(_new_hand, _c);
    END LOOP;

    _type := public._rami_meld_type(_cards, _g.joker_mode, _g.random_joker);
    IF _type IS NULL THEN RAISE EXCEPTION 'combinaison invalide dans le layout'; END IF;

    _is_pure := true;
    FOREACH _c IN ARRAY _cards LOOP
      IF public._rami_is_joker(_c, _g.joker_mode, _g.random_joker) THEN
        _is_pure := false;
      END IF;
    END LOOP;

    _melds := _melds || jsonb_build_array(
      jsonb_build_object(
        'player', _uid::text,
        'cards', to_jsonb(_cards),
        'type', _type,
        'pure', _is_pure
      )
    );

    IF _first_melds ? _uid::text = false OR _first_melds->_uid::text IS NULL THEN
      _first_melds := jsonb_set(_first_melds, ARRAY[_uid::text], to_jsonb(extract(epoch from now())::bigint), true);
    END IF;
  END LOOP;

  IF NOT (_discard_card = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte de défausse absente'; END IF;
  _new_hand := public._rami_remove_one(_new_hand, _discard_card);

  _state := jsonb_set(_state, '{melds}', _melds);
  _state := jsonb_set(_state, '{first_melds}', _first_melds, true);

  _action_log := COALESCE(_state->'action_log', '[]'::jsonb) ||
    jsonb_build_object('t', 'validate_hand', 'p', _uid::text, 'ts', extract(epoch from now())::bigint);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  IF COALESCE(array_length(_new_hand, 1), 0) = 0 THEN
    _won := public._rami_check_win(_state, _uid, _seven);
    IF _won THEN
      SELECT COALESCE(pseudo, 'Joueur') INTO _winner_name FROM public.profiles WHERE id=_uid;
      _comm := round(_g.pot * _g.commission_pct / 100.0, 0);
      _payout := _g.pot - _comm;
      UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) + _payout WHERE id = _uid;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (_uid, 'rami_win', _payout, _game_id, 'Win rami');
      UPDATE public.rami_games SET status='finished', winner_id=_uid, winner_name=_winner_name, finished_at=now(), state=_state WHERE id=_game_id;
      UPDATE public.rami_participants SET hand_count=0 WHERE game_id=_game_id AND user_id=_uid;
      RETURN jsonb_build_object('won', true, 'winner_name', _winner_name);
    ELSE
      _state := jsonb_set(_state, ARRAY['hands', _uid::text], to_jsonb(_new_hand));
      UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
      UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand, 1), 0)
        WHERE game_id=_game_id AND user_id=_uid;
      RETURN jsonb_build_object('won', false);
    END IF;
  ELSE
    _state := jsonb_set(_state, ARRAY['hands', _uid::text], to_jsonb(_new_hand));
    UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
    UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand, 1), 0)
      WHERE game_id=_game_id AND user_id=_uid;
    RETURN jsonb_build_object('won', false);
  END IF;
END;
$function$;
REVOKE ALL ON FUNCTION public.rami_validate_hand(uuid, jsonb, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_validate_hand(uuid, jsonb, integer) TO authenticated;

-- ═══ 5. rami_claim_seven: properly validate 7 pure cards ═══
CREATE OR REPLACE FUNCTION public.rami_claim_seven(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _melds jsonb; _m jsonb; _total_pure int := 0; _found boolean := false;
  _refunded jsonb; _action_log jsonb;
  _cards int[]; _c int; _is_pure boolean; _n int; _run4 int := 0; _run3 int := 0;
  _set3 int := 0; _set4 int := 0; _t text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;

  _state := _g.state;
  _refunded := COALESCE(_state->'refunded','{}'::jsonb);
  IF _refunded ? _uid::text THEN RAISE EXCEPTION 'deja rembourse'; END IF;

  _melds := COALESCE(_state->'melds','[]'::jsonb);
  FOR _m IN SELECT * FROM jsonb_array_elements(_melds) LOOP
    IF _m->>'player' = _uid::text THEN
      _t := _m->>'type';
      _cards := ARRAY(SELECT jsonb_array_elements_text(_m->'cards'))::int[];
      _n := COALESCE(array_length(_cards,1),0);
      _is_pure := true;
      FOREACH _c IN ARRAY _cards LOOP
        IF public._rami_is_joker(_c, _g.joker_mode, _g.random_joker) THEN
          _is_pure := false;
        END IF;
      END LOOP;
      IF _is_pure THEN
        _total_pure := _total_pure + _n;
        IF _t = 'run' AND _n >= 4 THEN _run4 := _run4 + 1;
        ELSIF _t = 'run' AND _n = 3 THEN _run3 := _run3 + 1;
        ELSIF _t = 'carre' AND _n = 4 THEN _set4 := _set4 + 1;
        ELSIF _t = 'trio' AND _n = 3 THEN _set3 := _set3 + 1;
        END IF;
      END IF;
    END IF;
  END LOOP;

  -- 7 pure cards: Option 1 (run4+set3) or Option 2 (run3+set4)
  IF _total_pure = 7 AND ((_run4 >= 1 AND _set3 >= 1) OR (_run3 >= 1 AND _set4 >= 1)) THEN
    _found := true;
  END IF;

  IF NOT _found THEN
    RAISE EXCEPTION 'tu dois poser 7 cartes pures: 4-suite + 3-brelan OU 3-suite + 4-carre';
  END IF;

  IF _g.stake > 0 THEN
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, 0) + _g.stake WHERE id=_uid;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (_uid,'rami_seven_refund',_g.stake,_game_id,'7 Cartes pures refund');
    UPDATE public.rami_games SET pot = GREATEST(pot - _g.stake, 0) WHERE id=_game_id;
  END IF;

  _refunded := _refunded || jsonb_build_object(_uid::text, true);
  _state := jsonb_set(_state, '{refunded}', _refunded);
  _action_log := COALESCE(_state->'action_log','[]'::jsonb) ||
    jsonb_build_object('t','seven','p',_uid::text,'ts',extract(epoch from now())::bigint);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.rami_claim_seven(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_claim_seven(uuid) TO authenticated;

-- ═══ 6. _rami_autoplay_bots: pass seven_cards to _rami_check_win + winner_name ═══
CREATE OR REPLACE FUNCTION public._rami_autoplay_bots(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  g public.rami_games; part public.rami_participants; guard int := 0;
  _key text; _hand int[]; _card int; _deck int[]; _new_hand int[]; _hands jsonb;
  _melds jsonb; _melded int[]; _type text; _intel int; _parts int[]; _next int;
  _top int; _matched boolean;
  _cfg record;
  _state jsonb; _discards jsonb; _pile int[]; _last text; _reshuffle jsonb;
  _all_discard int[]; _k text; _v jsonb;
  _winner_name text; _payout numeric; _comm numeric;
  _seven boolean;
BEGIN
  LOOP
    guard := guard + 1;
    IF guard > 100 THEN EXIT; END IF;

    SELECT * INTO g FROM public.rami_games WHERE id = _game_id FOR UPDATE;
    IF NOT FOUND OR g.status <> 'playing' THEN EXIT; END IF;
    IF COALESCE(g.paused, false) THEN EXIT; END IF;

    SELECT * INTO part FROM public.rami_participants
     WHERE game_id = _game_id AND slot = g.current_turn AND forfeited = false;
    IF NOT FOUND OR NOT COALESCE(part.is_bot,false) THEN EXIT; END IF;

    _key   := COALESCE(part.user_id::text, 'bot:' || part.slot::text);
    _intel := COALESCE(part.bot_intelligence, 70);
    _seven := COALESCE(g.seven_cards, false);
    SELECT * INTO _cfg FROM public._game_cfg('rami');
    _state := public._rami_normalize_state(g.state);
    _discards := public._rami_discards_map(_state);
    _last := public._rami_last_discarder(_state);

    IF g.turn_phase = 'draw' THEN
      _deck    := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'deck'))::int[], ARRAY[]::int[]);
      _hand    := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_key))::int[], ARRAY[]::int[]);
      _pile    := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_last))::int[], ARRAY[]::int[]);
      _card    := NULL;
      _matched := false;

      IF _intel >= 70 AND array_length(_pile,1) IS NOT NULL AND array_length(_pile,1) > 0 THEN
        _top := _pile[array_length(_pile,1)];
        IF _top < 52 AND EXISTS (SELECT 1 FROM unnest(_hand) c WHERE c < 52 AND c%13 = _top%13) THEN
          _matched := true;
          _card := _top;
          _pile := _pile[1:array_length(_pile,1)-1];
          IF array_length(_pile,1) IS NULL THEN
            _discards := _discards - _last;
          ELSE
            _discards := jsonb_set(_discards, ARRAY[_last], to_jsonb(_pile));
          END IF;
        END IF;
      END IF;

      IF NOT _matched THEN
        IF COALESCE(array_length(_deck,1),0) = 0 THEN
          _reshuffle := public._rami_reshuffle(_state);
          _deck := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_reshuffle->'deck'))::int[], ARRAY[]::int[]);
          _discards := _reshuffle->'discards';
        END IF;
        IF COALESCE(array_length(_deck,1),0) = 0 THEN EXIT; END IF;
        _card := _deck[1];
        _deck := _deck[2:array_length(_deck,1)];
      END IF;

      _hand := array_append(_hand, _card);
      _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_hand));
      _state := jsonb_set(_state,'{deck}',to_jsonb(_deck));
      _state := jsonb_set(_state,'{discards}',_discards);
      _state := jsonb_set(_state,'{hands}',_hands);
      _all_discard := ARRAY[]::int[];
      FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
        _all_discard := _all_discard || ARRAY(SELECT jsonb_array_elements_text(_v))::int[];
      END LOOP;
      _state := jsonb_set(_state, '{discard}', to_jsonb(_all_discard), true);

      UPDATE public.rami_games
         SET state = _state, turn_phase = 'play', updated_at = now()
       WHERE id = _game_id;
      UPDATE public.rami_participants
         SET hand_count = COALESCE(array_length(_hand,1),0)
       WHERE game_id = _game_id AND slot = part.slot;
      CONTINUE;
    END IF;

    _hand  := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_key))::int[], ARRAY[]::int[]);
    _melds := COALESCE(_state->'melds','[]'::jsonb);

    IF _intel >= 50 AND COALESCE(array_length(_hand,1),0) >= 4 THEN
      SELECT ARRAY[_hand[i], _hand[j], _hand[k]] INTO _melded
        FROM generate_subscripts(_hand,1) i, generate_subscripts(_hand,1) j, generate_subscripts(_hand,1) k
       WHERE i < j AND j < k
         AND public._rami_meld_type(ARRAY[_hand[i],_hand[j],_hand[k]], g.joker_mode, g.random_joker) IS NOT NULL
       LIMIT 1;

      IF _melded IS NOT NULL THEN
        _type := public._rami_meld_type(_melded, g.joker_mode, g.random_joker);
        _new_hand := _hand;
        FOREACH _card IN ARRAY _melded LOOP
          _new_hand := public._rami_remove_one(_new_hand, _card);
        END LOOP;
        _melds := _melds || jsonb_build_array(jsonb_build_object(
          'player', _key, 'cards', to_jsonb(_melded), 'type', _type
        ));
        _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_new_hand));
        _state := jsonb_set(_state,'{hands}',_hands);
        _state := jsonb_set(_state,'{melds}',_melds);
        UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
        UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand,1),0)
          WHERE game_id=_game_id AND slot=part.slot;
        _melded := NULL;
        CONTINUE;
      END IF;
    END IF;

    IF COALESCE(array_length(_hand,1),0) = 0 THEN EXIT; END IF;

    IF _intel < 50 THEN
      _card := _hand[1 + floor(random() * array_length(_hand,1))::int];
    ELSE
      SELECT c INTO _card FROM unnest(_hand) c
        ORDER BY (CASE WHEN c < 52 THEN c%13 ELSE -1 END) DESC, random()
        LIMIT 1;
    END IF;

    _new_hand := public._rami_remove_one(_hand, _card);
    _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_discards->_key))::int[], ARRAY[]::int[]);
    _pile := array_append(_pile, _card);
    _discards := jsonb_set(_discards, ARRAY[_key], to_jsonb(_pile), true);
    _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_new_hand));

    IF COALESCE(array_length(_new_hand,1),0) = 0 THEN
      _state := jsonb_set(_state,'{hands}',_hands);
      _state := jsonb_set(_state,'{discards}',_discards);
      _state := jsonb_set(_state,'{last_discard_by}',to_jsonb(_key));
      _all_discard := ARRAY[]::int[];
      FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
        _all_discard := _all_discard || ARRAY(SELECT jsonb_array_elements_text(_v))::int[];
      END LOOP;
      _state := jsonb_set(_state, '{discard}', to_jsonb(_all_discard), true);
      IF public._rami_check_win(_state, _key, _seven) THEN
        SELECT COALESCE(pseudo, 'Bot') INTO _winner_name FROM public.profiles WHERE id = part.user_id;
        IF part.user_id IS NOT NULL THEN
          _comm := round(g.pot * g.commission_pct / 100.0, 0);
          _payout := g.pot - _comm;
          UPDATE public.profiles SET balance_ar = balance_ar + _payout WHERE id = part.user_id;
          INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
            VALUES (part.user_id, 'rami_win', _payout, _game_id, 'Win rami (bot)');
        END IF;
        UPDATE public.rami_games
           SET status='finished', winner_id=part.user_id, winner_name=COALESCE(_winner_name, part.display_name), finished_at=now(), state=_state
         WHERE id=_game_id;
        UPDATE public.rami_participants SET hand_count=0
         WHERE game_id=_game_id AND slot=part.slot;
        EXIT;
      ELSE
        _card := _hand[1 + floor(random() * array_length(_hand,1))::int];
        _new_hand := public._rami_remove_one(_hand, _card);
        _pile := COALESCE(ARRAY(SELECT jsonb_array_elements_text(g.state->'discards'->_key))::int[], ARRAY[]::int[]);
        _pile := array_append(_pile, _card);
        _discards := public._rami_discards_map(g.state);
        _discards := jsonb_set(_discards, ARRAY[_key], to_jsonb(_pile), true);
        _hands := jsonb_set(g.state->'hands', ARRAY[_key], to_jsonb(_new_hand));
      END IF;
    END IF;

    SELECT array_agg(slot ORDER BY slot) INTO _parts
      FROM public.rami_participants WHERE game_id = _game_id AND NOT forfeited;
    _next := g.current_turn;
    LOOP
      _next := (_next + 1) % g.max_players;
      EXIT WHEN _next = ANY(_parts);
    END LOOP;

    _state := jsonb_set(_state,'{hands}',_hands);
    _state := jsonb_set(_state,'{discards}',_discards);
    _state := jsonb_set(_state,'{last_discard_by}',to_jsonb(_key));
    _all_discard := ARRAY[]::int[];
    FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
      _all_discard := _all_discard || ARRAY(SELECT jsonb_array_elements_text(_v))::int[];
    END LOOP;
    _state := jsonb_set(_state, '{discard}', to_jsonb(_all_discard), true);

    UPDATE public.rami_games
       SET state = _state, current_turn = _next, turn_phase = 'draw',
           turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval,
           updated_at = now()
     WHERE id = _game_id;
    UPDATE public.rami_participants
       SET hand_count = COALESCE(array_length(_new_hand,1),0)
     WHERE game_id = _game_id AND slot = part.slot;
  END LOOP;
END;
$function$;
REVOKE ALL ON FUNCTION public._rami_autoplay_bots(uuid) FROM anon, authenticated;
