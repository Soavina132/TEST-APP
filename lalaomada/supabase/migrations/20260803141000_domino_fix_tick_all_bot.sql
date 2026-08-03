-- ─────────────────────────────────────────────────────────────────────────────
-- Fix : domino_tick_all inclut maintenant les jeux où bot_think_until est expiré
--        pour que le cron déclenche le bot rapidement même sans frontend ouvert.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.domino_tick_all()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  g_id uuid;
BEGIN
  FOR g_id IN
    SELECT id
    FROM public.domino_games
    WHERE status = 'playing'
      AND (
        (turn_deadline IS NOT NULL AND turn_deadline <= now())
        OR (
          state->>'phase' = 'reveal'
          AND NULLIF(state->>'reveal_until', '')::timestamptz <= now()
        )
        OR (
          state->>'phase' = 'break'
          AND NULLIF(state->>'break_until', '')::timestamptz <= now()
        )
        OR (
          state->>'phase' = 'dealing'
          AND NULLIF(state->>'deal_until', '')::timestamptz <= now()
        )
        OR (
          state->>'bot_think_until' IS NOT NULL
          AND NULLIF(state->>'bot_think_until', '')::timestamptz <= now()
        )
      )
  LOOP
    BEGIN
      PERFORM public.domino_tick(g_id);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
END
$function$;
