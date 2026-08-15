-- ============================================================
-- Fix RAMI bugs:
--   10) rami_unmeld: replace non-existent _rami_jarr/_rami_jset with inline code
--   11) rami_forfeit: advance turn when player forfeits during their turn
--   12) rami_start: add discards map + last_discard_by for consistency
-- ============================================================

-- ── Bug 10: Rewrite rami_unmeld without _rami_jarr/_rami_jset ───────────

CREATE OR REPLACE FUNCTION public.rami_unmeld(_game_id uuid, _meld_index integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _melds jsonb; _m jsonb; _cards int[]; _hand int[]; _new_melds jsonb := '[]'::jsonb;
  _i int; _stake numeric; _refunded jsonb; _bal numeric;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour de jouer'; END IF;

  _state := public._rami_normalize_state(_g.state);
  _melds := _state->'melds';
  IF _meld_index < 0 OR _meld_index >= jsonb_array_length(_melds) THEN
    RAISE EXCEPTION 'combinaison introuvable';
  END IF;
  _m := _melds->_meld_index;
  IF _m->>'player' <> _uid::text THEN RAISE EXCEPTION 'ce n''est pas ta combinaison'; END IF;

  -- Inline replacement for _rami_jarr: jsonb array → int[]
  _cards := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_m->'cards'))::int[], ARRAY[]::int[]);
  _hand  := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[], ARRAY[]::int[]) || _cards;

  FOR _i IN 0..jsonb_array_length(_melds)-1 LOOP
    IF _i <> _meld_index THEN _new_melds := _new_melds || jsonb_build_array(_melds->_i); END IF;
  END LOOP;

  -- Annule le remboursement « 7 cartes » si c'était cette combinaison
  IF COALESCE(_m->>'type','') = 'seven' THEN
    _refunded := COALESCE(_state->'refunded','{}'::jsonb);
    IF jsonb_typeof(_refunded) <> 'object' THEN _refunded := '{}'::jsonb; END IF;
    IF _refunded ? _uid::text THEN
      _stake := COALESCE(_g.stake,0);
      IF _stake > 0 THEN
        SELECT balance_ar INTO _bal FROM public.profiles WHERE id=_uid FOR UPDATE;
        IF COALESCE(_bal,0) < _stake THEN
          RAISE EXCEPTION 'solde insuffisant pour annuler le retour de mise';
        END IF;
        UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id=_uid;
        INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
        VALUES (_uid,'rami_refund_cancel',-_stake,_game_id,'Annulation du retour de mise — 7 cartes cassées');
        UPDATE public.rami_games SET pot = pot + _stake WHERE id=_game_id;
      END IF;
      _state := jsonb_set(_state,'{refunded}', _refunded - _uid::text, true);
      _state := _state - 'last_seven';
    END IF;
  END IF;

  _state := jsonb_set(_state, '{melds}', _new_melds, true);
  -- Inline replacement for _rami_jset: int[] → jsonb
  _state := jsonb_set(_state, ARRAY['hands',_uid::text], to_jsonb(_hand), true);

  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_hand,1),0)
    WHERE game_id=_game_id AND user_id=_uid;
END $function$;

-- ── Bug 11: Fix rami_forfeit — advance turn on forfeit ───────────────────

