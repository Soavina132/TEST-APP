DROP POLICY IF EXISTS fanorona_games_select ON public.fanorona_games;
CREATE POLICY fanorona_games_select ON public.fanorona_games FOR SELECT USING (
  ((status = ANY (ARRAY['open'::game_status, 'playing'::game_status])) AND (is_private = false))
  OR (host_id = auth.uid())
  OR (EXISTS (SELECT 1 FROM public.fanorona_participants p WHERE p.game_id = fanorona_games.id AND p.user_id = auth.uid()))
  OR is_admin()
);