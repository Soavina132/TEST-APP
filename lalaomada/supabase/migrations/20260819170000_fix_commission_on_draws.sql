-- ============================================================
-- FIX: 10% commission ALWAYS deducted, even on draws.
--
-- Bug: On draw/nul, the system refunded the full stake to each
-- player without deducting the platform commission.
-- User rule: 10% is ALWAYS deducted when a game starts.
-- On draw: pot - 10% is distributed to all active players.
-- Example: 2 players × 1000ar = pot 2000ar → 10% = 200ar
-- → distribute 1800ar → 900ar each.
--
-- Games fixed:
-- 1. Chess: _chess_settle (draw path) — split pot-commission
-- 2. Fanorona: _fanorona_draw_refund — split pot-commission
-- 3. Domino: _domino_finalize (draw path) — split pot-commission
-- ============================================================

-- ═══ 1. Chess: _chess_settle — deduct commission on draws ═══
CREATE OR REPLACE FUNCTION public._chess_settle(
  _id uuid, _winner uuid, _draw boolean, _reason text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_g chess_games%ROWTYPE;
  v_net numeric;
  v_each numeric;
  v_commission numeric;
  v_white_bot boolean;
  v_black_bot boolean;
  v_winner_is_bot boolean;
BEGIN
  SELECT * INTO v_g FROM chess_games WHERE id = _id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF v_g.status IN ('finished','cancelled') THEN RETURN; END IF;

  v_white_bot := coalesce(v_g.white_is_bot,false);
  v_black_bot := coalesce(v_g.black_is_bot,false);

  IF v_g.mode = 'stake' AND v_g.pot > 0 THEN
    v_commission := round(v_g.pot * (coalesce(v_g.commission_pct,10)/100.0));
    v_net := v_g.pot - v_commission;

    IF _draw THEN
      v_each := v_net / 2;
      IF v_g.white_id IS NOT NULL AND NOT v_white_bot THEN
        UPDATE profiles SET balance_ar = balance_ar + v_each WHERE id = v_g.white_id;
        INSERT INTO transactions(user_id,type,amount,meta)
          VALUES (v_g.white_id,'chess_draw',v_each,jsonb_build_object('game',_id,'reason','draw','commission',v_commission));
      END IF;
      IF v_g.black_id IS NOT NULL AND NOT v_black_bot THEN
        UPDATE profiles SET balance_ar = balance_ar + v_each WHERE id = v_g.black_id;
        INSERT INTO transactions(user_id,type,amount,meta)
          VALUES (v_g.black_id,'chess_draw',v_each,jsonb_build_object('game',_id,'reason','draw','commission',v_commission));
      END IF;
    ELSIF _winner IS NOT NULL THEN
      v_winner_is_bot := (_winner = v_g.white_id AND v_white_bot)
                      OR (_winner = v_g.black_id AND v_black_bot);
      IF NOT v_winner_is_bot THEN
        UPDATE profiles SET balance_ar = balance_ar + v_net WHERE id = _winner;
        INSERT INTO transactions(user_id,type,amount,meta)
          VALUES (_winner,'chess_win',v_net,jsonb_build_object('game',_id,'reason',_reason,'commission',v_commission));
      END IF;
    END IF;
  END IF;

  UPDATE chess_games SET
    status='finished', winner_id=_winner, draw=_draw, end_reason=_reason,
    finished_at=now(), turn_deadline=NULL
  WHERE id = _id;
END $$;

REVOKE EXECUTE ON FUNCTION public._chess_settle(uuid, uuid, boolean, text) FROM anon, authenticated;

-- ═══ 2. Chess: _chess_payout — also fix to use same logic (used by chess_tick, chess_accept_draw) ═══
CREATE OR REPLACE FUNCTION public._chess_payout(_game_id uuid, _winner uuid, _draw boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_g chess_games%ROWTYPE; v_net numeric; v_each numeric; v_commission numeric;
BEGIN
  SELECT * INTO v_g FROM chess_games WHERE id = _game_id FOR UPDATE;
  IF v_g.status = 'finished' THEN RETURN; END IF;

  v_commission := round(v_g.pot * (coalesce(v_g.commission_pct,10)/100.0));
  v_net := v_g.pot - v_commission;

  IF _draw THEN
    v_each := v_net / 2;
    IF v_g.white_id IS NOT NULL THEN
      UPDATE profiles SET balance_ar = balance_ar + v_each WHERE id = v_g.white_id;
      INSERT INTO transactions(user_id,type,amount,ref_id,note)
        VALUES (v_g.white_id,'chess_draw',v_each,_game_id,'Chess draw (commission deducted)');
    END IF;
    IF v_g.black_id IS NOT NULL THEN
      UPDATE profiles SET balance_ar = balance_ar + v_each WHERE id = v_g.black_id;
      INSERT INTO transactions(user_id,type,amount,ref_id,note)
        VALUES (v_g.black_id,'chess_draw',v_each,_game_id,'Chess draw (commission deducted)');
    END IF;
    UPDATE chess_games SET status='finished', draw=true, finished_at=now(), turn_deadline=NULL WHERE id=_game_id;
  ELSE
    IF _winner IS NOT NULL THEN
      UPDATE profiles SET balance_ar = balance_ar + v_net WHERE id = _winner;
      INSERT INTO transactions(user_id,type,amount,ref_id,note)
        VALUES (_winner,'chess_payout',v_net,_game_id,'Chess win');
    END IF;
    UPDATE chess_games SET status='finished', winner_id=_winner, finished_at=now(), turn_deadline=NULL WHERE id=_game_id;
  END IF;
END $$;

-- ═══ 3. Chess: chess_finish — also fix draw path ═══
CREATE OR REPLACE FUNCTION public.chess_finish(
  _id      uuid,
  _winner  uuid,
  _draw    boolean DEFAULT false,
  _reason  text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_g chess_games%ROWTYPE;
  v_net numeric;
  v_each numeric;
  v_commission numeric;
BEGIN
  SELECT * INTO v_g FROM public.chess_games WHERE id = _id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF v_g.status = 'finished' THEN RETURN; END IF;

  v_commission := round(v_g.pot * (coalesce(v_g.commission_pct,10)/100.0));
  v_net := v_g.pot - v_commission;

  IF _draw THEN
    v_each := v_net / 2;
    IF v_g.white_id IS NOT NULL THEN
      UPDATE public.profiles SET balance_ar = balance_ar + v_each WHERE id = v_g.white_id;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (v_g.white_id, 'chess_draw', v_each, _id, 'Chess draw (commission deducted)');
    END IF;
    IF v_g.black_id IS NOT NULL THEN
      UPDATE public.profiles SET balance_ar = balance_ar + v_each WHERE id = v_g.black_id;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (v_g.black_id, 'chess_draw', v_each, _id, 'Chess draw (commission deducted)');
    END IF;
    UPDATE public.chess_games
      SET status = 'finished', draw = true, end_reason = _reason, finished_at = now(), turn_deadline = NULL
      WHERE id = _id;
  ELSE
    IF _winner IS NOT NULL THEN
      UPDATE public.profiles SET balance_ar = balance_ar + v_net WHERE id = _winner;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (_winner, 'chess_payout', v_net, _id, 'Chess win');
    END IF;
    UPDATE public.chess_games
      SET status = 'finished', winner_id = _winner, end_reason = _reason, finished_at = now(), turn_deadline = NULL
      WHERE id = _id;
  END IF;
END $$;

GRANT EXECUTE ON FUNCTION public.chess_finish(uuid, uuid, boolean, text) TO authenticated;

-- ═══ 4. Fanorona: _fanorona_draw_refund — deduct commission ═══
CREATE OR REPLACE FUNCTION public._fanorona_draw_refund(_game_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  g record;
  p record;
  v_net numeric;
  v_each numeric;
  v_active_count int;
  v_commission numeric;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN; END IF;

  IF g.stake > 0 AND g.pot > 0 THEN
    v_commission := round(g.pot * (coalesce(g.commission_pct, 10) / 100.0));
    v_net := g.pot - v_commission;

    SELECT count(*) INTO v_active_count
      FROM public.fanorona_participants
      WHERE game_id = _game_id AND forfeited = false AND is_bot = false;

    IF v_active_count > 0 THEN
      v_each := v_net / v_active_count;
      FOR p IN SELECT user_id FROM public.fanorona_participants
               WHERE game_id = _game_id AND forfeited = false AND is_bot = false
      LOOP
        UPDATE public.profiles SET balance_ar = balance_ar + v_each WHERE id = p.user_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (p.user_id, 'fanorona_draw', v_each, _game_id, 'Fanorona draw (commission deducted)');
      END LOOP;
    END IF;
  END IF;

  UPDATE public.fanorona_games
     SET status = 'draw', finished_at = now(), winner_id = NULL
   WHERE id = _game_id;
END
$function$;

REVOKE EXECUTE ON FUNCTION public._fanorona_draw_refund(uuid) FROM anon, authenticated;

-- ═══ 5. Domino: _domino_finalize — deduct commission on draw ═══
CREATE OR REPLACE FUNCTION public._domino_finalize(_game_id uuid, _winner_slot int DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  g record; winner_uid uuid; v_is_bot boolean := false;
  payout numeric; p record; n_active integer;
  refund_each numeric; st jsonb;
  v_net numeric; v_commission numeric;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status = 'finished' THEN RETURN; END IF;

  IF _winner_slot IS NULL THEN
    -- Match nul: distribute pot - commission
    SELECT count(*) INTO n_active
      FROM public.domino_participants
      WHERE game_id = _game_id AND forfeited = false AND is_bot = false;

    IF n_active > 0 AND g.pot > 0 THEN
      v_commission := round(g.pot * (coalesce(g.commission_pct, 10) / 100.0));
      v_net := g.pot - v_commission;
      refund_each := floor(v_net / n_active);
      FOR p IN SELECT user_id FROM public.domino_participants
               WHERE game_id = _game_id AND forfeited = false AND user_id IS NOT NULL AND is_bot = false
      LOOP
        UPDATE public.profiles SET balance_ar = balance_ar + refund_each WHERE id = p.user_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (p.user_id, 'domino_draw', refund_each, _game_id, 'Domino match nul (commission deducted)');
      END LOOP;
    END IF;
    st := jsonb_set(COALESCE(g.state,'{}'::jsonb), '{winner_slot}', 'null'::jsonb, true);
    UPDATE public.domino_games
       SET status='finished', winner_id=NULL, finished_at=now(), state=st
     WHERE id=_game_id;
    RETURN;
  END IF;

  SELECT user_id, COALESCE(is_bot, false) INTO winner_uid, v_is_bot
  FROM public.domino_participants WHERE game_id = _game_id AND slot = _winner_slot;
  payout := g.pot * (100 - g.commission_pct) / 100;
  IF winner_uid IS NOT NULL AND NOT v_is_bot THEN
    UPDATE public.profiles SET balance_ar = balance_ar + payout WHERE id = winner_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (winner_uid, 'domino_win', payout, _game_id, 'Domino win');
  END IF;
  st := jsonb_set(COALESCE(g.state,'{}'::jsonb), '{winner_slot}', to_jsonb(_winner_slot), true);
  UPDATE public.domino_games
     SET status='finished', winner_id=winner_uid, finished_at=now(), state=st
   WHERE id=_game_id;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public._domino_finalize(uuid, int) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public._domino_finalize(uuid, int) TO authenticated, service_role;
