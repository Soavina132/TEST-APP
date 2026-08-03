-- Set both roll and move delays to 2 seconds (simplified: single threshold)
CREATE OR REPLACE FUNCTION public.ludo_tick_all()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  g_id UUID;
  v_slot INT;
  v_isbot BOOLEAN;
  v_started TIMESTAMPTZ;
  st JSONB;
BEGIN
  FOR g_id IN SELECT id FROM public.ludo_games WHERE status='playing' LOOP
    BEGIN
      PERFORM public.ludo_check_timeout(g_id);
      SELECT state INTO st FROM public.ludo_games WHERE id=g_id;
      IF st IS NULL THEN CONTINUE; END IF;
      v_slot := (st->>'turn_slot')::INT;
      SELECT is_bot INTO v_isbot FROM public.ludo_participants
        WHERE game_id=g_id AND slot=v_slot;
      IF v_isbot THEN
        v_started := (st->>'turn_started_at')::TIMESTAMPTZ;
        IF now() - v_started >= interval '2 seconds' THEN
          PERFORM public.ludo_bot_play(g_id);
        END IF;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
END $function$;
