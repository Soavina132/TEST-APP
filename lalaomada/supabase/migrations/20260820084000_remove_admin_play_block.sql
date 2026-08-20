-- Remove "Les administrateurs ne peuvent pas jouer" from all game functions

-- 1. create_game
CREATE OR REPLACE FUNCTION public.create_game(_max_players integer, _stake numeric)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_balance NUMERIC;
  v_game_id UUID;
  v_commission NUMERIC;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _max_players NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'Joueurs invalides'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'Mise invalide'; END IF;

  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id=1;

  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct)
  VALUES (v_uid, _max_players, _stake, _stake, COALESCE(v_commission,10))
  RETURNING id INTO v_game_id;

  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id,type,amount,ref_id,note) VALUES (v_uid,'stake',-_stake,v_game_id,'Mise création partie');

  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name)
  SELECT v_game_id, v_uid, 0, 'red', pseudo FROM public.profiles WHERE id = v_uid;

  RETURN v_game_id;
END $$;

-- 2. ludo_quick_start
CREATE OR REPLACE FUNCTION public.ludo_quick_start(
  _max_players integer DEFAULT 2,
  _stake numeric DEFAULT 0,
  _mode text DEFAULT 'classic',
  _match_type text DEFAULT 'solo'
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_balance NUMERIC;
  v_game_id UUID;
  v_commission NUMERIC;
  v_slots int[];
  v_start int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _max_players NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'Joueurs invalides'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'Mise invalide'; END IF;

  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id=1;

  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, is_private, mode, match_type)
  VALUES (v_uid, _max_players, _stake, _stake, COALESCE(v_commission,10), false, _mode, _match_type)
  RETURNING id INTO v_game_id;

  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id,type,amount,ref_id,note) VALUES (v_uid,'stake',-_stake,v_game_id,'Mise création partie');

  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name)
  SELECT v_game_id, v_uid, 0, 'red', pseudo FROM public.profiles WHERE id = v_uid;

  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name,is_bot)
  SELECT v_game_id, NULL, s, c, 'Bot '||s, true
  FROM (VALUES (1,'blue','Bot 1'),(2,'green','Bot 2'),(3,'yellow','Bot 3')) AS t(s,c)
  WHERE s < _max_players;

  SELECT array_agg(slot) INTO v_slots FROM public.ludo_participants WHERE game_id=v_game_id;
  v_start := v_slots[1 + public._crypto_rand_int(array_length(v_slots,1))];

  UPDATE public.ludo_games SET status = 'playing'::game_status, started_at = now(),
    state = public._ludo_init_state(_max_players, _mode), current_turn = v_start
    WHERE id = v_game_id;

  RETURN v_game_id;
END $$;

-- 3. ludo_start_solo_bot
CREATE OR REPLACE FUNCTION public.ludo_start_solo_bot(
  _max_players integer DEFAULT 2,
  _difficulty text DEFAULT 'medium',
  _stake numeric DEFAULT 0,
  _mode text DEFAULT 'classic',
  _match_type text DEFAULT 'solo'
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_balance NUMERIC;
  v_game_id UUID;
  v_commission NUMERIC;
  v_slots int[];
  v_start int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _max_players NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'Joueurs invalides'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'Mise invalide'; END IF;

  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id=1;

  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, is_private, mode, match_type, status, is_solo)
  VALUES (v_uid, _max_players, _stake, _stake, COALESCE(v_commission,10), true, _mode, _match_type, 'playing', true)
  RETURNING id INTO v_game_id;

  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id,type,amount,ref_id,note) VALUES (v_uid,'stake',-_stake,v_game_id,'Mise création partie solo bot');

  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name,is_bot)
  SELECT v_game_id, v_uid, 0, 'red', pseudo, false FROM public.profiles WHERE id = v_uid;

  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name,is_bot,difficulty)
  SELECT v_game_id, NULL, s, c, 'Bot '||s, true, _difficulty
  FROM (VALUES (1,'blue','Bot 1'),(2,'green','Bot 2'),(3,'yellow','Bot 3')) AS t(s,c,n)
  WHERE s < _max_players;

  SELECT array_agg(slot) INTO v_slots FROM public.ludo_participants WHERE game_id=v_game_id;
  v_start := v_slots[1 + public._crypto_rand_int(array_length(v_slots,1))];

  UPDATE public.ludo_games SET status = 'playing', started_at = now(),
    state = public._ludo_init_state(_max_players, COALESCE(_mode, 'classic')),
    current_turn = v_start
    WHERE id = v_game_id;

  IF v_start <> 0 THEN
    PERFORM public.ludo_bot_move(v_game_id);
  END IF;

  RETURN v_game_id;
END $$;
