-- ═══ Fix rami_start: joker mode values + random joker logic ═══
-- Bug: rami_start utilisait 'aucun' et 'fixe' au lieu de 'sans', 'classique', etc.
-- Bug: random_joker était juste floor(random()*52) sans retirer la carte du deck
-- Aligné avec rami_start_solo_bot qui gère correctement les 4 modes

CREATE OR REPLACE FUNCTION public.rami_start(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  _g public.rami_games; _deck int[]; _i int; _j int; _tmp int;
  _hands jsonb := '{}'::jsonb; _hand int[]; _state jsonb; _key text;
  _cfg record; _joker_mode text; _random_joker int;
  _discards jsonb; _action_log jsonb;
  _slot int; _uid uuid; _is_bot boolean;
  _is_first boolean := true;
  _card_count int;
  _max int;  -- cards per deck (52 or 56)
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

  -- ═══ Fix: valeurs correctes des joker modes ═══
  -- sans = pas de jokers (52 cartes/paquet)
  -- aleatoire = pas de jokers dans le paquet, mais une carte non-joker est désignée joker couleur opposée
  -- classique = 4 jokers par paquet (56 cartes/paquet)
  -- double = 4 jokers par paquet + random joker couleur opposée
  IF _joker_mode IN ('classique','double') THEN
    _max := 56;
  ELSE
    _max := 52;
  END IF;

  _max_players := _g.max_players;
  IF _max_players <= 2 THEN
    _deck := ARRAY(SELECT generate_series(0, _max - 1))
          || ARRAY(SELECT 56 + generate_series(0, _max - 1));
  ELSE
    _deck := ARRAY(SELECT generate_series(0, _max - 1))
          || ARRAY(SELECT 56 + generate_series(0, _max - 1))
          || ARRAY(SELECT 112 + generate_series(0, _max - 1));
  END IF;

  -- Mélange Fisher-Yates
  FOR _i IN REVERSE array_length(_deck,1)..2 LOOP
    _j := 1 + floor(random()*_i)::int;
    _tmp := _deck[_i]; _deck[_i] := _deck[_j]; _deck[_j] := _tmp;
  END LOOP;

  -- Distribution: 1er joueur = 14 cartes, autres = 13
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

  -- ═══ Fix: random joker couleur opposée (comme rami_start_solo_bot) ═══
  IF _joker_mode IN ('aleatoire','double') THEN
    _i := 1;
    WHILE _i <= array_length(_deck,1) AND (_deck[_i] % 56) >= 52 LOOP
      _i := _i + 1;
    END LOOP;
    IF _i <= array_length(_deck,1) THEN
      _random_joker := _deck[_i];
      _deck := _deck[1:_i-1] || _deck[_i+1:array_length(_deck,1)];
    END IF;
  END IF;

  -- Pas de carte seed sur la défausse — la défausse commence vide
  _discards := '{}'::jsonb;

  _action_log := jsonb_build_array(
    jsonb_build_object('t', 'start', 'ts', extract(epoch from now())::bigint)
  );

  _state := jsonb_build_object(
    'deck', to_jsonb(_deck),
    'discards', _discards,
    'discard', '[]'::jsonb,
    'last_discard_by', null::jsonb,
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
