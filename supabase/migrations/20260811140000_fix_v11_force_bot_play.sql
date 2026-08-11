-- ═══════════════════════════════════════════════════════════════════════
-- FIX v11 — Forcer le bot à jouer immédiatement dans la boucle
--
-- Problème: _domino_bot_step arme le bot (bot_think_until = now+400ms)
-- mais le 2e domino_tick ne fait pas jouer le bot. Le bot attend 30s (cron).
-- Test: 34s avant, 2.7s après.
--
-- Solution: avant chaque domino_tick, on force bot_think_until dans le passé
-- et bot_locked_slot = current_turn. Ainsi _domino_bot_step joue immédiatement.
-- ═══════════════════════════════════════════════════════════════════════

-- ═══ 1. _domino_bot_loop avec force-play ═══
CREATE OR REPLACE FUNCTION public._domino_bot_loop(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_is_bot boolean;
  v_max_loops int := 30;
  g_status text;
  g_phase text;
  v_turn int;
BEGIN
  LOOP
    EXIT WHEN v_max_loops <= 0;
    v_max_loops := v_max_loops - 1;

    SELECT status::text, state->>'phase' INTO g_status, g_phase
      FROM public.domino_games WHERE id = _game_id;
    EXIT WHEN g_status IS NULL OR g_status <> 'playing';
    EXIT WHEN g_phase NOT IN ('play', 'playing');
    EXIT WHEN g_phase IN ('reveal', 'break', 'dealing');

    SELECT COALESCE(dp.is_bot, false), g.current_turn INTO v_is_bot, v_turn
      FROM public.domino_participants dp
      JOIN public.domino_games g ON g.id = dp.game_id
     WHERE dp.game_id = _game_id
       AND dp.slot = g.current_turn
       AND dp.forfeited = false;

    EXIT WHEN NOT COALESCE(v_is_bot, false);

    -- Forcer bot_think_until dans le passé + bot_locked_slot = current_turn
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

-- ═══ 2. domino_play_and_bot avec force-play ═══
CREATE OR REPLACE FUNCTION public.domino_play_and_bot(_game_id uuid, _move jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_is_bot boolean;
  v_max_loops int := 30;
  g_status text;
  g_phase text;
  v_turn int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;

  -- 1. Le joueur humain joue
  PERFORM public.domino_play(_game_id, _move);

  -- 2. Boucle: faire jouer les bots un par un
  LOOP
    EXIT WHEN v_max_loops <= 0;
    v_max_loops := v_max_loops - 1;

    SELECT status::text, state->>'phase' INTO g_status, g_phase
      FROM public.domino_games WHERE id = _game_id;
    EXIT WHEN g_status IS NULL OR g_status <> 'playing';
    EXIT WHEN g_phase NOT IN ('play', 'playing');
    EXIT WHEN g_phase IN ('reveal', 'break', 'dealing');

    SELECT COALESCE(dp.is_bot, false), g.current_turn INTO v_is_bot, v_turn
      FROM public.domino_participants dp
      JOIN public.domino_games g ON g.id = dp.game_id
     WHERE dp.game_id = _game_id
       AND dp.slot = g.current_turn
       AND dp.forfeited = false;

    EXIT WHEN NOT COALESCE(v_is_bot, false);

    -- Forcer bot_think_until dans le passé + bot_locked_slot = current_turn
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
