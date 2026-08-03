DROP FUNCTION IF EXISTS public.game_online_count(text);

CREATE TABLE IF NOT EXISTS public.poker_games (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  status text NOT NULL DEFAULT 'waiting',
  stake numeric NOT NULL DEFAULT 0,
  commission_pct numeric NOT NULL DEFAULT 10,
  max_players int NOT NULL DEFAULT 6,
  is_private boolean NOT NULL DEFAULT false,
  room_code text,
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  pot numeric NOT NULL DEFAULT 0,
  state jsonb NOT NULL DEFAULT '{}',
  phase text NOT NULL DEFAULT 'waiting',
  hand_number int NOT NULL DEFAULT 0,
  community_cards int[] NOT NULL DEFAULT '{}',
  current_player uuid,
  turn_deadline timestamptz,
  winner_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  finished_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS poker_games_status ON public.poker_games(status);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.poker_games TO authenticated;
GRANT ALL ON public.poker_games TO service_role;
GRANT SELECT ON public.poker_games TO anon;

CREATE TABLE IF NOT EXISTS public.poker_players (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id uuid NOT NULL REFERENCES public.poker_games(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  seat int NOT NULL,
  chips numeric NOT NULL DEFAULT 0,
  bet_round numeric NOT NULL DEFAULT 0,
  total_bet numeric NOT NULL DEFAULT 0,
  hole_cards int[] NOT NULL DEFAULT '{}',
  status text NOT NULL DEFAULT 'waiting',
  is_ready boolean NOT NULL DEFAULT false,
  last_action text,
  hand_result jsonb,
  joined_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(game_id, seat),
  UNIQUE(game_id, user_id)
);
CREATE INDEX IF NOT EXISTS poker_players_game ON public.poker_players(game_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.poker_players TO authenticated;
GRANT ALL ON public.poker_players TO service_role;
GRANT SELECT ON public.poker_players TO anon;

ALTER TABLE public.poker_games ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.poker_players ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "poker_games_read" ON public.poker_games;
DROP POLICY IF EXISTS "poker_players_read" ON public.poker_players;
CREATE POLICY "poker_games_read" ON public.poker_games FOR SELECT USING (true);
CREATE POLICY "poker_players_read" ON public.poker_players FOR SELECT USING (true);

CREATE OR REPLACE FUNCTION public.game_online_count(_slug text)
RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT CASE _slug
    WHEN 'ludo'     THEN (SELECT count(*) FROM public.ludo_games     WHERE status::text IN ('waiting','playing'))
    WHEN 'domino'   THEN (SELECT count(*) FROM public.domino_games   WHERE status::text IN ('waiting','playing'))
    WHEN 'fanorona' THEN (SELECT count(*) FROM public.fanorona_games WHERE status::text IN ('waiting','playing'))
    WHEN 'chess'    THEN (SELECT count(*) FROM public.chess_games    WHERE status::text IN ('waiting','playing'))
    WHEN 'rami'     THEN (SELECT count(*) FROM public.rami_games     WHERE status::text IN ('waiting','playing'))
    WHEN 'poker'    THEN (SELECT count(*) FROM public.poker_games    WHERE status IN ('waiting','playing'))
    ELSE 0
  END;
$$;
GRANT EXECUTE ON FUNCTION public.game_online_count(text) TO authenticated, anon;