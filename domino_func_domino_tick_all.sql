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
    SELECT g.id
      FROM public.domino_games g
     WHERE g.status = 'playing'
       AND (
         (g.turn_deadline IS NOT NULL AND g.turn_deadline <= now())
         OR (g.state->>'phase' = 'dealing' AND COALESCE(NULLIF(g.state->>'deal_until','')::timestamptz, now()) <= now())
         OR (g.state->>'phase' = 'reveal'  AND NULLIF(g.state->>'reveal_until','')::timestamptz <= now())
         OR (g.state->>'phase' = 'break'   AND NULLIF(g.state->>'break_until','')::timestamptz <= now())
         OR (
           EXISTS (
             SELECT 1
               FROM public.domino_participants p
              WHERE p.game_id = g.id
                AND p.slot = g.current_turn
                AND p.forfeited = false
                AND p.is_bot = true
           )
           AND (
             NULLIF(g.state->>'bot_think_until','')::timestamptz IS NULL
             OR NULLIF(g.state->>'bot_think_until','')::timestamptz <= now()
             OR COALESCE(NULLIF(g.state->>'bot_locked_slot','null')::int, -1) IS DISTINCT FROM g.current_turn
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
END;
$function$
