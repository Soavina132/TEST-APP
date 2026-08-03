CREATE OR REPLACE FUNCTION public._export_auth_dump(_table text)
RETURNS SETOF text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_cols text;
  v_vals text;
BEGIN
  IF _table NOT IN ('users','identities') THEN
    RAISE EXCEPTION 'unsupported table';
  END IF;

  SELECT string_agg(format('%I', column_name), ', ' ORDER BY ordinal_position),
         string_agg(format('quote_nullable(%I::text)', column_name), ' || '', '' || ' ORDER BY ordinal_position)
    INTO v_cols, v_vals
  FROM information_schema.columns
  WHERE table_schema = 'auth' AND table_name = _table AND is_generated = 'NEVER';

  RETURN QUERY EXECUTE format(
    'SELECT ''INSERT INTO auth.%I (%s) VALUES ('' || %s || '') ON CONFLICT DO NOTHING;'' FROM auth.%I',
    _table, v_cols, v_vals, _table
  );
END $$;

REVOKE ALL ON FUNCTION public._export_auth_dump(text) FROM PUBLIC, anon, authenticated;