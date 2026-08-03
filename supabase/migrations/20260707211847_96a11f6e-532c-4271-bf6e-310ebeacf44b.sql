
-- retry with DROP first for return type change
ALTER TABLE public.achievements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "achievements_public_read" ON public.achievements;
CREATE POLICY "achievements_public_read" ON public.achievements FOR SELECT TO anon, authenticated USING (true);

ALTER TABLE public.referral_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "referral_settings_admin_all" ON public.referral_settings;
CREATE POLICY "referral_settings_admin_all" ON public.referral_settings FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "billiard_games_update" ON public.billiard_games;
CREATE POLICY "billiard_games_update" ON public.billiard_games FOR UPDATE TO authenticated
  USING (
    host_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.billiard_participants p WHERE p.game_id = billiard_games.id AND p.user_id = auth.uid())
    OR public.is_admin()
  )
  WITH CHECK (
    host_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.billiard_participants p WHERE p.game_id = billiard_games.id AND p.user_id = auth.uid())
    OR public.is_admin()
  );

DROP POLICY IF EXISTS "billiard_participants_update" ON public.billiard_participants;
CREATE POLICY "billiard_participants_update" ON public.billiard_participants FOR UPDATE TO authenticated
  USING (user_id = auth.uid() OR public.is_admin())
  WITH CHECK (user_id = auth.uid() OR public.is_admin());

-- poker_players hole_cards protection
DROP POLICY IF EXISTS "poker_players_read" ON public.poker_players;
CREATE POLICY "poker_players_read" ON public.poker_players FOR SELECT TO authenticated USING (true);

REVOKE SELECT ON public.poker_players FROM anon, authenticated;
GRANT SELECT (id, game_id, user_id, seat, chips, bet_round, total_bet, status, is_ready, last_action, hand_result, joined_at)
  ON public.poker_players TO authenticated;
GRANT SELECT (hole_cards) ON public.poker_players TO service_role;

CREATE OR REPLACE FUNCTION public.poker_my_hole_cards(_game_id uuid)
RETURNS TABLE (user_id uuid, hole_cards int[])
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT pp.user_id, pp.hole_cards
    FROM public.poker_players pp
   WHERE pp.game_id = _game_id
     AND (pp.user_id = auth.uid()
          OR public.is_admin()
          OR EXISTS (SELECT 1 FROM public.poker_games g WHERE g.id = _game_id AND g.status = 'finished'));
$$;
REVOKE EXECUTE ON FUNCTION public.poker_my_hole_cards(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.poker_my_hole_cards(uuid) TO authenticated;

-- Password reset: drop first (return type change), recreate without leaking the code
DROP FUNCTION IF EXISTS public.request_password_reset(text, text);
CREATE FUNCTION public.request_password_reset(_contact text, _type text)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid; v_code text; v_norm text;
BEGIN
  IF _type NOT IN ('email','phone') THEN RAISE EXCEPTION 'Type invalide'; END IF;
  v_norm := trim(_contact);
  IF _type = 'email' THEN v_norm := lower(v_norm); END IF;
  IF length(v_norm) < 3 THEN RAISE EXCEPTION 'Contact invalide'; END IF;

  IF _type = 'email' THEN
    SELECT id INTO v_uid FROM public.profiles WHERE lower(email) = v_norm LIMIT 1;
  ELSE
    SELECT id INTO v_uid FROM public.profiles WHERE phone = v_norm LIMIT 1;
  END IF;

  IF v_uid IS NULL THEN
    RETURN true;
  END IF;

  v_code := lpad((floor(random()*1000000))::int::text, 6, '0');
  INSERT INTO public.password_reset_requests(user_id, contact, contact_type, code, status)
  VALUES (v_uid, v_norm, _type, v_code, 'pending');
  RETURN true;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.request_password_reset(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_password_reset(text, text) TO anon, authenticated;

ALTER VIEW public.v_player_stats SET (security_invoker = true);
ALTER VIEW public.v_referral_stats SET (security_invoker = true);

DO $$
DECLARE r record;
  keep text[] := ARRAY[
    'get_public_help_texts','get_legal_texts','request_password_reset',
    'get_public_profile','resolve_room_code','list_tournaments','list_live_games',
    'game_online_count','leaderboard_winners','get_referral_leaderboard','has_role','is_admin'
  ];
BEGIN
  FOR r IN
    SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) AS args
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.prosecdef
       AND has_function_privilege('anon', p.oid, 'EXECUTE')
       AND NOT (p.proname = ANY(keep))
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION public.%I(%s) FROM anon, PUBLIC', r.proname, r.args);
  END LOOP;
END $$;
