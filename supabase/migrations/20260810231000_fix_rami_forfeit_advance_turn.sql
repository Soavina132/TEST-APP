-- ═══ Fix rami_forfeit: advance turn when quitter is the current player ═══
-- Before: if you quit during your turn, the bot had to wait 120s (turn deadline)
--         before it could play. The game appeared "stuck".
-- After:  the turn advances immediately to the next non-forfeited player,
--         and the bot think timer is armed so the bot plays within 1-2s.
--
-- Also fixes: winner_is_bot check now uses rami_participants.is_bot
--            (bots have user_id=NULL, so checking profiles.is_bot was wrong)

SELECT 1; -- fixes were deployed directly via Supabase Management API
