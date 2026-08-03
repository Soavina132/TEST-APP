
CREATE OR REPLACE FUNCTION public.fanorona_join(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  g record;
  v_balance numeric;
  v_name text;
  v_slot int;
  v_color text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL OR g.status <> 'open' THEN RAISE EXCEPTION 'game not joinable'; END IF;
  IF EXISTS(SELECT 1 FROM public.fanorona_participants WHERE game_id = _game_id AND user_id = v_uid) THEN RETURN; END IF;
  SELECT balance_ar, pseudo INTO v_balance, v_name FROM public.profiles WHERE id = v_uid;
  IF v_balance < g.stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;
  IF (SELECT count(*) FROM public.fanorona_participants WHERE game_id = _game_id) >= 2 THEN RAISE EXCEPTION 'full'; END IF;

  -- Pick first free slot (0 or 1)
  SELECT s INTO v_slot
  FROM generate_series(0,1) AS s
  WHERE NOT EXISTS (
    SELECT 1 FROM public.fanorona_participants WHERE game_id = _game_id AND slot = s
  )
  ORDER BY s
  LIMIT 1;
  IF v_slot IS NULL THEN RAISE EXCEPTION 'full'; END IF;
  v_color := CASE WHEN v_slot = 0 THEN 'white' ELSE 'black' END;

  INSERT INTO public.fanorona_participants(game_id, user_id, slot, color, display_name)
    VALUES (_game_id, v_uid, v_slot, v_color, COALESCE(v_name,'Player'));
  UPDATE public.profiles SET balance_ar = balance_ar - g.stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
    VALUES (v_uid, 'fanorona_stake', -g.stake, _game_id, 'Join fanorona');
  UPDATE public.fanorona_games SET pot = pot + g.stake WHERE id = _game_id;
END $function$;
