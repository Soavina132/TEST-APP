-- Fix: fanorona_join should NOT auto-start the game.
-- Keep status = 'open' so both players go through the waiting room.
-- The game starts only when both players are ready (via fanorona_set_ready → drawing → playing).

CREATE OR REPLACE FUNCTION public.fanorona_join(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  g record;
  v_balance numeric;
  v_name text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL OR g.status <> 'open' THEN RAISE EXCEPTION 'game not joinable'; END IF;
  IF EXISTS(SELECT 1 FROM public.fanorona_participants WHERE game_id = _game_id AND user_id = v_uid) THEN RETURN; END IF;
  SELECT balance_ar, pseudo INTO v_balance, v_name FROM public.profiles WHERE id = v_uid;
  IF v_balance < g.stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;
  IF (SELECT count(*) FROM public.fanorona_participants WHERE game_id = _game_id) >= 2 THEN RAISE EXCEPTION 'full'; END IF;

  INSERT INTO public.fanorona_participants(game_id, user_id, slot, color, display_name) VALUES (_game_id, v_uid, 1, 'black', COALESCE(v_name,'Player'));
  UPDATE public.profiles SET balance_ar = balance_ar - g.stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note) VALUES (v_uid, 'fanorona_stake', -g.stake, _game_id, 'Join fanorona');
  -- Do NOT set status = 'playing' here. Keep 'open' for the waiting room.
  UPDATE public.fanorona_games SET pot = pot + g.stake WHERE id = _game_id;
END $$;

REVOKE EXECUTE ON FUNCTION public.fanorona_join(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.fanorona_join(uuid) TO authenticated;
