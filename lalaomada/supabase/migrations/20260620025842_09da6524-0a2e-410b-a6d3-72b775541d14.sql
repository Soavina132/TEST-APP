-- Fix gen_random_bytes not found by qualifying with extensions schema in draw RPCs
-- Recreate the two functions using extensions.gen_random_bytes

CREATE OR REPLACE FUNCTION public.chess_request_or_accept_draw(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_white uuid; v_black uuid; v_status text; v_offered uuid;
BEGIN
  SELECT white_player_id, black_player_id, status, draw_offered_by
    INTO v_white, v_black, v_status, v_offered
  FROM public.chess_games WHERE id = _game_id FOR UPDATE;
  IF v_status <> 'active' THEN RETURN; END IF;
  IF v_uid <> v_white AND v_uid <> v_black THEN RETURN; END IF;
  IF v_offered IS NULL THEN
    UPDATE public.chess_games SET draw_offered_by = v_uid, updated_at = now() WHERE id = _game_id;
  ELSIF v_offered <> v_uid THEN
    UPDATE public.chess_games SET status='finished', result='draw', draw_offered_by=NULL, finished_at=now(), updated_at=now() WHERE id=_game_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.fanorona_request_or_accept_draw(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_status text; v_offered uuid;
BEGIN
  SELECT status, draw_offered_by INTO v_status, v_offered FROM public.fanorona_games WHERE id=_game_id FOR UPDATE;
  IF v_status <> 'active' THEN RETURN; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.fanorona_participants WHERE game_id=_game_id AND user_id=v_uid) THEN RETURN; END IF;
  IF v_offered IS NULL THEN
    UPDATE public.fanorona_games SET draw_offered_by=v_uid, updated_at=now() WHERE id=_game_id;
  ELSIF v_offered <> v_uid THEN
    UPDATE public.fanorona_games SET status='finished', result='draw', draw_offered_by=NULL, finished_at=now(), updated_at=now() WHERE id=_game_id;
  END IF;
END;
$$;

-- Find every function that references gen_random_bytes and recreate-by-altering search_path to include extensions
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT n.nspname, p.proname, p.oid
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND pg_get_functiondef(p.oid) ILIKE '%gen_random_bytes%'
  LOOP
    EXECUTE format('ALTER FUNCTION %I.%I(%s) SET search_path = public, extensions',
      r.nspname, r.proname, pg_get_function_identity_arguments(r.oid));
  END LOOP;
END $$;