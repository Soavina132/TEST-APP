-- ============================================
-- Security Hardening: Admin functions + fixes
-- ============================================

-- 1. Fix admin_add_bot: add is_admin() guard
CREATE OR REPLACE FUNCTION public.admin_add_bot(
  _game_id uuid, _bot_name text, _intelligence integer DEFAULT 70, _win_bias integer DEFAULT 0
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_game public.ludo_games%ROWTYPE;
  v_count INT;
  v_slot INT;
  v_color TEXT;
  v_colors TEXT[] := ARRAY['red','green','yellow','blue'];
  v_team INT;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;

  SELECT * INTO v_game FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF v_game.id IS NULL OR v_game.status NOT IN ('open','waiting') THEN
    RAISE EXCEPTION 'Partie non ouverte';
  END IF;

  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = _game_id;
  IF v_count >= v_game.max_players THEN
    RAISE EXCEPTION 'Partie pleine';
  END IF;

  v_slot := v_count;
  v_color := v_colors[(v_slot % 4) + 1];
  v_team := v_slot;

  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, team, is_bot, bot_name, bot_intelligence, bot_win_bias)
  VALUES (_game_id, gen_random_uuid(), v_slot, v_color, v_team, true, _bot_name, _intelligence, _win_bias);
END $function$;

-- 2. Revoke EXECUTE from anon on all admin_ functions (defense in depth)
--    Even though they have is_admin() guards, anon should never call admin functions
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
    AND p.proname LIKE 'admin%'
    AND has_function_privilege('anon', p.oid, 'EXECUTE') = true
  LOOP
    -- Need to strip param names from identity arguments
    EXECUTE format('REVOKE EXECUTE ON FUNCTION public.%I(%s) FROM anon',
      r.proname,
      regexp_replace(r.args, '\b_\w+\s+', '', 'g')
    );
  END LOOP;
END $$;

-- 3. Revoke anon on chess_claim_win and claim_daily_bonus (they have guards but anon shouldn't call them)
REVOKE EXECUTE ON FUNCTION public.chess_claim_win(uuid, uuid, boolean) FROM anon;
REVOKE EXECUTE ON FUNCTION public.claim_daily_bonus() FROM anon;

-- 4. Revoke anon on check_pseudo_availability / check_pseudo_available (info leak)
REVOKE EXECUTE ON FUNCTION public.check_pseudo_availability(text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.check_pseudo_available(text) FROM anon;
