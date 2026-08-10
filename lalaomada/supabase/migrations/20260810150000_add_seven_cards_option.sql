-- ═══ 7 Cartes (Miverim-bola) option for Rami ═══

-- 1. Add seven_cards column to rami_games
ALTER TABLE public.rami_games ADD COLUMN IF NOT EXISTS seven_cards boolean DEFAULT true;

-- 2. Update rami_create to accept _seven_cards parameter
-- (adds _seven_cards boolean DEFAULT true, stores in rami_games.seven_cards)

-- 3. Update rami_claim_seven to check the flag
-- (raises exception if seven_cards = false)
