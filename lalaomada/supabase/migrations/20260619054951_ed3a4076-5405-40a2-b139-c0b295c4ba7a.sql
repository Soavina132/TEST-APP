CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.domino_tick_all()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
          state->>'phase' = 'break'
          AND NULLIF(state->>'break_until', '')::timestamptz <= now()
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
$$;

GRANT EXECUTE ON FUNCTION public.domino_tick_all() TO service_role;

DO $$
DECLARE
  j bigint;
BEGIN
  SELECT jobid INTO j FROM cron.job WHERE jobname = 'domino_tick_all';
  IF j IS NOT NULL THEN
    PERFORM cron.unschedule(j);
  END IF;
END
$$;

SELECT cron.schedule('domino_tick_all', '5 seconds', $$SELECT public.domino_tick_all();$$);