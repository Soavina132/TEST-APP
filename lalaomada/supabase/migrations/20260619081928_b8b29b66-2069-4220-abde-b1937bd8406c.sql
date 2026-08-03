
CREATE OR REPLACE FUNCTION public.domino_join(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  g record;
  v_balance numeric;
  v_name text;
  v_slot int;
  v_count int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL OR g.status <> 'open' THEN RAISE EXCEPTION 'game not joinable'; END IF;
  IF EXISTS(SELECT 1 FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid) THEN RETURN; END IF;
  SELECT balance_ar, pseudo INTO v_balance, v_name FROM public.profiles WHERE id = v_uid;
  IF v_balance < g.stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;

  SELECT count(*) INTO v_count FROM public.domino_participants WHERE game_id = _game_id;
  IF v_count >= g.max_players THEN RAISE EXCEPTION 'full'; END IF;
  v_slot := v_count;

  INSERT INTO public.domino_participants(game_id, user_id, slot, display_name) VALUES (_game_id, v_uid, v_slot, COALESCE(v_name,'Player'));
  UPDATE public.profiles SET balance_ar = balance_ar - g.stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note) VALUES (v_uid, 'domino_stake', -g.stake, _game_id, 'Join domino game');
  UPDATE public.domino_games SET pot = pot + g.stake WHERE id = _game_id;

  -- No auto-start: wait for all participants to mark themselves ready (domino_set_ready).
END $$;
