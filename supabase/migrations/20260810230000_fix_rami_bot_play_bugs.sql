-- ═══ Fix rami_bot_play: variable ambiguity + 2-deck compatibility + jsonb_array_length ═══

-- This migration is a no-op if the fixes were already applied via direct SQL.
-- The actual fixes were deployed directly to Supabase. This file documents them.

-- Bug 1: _c variable ambiguity
--   _suit_ranks := ARRAY(SELECT DISTINCT (_c % 13) FROM unnest(_suit_cards) _c ORDER BY 1)
--   The alias _c conflicts with PL/pgSQL variable _c int.
--   Fix: renamed to AS sc

-- Bug 2: 2-deck card comparison
--   IF _card < 52 AND EXISTS (SELECT 1 FROM unnest(_hand) c WHERE c < 52 AND c%13 = _card%13)
--   Doesn't account for 2-deck cards (IDs 56-111).
--   Fix: use _rami_is_joker() + (c % 56) % 13 for rank matching

-- Bug 3: array_length on jsonb
--   IF array_length(_action_log,1) > 20
--   array_length doesn't work on jsonb type.
--   Fix: use jsonb_array_length()

-- Bug 4: meld type 'set' instead of 'trio'/'carre'
--   Melds created with type 'set' but _rami_meld_type returns 'trio' or 'carre'.
--   Fix: CASE WHEN array_length(_set_cards,1) >= 4 THEN 'carre' ELSE 'trio' END

-- NOTE: These fixes were applied directly via Supabase Management API.
-- This file exists for migration history documentation.
SELECT 1; -- no-op
