DROP POLICY IF EXISTS domino_games_select ON public.domino_games;

CREATE POLICY domino_games_select ON public.domino_games
FOR SELECT
USING (
  ((status IN ('open'::public.game_status, 'playing'::public.game_status)) AND is_private = false)
  OR host_id = auth.uid()
  OR EXISTS (
    SELECT 1
    FROM public.domino_participants p
    WHERE p.game_id = domino_games.id
      AND p.user_id = auth.uid()
  )
  OR public.is_admin()
);

CREATE OR REPLACE FUNCTION public._domino_required_starter_slot(_game_id uuid, _state jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  first_dbl integer;
  p record;
  t jsonb;
BEGIN
  IF jsonb_array_length(COALESCE(_state->'board', '[]'::jsonb)) > 0 THEN
    RETURN NULL;
  END IF;

  first_dbl := NULLIF(_state->>'first_move_double', 'null')::integer;
  IF first_dbl IS NULL THEN
    RETURN NULL;
  END IF;

  FOR p IN
    SELECT slot
    FROM public.domino_participants
    WHERE game_id = _game_id
      AND forfeited = false
    ORDER BY slot
  LOOP
    FOR t IN SELECT * FROM jsonb_array_elements(COALESCE(_state->'hands'->p.slot::text, '[]'::jsonb)) LOOP
      IF (t->>0)::integer = first_dbl AND (t->>1)::integer = first_dbl THEN
        RETURN p.slot;
      END IF;
    END LOOP;
  END LOOP;

  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.domino_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  g record;
  cur_uid uuid;
  _cfg record;
  _skips int;
  _next int;
  remaining int;
  last_slot int;
  _break_until timestamptz;
  _deal_until timestamptz;
  required_slot int;
  board_empty boolean;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

  IF (g.state->>'phase') = 'dealing' THEN
    _deal_until := NULLIF(g.state->>'deal_until','')::timestamptz;
    IF _deal_until IS NOT NULL AND _deal_until <= now() THEN
      PERFORM public._domino_place_first(_game_id);
    END IF;
    RETURN;
  END IF;

  IF (g.state->>'phase') = 'break' THEN
    _break_until := NULLIF(g.state->>'break_until','')::timestamptz;
    IF _break_until IS NOT NULL AND _break_until <= now() THEN
      PERFORM public._domino_next_round(_game_id);
    END IF;
    RETURN;
  END IF;

  SELECT * INTO _cfg FROM public._game_cfg('domino');
  board_empty := jsonb_array_length(COALESCE(g.state->'board', '[]'::jsonb)) = 0;
  required_slot := public._domino_required_starter_slot(_game_id, g.state);

  IF board_empty AND required_slot IS NOT NULL AND required_slot <> g.current_turn THEN
    UPDATE public.domino_games
       SET current_turn = required_slot,
           turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
     WHERE id = _game_id;
    RETURN;
  END IF;

  IF g.turn_deadline IS NULL OR g.turn_deadline > now() THEN RETURN; END IF;

  SELECT user_id INTO cur_uid
    FROM public.domino_participants
   WHERE game_id = _game_id
     AND slot = g.current_turn
     AND forfeited = false;

  IF cur_uid IS NULL THEN
    _next := public._domino_next_playable_slot(_game_id, g.current_turn, g.state);
    IF _next IS NOT NULL THEN
      UPDATE public.domino_games
         SET current_turn = _next,
             turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
       WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;

  _skips := COALESCE((g.turn_skips->>cur_uid::text)::int, 0) + 1;

  IF _skips >= _cfg.max_turn_skips THEN
    UPDATE public.domino_participants
       SET forfeited = true
     WHERE game_id = _game_id
       AND user_id = cur_uid;

    SELECT count(*) INTO remaining
      FROM public.domino_participants
     WHERE game_id = _game_id
       AND forfeited = false;

    IF remaining <= 1 THEN
      SELECT slot INTO last_slot
        FROM public.domino_participants
       WHERE game_id = _game_id
         AND forfeited = false
       LIMIT 1;

      IF last_slot IS NOT NULL THEN
        PERFORM public._domino_finalize(_game_id, last_slot);
      ELSE
        UPDATE public.domino_games SET status='cancelled', finished_at=now() WHERE id = _game_id;
      END IF;
      RETURN;
    END IF;

    g.turn_skips := jsonb_set(COALESCE(g.turn_skips,'{}'::jsonb), ARRAY[cur_uid::text], to_jsonb(_skips), true);
    g.state := jsonb_set(g.state, ARRAY['hands', g.current_turn::text], '[]'::jsonb, true);
    required_slot := public._domino_required_starter_slot(_game_id, g.state);

    IF board_empty AND required_slot IS NOT NULL THEN
      UPDATE public.domino_games
         SET state = g.state,
             turn_skips = g.turn_skips,
             current_turn = required_slot,
             turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
       WHERE id = _game_id;
      RETURN;
    END IF;
  ELSE
    g.turn_skips := jsonb_set(COALESCE(g.turn_skips,'{}'::jsonb), ARRAY[cur_uid::text], to_jsonb(_skips), true);

    IF board_empty AND required_slot IS NOT NULL THEN
      UPDATE public.domino_games
         SET turn_skips = g.turn_skips,
             current_turn = required_slot,
             turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
       WHERE id = _game_id;
      RETURN;
    END IF;

    UPDATE public.domino_games
       SET turn_skips = g.turn_skips
     WHERE id = _game_id;
  END IF;

  _next := public._domino_next_playable_slot(_game_id, g.current_turn, g.state);
  IF _next IS NULL THEN
    _next := public._domino_lowest_pip_slot(_game_id, g.state);
    IF _next IS NOT NULL THEN
      PERFORM public._domino_end_round(_game_id, _next);
    END IF;
    RETURN;
  END IF;

  UPDATE public.domino_games
     SET current_turn = _next,
         turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
   WHERE id = _game_id;
END;
$function$;

DO $function$
DECLARE
  g record;
  required_slot integer;
  _cfg record;
BEGIN
  SELECT * INTO _cfg FROM public._game_cfg('domino');

  FOR g IN
    SELECT *
    FROM public.domino_games
    WHERE status = 'playing'
      AND COALESCE(state->>'phase', 'playing') = 'playing'
      AND jsonb_array_length(COALESCE(state->'board', '[]'::jsonb)) = 0
  LOOP
    required_slot := public._domino_required_starter_slot(g.id, g.state);
    IF required_slot IS NOT NULL AND required_slot <> g.current_turn THEN
      UPDATE public.domino_games
         SET current_turn = required_slot,
             turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
       WHERE id = g.id;
    END IF;
  END LOOP;
END;
$function$;