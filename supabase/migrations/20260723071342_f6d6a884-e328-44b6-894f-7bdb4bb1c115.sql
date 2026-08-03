
-- 1) rami_join: pick first free slot (so bots + humans cohabit)
CREATE OR REPLACE FUNCTION public.rami_join(_game_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  _uid uuid := auth.uid();
  _g public.rami_games;
  _bal numeric;
  _name text;
  _count int;
  _slot int;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id = _game_id FOR UPDATE;
  IF _g.id IS NULL          THEN RAISE EXCEPTION 'partie introuvable'; END IF;
  IF _g.status <> 'waiting' THEN RAISE EXCEPTION 'partie déjà commencée'; END IF;
  IF _g.is_private          THEN RAISE EXCEPTION 'partie privée — utilise le code pour rejoindre'; END IF;

  IF EXISTS (SELECT 1 FROM public.rami_participants WHERE game_id=_g.id AND user_id=_uid) THEN
    RETURN _g.id;
  END IF;

  SELECT count(*) INTO _count FROM public.rami_participants WHERE game_id = _g.id;
  IF _count >= _g.max_players THEN RAISE EXCEPTION 'partie pleine'; END IF;

  SELECT balance_ar, COALESCE(pseudo,'Joueur') INTO _bal, _name
    FROM public.profiles WHERE id = _uid FOR UPDATE;
  IF _bal IS NULL OR _bal < _g.stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  -- first free slot in 0.._max-1
  SELECT s.slot INTO _slot
  FROM generate_series(0, _g.max_players - 1) s(slot)
  WHERE s.slot NOT IN (SELECT slot FROM public.rami_participants WHERE game_id = _g.id)
  ORDER BY s.slot LIMIT 1;
  IF _slot IS NULL THEN RAISE EXCEPTION 'partie pleine'; END IF;

  IF _g.stake > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar - _g.stake WHERE id = _uid;
    UPDATE public.rami_games SET pot = pot + _g.stake WHERE id = _g.id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
    VALUES (_uid, 'rami_stake', -_g.stake, _g.id, 'Join rami');
  END IF;

  INSERT INTO public.rami_participants(game_id, user_id, slot, display_name)
  VALUES (_g.id, _uid, _slot, _name);

  RETURN _g.id;
END $$;

-- 2) rami_add_bot: real implementation
CREATE OR REPLACE FUNCTION public.rami_add_bot(_game_id uuid, _bot_name text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  g public.rami_games;
  v_is_admin boolean;
  v_slot int;
  v_count int;
  v_name text;
  v_bot_names text[] := ARRAY['Bot Rija','Bot Naina','Bot Hery','Bot Voara','Bot Miora','Bot Tahina'];
  v_intel int := 70;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO g FROM public.rami_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'partie introuvable'; END IF;
  IF g.status <> 'waiting' THEN RAISE EXCEPTION 'partie déjà commencée'; END IF;

  v_is_admin := public.has_role(v_uid, 'admin'::app_role);
  IF NOT v_is_admin AND g.created_by <> v_uid THEN
    RAISE EXCEPTION 'seul l''hôte peut ajouter un bot';
  END IF;
  IF NOT v_is_admin AND g.stake > 0 THEN
    RAISE EXCEPTION 'les bots ne sont autorisés qu''en partie gratuite';
  END IF;

  SELECT count(*) INTO v_count FROM public.rami_participants WHERE game_id = _game_id;
  IF v_count >= g.max_players THEN RAISE EXCEPTION 'partie pleine'; END IF;

  -- first free slot
  SELECT s.slot INTO v_slot
  FROM generate_series(0, g.max_players - 1) s(slot)
  WHERE s.slot NOT IN (SELECT slot FROM public.rami_participants WHERE game_id = _game_id)
  ORDER BY s.slot LIMIT 1;

  v_name := COALESCE(NULLIF(_bot_name,''), v_bot_names[1 + (v_slot % array_length(v_bot_names,1))]);

  INSERT INTO public.rami_participants(
    game_id, user_id, slot, display_name, ready, is_bot, bot_name, bot_intelligence, hand_count
  ) VALUES (
    _game_id, NULL, v_slot, v_name, true, true, v_name, v_intel, 0
  );

  -- Auto-start if now full and all humans ready
  IF (SELECT count(*) FROM public.rami_participants WHERE game_id = _game_id) = g.max_players
     AND (SELECT count(*) FROM public.rami_participants WHERE game_id = _game_id AND NOT ready) = 0 THEN
    PERFORM public.rami_start(_game_id);
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.rami_add_bot(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_add_bot(uuid,text) TO authenticated;

-- 3) rami_start: bot key = 'bot:<slot>' (fix hands keying for bots)
CREATE OR REPLACE FUNCTION public.rami_start(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  _g public.rami_games;
  _rows RECORD;
  _deck int[]; _i int; _j int; _tmp int;
  _hands jsonb := '{}'::jsonb; _hand int[]; _state jsonb;
  _max int; _rj int := NULL; _first int; _top int; _key text;
  _n int;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'waiting' THEN RETURN; END IF;

  SELECT count(*) INTO _n FROM public.rami_participants WHERE game_id=_game_id;
  IF _n < 2 THEN RAISE EXCEPTION 'pas assez de joueurs'; END IF;

  IF _g.joker_mode IN ('classique','double') THEN _max := 56; ELSE _max := 52; END IF;
  _deck := ARRAY(SELECT generate_series(0,_max-1));

  FOR _i IN REVERSE _max..2 LOOP
    _j := 1 + floor(random()*_i)::int;
    _tmp := _deck[_i]; _deck[_i] := _deck[_j]; _deck[_j] := _tmp;
  END LOOP;

  FOR _rows IN SELECT slot, user_id, is_bot FROM public.rami_participants
                WHERE game_id=_game_id ORDER BY slot LOOP
    _hand := _deck[1:13];
    _deck := _deck[14:array_length(_deck,1)];
    _key := CASE WHEN COALESCE(_rows.is_bot,false) OR _rows.user_id IS NULL
                 THEN 'bot:' || _rows.slot::text
                 ELSE _rows.user_id::text END;
    _hands := _hands || jsonb_build_object(_key, to_jsonb(_hand));
    UPDATE public.rami_participants SET hand_count=13
      WHERE game_id=_game_id AND slot=_rows.slot;
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
  _first := floor(random() * _n)::int;

  _state := jsonb_build_object(
    'deck', to_jsonb(_deck),
    'discard', jsonb_build_array(_top),
    'hands', _hands,
    'melds', '[]'::jsonb,
    'first_player', _first
  );

  UPDATE public.rami_games
    SET status='playing', state=_state, started_at=now(),
        current_turn=_first, turn_phase='draw',
        random_joker=_rj,
        turn_deadline=now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('rami')),60) || ' seconds')::interval
  WHERE id=_game_id;

  PERFORM public._rami_autoplay_bots(_game_id);
