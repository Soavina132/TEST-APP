-- Safe, minimal directory listing for the "browse all players" DM picker.
-- profiles SELECT is restricted to self/admin (profiles_self_select), so the
-- client cannot query profiles directly to list other users. This RPC
-- exposes only the minimal safe fields needed to start a conversation,
-- excludes the caller and banned accounts, and supports server-side search.
CREATE OR REPLACE FUNCTION public.list_players_for_dm(_search text DEFAULT NULL, _limit int DEFAULT 50)
RETURNS TABLE (id uuid, pseudo text, avatar_url text, unique_code text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'auth'; END IF;
  RETURN QUERY
    SELECT p.id, p.pseudo, p.avatar_url, p.unique_code
    FROM public.profiles p
    WHERE p.id <> auth.uid()
      AND COALESCE(p.banned, FALSE) = FALSE
      AND (_search IS NULL OR _search = '' OR p.pseudo ILIKE '%' || _search || '%')
    ORDER BY p.pseudo ASC
    LIMIT LEAST(COALESCE(_limit, 50), 100);
END $$;

GRANT EXECUTE ON FUNCTION public.list_players_for_dm(text, int) TO authenticated;
