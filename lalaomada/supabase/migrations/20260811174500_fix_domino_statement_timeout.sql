-- ============================================================
-- Fix: statement timeout sur domino_play
-- Cause: _domino_bot_loop avait des pg_sleep qui bloquaient l'API
-- Solution: _domino_bot_loop arme juste le timer, le cron (5s) joue le bot
-- ============================================================

CREATE OR REPLACE FUNCTION public._domino_bot_loop(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_is_bot    boolean;
  g_status    text;
  g_phase     text;
BEGIN
  -- Arme juste le think timer, ne dort pas
  -- Le cron domino_tick_all (toutes les 5s) déclenche le coup du bot
  SELECT status::text, state->>'phase' INTO g_status, g_phase
    FROM public.domino_games WHERE id = _game_id;

  IF g_status IS NULL OR g_status <> 'playing' THEN RETURN; END IF;
  IF g_phase NOT IN ('play', 'playing') THEN RETURN; END IF;
  IF g_phase IN ('reveal', 'break', 'dealing') THEN RETURN; END IF;

  SELECT COALESCE(dp.is_bot, false) INTO v_is_bot
    FROM public.domino_participants dp
    JOIN public.domino_games g ON g.id = dp.game_id
   WHERE dp.game_id = _game_id
     AND dp.slot = g.current_turn
     AND dp.forfeited = false;

  IF COALESCE(v_is_bot, false) THEN
    PERFORM public.domino_tick(_game_id);
  END IF;
END;
$function$;
