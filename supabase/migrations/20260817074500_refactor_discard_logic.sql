-- ═══════════════════════════════════════════════════════════════════
-- REFACTOR COMPLET: Logique de défausse RAMI
-- 
-- Problème: la pioche sur défausse ne marche pas à cause du système
-- multi-piles (discards object) qui perdait les clés / vidait les piles.
--
-- Solution: le tableau plat `discard` devient la source de vérité unique
-- pour la pioche sur défausse. L'objet `discards` (multi-pile) est gardé
-- pour l'affichage mais n'est plus utilisé pour la logique de pioche.
-- ═══════════════════════════════════════════════════════════════════

-- ═══ 1. rami_draw: pioche simplifiée ═══
CREATE OR REPLACE FUNCTION public.rami_draw(_game_id uuid, _from text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  _uid uuid := auth.uid();
  _g public.rami_games;
  _slot int;
  _state jsonb;
  _deck int[];
  _discard_arr int[];   -- tableau plat = source de vérité
  _discards jsonb;      -- multi-pile pour affichage
  _hand int[];
  _card int;
  _hands jsonb;
  _pile int[];
  _cfg record;
  _action_log jsonb;
  _last_by text;
  _k text;
  _v jsonb;
  _all int[];
  _new_discards jsonb;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn THEN RAISE EXCEPTION 'pas ton tour'; END IF;
  IF _g.turn_phase <> 'draw' THEN RAISE EXCEPTION 'deja pioché ou phase de jeu'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _state := public._rami_normalize_state(_g.state);
  _deck := COALESCE(public._rami_jarr(_state->'deck'), ARRAY[]::int[]);
  _discards := public._rami_discards_map(_state);
  _hand := COALESCE(public._rami_jarr(_state->'hands'->_uid::text), ARRAY[]::int[]);
  _discard_arr := COALESCE(public._rami_jarr(_state->'discard'), ARRAY[]::int[]);

  IF _from = 'discard' THEN
    -- ═══ SOURCE DE VÉRITÉ: le tableau plat discard ═══
    -- Filtrer les NULL au cas où
    _discard_arr := ARRAY(SELECT x FROM unnest(_discard_arr) x WHERE x IS NOT NULL);
    
    IF array_length(_discard_arr, 1) IS NULL THEN RAISE EXCEPTION 'défausse vide'; END IF;
    
    -- Prendre la dernière carte du tableau plat
    _card := _discard_arr[array_length(_discard_arr, 1)];
    _discard_arr := _discard_arr[1:array_length(_discard_arr, 1)-1];
    
    -- Mettre à jour l'affichage multi-pile: retirer la carte de la pile correspondante
    _last_by := COALESCE(_state->>'last_discard_by', '_seed');
    _pile := COALESCE(public._rami_jarr(_discards->_last_by), ARRAY[]::int[]);
    _pile := ARRAY(SELECT x FROM unnest(_pile) x WHERE x IS NOT NULL);
    
    IF array_length(_pile, 1) IS NOT NULL AND _pile[array_length(_pile, 1)] = _card THEN
      -- La carte est bien au sommet de la pile last_discard_by
      _pile := _pile[1:array_length(_pile, 1)-1];
      IF array_length(_pile, 1) IS NULL THEN
        _discards := _discards - _last_by;
      ELSE
        _discards := jsonb_set(_discards, ARRAY[_last_by], to_jsonb(_pile));
      END IF;
    ELSE
      -- La carte n'est pas au sommet de last_discard_by: chercher dans toutes les piles
      _new_discards := '{}'::jsonb;
      FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
        _pile := public._rami_jarr(_v);
        _pile := ARRAY(SELECT x FROM unnest(_pile) x WHERE x IS NOT NULL);
        IF array_length(_pile, 1) IS NOT NULL AND _pile[array_length(_pile, 1)] = _card THEN
          _pile := _pile[1:array_length(_pile, 1)-1];
        END IF;
        IF array_length(_pile, 1) IS NOT NULL THEN
          _new_discards := _new_discards || jsonb_build_object(_k, to_jsonb(_pile));
        END IF;
      END LOOP;
      _discards := _new_discards;
    END IF;
  ELSE
    -- ═══ Pioche depuis le deck ═══
    IF COALESCE(array_length(_deck, 1), 0) = 0 THEN
      -- Reshuffle: utiliser le tableau plat discard
      IF array_length(_discard_arr, 1) IS NOT NULL AND array_length(_discard_arr, 1) > 1 THEN
        _all := _discard_arr[1:array_length(_discard_arr, 1)-1];  -- tout sauf le dessus
        _discard_arr := ARRAY[_discard_arr[array_length(_discard_arr, 1)]];  -- garder le dessus
        _deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_all) c);
        -- Rebuild discards multi-pile: une seule pile avec le dessus
        _discards := jsonb_build_object('_reshuffled', to_jsonb(_discard_arr));
      ELSIF array_length(_discard_arr, 1) = 1 THEN
        -- Une seule carte, ne peut pas reshuffle
        RAISE EXCEPTION 'plus de cartes';
      ELSE
        RAISE EXCEPTION 'plus de cartes';
      END IF;
    END IF;
    _card := _deck[1];
    _deck := _deck[2:array_length(_deck, 1)];
  END IF;

  -- Ajouter la carte à la main
  _hand := array_append(_hand, _card);
  _hands := jsonb_set(_state->'hands', ARRAY[_uid::text], to_jsonb(_hand));

  -- Action log
  _action_log := COALESCE(_state->'action_log', '[]'::jsonb) ||
    jsonb_build_object('t', 'draw', 'p', _uid::text, 'from', _from, 'card', _card, 'ts', extract(epoch from now())::bigint);

  -- Sauvegarder l'état
  _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
  _state := jsonb_set(_state, '{discards}', _discards, true);
  _state := jsonb_set(_state, '{hands}', _hands);
  _state := jsonb_set(_state, '{action_log}', _action_log);

  UPDATE public.rami_games
    SET state=_state, turn_phase='play',
        turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
        updated_at=now()
    WHERE id=_game_id;
  UPDATE public.rami_participants SET hand_count=array_length(_hand, 1)
    WHERE game_id=_game_id AND user_id=_uid;
