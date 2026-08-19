-- ============================================================
-- FIX 1: LUDO — ludo_tick_all() n'est jamais appelée par tick_all_games()
--        → les bots ne jouent pas, les timeouts ne marchent pas
-- FIX 2: DOMINO — _domino_payout n'existe pas (appelée par _domino_end_round)
--        → erreur "function public._domino_payout(uuid, integer) does not exist"
-- ============================================================

-- ═══ FIX 1: Add Ludo to _auto_advance_overdue_turns ═══
CREATE OR REPLACE FUNCTION public._auto_advance_overdue_turns()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r record;
  v_g chess_games%ROWTYPE;
  v_elapsed_ms int;
  v_remaining int;
BEGIN
  -- Fanorona turn deadlines
  FOR r IN SELECT id FROM public.fanorona_games
           WHERE status='playing' AND paused = FALSE AND turn_deadline IS NOT NULL AND turn_deadline < now()
  LOOP PERFORM public.fanorona_tick(r.id); END LOOP;

  -- Fanorona global timeout
  FOR r IN SELECT id FROM public.fanorona_games
           WHERE status='playing' AND game_deadline IS NOT NULL AND game_deadline < now()
  LOOP PERFORM public.fanorona_check_global_timeout(r.id); END LOOP;

  -- Chess turn deadlines (per-move timer)
  FOR r IN SELECT id FROM public.chess_games
           WHERE status='playing' AND paused = FALSE AND turn_deadline IS NOT NULL AND turn_deadline < now()
  LOOP PERFORM public.chess_tick(r.id); END LOOP;

  -- Chess clock timeout
  FOR r IN SELECT id FROM public.chess_games
           WHERE status='playing'
             AND paused = FALSE
             AND time_control_min > 0
  LOOP
    SELECT * INTO v_g FROM public.chess_games WHERE id = r.id FOR UPDATE;
    IF v_g.id IS NULL OR v_g.status <> 'playing' OR COALESCE(v_g.paused, false) THEN CONTINUE; END IF;

    v_elapsed_ms := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (now() - COALESCE(v_g.last_move_at, v_g.started_at, now()))) * 1000)::int);

    IF v_g.turn = 'w' THEN
      v_remaining := v_g.white_time_ms - v_elapsed_ms;
    ELSE
      v_remaining := v_g.black_time_ms - v_elapsed_ms;
    END IF;

    IF v_remaining <= 0 THEN
      PERFORM public.chess_auto_timeout(r.id);
    END IF;
  END LOOP;

  -- Chess global game deadline
  FOR r IN SELECT id FROM public.chess_games
           WHERE status='playing' AND game_deadline IS NOT NULL AND game_deadline < now()
  LOOP PERFORM public.chess_check_global_timeout(r.id); END LOOP;

  -- Domino turn deadlines
  FOR r IN SELECT id FROM public.domino_games
           WHERE status='playing' AND paused = FALSE AND turn_deadline IS NOT NULL AND turn_deadline < now()
  LOOP PERFORM public.domino_tick(r.id); END LOOP;

  -- Rami turn deadlines
  FOR r IN SELECT id FROM public.rami_games
           WHERE status='playing' AND paused = FALSE AND turn_deadline IS NOT NULL AND turn_deadline < now()
  LOOP PERFORM public.rami_tick(r.id); END LOOP;

  -- LUDO: bot play + timeout + auto-move + stalemate detection
  -- This was MISSING — ludo_tick_all() was never called!
  PERFORM public.ludo_tick_all();
END $$;

GRANT EXECUTE ON FUNCTION public._auto_advance_overdue_turns() TO authenticated, anon, service_role;

-- ═══ FIX 2: Create _domino_payout (called by _domino_end_round) ═══
-- _domino_end_round already sets status='finished' and winner_id before calling this,
-- so _domino_payout ONLY handles the money transfer (no status update).
-- _domino_finalize can't be used here because it returns early if status='finished'.
CREATE OR REPLACE FUNCTION public._domino_payout(_game_id uuid, _winner_slot integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $func$
DECLARE
  g record;
  winner_uid uuid;
  v_is_bot boolean := false;
  payout numeric;
  v_referrer uuid;
  v_ref_pct numeric;
  v_ref_amount numeric;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL THEN RETURN; END IF;

  -- Lookup winner
  SELECT user_id, COALESCE(is_bot, false) INTO winner_uid, v_is_bot
  FROM public.domino_participants
  WHERE game_id = _game_id AND slot = _winner_slot;

  payout := g.pot * (100 - g.commission_pct) / 100.0;

  -- Award pot to winner (skip if bot — no profile)
  IF winner_uid IS NOT NULL AND NOT v_is_bot THEN
    UPDATE public.profiles SET balance_ar = balance_ar + payout WHERE id = winner_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (winner_uid, 'domino_win', payout, _game_id, 'Gain domino');

    -- Referral commission on win (one-time per game)
    SELECT referred_by INTO v_referrer FROM public.profiles WHERE id = winner_uid;
    IF v_referrer IS NOT NULL THEN
      SELECT referral_pct INTO v_ref_pct FROM public.app_settings WHERE id = 1;
      v_ref_amount := payout * COALESCE(v_ref_pct, 0) / 100.0;
      IF v_ref_amount > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + v_ref_amount WHERE id = v_referrer;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (v_referrer, 'referral', v_ref_amount, _game_id, 'Commission parrainage domino');
      END IF;
    END IF;
  END IF;
END;
$func$;

REVOKE ALL ON FUNCTION public._domino_payout(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._domino_payout(uuid, integer) TO authenticated, service_role;
