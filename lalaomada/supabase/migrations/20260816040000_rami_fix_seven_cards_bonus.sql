-- ============================================================
-- Fix: 7 cartes is NOT a deal mode — it's a BONUS within a 13-card game.
-- Players ALWAYS get 13 cards. The first to meld 7 pure cards gets stake refunded.
-- The game continues. Win condition is always the 13-card structure.
-- ============================================================

-- ═══ 1. _rami_check_win: always 13-card validation (no 7-card mode) ═══
CREATE OR REPLACE FUNCTION public._rami_check_win(_state jsonb, _key text, _seven_cards boolean DEFAULT false)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public'
AS $function$
DECLARE
  _carre int := 0; _trio int := 0; _run int := 0; _total int := 0;
  _m jsonb; _t text; _cards int[]; _n int; _has_long_run boolean := false;
BEGIN
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
    END IF;
  END LOOP;

  -- Standard: 2 trios + 1 run + 1 carre = 13
  IF _carre >= 1 AND _trio >= 2 AND _run >= 1 AND _total >= 13 THEN
    RETURN true;
  END IF;
  -- Alternative: no carre, at least one 4+ run, enough trios+runs to reach 13
  IF _carre = 0 AND _has_long_run AND _total >= 13 AND (_trio + _run) >= 2 THEN
    RETURN true;
  END IF;
  RETURN false;
END;
$function$;

-- ═══ 2. rami_start: ALWAYS deal 13 cards (seven_cards is just a bonus flag) ═══
CREATE OR REPLACE FUNCTION public.rami_start(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE _g rami_games; _parts uuid[]; _deck int[]; _i int; _j int; _tmp int;
  _hands jsonb := '{}'::jsonb; _p uuid; _hand int[]; _state jsonb;
  _max int; _rj int := NULL; _first int; _top int;
  _seven boolean;
BEGIN
  SELECT * INTO _g FROM rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status <> 'waiting' THEN RETURN; END IF;
  SELECT array_agg(user_id ORDER BY slot) INTO _parts FROM rami_participants WHERE game_id=_game_id;
  IF array_length(_parts,1) < 2 THEN RAISE EXCEPTION 'pas assez de joueurs'; END IF;

  _seven := COALESCE(_g.seven_cards, true);

  -- Deck size by joker mode (NOT by seven_cards)
  IF _g.joker_mode IN ('classique','double') THEN _max := 56;
  ELSE _max := 52; END IF;
  _deck := ARRAY(SELECT generate_series(0,_max-1));

  FOR _i IN REVERSE _max..2 LOOP
    _j := 1 + floor(random()*_i)::int;
    _tmp := _deck[_i]; _deck[_i] := _deck[_j]; _deck[_j] := _tmp;
  END LOOP;

  -- ALWAYS deal 13 cards per player
  FOREACH _p IN ARRAY _parts LOOP
    _hand := _deck[1:13];
    _deck := _deck[14:array_length(_deck,1)];
    _hands := _hands || jsonb_build_object(_p::text, to_jsonb(_hand));
    UPDATE rami_participants SET hand_count=13 WHERE game_id=_game_id AND user_id=_p;
  END LOOP;

  -- Random Joker (mode aleatoire & double)
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
