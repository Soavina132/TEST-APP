DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND pg_get_functiondef(p.oid) ILIKE '%gen_salt%'
  LOOP
    EXECUTE format('ALTER FUNCTION %I.%I(%s) SET search_path = public, extensions', r.nspname, r.proname, r.args);
  END LOOP;
END $$;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;