END $function$;

-- ═══ 2. rami_discard: défausse simplifiée ═══
CREATE OR REPLACE FUNCTION public.rami_discard(_game_id uuid, _card integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  _uid uuid := auth.uid();
  _g rami_games;
  _slot int;
  _state jsonb;
  _hand int[];
  _new_hand int[];
  _discard_arr int[];   -- tableau plat = source de vérité
  _discards jsonb;      -- multi-pile pour affichage
  _pile int[];
  _hands jsonb;
  _parts int[];
  _next int;
  _payout numeric;
  _comm numeric;
  _won boolean;
  _cfg record;
  _key text;
  _winner_name text;
  _seven boolean;
  _k text;
  _v jsonb;
  _all int[];
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'playing' THEN RAISE EXCEPTION 'partie inactive'; END IF;
  SELECT slot INTO _slot FROM rami_participants WHERE game_id=_game_id AND user_id=_uid;
  IF _slot IS NULL THEN RAISE EXCEPTION 'non participant'; END IF;
  IF _slot <> _g.current_turn OR _g.turn_phase <> 'play' THEN RAISE EXCEPTION 'pas ton tour'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');
  _key := _uid::text;
  _seven := COALESCE(_g.seven_cards, false);
  _state := public._rami_normalize_state(_g.state);
  _hand := COALESCE(public._rami_jarr(_state->'hands'->_key), ARRAY[]::int[]);
  IF NOT (_card = ANY(_hand)) THEN RAISE EXCEPTION 'carte absente'; END IF;
  _new_hand := public._rami_remove_one(_hand, _card);

  -- ═══ Tableau plat: ajouter la carte à la fin ═══
  _discard_arr := COALESCE(public._rami_jarr(_state->'discard'), ARRAY[]::int[]);
  _discard_arr := array_append(_discard_arr, _card);

  -- ═══ Multi-pile pour affichage: ajouter à la pile du joueur ═══
  _discards := public._rami_discards_map(_state);
  _pile := COALESCE(public._rami_jarr(_discards->_key), ARRAY[]::int[]);
  _pile := array_append(_pile, _card);
  _discards := jsonb_set(_discards, ARRAY[_key], to_jsonb(_pile), true);

  -- Mettre à jour l'état
  _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_new_hand));
  _state := jsonb_set(_state, '{hands}', _hands);
  _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
  _state := jsonb_set(_state, '{discards}', _discards, true);
  _state := jsonb_set(_state, '{last_discard_by}', to_jsonb(_key));

  -- Mettre à jour hand_count
  UPDATE public.rami_participants
     SET hand_count=COALESCE(array_length(_new_hand, 1), 0)
   WHERE game_id=_game_id AND user_id=_uid;

  -- Vérifier victoire
  IF COALESCE(array_length(_new_hand, 1), 0) = 0 THEN
    _won := public._rami_check_win(_state, _uid, _seven);
    IF _won THEN
      SELECT COALESCE(pseudo, 'Joueur') INTO _winner_name FROM public.profiles WHERE id=_uid;
      _comm := round(_g.pot * (_g.commission_pct / 2.0) / 100.0, 0);
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

  -- Passer au joueur suivant
  SELECT array_agg(slot ORDER BY slot) INTO _parts
    FROM public.rami_participants WHERE game_id=_game_id AND NOT forfeited;
  _next := _g.current_turn;
  LOOP
    _next := (_next + 1) % _g.max_players;
    EXIT WHEN _next = ANY(_parts);
  END LOOP;

  -- Commit la défausse + changement de tour
  UPDATE public.rami_games
     SET state=_state, current_turn=_next, turn_phase='draw',
         turn_deadline=now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
         updated_at=now()
   WHERE id=_game_id;

  -- Si le prochain joueur est un bot, attendre puis déclencher
  BEGIN
    PERFORM pg_sleep(5);
    PERFORM public._rami_autoplay_bots(_game_id);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END $function$;

