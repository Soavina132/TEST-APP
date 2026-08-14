CREATE OR REPLACE FUNCTION public.poker_create(_stake numeric, _max integer DEFAULT 6, _private boolean DEFAULT false, _commission numeric DEFAULT 10)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_gid uuid;
  v_code text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _stake IS NULL OR _stake < 0 THEN RAISE EXCEPTION 'Stake invalide'; END IF;
  IF _commission IS NULL OR _commission < 0 OR _commission > 50 THEN RAISE EXCEPTION 'Commission invalide (0-50)'; END IF;
  IF _max < 2 OR _max > 9 THEN RAISE EXCEPTION 'Nombre de joueurs invalide (2-9)'; END IF;
  -- Check balance
  IF _stake > 0 AND (SELECT balance_ar FROM public.profiles WHERE id=v_uid) < _stake THEN
    RAISE EXCEPTION 'Solde insuffisant';
  END IF;
  -- Deduct stake
  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar=balance_ar-_stake WHERE id=v_uid;
    INSERT INTO public.transactions(user_id,type,amount,note) VALUES(v_uid,'stake',-_stake,'Mise Poker');
  END IF;
  -- Generate code
  IF _private THEN v_code := upper(substring(md5(random()::text),1,6)); END IF;
  -- Create game
  INSERT INTO public.poker_games(stake,commission_pct,max_players,is_private,room_code,created_by,state)
  VALUES(_stake,_commission,_max,_private,v_code,v_uid,'{}')
  RETURNING id INTO v_gid;
  -- Add creator as player (seat 0)
  INSERT INTO public.poker_players(game_id,user_id,seat,chips,status,is_ready)
  VALUES(v_gid,v_uid,0,GREATEST(_stake * 100, 10000),'waiting',false);
  RETURN v_gid;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.poker_create(numeric, integer, boolean, numeric) FROM anon;
GRANT EXECUTE ON FUNCTION public.poker_create(numeric, integer, boolean, numeric) TO authenticated;
