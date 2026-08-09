-- ============================================================
-- Fix: Create chess_finish function (was missing from DB!)
-- The frontend calls chess_finish but only chess_claim_win existed.
-- This handles checkmate, stalemate, draw, timeout, and resignation.
-- ============================================================

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
BEGIN
  SELECT * INTO v_g FROM public.chess_games WHERE id = _id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF v_g.status = 'finished' THEN RETURN; END IF;

  v_net := v_g.pot - (v_g.pot * v_g.commission_pct / 100.0);

  IF _draw THEN
    v_each := v_net / 2;
    IF v_g.white_id IS NOT NULL THEN
      UPDATE public.profiles SET balance_ar = balance_ar + v_each WHERE id = v_g.white_id;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (v_g.white_id, 'chess_payout', v_each, _id, 'Chess draw');
    END IF;
    IF v_g.black_id IS NOT NULL THEN
      UPDATE public.profiles SET balance_ar = balance_ar + v_each WHERE id = v_g.black_id;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (v_g.black_id, 'chess_payout', v_each, _id, 'Chess draw');
    END IF;
    UPDATE public.chess_games
      SET status = 'finished', draw = true, end_reason = _reason, finished_at = now()
      WHERE id = _id;
  ELSE
    IF _winner IS NOT NULL THEN
      UPDATE public.profiles SET balance_ar = balance_ar + v_net WHERE id = _winner;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (_winner, 'chess_payout', v_net, _id, 'Chess win');
    END IF;
    UPDATE public.chess_games
      SET status = 'finished', winner_id = _winner, end_reason = _reason, finished_at = now()
      WHERE id = _id;
  END IF;
END $$;

GRANT EXECUTE ON FUNCTION public.chess_finish(uuid, uuid, boolean, text) TO authenticated;
