-- FIX: column "description" of relation "transactions" does not exist
-- The transactions table uses 'note' not 'description'.
-- Three domino functions used 'description' in INSERT INTO transactions:
--   - domino_create: stake transaction
--   - domino_end_round: winnings transaction
--   - domino_forfeit_internal: forfeit winnings transaction

CREATE OR REPLACE FUNCTION public.domino_end_round(_game_id uuid, _winner_slot integer DEFAULT NULL::integer, _blocked boolean DEFAULT false)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  _game record; _state jsonb; _p record; _pips int; _total int := 0;
  _hand_pips jsonb := '{}'::jsonb; _final_hands jsonb := '{}'::jsonb;
  _round_score int; _scores jsonb; _winner_uid text := null; _target int;
  _game_over boolean := false; _max int := -1; _ws int; _wu text;
  _now timestamp; _bu timestamp; _key text; _best int := 999; _tie int;
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
    _best := 999; _winner_slot := null;
    FOR _p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
      _key := COALESCE(_p.user_id::text, 'bot_'||_p.slot);
      _pips := (_hand_pips->>_key)::int;
      IF _pips < _best THEN _best := _pips; _winner_slot := _p.slot; _winner_uid := _key;
      ELSIF _pips = _best THEN _winner_uid := null; END IF;
    END LOOP;
    _round_score := GREATEST(0, _total - _best);
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
    _game_over := true;
  END IF;

  _now := now(); _bu := _now + interval '7 seconds';
  _state := _state || jsonb_build_object('phase', 'break', 'break_until', to_char(_bu, 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'last_round', jsonb_build_object('winner_uid', _winner_uid, 'winner_slot', _winner_slot, 'round_score', _round_score,
    'hand_pips', _hand_pips, 'final_hands', _final_hands, 'blocked', _blocked, 'round', (_state->>'round')::int));

  IF _game_over THEN
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
    UPDATE public.domino_games SET state = _state, scores = _scores, turn_deadline = null, updated_at = _now WHERE id = _game_id;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.domino_forfeit_internal(_game_id uuid, _part record)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  _game record; _remaining int; _winner record; _state jsonb; _now timestamp;
BEGIN
  UPDATE public.domino_participants SET forfeited = true WHERE id = _part.id;
  SELECT count(*) INTO _remaining FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  IF _remaining <= 1 THEN
    SELECT * INTO _winner FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false LIMIT 1;
    _now := now();
    SELECT state INTO _state FROM public.domino_games WHERE id = _game_id;
    _state := _state || jsonb_build_object('phase', 'finished', 'winner_slot', _winner.slot);
    SELECT * INTO _game FROM public.domino_games WHERE id = _game_id;
    IF _winner.user_id IS NOT NULL AND _game.stake > 0 THEN
      UPDATE public.profiles SET balance_ar = balance_ar + (_game.pot * (100 - _game.commission_pct) / 100)::int WHERE id = _winner.user_id;
      INSERT INTO public.transactions(user_id, type, amount, note) VALUES (_winner.user_id, 'winnings', (_game.pot * (100 - _game.commission_pct) / 100)::int, 'Gain domino (forfait)');
    END IF;
    UPDATE public.domino_games SET status = 'finished', state = _state, winner_id = _winner.user_id, finished_at = _now, turn_deadline = null, updated_at = _now WHERE id = _game_id;
  ELSE
    SELECT * INTO _game FROM public.domino_games WHERE id = _game_id;
    IF _game.current_turn = _part.slot THEN PERFORM public.domino_advance_turn(_game_id, _game.state); END IF;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.domino_create(_stake numeric DEFAULT 0, _max integer DEFAULT 2, _private boolean DEFAULT false, _mode text DEFAULT 'classic'::text, _commission integer DEFAULT 10, _target_score integer DEFAULT 0, _draw_mode text DEFAULT 'with'::text, _first_tile_rule text DEFAULT 'libre'::text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  _id uuid; _host uuid := auth.uid(); _rc text; _pr record; _si int := GREATEST(0, ROUND(_stake));
  _mp int := LEAST(4, GREATEST(2, _max)); _c int := LEAST(30, GREATEST(0, _commission));
  _t int := CASE WHEN _mode = 'points' THEN GREATEST(50, _target_score) ELSE 0 END;
BEGIN
  IF _host IS NULL THEN RAISE EXCEPTION 'Auth required'; END IF;
  IF _si > 0 AND _si < 200 THEN RAISE EXCEPTION 'Mise minimum 200 Ar'; END IF;
  SELECT pseudo INTO _pr FROM public.profiles WHERE id = _host;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profil introuvable'; END IF;
  IF _si > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar - _si WHERE id = _host AND balance_ar >= _si;
    IF NOT FOUND THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
    INSERT INTO public.transactions(user_id, type, amount, note) VALUES (_host, 'stake', -_si, 'Mise domino');
  END IF;
  IF _private THEN _rc := lpad(floor(random()*1000000)::text, 6, '0'); END IF;
  INSERT INTO public.domino_games(
    host_id, status, stake, pot, commission_pct, is_private, room_code, state,
    max_players, target_score, scores, turn_skips, paused, pause_used,
    first_tile_rule, mode, current_turn, created_at, updated_at
  ) VALUES (
    _host, 'open', _si, 0, _c, _private, _rc,
    jsonb_build_object('phase','waiting','round',0,'board','[]'::jsonb,'left_end',null,'right_end',null,
      'hands','{}'::jsonb,'stock','[]'::jsonb,'draw_mode',_draw_mode,'first_tile_rule',_first_tile_rule,
      'passes',0,'last_pass_by',null),
    _mp, _t, '{}'::jsonb, '{}'::jsonb, false, false, _first_tile_rule, _mode, -1, now(), now()
  ) RETURNING id INTO _id;
  INSERT INTO public.domino_participants(game_id, user_id, slot, ready, forfeited, score, display_name, is_bot, joined_at)
  VALUES (_id, _host, 0, false, false, 0, COALESCE(_pr.pseudo, 'Joueur'), false, now());
  RETURN _id;
END;
$function$;
