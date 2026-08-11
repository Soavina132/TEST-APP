-- ============================================================
-- Fix: statement timeout sur domino
-- Cause: pg_sleep(3.5) dans domino_set_ready + trop de loops dans _domino_bot_loop
-- ============================================================

-- 1. domino_set_ready: retirer pg_sleep, le cron (5s) gère le bot
CREATE OR REPLACE FUNCTION public.domino_set_ready(_game_id uuid, _ready boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_status text;
  v_count int;
  v_max int;
  v_ready_count int;
  v_has_bot boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  UPDATE public.domino_participants
     SET ready = COALESCE(_ready, false)
   WHERE game_id = _game_id AND user_id = v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not a participant';
  END IF;

  SELECT status::text, max_players
    INTO v_status, v_max
    FROM public.domino_games
   WHERE id = _game_id
   FOR UPDATE;

  IF v_status <> 'open' THEN
    RETURN;
  END IF;

  SELECT count(*), count(*) FILTER (WHERE ready)
    INTO v_count, v_ready_count
    FROM public.domino_participants
   WHERE game_id = _game_id;

  IF v_count = v_max AND v_ready_count = v_max THEN
    PERFORM public._domino_start(_game_id);

    SELECT EXISTS(SELECT 1 FROM public.domino_participants
      WHERE game_id = _game_id AND is_bot = true AND forfeited = false)
    INTO v_has_bot;

    IF v_has_bot THEN
      -- Le cron domino_tick_all (toutes les 5s) déclenche le bot
      -- Pas de pg_sleep pour éviter le statement timeout
      PERFORM public.domino_tick(_game_id);
    END IF;
  END IF;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.domino_set_ready(uuid, boolean) TO authenticated;

-- 2. _domino_bot_loop: réduire max_loops (15→8) et cap sleep (5s→1.5s)
CREATE OR REPLACE FUNCTION public._domino_bot_loop(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_is_bot    boolean;
  v_think_until timestamptz;
  v_sleep_sec numeric;
  v_max_loops int := 8;
  g_status    text;
  g_phase     text;
BEGIN
  LOOP
    EXIT WHEN v_max_loops <= 0;
    v_max_loops := v_max_loops - 1;

    SELECT status::text, state->>'phase' INTO g_status, g_phase
      FROM public.domino_games WHERE id = _game_id;
    EXIT WHEN g_status IS NULL OR g_status <> 'playing';
    EXIT WHEN g_phase NOT IN ('play', 'playing');
    EXIT WHEN g_phase IN ('reveal', 'break', 'dealing');

    SELECT COALESCE(dp.is_bot, false) INTO v_is_bot
      FROM public.domino_participants dp
      JOIN public.domino_games g ON g.id = dp.game_id
     WHERE dp.game_id = _game_id
       AND dp.slot = g.current_turn
       AND dp.forfeited = false;

    EXIT WHEN NOT COALESCE(v_is_bot, false);

    PERFORM public.domino_tick(_game_id);

    SELECT NULLIF(state->>'bot_think_until', '')::timestamptz INTO v_think_until
      FROM public.domino_games WHERE id = _game_id;

    IF v_think_until IS NOT NULL AND v_think_until > now() THEN
      v_sleep_sec := extract(epoch from (v_think_until - now()));
      IF v_sleep_sec > 0 AND v_sleep_sec <= 1.5 THEN
        PERFORM pg_sleep(v_sleep_sec);
      END IF;
    END IF;

    PERFORM public.domino_tick(_game_id);
  END LOOP;
END;
$function$;
