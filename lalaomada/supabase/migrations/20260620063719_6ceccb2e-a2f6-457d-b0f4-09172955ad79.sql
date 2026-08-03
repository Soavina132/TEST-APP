-- Fix: gen_random_bytes not found when search_path is restricted to public.
-- Re-define fanorona_set_ready (and any other functions referencing gen_random_bytes)
-- to either qualify with extensions.gen_random_bytes OR set search_path = public, extensions.

-- 1) fanorona_set_ready: replace gen_random_bytes with extensions.gen_random_bytes
CREATE OR REPLACE FUNCTION public.fanorona_set_ready(_game_id uuid, _ready boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_uid uuid := auth.uid(); v_total int; v_ready int; v_status text;
        v_starter uuid; v_p1 uuid; v_p2 uuid; v_swap boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  UPDATE public.fanorona_participants SET ready = COALESCE(_ready, false)
    WHERE game_id = _game_id AND user_id = v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'not a participant'; END IF;
  SELECT status INTO v_status FROM public.fanorona_games WHERE id = _game_id;
  IF v_status <> 'open' THEN RETURN; END IF;
  SELECT count(*), count(*) FILTER (WHERE ready) INTO v_total, v_ready
    FROM public.fanorona_participants WHERE game_id = _game_id;
  IF v_total = 2 AND v_ready = 2 THEN
    SELECT user_id INTO v_p1 FROM public.fanorona_participants WHERE game_id=_game_id ORDER BY joined_at LIMIT 1;
    SELECT user_id INTO v_p2 FROM public.fanorona_participants WHERE game_id=_game_id AND user_id <> v_p1 LIMIT 1;
    v_swap := (get_byte(extensions.gen_random_bytes(1),0) % 2) = 1;
    v_starter := CASE WHEN v_swap THEN v_p2 ELSE v_p1 END;
    UPDATE public.fanorona_participants
       SET slot  = CASE WHEN user_id = v_starter THEN 0 ELSE 1 END,
           color = CASE WHEN user_id = v_starter THEN 'white' ELSE 'black' END
     WHERE game_id = _game_id;

    UPDATE public.fanorona_games
       SET status = 'playing', started_at = now(), current_turn = 0,
           state = jsonb_set(state, '{phase}', '"playing"'::jsonb),
           turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')),60) || ' seconds')::interval
     WHERE id = _game_id AND status = 'open';
  END IF;
END $$;

-- 2) Patch any other function in public that references gen_random_bytes:
-- add extensions to its search_path so the call resolves.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND pg_get_functiondef(p.oid) ILIKE '%gen_random_bytes%'
      AND p.proname <> 'fanorona_set_ready'
  LOOP
    EXECUTE format('ALTER FUNCTION %I.%I(%s) SET search_path = public, extensions',
                   r.nspname, r.proname, r.args);
  END LOOP;
END $$;

-- 3) Ensure pgcrypto is installed in the extensions schema
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;