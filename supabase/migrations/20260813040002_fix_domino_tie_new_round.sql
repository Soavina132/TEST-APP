CREATE OR REPLACE FUNCTION public.domino_end_round(_game_id uuid, _winner_slot integer DEFAULT NULL::integer, _blocked boolean DEFAULT false)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  _game record; _state jsonb; _p record; _pips int; _total int := 0;
  _hand_pips jsonb := '{}'::jsonb; _final_hands jsonb := '{}'::jsonb;
  _round_score int; _scores jsonb; _winner_uid text := null; _target int;
  _game_over boolean := false; _max int := -1; _ws int; _wu text;
  _now timestamp; _bu timestamp; _key text; _best int := 999; _tie boolean := false;
BEGIN
  SELECT * INTO _game FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND OR _game.status != 'playing' THEN RETURN; END IF;
  _state := _game.state; _scores := _game.scores;

  FOR _p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
    _key := COALESCE(_p.user_id::text, 'bot_'||_p.slot);
    _pips := public.domino_hand_pips(_state->('hands')->(_p.slot::text));
    _hand_pips := _hand_pips || jsonb_build_object(_key, _pips);
    _final_hands := _final_hands || jsonb_build_object(_key, _state->('hands')->(_p.slot::text));
    _total := _total + _pips;
  END LOOP;

  IF _blocked THEN
    -- Blocked game: find player with fewest pips.
    _best := 999; _winner_slot := null;
    FOR _p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
      _key := COALESCE(_p.user_id::text, 'bot_'||_p.slot);
      _pips := (_hand_pips->>_key)::int;
      IF _pips < _best THEN
        _best := _pips; _winner_slot := _p.slot; _winner_uid := _key; _tie := false;
      ELSIF _pips = _best THEN
        _tie := true;
      END IF;
    END LOOP;
    -- On tie: no winner, no points — a new round will be played
    IF _tie THEN
      _winner_uid := null; _winner_slot := null; _round_score := 0;
    ELSE
      _round_score := GREATEST(0, _total - _best);
    END IF;
  ELSE
    SELECT COALESCE(user_id::text, 'bot_'||_winner_slot) INTO _winner_uid
    FROM public.domino_participants WHERE game_id = _game_id AND slot = _winner_slot AND forfeited = false;
    _round_score := GREATEST(0, _total - public.domino_hand_pips(_state->('hands')->(_winner_slot::text)));
  END IF;

  IF _winner_uid IS NOT NULL THEN
    _scores := jsonb_set(_scores, ARRAY[_winner_uid], to_jsonb((_scores->>_winner_uid)::int + _round_score));
  END IF;

  _target := _game.target_score;
  IF _target > 0 THEN
    FOR _p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
      _key := COALESCE(_p.user_id::text, 'bot_'||_p.slot);
      IF (_scores->>_key)::int >= _target THEN _game_over := true; END IF;
    END LOOP;
  ELSE
    -- Classic mode: game over only if there's a winner (not a tie)
    _game_over := (_winner_uid IS NOT NULL);
  END IF;

  _now := now(); _bu := _now + interval '7 seconds';
  _state := _state || jsonb_build_object('phase', 'break', 'break_until', to_char(_bu, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'last_round', jsonb_build_object('winner_uid', _winner_uid, 'winner_slot', _winner_slot, 'round_score', _round_score,
    'hand_pips', _hand_pips, 'final_hands', _final_hands, 'blocked', _blocked, 'tie', _tie, 'round', (_state->>'round')::int));

  IF _game_over THEN
    -- Find the overall winner (highest score)
    _max := -1; _wu := null; _ws := 0;
    FOR _p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
      _key := COALESCE(_p.user_id::text, 'bot_'||_p.slot);
      IF (_scores->>_key)::int > _max THEN _max := (_scores->>_key)::int; _wu := _p.user_id; _ws := _p.slot; END IF;
    END LOOP;
    _state := _state || jsonb_build_object('phase', 'finished', 'winner_slot', _ws);
    IF _wu IS NOT NULL AND _game.stake > 0 THEN
      UPDATE public.profiles SET balance_ar = balance_ar + (_game.pot * (100 - _game.commission_pct) / 100)::int WHERE id = _wu;
      INSERT INTO public.transactions(user_id, type, amount, note) VALUES (_wu, 'winnings', (_game.pot * (100 - _game.commission_pct) / 100)::int, 'Gain domino');
    END IF;
    UPDATE public.domino_games SET status = 'finished', state = _state, scores = _scores, winner_id = _wu, finished_at = _now, turn_deadline = null, updated_at = _now WHERE id = _game_id;
  ELSE
    -- Not game over (tie or points mode without target reached): next round will start after break
    UPDATE public.domino_games SET state = _state, scores = _scores, turn_deadline = null, updated_at = _now WHERE id = _game_id;
  END IF;
END;
$function$;