-- ═══ 3. _rami_autoplay_bots: refait avec tableau plat ═══
CREATE OR REPLACE FUNCTION public._rami_autoplay_bots(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $function$
DECLARE
  g public.rami_games; part public.rami_participants; guard int := 0;
  _key text; _hand int[]; _card int; _deck int[]; _new_hand int[]; _hands jsonb;
  _melds jsonb; _melded int[]; _type text; _intel int; _parts int[];
  _next int; _top int; _matched boolean;
  _cfg record;
  _state jsonb; _discards jsonb; _pile int[]; _last text; _reshuffle jsonb;
  _discard_arr int[];  -- tableau plat = source de vérité
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
    IF NOT FOUND OR NOT COALESCE(part.is_bot, false) THEN EXIT; END IF;

    _key   := COALESCE(part.user_id::text, 'bot:' || part.slot::text);
    _intel := COALESCE(part.bot_intelligence, 70);
    _seven := COALESCE(g.seven_cards, false);
    SELECT * INTO _cfg FROM public._game_cfg('rami');
    _state := public._rami_normalize_state(g.state);
    _discards := public._rami_discards_map(_state);
    _last := public._rami_last_discarder(_state);
    _discard_arr := COALESCE(public._rami_jarr(_state->'discard'), ARRAY[]::int[]);
    _discard_arr := ARRAY(SELECT x FROM unnest(_discard_arr) x WHERE x IS NOT NULL);

    IF g.turn_phase = 'draw' THEN
      _deck := COALESCE(public._rami_jarr(_state->'deck'), ARRAY[]::int[]);
      _hand := COALESCE(public._rami_jarr(_state->'hands'->_key), ARRAY[]::int[]);
      _card := NULL;
      _matched := false;

      -- ═══ Bot peut piocher sur défausse: utiliser le tableau plat ═══
      IF _intel >= 70 AND array_length(_discard_arr, 1) IS NOT NULL AND array_length(_discard_arr, 1) > 0 THEN
        _top := _discard_arr[array_length(_discard_arr, 1)];
        -- Carte normale (non-joker): peut matcher
        IF (_top % 56) < 52 AND EXISTS (
          SELECT 1 FROM unnest(_hand) c
          WHERE (c % 56) < 52 AND c%13 = _top%13
        ) THEN
          _matched := true;
          _card := _top;
          -- Retirer du tableau plat
          _discard_arr := _discard_arr[1:array_length(_discard_arr, 1)-1];
          -- Retirer de la multi-pile (pour affichage)
          _pile := COALESCE(public._rami_jarr(_discards->_last), ARRAY[]::int[]);
          _pile := ARRAY(SELECT x FROM unnest(_pile) x WHERE x IS NOT NULL);
          IF array_length(_pile, 1) IS NOT NULL AND _pile[array_length(_pile, 1)] = _card THEN
            _pile := _pile[1:array_length(_pile, 1)-1];
            IF array_length(_pile, 1) IS NULL THEN
              _discards := _discards - _last;
            ELSE
              _discards := jsonb_set(_discards, ARRAY[_last], to_jsonb(_pile));
            END IF;
          ELSE
            -- Chercher dans toutes les piles
            DECLARE _nd jsonb := '{}'::jsonb; BEGIN
              FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
                _pile := public._rami_jarr(_v);
                _pile := ARRAY(SELECT x FROM unnest(_pile) x WHERE x IS NOT NULL);
                IF array_length(_pile, 1) IS NOT NULL AND _pile[array_length(_pile, 1)] = _card THEN
                  _pile := _pile[1:array_length(_pile, 1)-1];
                END IF;
                IF array_length(_pile, 1) IS NOT NULL THEN
                  _nd := _nd || jsonb_build_object(_k, to_jsonb(_pile));
                END IF;
              END LOOP;
              _discards := _nd;
            END;
          END IF;
        END IF;
      END IF;

      IF NOT _matched THEN
        -- Piocher depuis le deck
        IF COALESCE(array_length(_deck, 1), 0) = 0 THEN
          -- Reshuffle avec le tableau plat
          IF array_length(_discard_arr, 1) IS NOT NULL AND array_length(_discard_arr, 1) > 1 THEN
            _all_discard := _discard_arr[1:array_length(_discard_arr, 1)-1];
            _discard_arr := ARRAY[_discard_arr[array_length(_discard_arr, 1)]];
            _deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_all_discard) c);
            _discards := jsonb_build_object('_reshuffled', to_jsonb(_discard_arr));
          ELSE
            EXIT;  -- plus de cartes
          END IF;
        END IF;
        IF COALESCE(array_length(_deck, 1), 0) = 0 THEN EXIT; END IF;
        _card := _deck[1];
        _deck := _deck[2:array_length(_deck, 1)];
      END IF;

      _hand := array_append(_hand, _card);
      _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_hand));
      _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
      _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
      _state := jsonb_set(_state, '{discards}', _discards, true);
      _state := jsonb_set(_state, '{hands}', _hands);

      UPDATE public.rami_games
         SET state = _state, turn_phase = 'play', updated_at = now()
       WHERE id = _game_id;
      UPDATE public.rami_participants
         SET hand_count = COALESCE(array_length(_hand, 1), 0)
       WHERE game_id = _game_id AND slot = part.slot;
      CONTINUE;
    END IF;

    -- ═══ Phase 'play' ═══
    _hand := COALESCE(public._rami_jarr(_state->'hands'->_key), ARRAY[]::int[]);
    _melds := COALESCE(_state->'melds', '[]'::jsonb);
    _melded := NULL;

    IF _intel >= 50 AND COALESCE(array_length(_hand, 1), 0) >= 4 THEN
      -- Chercher un meld de 4 cartes
      SELECT ARRAY[_hand[ai], _hand[aj], _hand[ak], _hand[al]] INTO _melded
        FROM generate_subscripts(_hand, 1) ai, generate_subscripts(_hand, 1) aj,
             generate_subscripts(_hand, 1) ak, generate_subscripts(_hand, 1) al
       WHERE ai < aj AND aj < ak AND ak < al
         AND public._rami_meld_type(ARRAY[_hand[ai], _hand[aj], _hand[ak], _hand[al]], g.joker_mode, g.random_joker) IS NOT NULL
       LIMIT 1;

      -- Si pas de 4 cartes, chercher 3 cartes
      IF _melded IS NULL THEN
        SELECT ARRAY[_hand[bi], _hand[bj], _hand[bk]] INTO _melded
          FROM generate_subscripts(_hand, 1) bi, generate_subscripts(_hand, 1) bj, generate_subscripts(_hand, 1) bk
         WHERE bi < bj AND bj < bk
           AND public._rami_meld_type(ARRAY[_hand[bi], _hand[bj], _hand[bk]], g.joker_mode, g.random_joker) IS NOT NULL
         LIMIT 1;
      END IF;

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
        _state := jsonb_set(_state, '{hands}', _hands);
        _state := jsonb_set(_state, '{melds}', _melds);
        UPDATE public.rami_games SET state = _state, updated_at = now() WHERE id = _game_id;
        UPDATE public.rami_participants SET hand_count = COALESCE(array_length(_new_hand, 1), 0)
          WHERE game_id = _game_id AND slot = part.slot;
        _melded := NULL;
        CONTINUE;
      END IF;
    END IF;

    IF COALESCE(array_length(_hand, 1), 0) = 0 THEN EXIT; END IF;

    -- Choisir une carte à défausser
    IF _intel < 50 THEN
      _card := _hand[1 + floor(random() * array_length(_hand, 1))::int];
    ELSE
      SELECT c INTO _card FROM unnest(_hand) c
        ORDER BY (CASE WHEN (c % 56) < 52 THEN c%13 ELSE -1 END) DESC, random()
        LIMIT 1;
    END IF;

    _new_hand := public._rami_remove_one(_hand, _card);

    -- ═══ Gérer le cas où _new_hand est vide (dernière carte) ═══
    IF COALESCE(array_length(_new_hand, 1), 0) = 0 THEN
      -- Ajouter au tableau plat
      _discard_arr := array_append(_discard_arr, _card);
      -- Ajouter à la multi-pile
      _pile := COALESCE(public._rami_jarr(_discards->_key), ARRAY[]::int[]);
      _pile := array_append(_pile, _card);
      _discards := jsonb_set(_discards, ARRAY[_key], to_jsonb(_pile), true);
      
      _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_new_hand));
      _state := jsonb_set(_state, '{hands}', _hands);
      _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
      _state := jsonb_set(_state, '{discards}', _discards, true);
      _state := jsonb_set(_state, '{last_discard_by}', to_jsonb(_key));

      IF public._rami_check_win(_state, _key, _seven) THEN
        SELECT COALESCE(pseudo, 'Bot') INTO _winner_name FROM public.profiles WHERE id = part.user_id;
        IF part.user_id IS NOT NULL THEN
          _comm := round(g.pot * (g.commission_pct / 2.0) / 100.0, 0);
          _payout := g.pot - _comm;
          UPDATE public.profiles SET balance_ar = balance_ar + _payout WHERE id = part.user_id;
          INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
            VALUES (part.user_id, 'rami_win', _payout, _game_id, 'Win rami (bot)');
        END IF;
        UPDATE public.rami_games
           SET status='finished', winner_id=part.user_id, winner_name=COALESCE(_winner_name, part.display_name), finished_at=now(), state=_state
         WHERE id = _game_id;
        UPDATE public.rami_participants SET hand_count = 0
         WHERE game_id = _game_id AND slot = part.slot;
        EXIT;
      ELSE
        -- Remettre la carte dans la main (ne peut pas gagner avec 0 cartes)
        _new_hand := ARRAY[_card];
        _discard_arr := _discard_arr[1:array_length(_discard_arr, 1)-1];
        _pile := _pile[1:array_length(_pile, 1)-1];
        IF array_length(_pile, 1) IS NULL THEN
          _discards := _discards - _key;
        ELSE
          _discards := jsonb_set(_discards, ARRAY[_key], to_jsonb(_pile));
        END IF;
        _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_new_hand));
        _state := jsonb_set(_state, '{hands}', _hands);
        _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
        _state := jsonb_set(_state, '{discards}', _discards, true);
        UPDATE public.rami_games SET state = _state, updated_at = now() WHERE id = _game_id;
        UPDATE public.rami_participants SET hand_count = 1
          WHERE game_id = _game_id AND slot = part.slot;
        CONTINUE;
      END IF;
    END IF;

    -- ═══ Défausser normalement ═══
    -- Tableau plat
    _discard_arr := array_append(_discard_arr, _card);
    -- Multi-pile pour affichage
    _pile := COALESCE(public._rami_jarr(_discards->_key), ARRAY[]::int[]);
    _pile := array_append(_pile, _card);
    _discards := jsonb_set(_discards, ARRAY[_key], to_jsonb(_pile), true);
    
    _hands := jsonb_set(_state->'hands', ARRAY[_key], to_jsonb(_new_hand));
    _state := jsonb_set(_state, '{hands}', _hands);
    _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
    _state := jsonb_set(_state, '{discards}', _discards, true);
    _state := jsonb_set(_state, '{last_discard_by}', to_jsonb(_key));

    -- Passer au joueur suivant
    SELECT array_agg(slot ORDER BY slot) INTO _parts
      FROM public.rami_participants WHERE game_id = _game_id AND NOT forfeited;
    _next := g.current_turn;
    LOOP
      _next := (_next + 1) % g.max_players;
      EXIT WHEN _next = ANY(_parts);
    END LOOP;

    UPDATE public.rami_games
       SET state = _state, current_turn = _next, turn_phase = 'draw',
           turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 60) || ' seconds')::interval,
           updated_at = now()
     WHERE id = _game_id;
    UPDATE public.rami_participants
       SET hand_count = COALESCE(array_length(_new_hand, 1), 0)
     WHERE game_id = _game_id AND slot = part.slot;
  END LOOP;
