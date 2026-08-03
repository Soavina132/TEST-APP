-- Migration: add badge column to game_configs + set default cover URLs

-- 1. Add badge column
ALTER TABLE public.game_configs
  ADD COLUMN IF NOT EXISTS badge TEXT DEFAULT NULL;

-- 2. Add constraint for valid values
ALTER TABLE public.game_configs
  DROP CONSTRAINT IF EXISTS game_configs_badge_check;
ALTER TABLE public.game_configs
  ADD CONSTRAINT game_configs_badge_check
    CHECK (badge IS NULL OR badge IN ('new', 'coming_soon', 'hot'));

-- 3. Set default cover URLs for each game (only if cover_url is currently empty/null)
UPDATE public.game_configs SET cover_url = '/covers/cover_ludo.png'     WHERE slug = 'ludo'     AND (cover_url IS NULL OR cover_url = '');
UPDATE public.game_configs SET cover_url = '/covers/cover_domino.png'   WHERE slug = 'domino'   AND (cover_url IS NULL OR cover_url = '');
UPDATE public.game_configs SET cover_url = '/covers/cover_fanorona.png' WHERE slug = 'fanorona' AND (cover_url IS NULL OR cover_url = '');
UPDATE public.game_configs SET cover_url = '/covers/cover_chess.png'    WHERE slug = 'chess'    AND (cover_url IS NULL OR cover_url = '');
UPDATE public.game_configs SET cover_url = '/covers/cover_rami.png'     WHERE slug = 'rami'     AND (cover_url IS NULL OR cover_url = '');
UPDATE public.game_configs SET cover_url = '/covers/cover_poker.png'    WHERE slug = 'poker'    AND (cover_url IS NULL OR cover_url = '');
