
ALTER TABLE public.chess_games
  ADD COLUMN IF NOT EXISTS draw_offered_by uuid;

-- Proposer une nulle
CREATE OR REPLACE FUNCTION public.chess_offer_draw(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid := auth.uid(); v_g chess_games%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id=_game_id FOR UPDATE;
  IF v_g.status <> 'playing' THEN RAISE EXCEPTION 'not active'; END IF;
  IF v_uid <> v_g.white_id AND v_uid <> v_g.black_id THEN RAISE EXCEPTION 'not a player'; END IF;
  UPDATE chess_games SET draw_offered_by = v_uid WHERE id=_game_id;
END $$;

-- Accepter la nulle proposée par l'adversaire
CREATE OR REPLACE FUNCTION public.chess_accept_draw(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid := auth.uid(); v_g chess_games%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id=_game_id FOR UPDATE;
  IF v_g.status <> 'playing' THEN RAISE EXCEPTION 'not active'; END IF;
  IF v_g.draw_offered_by IS NULL OR v_g.draw_offered_by = v_uid THEN
    RAISE EXCEPTION 'no draw offer to accept';
  END IF;
  IF v_uid <> v_g.white_id AND v_uid <> v_g.black_id THEN RAISE EXCEPTION 'not a player'; END IF;
  PERFORM public._chess_payout(_game_id, NULL, true);
END $$;

-- Refuser la nulle
CREATE OR REPLACE FUNCTION public.chess_decline_draw(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  UPDATE chess_games SET draw_offered_by = NULL
    WHERE id=_game_id AND draw_offered_by IS NOT NULL AND draw_offered_by <> v_uid
      AND (white_id = v_uid OR black_id = v_uid);
END $$;

-- Fin automatique (mat / pat / nulle par règle), appelée par le client après son coup
CREATE OR REPLACE FUNCTION public.chess_auto_end(_game_id uuid, _winner uuid, _draw boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid := auth.uid(); v_g chess_games%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id=_game_id FOR UPDATE;
  IF v_g.status <> 'playing' THEN RETURN; END IF;
  IF v_uid <> v_g.white_id AND v_uid <> v_g.black_id THEN RAISE EXCEPTION 'not a player'; END IF;
  IF NOT _draw AND _winner IS NOT NULL
     AND _winner <> v_g.white_id AND _winner <> v_g.black_id THEN
    RAISE EXCEPTION 'invalid winner';
  END IF;
  PERFORM public._chess_payout(_game_id, _winner, _draw);
END $$;
