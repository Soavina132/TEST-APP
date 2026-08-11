-- Fix v13: _domino_bot_loop gère reveal/break/dealing + domino_play_and_bot simplifié
-- Les bots ne sont plus bloqués pendant les transitions de manche

CREATE OR REPLACE FUNCTION public._domino_bot_loop(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_is_bot boolean;
  v_max_loops int := 60;
  g_status text;
  g_phase text;
  v_turn int;
  v_until timestamptz;
  v_sleep_sec numeric;
BEGIN
  LOOP
    EXIT WHEN v_max_loops <= 0;
    v_max_loops := v_max_loops - 1;

    SELECT status::text, state->>'phase' INTO g_status, g_phase
      FROM public.domino_games WHERE id = _game_id;
    EXIT WHEN g_status IS NULL OR g_status <> 'playing';

    -- Phase: reveal - attendre reveal_until puis tick
    IF g_phase = 'reveal' THEN
      SELECT NULLIF(state->>'reveal_until', '')::timestamptz INTO v_until
        FROM public.domino_games WHERE id = _game_id;
      IF v_until IS NOT NULL AND v_until > now() THEN
        v_sleep_sec := EXTRACT(epoch FROM (v_until - now()));
        IF v_sleep_sec > 0 AND v_sleep_sec < 15 THEN
          PERFORM pg_sleep(v_sleep_sec);
        END IF;
      END IF;
      PERFORM public.domino_tick(_game_id);
      CONTINUE;
    END IF;

    -- Phase: break - attendre break_until puis tick
    IF g_phase = 'break' THEN
      SELECT NULLIF(state->>'break_until', '')::timestamptz INTO v_until
        FROM public.domino_games WHERE id = _game_id;
      IF v_until IS NOT NULL AND v_until > now() THEN
        v_sleep_sec := EXTRACT(epoch FROM (v_until - now()));
        IF v_sleep_sec > 0 AND v_sleep_sec < 15 THEN
          PERFORM pg_sleep(v_sleep_sec);
        END IF;
      END IF;
      PERFORM public.domino_tick(_game_id);
      CONTINUE;
    END IF;

    -- Phase: dealing - attendre deal_until puis tick
    IF g_phase = 'dealing' THEN
      SELECT NULLIF(state->>'deal_until', '')::timestamptz INTO v_until
        FROM public.domino_games WHERE id = _game_id;
      IF v_until IS NOT NULL AND v_until > now() THEN
        v_sleep_sec := EXTRACT(epoch FROM (v_until - now()));
        IF v_sleep_sec > 0 AND v_sleep_sec < 10 THEN
          PERFORM pg_sleep(v_sleep_sec);
        END IF;
      END IF;
      PERFORM public.domino_tick(_game_id);
      CONTINUE;
    END IF;

    -- Phase: play
    EXIT WHEN g_phase NOT IN ('play', 'playing');

    SELECT COALESCE(dp.is_bot, false), g.current_turn INTO v_is_bot, v_turn
      FROM public.domino_participants dp
      JOIN public.domino_games g ON g.id = dp.game_id
     WHERE dp.game_id = _game_id
       AND dp.slot = g.current_turn
       AND dp.forfeited = false;

    EXIT WHEN NOT COALESCE(v_is_bot, false);

    -- Forcer bot_think_until dans le passe + bot_locked_slot
    UPDATE public.domino_games
       SET state = jsonb_set(
             jsonb_set(state, '{bot_think_until}',
               to_jsonb((now() - interval '10 seconds')::timestamptz::text), true),
             '{bot_locked_slot}', to_jsonb(v_turn), true)
     WHERE id = _game_id;

    PERFORM public.domino_tick(_game_id);
    PERFORM pg_sleep(0.5);
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.domino_play_and_bot(_game_id uuid, _move jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;

  -- 1. Le joueur humain joue
  PERFORM public.domino_play(_game_id, _move);

  -- 2. Faire jouer les bots (gere aussi reveal/break/dealing)
  PERFORM public._domino_bot_loop(_game_id);
END;
$function$;
