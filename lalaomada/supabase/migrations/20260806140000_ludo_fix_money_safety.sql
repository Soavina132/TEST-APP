-- ============================================================================
-- Fix Ludo: 5 CRITICAL bugs affecting money safety
--   5. No house_ledger trigger on ludo_games (platform can't track revenue)
--   6. _ludo_finish_team rounding differs from finish_game (platform loses money)
--   7. Pot money untracked when bot wins / no humans remain
--   8. Forfeited host can receive payout (money theft)
--   9. finish_game doesn't check forfeited=FALSE for winner validation
-- ============================================================================

-- ── Bug 5+7: Create house ledger trigger for ludo_games ───────────────────
-- Logs commission (human wins) or house_win (bot wins / no winner)
-- Credits unclaimed pot to house_balance when winner is NULL
CREATE OR REPLACE FUNCTION public._log_ludo_house_on_finish()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_pot numeric := COALESCE(NEW.pot, 0);
  v_pct numeric := COALESCE(NEW.commission_pct, 10);
  v_winner uuid := NULLIF(NEW.winner_id, ''::text);
  v_commission numeric;
  v_is_bot boolean := false;
BEGIN
  -- Only when transitioning to 'finished'
  IF NEW.status IS DISTINCT FROM 'finished' THEN RETURN NEW; END IF;
  IF OLD.status = 'finished' THEN RETURN NEW; END IF;
  IF v_pot IS NULL OR v_pot <= 0 THEN RETURN NEW; END IF;

  IF v_winner IS NULL THEN
    -- No winner: bot won or game force-ended → platform keeps the pot
    INSERT INTO public.house_ledger(game_type, game_id, entry_type, amount, pot, commission_pct, winner_id, note)
    VALUES ('ludo', NEW.id, 'house_win', v_pot, v_pot, v_pct, NULL,
            'Gain maison — victoire bot ou partie sans gagnant');
    RETURN NEW;
  END IF;

  -- Check if winner is a bot (bots have is_bot=true in ludo_participants, not profiles)
  SELECT COALESCE(is_bot, false) INTO v_is_bot 
  FROM public.ludo_participants 
  WHERE game_id = NEW.id AND user_id = v_winner LIMIT 1;

  IF v_is_bot THEN
    -- Bot won (shouldn't normally happen, but safety net)
    INSERT INTO public.house_ledger(game_type, game_id, entry_type, amount, pot, commission_pct, winner_id, note)
    VALUES ('ludo', NEW.id, 'house_win', v_pot, v_pot, v_pct, v_winner,
            'Gain maison — victoire bot');
  ELSE
    -- Human won: log commission
    v_commission := round(v_pot * v_pct / 100.0, 2);
    IF v_commission > 0 THEN
      INSERT INTO public.house_ledger(game_type, game_id, entry_type, amount, pot, commission_pct, winner_id, note)
      VALUES ('ludo', NEW.id, 'commission', v_commission, v_pot, v_pct, v_winner,
              'Commission ' || v_pct || '% sur pot Ludo');
    END IF;
  END IF;

  RETURN NEW;
END $function$;

-- Drop old trigger if exists, then create
DROP TRIGGER IF EXISTS trg_ludo_house_on_finish ON public.ludo_games;
CREATE TRIGGER trg_ludo_house_on_finish
  AFTER UPDATE ON public.ludo_games
  FOR EACH ROW
  EXECUTE FUNCTION public._log_ludo_house_on_finish();

-- ── Bug 6: Fix rounding in _ludo_finish_team to match finish_game ───────────
-- OLD: v_comm = round(pot * commission / 100, 0); v_payout = pot - v_comm
--      (rounds to 0 decimals, can overpay)
-- NEW: v_payout = pot * (100 - commission) / 100.0 (exact, same as finish_game)
CREATE OR REPLACE FUNCTION public._ludo_finish_team(_game_id uuid, _winner_id uuid, _team int)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_game public.ludo_games%ROWTYPE;
  v_payout numeric;
  v_half numeric;
  v_mate uuid;
  v_referrer uuid;
  v_ref_pct numeric;
  v_ref_amount numeric;
BEGIN
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.status = 'finished' THEN RETURN; END IF;

  -- Same formula as finish_game (no rounding, exact division)
  v_payout := v_game.pot * (100 - v_game.commission_pct) / 100.0;
  v_half := v_payout / 2.0;

  SELECT user_id INTO v_mate FROM public.ludo_participants
    WHERE game_id=_game_id AND team=_team AND user_id <> _winner_id
    AND NOT is_bot AND forfeited=FALSE LIMIT 1;

  UPDATE public.ludo_games SET status='finished', winner_id=_winner_id, finished_at=now()
    WHERE id=_game_id;

  IF v_mate IS NOT NULL THEN
    -- Two human teammates: each gets half (exact, no rounding)
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) + v_half WHERE id=_winner_id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (_winner_id,'win',v_half,_game_id,'Gain Ludo groupe (équipe '||_team||')');
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) + v_half WHERE id=v_mate;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_mate,'win',v_half,_game_id,'Gain Ludo groupe (équipe '||_team||', coéquipier)');
  ELSE
    -- No human teammate: winner gets full pot
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) + v_payout WHERE id=_winner_id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (_winner_id,'win',v_payout,_game_id,'Gain Ludo groupe (équipe '||_team||', solo)');
    -- Referral bonus
    SELECT referred_by INTO v_referrer FROM public.profiles WHERE id=_winner_id;
    IF v_referrer IS NOT NULL THEN
      SELECT referral_pct INTO v_ref_pct FROM public.app_settings WHERE id=1;
      v_ref_amount := v_payout * COALESCE(v_ref_pct,0) / 100.0;
      IF v_ref_amount > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + v_ref_amount WHERE id=v_referrer;
        INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
          VALUES (v_referrer,'referral',v_ref_amount,_game_id,'Bonus parrainage');
      END IF;
    END IF;
  END IF;
