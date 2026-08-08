-- ============================================================
-- Fix régression: joker_mode (Sans/Classique/Aléatoire/Double)
-- La migration du 3 août avait écrasé _rami_is_joker avec une
-- version qui ignore le mode choisi (jokers classiques toujours
-- actifs peu importe le mode, pas de vérif couleur opposée pour
-- le joker aléatoire, mode "double" jamais calculé).
-- On restaure la logique correcte du 20 juin, avec la
-- signature actuelle (_card, _joker_mode, _random_joker).
-- ============================================================

CREATE OR REPLACE FUNCTION public._rami_is_joker(_card int, _joker_mode text, _random_joker int)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE _base int; _rd int; _sd int; _r int; _s int; _color_d int; _color int;
BEGIN
  IF _card IS NULL THEN RETURN false; END IF;
  _base := _card % 56;

  -- Jokers classiques (cartes 52-55 du paquet) : actifs en mode classique/double uniquement
  IF _base >= 52 AND _joker_mode IN ('classique','double') THEN RETURN true; END IF;

  -- Joker tiré au hasard : même rang, couleur opposée. Actif en mode aleatoire/double
  IF _joker_mode IN ('aleatoire','double') AND _random_joker IS NOT NULL
     AND _base < 52 AND (_random_joker % 56) < 52 THEN
    _rd := (_random_joker % 56) % 13; _sd := (_random_joker % 56) / 13;
    _r  := _base % 13;                _s  := _base / 13;
    IF _r = _rd AND _s <> _sd THEN
      _color_d := CASE WHEN _sd IN (0,3) THEN 0 ELSE 1 END; -- 0 = noir, 1 = rouge
      _color   := CASE WHEN _s  IN (0,3) THEN 0 ELSE 1 END;
      IF _color <> _color_d THEN RETURN true; END IF;
    END IF;
  END IF;

  RETURN false;
END $$;

-- rami_start : calculer le joker aléatoire aussi pour le mode "double" (pas juste "aleatoire")
CREATE OR REPLACE FUNCTION public.rami_start(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  _g public.rami_games; _parts uuid[]; _deck int[]; _i int; _j int; _tmp int;
  _hands jsonb := '{}'::jsonb; _p uuid; _hand int[]; _state jsonb;
  _first_discard int; _cfg record; _joker_mode text; _random_joker int;
  _discards jsonb; _action_log jsonb;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status NOT IN ('waiting','open') THEN RETURN; END IF;
  SELECT array_agg(user_id ORDER BY slot) INTO _parts FROM public.rami_participants WHERE game_id=_game_id;
  IF array_length(_parts,1) < 2 THEN RAISE EXCEPTION 'pas assez de joueurs'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('rami');

  -- Build 2 decks: 0..55 twice = 112 cards (2×52 + 2×4 jokers = 112)
  -- Card IDs: 0-55 (deck 1), 56-111 (deck 2). Jokers: 52-55, 108-111
  _deck := ARRAY(SELECT generate_series(0, 111));

  -- Fisher-Yates shuffle
  FOR _i IN REVERSE 112..2 LOOP
    _j := 1 + floor(random()*_i)::int;
    _tmp := _deck[_i]; _deck[_i] := _deck[_j]; _deck[_j] := _tmp;
  END LOOP;

  -- Deal 13 cards each (standard Rummy)
  FOREACH _p IN ARRAY _parts LOOP
    _hand := _deck[1:13];
    _deck := _deck[14:array_length(_deck,1)];
    _hands := _hands || jsonb_build_object(_p::text, to_jsonb(_hand));
    UPDATE public.rami_participants SET hand_count = 13 WHERE game_id=_game_id AND user_id=_p;
  END LOOP;

  -- First card to discard (seed pile)
  _first_discard := _deck[1];
  _deck := _deck[2:array_length(_deck,1)];

  -- Joker mode setup
  _joker_mode := _g.joker_mode;
  _random_joker := NULL;
  IF _joker_mode IN ('aleatoire','double') THEN
    -- Pick a random non-joker card as the "random joker"
    _random_joker := floor(random()*52)::int;
  END IF;

  -- Per-player discard piles
  _discards := jsonb_build_object('_seed', jsonb_build_array(_first_discard));

  -- Action log
  _action_log := jsonb_build_array(
    jsonb_build_object('t', 'start', 'ts', extract(epoch from now())::bigint)
  );

  _state := jsonb_build_object(
    'deck', to_jsonb(_deck),
    'discards', _discards,
    'last_discard_by', '_seed',
    'hands', _hands,
    'melds', '[]'::jsonb,
    'action_log', _action_log,
    'refunded', '{}'::jsonb
  );

  UPDATE public.rami_games SET
    status='playing', state=_state, started_at=now(),
    current_turn=0, turn_phase='draw',
    random_joker=_random_joker,
    turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval
    WHERE id=_game_id;
END $$;
