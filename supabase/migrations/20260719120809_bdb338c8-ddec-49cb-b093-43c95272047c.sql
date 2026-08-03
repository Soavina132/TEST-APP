
ALTER TABLE public.chess_games ADD COLUMN IF NOT EXISTS game_deadline timestamptz;