END $function$;

-- ── Bug 8: _ludo_check_last_standing must not return forfeited host ────────
CREATE OR REPLACE FUNCTION public._ludo_check_last_standing(_game_id uuid)
RETURNS uuid
LANGUAGE plpgsql
AS $function$
DECLARE v_count INT; v_uid UUID; v_host UUID; v_host_forfeited BOOLEAN;
BEGIN
  SELECT count(*) INTO v_count FROM public.ludo_participants
   WHERE game_id=_game_id AND forfeited=FALSE;
  IF v_count <= 1 THEN
    -- Try non-bot survivor first
    SELECT user_id INTO v_uid FROM public.ludo_participants
     WHERE game_id=_game_id AND forfeited=FALSE AND is_bot=FALSE LIMIT 1;
    IF v_uid IS NOT NULL THEN RETURN v_uid; END IF;

    -- If only bots remain, check if host is still active (not forfeited)
    SELECT host_id INTO v_host FROM public.ludo_games WHERE id = _game_id;
    IF v_host IS NOT NULL THEN
      SELECT forfeited INTO v_host_forfeited FROM public.ludo_participants
       WHERE game_id=_game_id AND user_id=v_host AND is_bot=FALSE LIMIT 1;
      -- Only return host if they haven't forfeited
      IF COALESCE(v_host_forfeited, TRUE) = FALSE THEN
        RETURN v_host;
      END IF;
    END IF;

    -- Host forfeited or not found → no winner
    RETURN NULL;
  END IF;
  RETURN NULL;
END $function$;

-- ── Bug 9: finish_game must check forfeited=FALSE for winner ──────────────
CREATE OR REPLACE FUNCTION public.finish_game(_game_id uuid, _winner_id uuid)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_game       public.ludo_games%ROWTYPE;
  v_payout     NUMERIC;
  v_referrer   UUID;
  v_ref_pct    NUMERIC;
  v_ref_amount NUMERIC;
  v_caller     uuid := auth.uid();