CREATE OR REPLACE FUNCTION public.rami_forfeit(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _uid uuid := auth.uid();
  _g public.rami_games;
  _alive uuid[];
  _winner uuid;
  _payout numeric;
  _comm numeric;
  _parts int[];
  _next int;
  _cfg record;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id = _game_id FOR UPDATE;
  IF _g.status NOT IN ('waiting', 'playing') THEN RETURN; END IF;

  UPDATE public.rami_participants SET forfeited = true WHERE game_id = _game_id AND user_id = _uid;
  SELECT array_agg(user_id) INTO _alive FROM public.rami_participants WHERE game_id = _game_id AND NOT forfeited;

  IF _g.status = 'waiting' THEN
    UPDATE public.rami_games SET status = 'finished', finished_at = now() WHERE id = _game_id;
    IF _g.stake > 0 THEN
      UPDATE public.profiles SET balance_ar = balance_ar + _g.stake WHERE id = _uid;
      INSERT INTO public.transactions (user_id, type, amount, ref_id, note)
      VALUES (_uid, 'rami_refund', _g.stake, _game_id, 'Refund rami');
    END IF;
    RETURN;
  END IF;

  IF COALESCE(array_length(_alive, 1), 0) = 1 THEN
    _winner := _alive[1];
    _comm := round(_g.pot * _g.commission_pct / 100.0, 0);
    _payout := _g.pot - _comm;
    UPDATE public.profiles SET balance_ar = balance_ar + _payout WHERE id = _winner;
    INSERT INTO public.transactions (user_id, type, amount, ref_id, note)
    VALUES (_winner, 'rami_win', _payout, _game_id, 'Win rami by forfeit');
    UPDATE public.rami_games SET status = 'finished', winner_id = _winner, finished_at = now() WHERE id = _game_id;
  ELSE
    -- Advance turn if it was the forfeiting player's turn
    SELECT _g.current_turn INTO _next;
    IF EXISTS (SELECT 1 FROM public.rami_participants WHERE game_id = _game_id AND slot = _next AND user_id = _uid) THEN
      SELECT array_agg(slot ORDER BY slot) INTO _parts
        FROM public.rami_participants WHERE game_id = _game_id AND NOT forfeited;
      LOOP
        _next := (_next + 1) % _g.max_players;
        EXIT WHEN _next = ANY(_parts);
      END LOOP;
      SELECT * INTO _cfg FROM public._game_cfg('rami');
      UPDATE public.rami_games
         SET current_turn = _next,
             turn_phase = 'draw',
             turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
             updated_at = now()
       WHERE id = _game_id;
      -- Trigger bot autoplay if next player is a bot
      PERFORM public._rami_autoplay_bots(_game_id);
    END IF;
  END IF;
END;
$function$;

-- ── Bug 12: Fix rami_start — add discards + last_discard_by ─────────────

CREATE OR REPLACE FUNCTION public.rami_start(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE _g rami_games; _parts uuid[]; _deck int[]; _i int; _j int; _tmp int;
  _hands jsonb := '{}'::jsonb; _p uuid; _hand int[]; _state jsonb;
  _max int; _rj int := NULL; _first int; _top int;
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'waiting' THEN RETURN; END IF;
  SELECT array_agg(user_id ORDER BY slot) INTO _parts FROM rami_participants WHERE game_id=_game_id;
  IF array_length(_parts,1) < 2 THEN RAISE EXCEPTION 'pas assez de joueurs'; END IF;

  -- Deck size by mode
  IF _g.joker_mode IN ('classique','double') THEN _max := 56; -- 0..51 + 4 jokers (52..55)
  ELSE _max := 52; END IF;
  _deck := ARRAY(SELECT generate_series(0,_max-1));

  -- Fisher-Yates
  FOR _i IN REVERSE _max..2 LOOP
    _j := 1 + floor(random()*_i)::int;
    _tmp := _deck[_i]; _deck[_i] := _deck[_j]; _deck[_j] := _tmp;
  END LOOP;

  -- Deal 13 to each
  FOREACH _p IN ARRAY _parts LOOP
    _hand := _deck[1:13];
    _deck := _deck[14:array_length(_deck,1)];
    _hands := _hands || jsonb_build_object(_p::text, to_jsonb(_hand));
    UPDATE rami_participants SET hand_count=13 WHERE game_id=_game_id AND user_id=_p;
  END LOOP;

  -- Random Joker (mode 2 & 4) : pop first non-classical card
  IF _g.joker_mode IN ('aleatoire','double') THEN
    _i := 1;
    WHILE _i <= array_length(_deck,1) AND _deck[_i] >= 52 LOOP _i := _i + 1; END LOOP;
    IF _i <= array_length(_deck,1) THEN
      _rj := _deck[_i];
      _deck := _deck[1:_i-1] || _deck[_i+1:array_length(_deck,1)];
    END IF;
  END IF;

  -- First discard
  _top := _deck[1];
  _deck := _deck[2:array_length(_deck,1)];

  -- Random first player slot
  _first := floor(random() * array_length(_parts,1))::int;

  _state := jsonb_build_object(
    'deck', to_jsonb(_deck),
    'discard', jsonb_build_array(_top),
    'discards', jsonb_build_object('_seed', jsonb_build_array(_top)),
    'last_discard_by', '_seed',
    'hands', _hands,
    'melds', '[]'::jsonb,
    'first_player', _first
  );

  UPDATE rami_games SET status='playing', state=_state, started_at=now(),
    current_turn=_first, turn_phase='draw',
    random_joker=_rj,
    turn_deadline=now() + interval '60 seconds'
  WHERE id=_game_id;
END $function$;
