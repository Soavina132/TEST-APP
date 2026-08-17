-- ═══ Fix: rami_unmeld doit accepter phase 'draw' OU 'play' ═══
-- Le frontend permet de reprendre une combinaison pendant 'draw' ET 'play'
-- (canBreak = mine && isMyTurn && (phase play OR draw)), mais le backend
-- n'acceptait que 'play' -> le clic échouait silencieusement pendant 'draw'.

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
  IF _slot <> _g.current_turn OR _g.turn_phase NOT IN ('play','draw') THEN
    RAISE EXCEPTION 'pas ton tour de jouer';
  END IF;

  _state := public._rami_normalize_state(_g.state);
  _melds := _state->'melds';
  IF _meld_index < 0 OR _meld_index >= jsonb_array_length(_melds) THEN
    RAISE EXCEPTION 'combinaison introuvable';
  END IF;
  _m := _melds->_meld_index;
  IF _m->>'player' <> _uid::text THEN RAISE EXCEPTION 'ce n''est pas ta combinaison'; END IF;

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
  _state := jsonb_set(_state, ARRAY['hands',_uid::text], to_jsonb(_hand), true);

  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_hand,1),0)
    WHERE game_id=_game_id AND user_id=_uid;
END $function$;
