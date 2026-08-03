DO $$
DECLARE r record; err text;
BEGIN
  FOR r IN SELECT id FROM public.domino_games WHERE status='playing' AND EXISTS (SELECT 1 FROM public.domino_participants p WHERE p.game_id=domino_games.id AND p.is_bot=true AND p.forfeited=false) LOOP
    BEGIN
      PERFORM public._domino_bot_step(r.id);
      RAISE NOTICE 'stepped %', r.id;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'game % err: % (%)', r.id, SQLERRM, SQLSTATE;
    END;
  END LOOP;
END $$;