BEGIN
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_game.status = 'finished' THEN RETURN 0; END IF;
  IF v_game.status <> 'playing' THEN RAISE EXCEPTION 'La partie n''est pas en cours'; END IF;

  -- Auth guard
  IF v_caller IS NOT NULL
     AND v_caller <> v_game.host_id
     AND NOT public._is_game_participant(_game_id, v_caller)
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Non autorisé';
  END IF;

  -- Winner must be a non-bot, non-forfeited participant
  IF _winner_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.ludo_participants 
    WHERE game_id=_game_id AND user_id=_winner_id AND is_bot=FALSE AND forfeited=FALSE
  ) THEN
    RAISE EXCEPTION 'Gagnant invalide';
  END IF;

  v_payout := v_game.pot * (100 - v_game.commission_pct) / 100.0;
  UPDATE public.ludo_games SET status='finished', winner_id=_winner_id, finished_at=now() WHERE id=_game_id;

  IF _winner_id IS NOT NULL THEN
    UPDATE public.profiles SET balance_ar = balance_ar + v_payout WHERE id=_winner_id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (_winner_id,'win',v_payout,_game_id,'Gain partie');

    SELECT referred_by INTO v_referrer FROM public.profiles WHERE id=_winner_id;
    IF v_referrer IS NOT NULL THEN
      SELECT referral_pct INTO v_ref_pct FROM public.app_settings WHERE id=1;
      v_ref_amount := v_payout * COALESCE(v_ref_pct,0) / 100.0;
      IF v_ref_amount > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + v_ref_amount WHERE id=v_referrer;
        INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
          VALUES (v_referrer,'referral',v_ref_amount,_game_id,'Bonus parrainage');
      END IF;
    END IF;
  END IF;

  RETURN v_payout;
END $function$;

-- ── Bug 8b: ludo_quit must also check _ludo_active_humans before paying ───
-- When the last human quits, _ludo_check_last_standing may return the host
-- even if the host is the one quitting. Add an extra guard.
CREATE OR REPLACE FUNCTION public.ludo_quit(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); g public.ludo_games%ROWTYPE; st jsonb;
  v_slot INT; v_winner UUID; v_remaining INT;
  v_pawns jsonb; i INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status NOT IN ('playing','open') THEN RAISE EXCEPTION 'Partie terminée'; END IF;
  SELECT slot INTO v_slot FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid AND is_bot=false;
  IF v_slot IS NULL THEN RAISE EXCEPTION 'Non participant'; END IF;

  IF g.status = 'open' THEN
    UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id=v_uid;
    UPDATE public.ludo_games SET pot = pot - g.stake WHERE id=_game_id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_uid,'refund',g.stake,_game_id,'Annulation avant départ');
    DELETE FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid AND is_bot=false;
    SELECT count(*) INTO v_remaining FROM public.ludo_participants WHERE game_id=_game_id AND is_bot=false;
    IF v_remaining = 0 THEN PERFORM public._ludo_purge(_game_id); END IF;
    RETURN;
  END IF;

  -- Send all forfeited player's pawns back to the yard
  st := g.state;
  IF st ? 'pawns' AND (st->'pawns') ? v_slot::text THEN
    v_pawns := '[]'::jsonb;
    FOR i IN 1..4 LOOP
      v_pawns := v_pawns || jsonb_build_object('s','yard','k',-1);
    END LOOP;
    st := jsonb_set(st, ARRAY['pawns', v_slot::text], v_pawns);
  END IF;

  -- Solo game: mark forfeited, finish immediately (no winner payout)
  IF g.is_solo OR g.match_type = 'solo' THEN
    UPDATE public.ludo_participants SET forfeited=TRUE WHERE game_id=_game_id AND user_id=v_uid AND is_bot=false;
    UPDATE public.ludo_games SET status='finished', finished_at=now(), state=st WHERE id=_game_id;
    PERFORM public._ludo_purge(_game_id);
    RETURN;
  END IF;

  -- Multiplayer: forfeit and check if game should end
  UPDATE public.ludo_participants SET forfeited=TRUE WHERE game_id=_game_id AND user_id=v_uid AND is_bot=false;
  IF (st->>'turn_slot')::INT = v_slot THEN
    st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('forfeit'));
  END IF;
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  
  -- Only pay if there are still active humans
  IF public._ludo_active_humans(_game_id) > 0 THEN
    v_winner := public._ludo_check_last_standing(_game_id);
    IF v_winner IS NOT NULL THEN
      PERFORM public.finish_game(_game_id, v_winner);
    END IF;
  ELSE
    -- No humans left → end without payout (platform keeps the pot)
    UPDATE public.ludo_games SET status='finished', finished_at=now() WHERE id=_game_id;
    PERFORM public._ludo_purge(_game_id);
  END IF;
END $function$;

-- ── Cleanup: Drop old 2-param create_game overload ────────────────────────
-- This prevents the wrong function from being called when match_type is omitted
DROP FUNCTION IF EXISTS public.create_game(integer, numeric) CASCADE;
