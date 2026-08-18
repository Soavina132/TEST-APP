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
  _refund numeric; _comm_half numeric;
  _meld_idx int; _mark_idx text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;

  _state := _g.state;
  _refunded := COALESCE(_state->'refunded','{}'::jsonb);
  IF _refunded ? _uid::text THEN RAISE EXCEPTION 'deja rembourse'; END IF;

  -- Check player's melds: must have at least 7 pure cards in valid combo
  _melds := COALESCE(_state->'melds','[]'::jsonb);
  _meld_idx := 0;
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
        -- Handle 'seven' type: 7 cards played as a single meld
        IF _t = 'seven' AND _n = 7 THEN
          _found := true;
          -- Mark this meld as seven-claimed
          _melds := jsonb_set(_melds, ARRAY[_meld_idx::text, 'seven'], 'true'::jsonb, true);
        ELSIF _t = 'seven' THEN
          CONTINUE;
        END IF;

        _total_pure := _total_pure + _n;
        IF _t = 'run' AND _n >= 4 THEN _run4 := _run4 + 1;
        ELSIF _t = 'run' AND _n = 3 THEN _run3 := _run3 + 1;
        ELSIF _t = 'carre' AND _n = 4 THEN _set4 := _set4 + 1;
        ELSIF _t = 'trio' AND _n = 3 THEN _set3 := _set3 + 1;
        END IF;
      END IF;
    END IF;
    _meld_idx := _meld_idx + 1;
  END LOOP;

  -- 7 pure cards: Option 1 (run4+set3) or Option 2 (run3+set4) or single 'seven' meld
  IF NOT _found THEN
    IF _total_pure >= 7 AND ((_run4 >= 1 AND _set3 >= 1) OR (_run3 >= 1 AND _set4 >= 1)) THEN
      _found := true;
      -- Mark all pure melds from this player as seven-claimed
      _meld_idx := 0;
      FOR _m IN SELECT * FROM jsonb_array_elements(_melds) LOOP
        IF _m->>'player' = _uid::text THEN
          _cards := ARRAY(SELECT jsonb_array_elements_text(_m->'cards'))::int[];
          _is_pure := true;
          FOREACH _c IN ARRAY _cards LOOP
            IF public._rami_is_joker(_c, _g.joker_mode, _g.random_joker) THEN
              _is_pure := false;
            END IF;
          END LOOP;
          IF _is_pure THEN
            _melds := jsonb_set(_melds, ARRAY[_meld_idx::text, 'seven'], 'true'::jsonb, true);
          END IF;
        END IF;
        _meld_idx := _meld_idx + 1;
      END LOOP;
    END IF;
  END IF;

  IF NOT _found THEN
    RAISE EXCEPTION 'tu dois poser 7 cartes pures: 4-suite + 3-brelan OU 3-suite + 4-carre';
  END IF;

  -- Save melds with seven markers
  _state := jsonb_set(_state, '{melds}', _melds);

  -- Refund stake minus half commission
  IF _g.stake > 0 THEN
    _comm_half := round(_g.stake * (_g.commission_pct / 2.0) / 100.0, 0);
    _refund := _g.stake - _comm_half;
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, 0) + _refund WHERE id=_uid;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (_uid,'rami_seven_refund',_refund,_game_id,'7 Cartes pures refund');
    -- Reduce pot by full stake
    UPDATE public.rami_games SET pot = GREATEST(pot - _g.stake, 0) WHERE id=_game_id;
  END IF;

  _refunded := _refunded || jsonb_build_object(_uid::text, true);
  _state := jsonb_set(_state, '{refunded}', _refunded);
  _action_log := COALESCE(_state->'action_log','[]'::jsonb) ||
    jsonb_build_object('t','seven','p',_uid::text,'ts',extract(epoch from now())::bigint,'refund',_refund);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rami_claim_seven(uuid) TO authenticated;
