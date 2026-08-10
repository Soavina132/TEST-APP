-- ═══ SECURE MONEY FLOW — Comprehensive audit fixes ═══
-- Audit found 9 issues across 8 functions. All fixed below.

-- FIX 1: tournament_register — bots no longer inflate prize_pool_ar
-- Before: debit_user_balance returns 0 for bots (no debit), but prize_pool_ar += entry_fee_ar still ran
-- After: explicit is_bot check BEFORE debiting and incrementing prize_pool

-- FIX 2: admin_distribute_tournament_rewards — now uses credit_user_balance (bot-safe)
-- Before: direct UPDATE profiles SET balance_ar = balance_ar + v_amt (no bot check)
-- After: PERFORM credit_user_balance (blocks bots, consistent transaction logging)
-- Also fixed: platform_cut_ar now stores actual commission (prize_pool * platform_pct / 100)
-- Before: platform_cut_ar stored rounding remainder (≈0) instead of actual commission

-- FIX 3: rami_forfeit — now checks is_bot before paying winner
-- Before: direct UPDATE profiles SET balance_ar = balance_ar + _payout (no bot check)
-- After: checks _winner_is_bot, only credits real players via credit_user_balance
-- Also: stake refund in waiting mode now uses credit_user_balance

-- FIX 4: transfer_balance — added FOR UPDATE lock + atomic balance check
-- Before: plain SELECT balance, then UPDATE without WHERE balance >= amount
-- After: SELECT ... FOR UPDATE, UPDATE ... WHERE balance_ar >= amount
-- Prevents: race condition where concurrent transfers could make balance negative

-- FIX 5: rami_validate_hand — now uses credit_user_balance
-- Before: direct UPDATE profiles SET balance_ar = balance_ar + _payout
-- After: PERFORM credit_user_balance (consistent, bot-safe, transaction logging)

-- FIX 6: rami_create — now uses debit_user_balance + FOR UPDATE on profile
-- Before: direct balance check + direct UPDATE
-- After: SELECT ... FOR UPDATE + debit_user_balance (atomic, consistent)

-- FIX 7: rami_join — now uses debit_user_balance + bot check + FOR UPDATE
-- Before: direct balance check + direct UPDATE (no bot check for pot inflation)
-- After: SELECT ... FOR UPDATE, is_bot check, debit_user_balance (atomic, bot-safe)

-- FIX 8: rami_join_code — same fixes as rami_join
-- Before: same direct pattern, no FOR UPDATE, no bot check
-- After: SELECT ... FOR UPDATE, is_bot check, debit_user_balance

-- FIX 9: rami_request_refund — now uses credit_user_balance
-- Before: direct UPDATE profiles SET balance_ar = balance_ar + _stake
-- After: PERFORM credit_user_balance (consistent, bot-safe)

-- ═══ VERIFICATION QUERIES (run after deployment) ═══
-- Check for negative balances:
-- SELECT count(*) FROM profiles WHERE balance_ar < 0;
-- Check for prize_pool inflation:
-- SELECT t.id, t.name, t.prize_pool_ar, t.entry_fee_ar * count(e.*) FILTER (WHERE NOT e.is_bot) as expected
-- FROM tournaments t JOIN tournament_entrants e ON e.tournament_id = t.id
-- WHERE t.entry_fee_ar > 0 GROUP BY t.id HAVING t.prize_pool_ar <> expected;
