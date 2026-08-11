-- Fix: domino_tick_all didn't catch games where it's a bot's turn but bot_think_until is NULL
-- This caused the bot to be stuck for 30s (turn_deadline) instead of ~1s
CREATE OR REPLACE FUNCTION public.domino_tick_all()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $func$
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
        OR (
          -- Bot's turn but think timer not armed yet — pick up immediately
          state->>'bot_think_until' IS NULL
          AND EXISTS (
            SELECT 1 FROM public.domino_participants dp
            WHERE dp.game_id = domino_games.id
              AND dp.slot = domino_games.current_turn
              AND dp.is_bot = true
              AND dp.forfeited = false
          )
        )
      )
  LOOP
    BEGIN
      PERFORM public.domino_tick(g_id);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
END $func$;