END $$;

-- 4) Trigger bot autoplay after each human action
CREATE OR REPLACE FUNCTION public.rami_draw(_game_id uuid, _from text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _uid uuid := auth.uid(); _g rami_games; _slot int; _state jsonb;
  _deck int[]; _discard int[]; _hand int[]; _card int; _hands jsonb;
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM rami_participants WHERE game_id=_game_id AND user_id=_uid AND is_bot=false;
  IF _slot IS NULL OR _slot <> _g.current_turn THEN RAISE EXCEPTION 'pas ton tour'; END IF;
  IF _g.turn_phase <> 'draw' THEN RAISE EXCEPTION 'déjà pioché'; END IF;
  _state := _g.state;
  _deck := ARRAY(SELECT jsonb_array_elements_text(_state->'deck'))::int[];
  _discard := ARRAY(SELECT jsonb_array_elements_text(_state->'discard'))::int[];
  _hand := ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[];
  IF _from = 'discard' THEN
    IF array_length(_discard,1) IS NULL THEN RAISE EXCEPTION 'défausse vide'; END IF;
    _card := _discard[array_length(_discard,1)];
    _discard := _discard[1:array_length(_discard,1)-1];
  ELSE
    IF array_length(_deck,1) IS NULL THEN
      IF array_length(_discard,1) <= 1 THEN RAISE EXCEPTION 'plus de cartes'; END IF;
      _deck := _discard[1:array_length(_discard,1)-1];
      _discard := ARRAY[_discard[array_length(_discard,1)]];
      _deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_deck) c);
    END IF;
    _card := _deck[1];
    _deck := _deck[2:array_length(_deck,1)];
  END IF;
  _hand := array_append(_hand, _card);
  _hands := jsonb_set(_state->'hands', ARRAY[_uid::text], to_jsonb(_hand));
  _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard));
  _state := jsonb_set(_state, '{hands}', _hands);
  UPDATE rami_games SET state=_state, turn_phase='play', updated_at=now() WHERE id=_game_id;
  UPDATE rami_participants SET hand_count=array_length(_hand,1) WHERE game_id=_game_id AND user_id=_uid;
