ALTER TABLE public.chess_games
  ADD COLUMN IF NOT EXISTS white_is_bot boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS black_is_bot boolean NOT NULL DEFAULT false;

UPDATE public.chess_games
SET white_is_bot = false
WHERE white_is_bot IS NULL;

UPDATE public.chess_games
SET black_is_bot = false
WHERE black_is_bot IS NULL;