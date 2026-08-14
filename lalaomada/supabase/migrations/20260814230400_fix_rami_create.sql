-- rami_create overload 1: (_stake, _max, _private, _commission, _joker_mode)
CREATE OR REPLACE FUNCTION public.rami_create(_stake numeric, _max integer, _private boolean, _commission integer, _joker_mode text DEFAULT 'classique'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE _uid uuid := auth.uid(); _id uuid; _code text; _bal numeric; _name text; _mode text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _max < 2 OR _max > 4 THEN RAISE EXCEPTION 'players 2-4'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'stake invalid'; END IF;
  IF _commission IS NULL OR _commission < 0 OR _commission > 50 THEN RAISE EXCEPTION 'commission invalide (0-50)'; END IF;
  _mode := COALESCE(_joker_mode,'classique');
  IF _mode NOT IN ('sans','aleatoire','classique','double') THEN
    RAISE EXCEPTION 'mode joker invalide';
  END IF;

  SELECT balance_ar, COALESCE(pseudo,'Joueur') INTO _bal,_name
    FROM public.profiles WHERE id=_uid FOR UPDATE;
  IF _bal IS NULL OR _bal < _stake THEN RAISE EXCEPTION 'solde insuffisant'; END IF;
  _code := public._rami_gen_code();

  INSERT INTO public.rami_games (room_code,is_private,stake,max_players,commission_pct,created_by,pot,joker_mode)
  VALUES (_code,COALESCE(_private,true),_stake,_max,COALESCE(_commission,10),_uid,_stake,_mode)
  RETURNING id INTO _id;

  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar=balance_ar-_stake WHERE id=_uid;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
    VALUES (_uid,'rami_stake',-_stake,_id,'Create rami');
  END IF;

  INSERT INTO public.rami_participants(game_id,user_id,slot,display_name)
  VALUES (_id,_uid,0,_name);

  RETURN _id;
END $function$;

-- rami_create overload 2: (_stake, _max, _private, _commission, _joker_mode, _game_mode, _seven_cards)
CREATE OR REPLACE FUNCTION public.rami_create(_stake numeric, _max integer, _private boolean, _commission integer, _joker_mode text DEFAULT 'classique'::text, _game_mode text DEFAULT 'bordel'::text, _seven_cards boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _uid   uuid := auth.uid();
  _id    uuid;
  _code  text;
  _bal   numeric;
  _name  text;
  _mode  text;
  _gmode text;
  _seven boolean;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _max < 2 OR _max > 4 THEN RAISE EXCEPTION 'players 2-4'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'stake invalid'; END IF;
  IF _commission IS NULL OR _commission < 0 OR _commission > 50 THEN RAISE EXCEPTION 'commission invalide (0-50)'; END IF;

  _mode := COALESCE(_joker_mode, 'classique');
  IF _mode NOT IN ('sans','aleatoire','classique','double') THEN
    RAISE EXCEPTION 'mode joker invalide';
  END IF;

  _gmode := COALESCE(_game_mode, 'bordel');
  IF _gmode NOT IN ('bordel','naturel') THEN RAISE EXCEPTION 'mode de jeu invalide'; END IF;

  _seven := COALESCE(_seven_cards, true);

  SELECT balance_ar, COALESCE(pseudo,'Joueur') INTO _bal, _name
    FROM public.profiles WHERE id = _uid FOR UPDATE;
  IF _bal IS NULL OR _bal < _stake THEN RAISE EXCEPTION 'solde insuffisant'; END IF;

  _code := public._rami_gen_code();

  INSERT INTO public.rami_games (
    room_code, is_private, stake, max_players, commission_pct,
    created_by, pot, joker_mode, game_mode, seven_cards
  ) VALUES (
    _code, COALESCE(_private, true), _stake, _max, COALESCE(_commission, 10),
    _uid, _stake, _mode, _gmode, _seven
  ) RETURNING id INTO _id;

  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = _uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
    VALUES (_uid, 'rami_stake', -_stake, _id, 'Create rami');
  END IF;

  INSERT INTO public.rami_participants(game_id, user_id, slot, display_name)
  VALUES (_id, _uid, 0, _name);

  RETURN _id;
END $function$;

REVOKE EXECUTE ON FUNCTION public.rami_create(numeric, integer, boolean, integer, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.rami_create(numeric, integer, boolean, integer, text) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rami_create(numeric, integer, boolean, integer, text, text, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.rami_create(numeric, integer, boolean, integer, text, text, boolean) TO authenticated;