END $$;

-- Wrap discard/meld/layoff to chain bots via post-hook (re-defining previous bodies + PERFORM autoplay)
CREATE OR REPLACE FUNCTION public.rami_discard(_game_id uuid, _card integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _hand int[]; _new_hand int[]; _discard int[]; _hands jsonb;
  _parts int[]; _next int; _payout numeric; _comm numeric; _won boolean;
  _cfg record;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _state := _g.state;
  _hand := ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[];
  IF NOT (_card = ANY(_hand)) THEN RAISE EXCEPTION 'carte absente'; END IF;
  _new_hand := public._rami_remove_one(_hand,_card);
  _discard := ARRAY(SELECT jsonb_array_elements_text(_state->'discard'))::int[];
  _discard := array_append(_discard,_card);
  _hands := jsonb_set(_state->'hands', ARRAY[_uid::text], to_jsonb(_new_hand));
  _state := jsonb_set(_state,'{hands}',_hands);
  _state := jsonb_set(_state,'{discard}',to_jsonb(_discard));

  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand,1),0)
   WHERE game_id=_game_id AND user_id=_uid;

  IF COALESCE(array_length(_new_hand,1),0) = 0 THEN
    _won := public._rami_check_win(_state, _uid);
    IF _won THEN
      _comm := round(_g.pot * _g.commission_pct / 100.0, 0);
      _payout := _g.pot - _comm;
      UPDATE public.profiles SET balance_ar=balance_ar+_payout WHERE id=_uid;
      INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (_uid,'rami_win',_payout,_game_id,'Win rami');
      UPDATE public.rami_games SET status='finished', winner_id=_uid,
        finished_at=now(), state=_state WHERE id=_game_id;
      RETURN;
    ELSE
      RAISE EXCEPTION 'combinaisons incomplètes: pose toutes tes cartes en combinaisons valides avant de finir';
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
         turn_deadline=now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval,
         updated_at=now()
   WHERE id=_game_id;

  PERFORM public._rami_autoplay_bots(_game_id);
END $$;

