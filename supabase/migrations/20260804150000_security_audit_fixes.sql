-- ============================================================
-- SECURITY AUDIT FIXES — 2026-08-04
-- Corrige les vulnérabilités critiques identifiées lors de l'audit
-- ============================================================

-- ============================================================
-- 1. CRITIQUE : REVOKE anon/anonymous sur admin_record_login_attempt
--    N'importe qui (anon) pouvait verrouiller un compte admin
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.admin_record_login_attempt(uuid, boolean, text, inet, text) FROM anon, PUBLIC;

-- ============================================================
-- 2. CRITIQUE : REVOKE anon sur admin_check_lockout
--    Fuite d'information sur le statut admin/lockout d'un user
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.admin_check_lockout(uuid) FROM anon, PUBLIC;

-- ============================================================
-- 3. CRITIQUE : REVOKE authenticated sur run_finance_tests
--    La fonction crée des users de test dans auth.users
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.run_finance_tests() FROM authenticated, PUBLIC;
GRANT EXECUTE ON FUNCTION public.run_finance_tests() TO service_role;

-- ============================================================
-- 4. HAUT : REVOKE authenticated sur les fonctions tick/engine
--    Utilise DO block pour ne pas échouer si une fonction n'existe pas
-- ============================================================
DO $$
DECLARE r record;
  fns text[] := ARRAY[
    'chess_tick','chess_tick_all','fanorona_tick','fanorona_bot_play',
    'rami_tick','domino_tick','ludo_check_timeout','ludo_purge_unready_rooms',
    'cleanup_stale_open_games','tournament_engine','tournament_engine_all',
    'tournament_launch_pending_ludo','petanque_bot_step'
  ];
BEGIN
  FOR r IN
    SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) AS args
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = ANY(fns)
       AND p.prosecdef = true
  LOOP
    BEGIN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION public.%I(%s) FROM authenticated, anon, PUBLIC', r.proname, r.args);
      RAISE NOTICE 'Revoked on %', r.proname;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Skip %: %', r.proname, SQLERRM;
    END;
  END LOOP;
END $$;

-- ============================================================
-- 5. Sécurité : admin_check_lockout — recréer avec guard
-- ============================================================
CREATE OR REPLACE FUNCTION public.admin_check_lockout(_user_id uuid)
RETURNS TABLE(locked boolean, locked_until timestamptz, reason text)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public
AS $$
  SELECT
    (l.locked_until > now()) AS locked,
    l.locked_until,
    l.reason
  FROM public.admin_lockouts l
  WHERE l.user_id = _user_id
  UNION ALL
  SELECT false, NULL::timestamptz, NULL::text
  WHERE NOT EXISTS (SELECT 1 FROM public.admin_lockouts WHERE user_id = _user_id)
  LIMIT 1;
$$;
REVOKE EXECUTE ON FUNCTION public.admin_check_lockout(uuid) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_check_lockout(uuid) TO authenticated;

-- ============================================================
-- 6. admin_record_login_attempt : ajouter guard cross-user
-- ============================================================
CREATE OR REPLACE FUNCTION public.admin_record_login_attempt(
  _user_id uuid, _success boolean, _reason text, _ip inet, _ua text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  _recent_fails int;
  _lock_until timestamptz;
  _caller uuid := auth.uid();
BEGIN
  -- Si _user_id != _caller, doit être un admin
  IF _caller IS NOT NULL AND _caller <> _user_id THEN
    IF NOT public.has_role(_caller, 'admin') THEN
      RAISE EXCEPTION 'Not authorized';
    END IF;
  END IF;

  INSERT INTO public.admin_login_attempts(user_id, success, reason, ip, user_agent)
  VALUES (_user_id, _success, _reason, _ip, _ua);

  IF _success THEN
    DELETE FROM public.admin_lockouts WHERE user_id = _user_id;
    RETURN jsonb_build_object('locked', false);
  END IF;

  -- Only count fails for admin users
  IF NOT public.has_role(_user_id, 'admin') THEN
    RETURN jsonb_build_object('locked', false, 'admin', false);
  END IF;

  SELECT count(*) INTO _recent_fails
  FROM public.admin_login_attempts
  WHERE user_id = _user_id
    AND success = false
    AND created_at > now() - interval '10 minutes';

  IF _recent_fails >= 3 THEN
    _lock_until := now() + interval '1 hour';
    INSERT INTO public.admin_lockouts(user_id, locked_until, reason, fail_count)
    VALUES (_user_id, _lock_until, 'Trop de tentatives échouées', _recent_fails)
    ON CONFLICT (user_id) DO UPDATE
      SET locked_until = EXCLUDED.locked_until,
          reason = EXCLUDED.reason,
          fail_count = EXCLUDED.fail_count,
          updated_at = now();

    PERFORM public._admin_notify_others(
      'admin_locked_out',
      jsonb_build_object('user_id', _user_id, 'until', _lock_until, 'ip', _ip::text, 'ua', _ua)
    );

    RETURN jsonb_build_object('locked', true, 'until', _lock_until);
  END IF;

  RETURN jsonb_build_object('locked', false, 'fails', _recent_fails);
END $$;
REVOKE EXECUTE ON FUNCTION public.admin_record_login_attempt(uuid, boolean, text, inet, text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_record_login_attempt(uuid, boolean, text, inet, text) TO authenticated;

-- ============================================================
-- 7. MOYEN : RLS sur toutes les tables publiques manquantes
-- ============================================================
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT tablename FROM pg_tables
     WHERE schemaname = 'public'
       AND tablename NOT LIKE 'pg_%'
       AND tablename NOT LIKE '_dbg_%'
       AND NOT EXISTS (
         SELECT 1 FROM pg_class c
           JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'public' AND c.relname = pg_tables.tablename AND c.relrowsecurity = true
       )
  LOOP
    BEGIN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', r.tablename);
      RAISE NOTICE 'RLS enabled on %', r.tablename;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Skip RLS on %: %', r.tablename, SQLERRM;
    END;
  END LOOP;
END $$;

-- ============================================================
-- 8. MOYEN : Revoke anon execute sur les fonctions SECURITY DEFINER
--    Sauf les fonctions explicitement publiques
-- ============================================================
DO $$
DECLARE r record;
  keep text[] := ARRAY[
    'get_public_help_texts','get_legal_texts','request_password_reset',
    'get_public_profile','resolve_room_code','list_tournaments','list_live_games',
    'game_online_count','leaderboard_winners','get_referral_leaderboard','has_role','is_admin',
    'check_pseudo_available','check_pseudo_availability','hall_of_fame',
    'list_public_open_games','get_tournament_detail','tournament_state','tournament_pools_state',
    'list_players_for_dm','admin_check_lockout','admin_record_login_attempt',
    'request_withdrawal'
  ];
BEGIN
  FOR r IN
    SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) AS args
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.prosecdef
       AND has_function_privilege('anon', p.oid, 'EXECUTE')
       AND NOT (p.proname = ANY(keep))
       AND p.proname NOT LIKE '\_%'
       AND p.proname NOT LIKE 'admin\_%'
  LOOP
    BEGIN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION public.%I(%s) FROM anon, PUBLIC', r.proname, r.args);
      RAISE NOTICE 'Revoked anon execute on %', r.proname;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Skip %: %', r.proname, SQLERRM;
    END;
  END LOOP;
END $$;
