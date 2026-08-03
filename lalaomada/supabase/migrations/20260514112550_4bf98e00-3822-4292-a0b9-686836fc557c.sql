-- Enable pg_cron for autonomous server-side bot/timer ticks
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

-- Master tick: process every active game (timeouts + bot turns) without any client
CREATE OR REPLACE FUNCTION public.ludo_tick_all()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE g_id UUID; v_slot INT; v_isbot BOOLEAN; v_started TIMESTAMPTZ; st JSONB;
BEGIN
  FOR g_id IN SELECT id FROM public.ludo_games WHERE status='playing' LOOP
    BEGIN
      -- Auto-forfeit / pass on 30s timeout (server-authoritative)
      PERFORM public.ludo_check_timeout(g_id);

      -- After potential timeout, refetch turn
      SELECT state INTO st FROM public.ludo_games WHERE id=g_id;
      IF st IS NULL THEN CONTINUE; END IF;
      v_slot := (st->>'turn_slot')::INT;
      SELECT is_bot INTO v_isbot FROM public.ludo_participants
        WHERE game_id=g_id AND slot=v_slot;

      -- Bot autonomous play (no client required)
      IF v_isbot THEN
        PERFORM public.ludo_bot_play(g_id);
        -- If bot got bonus turn (6/capture/home), play again
        SELECT state INTO st FROM public.ludo_games WHERE id=g_id;
        IF st IS NOT NULL AND (st->>'must_move')::BOOLEAN = false
           AND (st->>'turn_slot')::INT = v_slot THEN
          PERFORM public.ludo_bot_play(g_id);
        END IF;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- swallow per-game errors so one bad game doesn't kill the tick
      NULL;
    END;
  END LOOP;
END $$;

-- Unschedule prior job if exists, then schedule every 5 seconds
DO $$
DECLARE j BIGINT;
BEGIN
  SELECT jobid INTO j FROM cron.job WHERE jobname='ludo_tick_all';
  IF j IS NOT NULL THEN PERFORM cron.unschedule(j); END IF;
END $$;

SELECT cron.schedule('ludo_tick_all', '5 seconds', $$SELECT public.ludo_tick_all();$$);