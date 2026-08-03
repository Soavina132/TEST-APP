
-- Helper functions to break recursion
CREATE OR REPLACE FUNCTION public._is_game_participant(_game_id uuid, _user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.ludo_participants WHERE game_id = _game_id AND user_id = _user_id)
$$;

CREATE OR REPLACE FUNCTION public._game_visible(_game_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.ludo_games g
    WHERE g.id = _game_id
      AND (g.status IN ('open','playing')
           OR g.host_id = auth.uid()
           OR public._is_game_participant(g.id, auth.uid())
           OR public.is_admin())
  )
$$;

DROP POLICY IF EXISTS games_select ON public.ludo_games;
CREATE POLICY games_select ON public.ludo_games FOR SELECT USING (
  status IN ('open','playing')
  OR host_id = auth.uid()
  OR public._is_game_participant(id, auth.uid())
  OR public.is_admin()
);

DROP POLICY IF EXISTS parts_select ON public.ludo_participants;
CREATE POLICY parts_select ON public.ludo_participants FOR SELECT USING (
  public._game_visible(game_id)
);