CREATE OR REPLACE FUNCTION public.rami_meld(_game_id uuid, _cards integer[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _hand int[]; _c int; _new_hand int[]; _melds jsonb; _type text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour de jouer'; END IF;
  _type := public._rami_meld_type(_cards, _g.joker_mode, _g.random_joker);
  IF _type IS NULL THEN RAISE EXCEPTION 'combinaison invalide'; END IF;

  _state := _g.state;
  _hand := ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[];
  _new_hand := _hand;
  FOREACH _c IN ARRAY _cards LOOP
    IF NOT (_c = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte absente de la main'; END IF;
    _new_hand := public._rami_remove_one(_new_hand,_c);
  END LOOP;
  _melds := COALESCE(_state->'melds','[]'::jsonb) || jsonb_build_array(
    jsonb_build_object('player',_uid::text,'cards',to_jsonb(_cards),'type',_type)
  );
  _state := jsonb_set(_state, ARRAY['hands',_uid::text], to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{melds}', _melds);
  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand,1),0)
    WHERE game_id=_game_id AND user_id=_uid;
END $$;

CREATE OR REPLACE FUNCTION public.rami_layoff(_game_id uuid, _meld_index integer, _cards integer[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _uid uuid := auth.uid(); _g public.rami_games; _slot int; _state jsonb;
  _hand int[]; _c int; _new_hand int[]; _melds jsonb; _meld jsonb;
  _existing int[]; _combined int[]; _type text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  _state := _g.state;
  _melds := COALESCE(_state->'melds','[]'::jsonb);
  _meld  := _melds -> _meld_index;
  IF _meld IS NULL THEN RAISE EXCEPTION 'combinaison introuvable'; END IF;
  _existing := ARRAY(SELECT jsonb_array_elements_text(_meld->'cards'))::int[];
  _combined := _existing || _cards;
  _type := public._rami_meld_type(_combined, _g.joker_mode, _g.random_joker);
  IF _type IS NULL THEN RAISE EXCEPTION 'ajout invalide'; END IF;

  _hand := ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[];
  _new_hand := _hand;
  FOREACH _c IN ARRAY _cards LOOP
    IF NOT (_c = ANY(_new_hand)) THEN RAISE EXCEPTION 'carte absente'; END IF;
    _new_hand := public._rami_remove_one(_new_hand,_c);
  END LOOP;

  _melds := jsonb_set(_melds, ARRAY[_meld_index::text],
    jsonb_set(_meld, '{cards}', to_jsonb(_combined))
      || jsonb_build_object('type', _type));
  _state := jsonb_set(_state, ARRAY['hands',_uid::text], to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{melds}', _melds);
  UPDATE public.rami_games SET state=_state, updated_at=now() WHERE id=_game_id;
  UPDATE public.rami_participants SET hand_count=COALESCE(array_length(_new_hand,1),0)
    WHERE game_id=_game_id AND user_id=_uid;
END $$;

-- 5) rami_tick: if current player is a bot, autoplay instead of ticking
CREATE OR REPLACE FUNCTION public.rami_tick(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  _g public.rami_games; _state jsonb; _uid uuid; _hand int[]; _new_hand int[];
  _deck int[]; _discard int[]; _card int; _next int; _cfg record; _skips int;
  _best_card int; _best_pts int := -1; _pts int; _rank int; _c int;
  _is_bot boolean;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RETURN; END IF;

  SELECT COALESCE(is_bot,false), user_id INTO _is_bot, _uid
    FROM public.rami_participants WHERE game_id=_game_id AND slot=_g.current_turn;

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
      DECLARE _win uuid;
      BEGIN
        SELECT user_id INTO _win FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited LIMIT 1;
        UPDATE public.rami_games SET status='finished', winner_id=_win, finished_at=now() WHERE id=_game_id;
        IF _win IS NOT NULL THEN
          UPDATE public.profiles SET balance_ar = balance_ar + (_g.pot * (100 - _g.commission_pct) / 100) WHERE id=_win;
          INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
            VALUES (_win,'rami_win', _g.pot * (100 - _g.commission_pct) / 100, _game_id, 'Rami win (forfait)');
        END IF;
        RETURN;
      END;
    END IF;
  END IF;

  _state := _g.state;
  _deck := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'deck'))::int[], ARRAY[]::int[]);
  _discard := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'discard'))::int[], ARRAY[]::int[]);
  _hand := COALESCE(ARRAY(SELECT jsonb_array_elements_text(_state->'hands'->_uid::text))::int[], ARRAY[]::int[]);

  IF _g.turn_phase = 'draw' THEN
    IF COALESCE(array_length(_deck,1),0) = 0 THEN
      IF COALESCE(array_length(_discard,1),0) <= 1 THEN
        UPDATE public.rami_games SET status='finished', finished_at=now(),
          state = jsonb_set(_state,'{end_reason}', to_jsonb('deck exhausted'::text))
          WHERE id=_game_id;
        RETURN;
      END IF;
      _deck := _discard[1:array_length(_discard,1)-1];
      _discard := ARRAY[_discard[array_length(_discard,1)]];
      _deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_deck) c);
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
  _discard := array_append(_discard, _card);
  _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard));
  _state := jsonb_set(_state, ARRAY['hands',_uid::text], to_jsonb(_new_hand));
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
END $$;

-- 6) rami_set_ready: also allow start when all humans ready and only bots remain
CREATE OR REPLACE FUNCTION public.rami_set_ready(_game_id uuid, _ready boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_g public.rami_games;
  v_total int;
  v_ready int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM public.rami_games WHERE id = _game_id FOR UPDATE;
  IF v_g.id IS NULL THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status <> 'waiting' THEN RETURN; END IF;

  UPDATE public.rami_participants
     SET ready = COALESCE(_ready, false)
   WHERE game_id = _game_id AND user_id = v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'not a participant'; END IF;

  SELECT count(*), count(*) FILTER (WHERE ready)
    INTO v_total, v_ready
    FROM public.rami_participants WHERE game_id = _game_id;

  IF v_total = v_g.max_players AND v_ready = v_total THEN
    PERFORM public.rami_start(_game_id);
  END IF;
END $$;
