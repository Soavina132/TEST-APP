CREATE TABLE IF NOT EXISTS public._dbg_domino(id serial primary key, msg text, at timestamptz default now());
GRANT ALL ON public._dbg_domino TO service_role;
GRANT ALL ON SEQUENCE public._dbg_domino_id_seq TO service_role;

DO $$
DECLARE r record; before_state jsonb; after_state jsonb;
BEGIN
  SELECT state INTO before_state FROM public.domino_games WHERE id='f184c729-c62b-471f-a1ed-db2cb9c044c6';
  INSERT INTO public._dbg_domino(msg) VALUES ('before ' || (before_state->>'bot_think_until'));
  BEGIN
    PERFORM public._domino_autoplay_bots('f184c729-c62b-471f-a1ed-db2cb9c044c6');
    INSERT INTO public._dbg_domino(msg) VALUES ('autoplay ok');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public._dbg_domino(msg) VALUES ('autoplay ERR ' || SQLERRM || ' / ' || SQLSTATE);
  END;
  SELECT state INTO after_state FROM public.domino_games WHERE id='f184c729-c62b-471f-a1ed-db2cb9c044c6';
  INSERT INTO public._dbg_domino(msg) VALUES ('after hand1=' || COALESCE((after_state->'hands'->'1')::text,'null') || ' phase=' || (after_state->>'phase'));
END $$;