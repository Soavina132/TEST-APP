CREATE OR REPLACE FUNCTION public.list_players_for_dm(_search text DEFAULT NULL, _limit int DEFAULT 50)
RETURNS TABLE(id uuid, pseudo text, avatar_url text, unique_code text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='public' AS $$
  SELECT p.id, p.pseudo, p.avatar_url, p.unique_code
  FROM public.profiles p
  WHERE p.id <> auth.uid()
    AND (_search IS NULL OR _search = '' 
         OR p.pseudo ILIKE '%'||_search||'%' 
         OR p.unique_code ILIKE '%'||_search||'%')
  ORDER BY p.pseudo ASC
  LIMIT COALESCE(_limit, 50)
$$;
GRANT EXECUTE ON FUNCTION public.list_players_for_dm(text,int) TO authenticated;