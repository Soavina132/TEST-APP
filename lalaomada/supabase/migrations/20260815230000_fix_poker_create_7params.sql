-- Fix: poker_create was reduced to 4 params by 20260814230300_fix_poker_create.sql
-- but the frontend still sends _small_blind, _big_blind, _buy_in.
-- Restore the 7-param version so Poker game creation works again.

CREATE OR REPLACE FUNCTION public.poker_create(
  _stake numeric,
  _max integer DEFAULT 6,
  _private boolean DEFAULT false,
  _commission numeric DEFAULT 10,
  _small_blind numeric DEFAULT 10,
  _big_blind numeric DEFAULT 20,
  _buy_in numeric DEFAULT 10000
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_gid uuid;
  v_code text;
  v_chips numeric;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _stake IS NULL OR _stake < 0 THEN RAISE EXCEPTION 'Stake invalide'; END IF;
  IF _commission IS NULL OR _commission < 0 OR _commission > 50 THEN RAISE EXCEPTION 'Commission invalide (0-50)'; END IF;
  IF _max < 2 OR _max > 9 THEN RAISE EXCEPTION 'Nombre de joueurs invalide (2-9)'; END IF;
  IF _small_blind IS NULL OR _small_blind <= 0 THEN _small_blind := 10; END IF;
  IF _big_blind IS NULL OR _big_blind < _small_blind THEN _big_blind := _small_blind * 2; END IF;
  IF _buy_in IS NULL OR _buy_in < _big_blind * 2 THEN _buy_in := 10000; END IF;

  -- Check balance
  IF _stake > 0 AND (SELECT balance_ar FROM public.profiles WHERE id=v_uid) < _stake THEN
    RAISE EXCEPTION 'Solde insuffisant';
  END IF;

  -- Deduct stake
  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar=balance_ar-_stake WHERE id=v_uid;
    INSERT INTO public.transactions(user_id,type,amount,note)
      VALUES(v_uid,'stake',-_stake,'Mise Poker');
  END IF;

  -- Generate code
  IF _private THEN v_code := upper(substring(md5(random()::text),1,6)); END IF;

  -- Create game with blinds & buy-in
  INSERT INTO public.poker_games(
    host_id, stake, commission_pct, max_players, is_private, room_code,
    created_by, state, small_blind, big_blind, buy_in_chips
  )
  VALUES(
    v_uid, _stake, _commission, _max, _private, v_code,
    v_uid, '{}', _small_blind, _big_blind, _buy_in
  )
  RETURNING id INTO v_gid;

  -- Add creator as player (seat 0) with configured buy-in
  v_chips := _buy_in;
  INSERT INTO public.poker_players(game_id, user_id, seat, chips, status, is_ready)
  VALUES(v_gid, v_uid, 0, v_chips, 'waiting', false);

  RETURN v_gid;
END;
$function$;

-- Drop the 4-param overload if it exists (from the bad migration)
DROP FUNCTION IF EXISTS public.poker_create(numeric, integer, boolean, numeric);

REVOKE EXECUTE ON FUNCTION public.poker_create(numeric, integer, boolean, numeric, numeric, numeric, numeric) FROM anon;
GRANT EXECUTE ON FUNCTION public.poker_create(numeric, integer, boolean, numeric, numeric, numeric, numeric) TO authenticated;