END $function$;

-- ═══ 4. _rami_reshuffle: utilise le tableau plat ═══
CREATE OR REPLACE FUNCTION public._rami_reshuffle(_state jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $function$
DECLARE
  _discard_arr int[];
  _deck int[];
  _all int[];
BEGIN
  _discard_arr := public._rami_jarr(_state->'discard');
  _discard_arr := ARRAY(SELECT x FROM unnest(_discard_arr) x WHERE x IS NOT NULL);
  
  IF array_length(_discard_arr, 1) IS NULL OR array_length(_discard_arr, 1) <= 1 THEN
    RETURN jsonb_build_object('deck', '[]'::jsonb, 'discards', public._rami_discards_map(_state));
  END IF;
  
  -- Garder le dessus, reshuffle le reste
  _all := _discard_arr[1:array_length(_discard_arr, 1)-1];
  _deck := (SELECT array_agg(c ORDER BY random()) FROM unnest(_all) c);
  
  RETURN jsonb_build_object(
    'deck', to_jsonb(_deck),
    'discard', to_jsonb(ARRAY[_discard_arr[array_length(_discard_arr, 1)]]),
    'discards', jsonb_build_object('_reshuffled', to_jsonb(ARRAY[_discard_arr[array_length(_discard_arr, 1)]]))
  );
END $function$;

-- ═══ 5. _rami_normalize_state: assure que discard est toujours un array ═══
CREATE OR REPLACE FUNCTION public._rami_normalize_state(_state jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $function$
DECLARE
  _discards jsonb; _all_discard int[]; _k text; _v jsonb;
  _discard_val jsonb;
BEGIN
  IF _state IS NULL THEN RETURN '{}'::jsonb; END IF;
  
  -- Assurer que discard est un array
  _discard_val := _state->'discard';
  IF _discard_val IS NULL OR jsonb_typeof(_discard_val) = 'null' OR jsonb_typeof(_discard_val) <> 'array' THEN
    -- Rebuild from discards multi-pile
    _discards := public._rami_discards_map(_state);
    _all_discard := ARRAY[]::int[];
    FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
      _all_discard := _all_discard || public._rami_jarr(_v);
    END LOOP;
    _state := jsonb_set(_state, '{discard}', to_jsonb(_all_discard), true);
  END IF;
  
  -- Assurer que discards existe
  IF _state ? 'discards' = false OR _state->'discards' IS NULL THEN
    _discards := public._rami_discards_map(_state);
    _state := jsonb_set(_state, '{discards}', _discards, true);
  END IF;
  
  IF _state ? 'melds' = false THEN
    _state := jsonb_set(_state, '{melds}', '[]'::jsonb, true);
  END IF;
  IF _state ? 'action_log' = false THEN
    _state := jsonb_set(_state, '{action_log}', '[]'::jsonb, true);
  END IF;
  RETURN _state;
END $function$;

-- ═══ 6. Migration des jeux existants: synchroniser discard avec discards ═══
DO $$
DECLARE
  _g RECORD; _state jsonb; _discards jsonb; _discard_arr int[];
  _k text; _v jsonb; _needs_update boolean;
BEGIN
  FOR _g IN SELECT id, state FROM public.rami_games WHERE status = 'playing' LOOP
    _state := _g.state;
    _needs_update := false;
    
    -- Vérifier que discard est un array valide
    IF _state->'discard' IS NULL OR jsonb_typeof(_state->'discard') = 'null' OR jsonb_typeof(_state->'discard') <> 'array' THEN
      _needs_update := true;
    END IF;
    
    -- Vérifier que discard est synchronisé avec discards
    IF NOT _needs_update THEN
      _discards := public._rami_discards_map(_state);
      _discard_arr := ARRAY[]::int[];
      FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
        _discard_arr := _discard_arr || public._rami_jarr(_v);
      END LOOP;
      -- Comparer
      IF _discard_arr <> public._rami_jarr(_state->'discard') THEN
        _needs_update := true;
        _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
      END IF;
    ELSE
      -- Rebuild discard from discards
      _discards := public._rami_discards_map(_state);
      _discard_arr := ARRAY[]::int[];
      FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
        _discard_arr := _discard_arr || public._rami_jarr(_v);
      END LOOP;
      _state := jsonb_set(_state, '{discard}', to_jsonb(_discard_arr), true);
    END IF;
    
    -- S'assurer que discards existe
    IF _state->'discards' IS NULL OR jsonb_typeof(_state->'discards') = 'null' THEN
      _state := jsonb_set(_state, '{discards}', public._rami_discards_map(_state), true);
      _needs_update := true;
    END IF;
    
    IF _needs_update THEN
      UPDATE public.rami_games SET state = _state, updated_at = now() WHERE id = _g.id;
      RAISE NOTICE 'Sync discard pour jeu %', _g.id;
    END IF;
  END LOOP;
END $$;
