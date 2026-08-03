
-- Always create a fresh public ludo game (don't merge into an existing open one)
CREATE OR REPLACE FUNCTION public.create_public_game(_max_players int, _stake numeric)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_balance numeric;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _stake > 0 THEN
    SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
    IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
    UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
    INSERT INTO public.transactions(user_id,type,amount,note)
      VALUES (v_uid,'ludo_stake', -_stake, 'Mise Ludo');
  END IF;
  INSERT INTO public.ludo_games(host_id, max_players, stake, status, is_private, pot, mode)
    VALUES (v_uid, _max_players, _stake, 'open', false, _stake, 'classic')
    RETURNING id INTO v_id;
  INSERT INTO public.ludo_participants(game_id, user_id, slot)
    VALUES (v_id, v_uid, 0);
  RETURN v_id;
END $$;
GRANT EXECUTE ON FUNCTION public.create_public_game(int, numeric) TO authenticated;

-- Replace chess_resign so that 'open' games refund instead of erroring
CREATE OR REPLACE FUNCTION public.chess_resign(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_g chess_games%ROWTYPE;
  v_winner uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id = _game_id FOR UPDATE;
  IF v_g.id IS NULL THEN RAISE EXCEPTION 'not found'; END IF;

  -- Cancel & refund when the game has not started yet
  IF v_g.status = 'open' THEN
    IF v_uid <> v_g.host_id AND v_uid <> v_g.white_id AND v_uid <> v_g.black_id THEN
      RAISE EXCEPTION 'not a player';
    END IF;
    IF v_g.stake > 0 AND v_g.host_id IS NOT NULL THEN
      UPDATE public.profiles SET balance_ar = balance_ar + v_g.stake WHERE id = v_g.host_id;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (v_g.host_id, 'chess_refund', v_g.stake, _game_id, 'Annulation avant départ');
    END IF;
    UPDATE public.chess_games SET status='cancelled', finished_at=now() WHERE id=_game_id;
    RETURN;
  END IF;

  IF v_g.status <> 'playing' THEN RAISE EXCEPTION 'not active'; END IF;
  IF v_uid = v_g.white_id THEN v_winner := v_g.black_id;
  ELSIF v_uid = v_g.black_id THEN v_winner := v_g.white_id;
  ELSE RAISE EXCEPTION 'not a player'; END IF;
  PERFORM public._chess_payout(_game_id, v_winner, false);
END $$;
GRANT EXECUTE ON FUNCTION public.chess_resign(uuid) TO authenticated;
