-- Fix: fanorona_check_global_timeout used wrong column names
-- 'balance' → 'balance_ar', 'kind' → 'type', 'user_id' → user_id (correct)
-- Also missing commission deduction and transaction note

CREATE OR REPLACE FUNCTION public.fanorona_check_global_timeout(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  g public.fanorona_games%ROWTYPE;
  loser_slot int;
  loser_user uuid;
  winner_user uuid;
  v_payout numeric;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND OR g.status <> 'playing' OR g.game_deadline IS NULL THEN RETURN; END IF;
  IF now() < g.game_deadline THEN RETURN; END IF;

  loser_slot := g.current_turn;
  SELECT user_id INTO loser_user FROM public.fanorona_participants
    WHERE game_id = _game_id AND slot = loser_slot;
  SELECT user_id INTO winner_user FROM public.fanorona_participants
    WHERE game_id = _game_id AND slot <> loser_slot LIMIT 1;

  UPDATE public.fanorona_games
     SET status = 'finished', winner_id = winner_user, finished_at = now()
   WHERE id = _game_id;

  IF winner_user IS NOT NULL AND g.pot > 0 THEN
    v_payout := g.pot * (100 - COALESCE(g.commission_pct, 10)) / 100;
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, 0) + v_payout
      WHERE id = winner_user;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (winner_user, 'fanorona_win', v_payout, _game_id, 'Fanorona win (timeout)');
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fanorona_check_global_timeout(uuid) TO authenticated, service_role;
