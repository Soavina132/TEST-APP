-- Add match_type column to ludo_games
ALTER TABLE public.ludo_games ADD COLUMN IF NOT EXISTS match_type text NOT NULL DEFAULT 'groupe';

-- Update create_game to accept match_type
CREATE OR REPLACE FUNCTION public.create_game(_max_players integer, _stake numeric, _match_type text DEFAULT 'groupe')
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, match_type)
  VALUES (v_uid, _max_players, _stake, _stake, COALESCE(v_commission,10), COALESCE(_match_type, 'groupe'))
  RETURNING id INTO v_game_id;

  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id,type,amount,ref_id,note) VALUES (v_uid,'stake',-_stake,v_game_id,'Mise création partie');

  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name)
    SELECT v_game_id, v_uid, 0, 'red', pseudo FROM public.profiles WHERE id = v_uid;

  RETURN v_game_id;
END $function$;

-- Update create_private_game to accept match_type
CREATE OR REPLACE FUNCTION public.create_private_game(
  _max_players integer, _stake numeric, _mode text DEFAULT 'classic', _match_type text DEFAULT 'groupe'
)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_balance NUMERIC; v_game_id UUID;
  v_commission NUMERIC; v_paused BOOLEAN; v_banned BOOLEAN; v_code TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT paused INTO v_paused FROM public.app_settings WHERE id=1;
  IF COALESCE(v_paused,FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned INTO v_banned FROM public.profiles WHERE id=v_uid;
  IF COALESCE(v_banned,FALSE) THEN RAISE EXCEPTION 'Compte banni'; END IF;
  IF _max_players NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'Joueurs invalides'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'Mise invalide'; END IF;
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
  SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id=1;
  v_code := public._gen_room_code();
  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, room_code, is_private, mode, match_type)
    VALUES (v_uid, _max_players, _stake, _stake, COALESCE(v_commission,10), v_code, TRUE, COALESCE(_mode,'classic'), COALESCE(_match_type,'groupe'))
    RETURNING id INTO v_game_id;
  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id,type,amount,ref_id,note) VALUES (v_uid,'stake',-_stake,v_game_id,'Mise création partie privée');
  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name)
    SELECT v_game_id, v_uid, 0, 'red', pseudo FROM public.profiles WHERE id = v_uid;
  RETURN v_game_id;
END $function$;

-- Update find_or_create_game to accept match_type
CREATE OR REPLACE FUNCTION public.find_or_create_game(_max_players integer, _stake numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_game_id UUID; v_balance NUMERIC; v_count INT;
  v_commission NUMERIC; v_paused BOOLEAN; v_banned BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT paused INTO v_paused FROM public.app_settings WHERE id=1;
  IF COALESCE(v_paused,FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned INTO v_banned FROM public.profiles WHERE id=v_uid;
  IF COALESCE(v_banned,FALSE) THEN RAISE EXCEPTION 'Compte banni'; END IF;
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id=v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
  SELECT id INTO v_game_id FROM public.ludo_games
    WHERE status='open' AND is_private=false AND max_players=_max_players AND stake=_stake
    ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED;
  IF v_game_id IS NULL THEN
    SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id=1;
    INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, match_type)
      VALUES (v_uid, _max_players, _stake, _stake, COALESCE(v_commission,10), 'groupe')
      RETURNING id INTO v_game_id;
    UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note) VALUES (v_uid,'stake',-_stake,v_game_id,'Mise création partie');
    INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name)
      SELECT v_game_id, v_uid, 0, 'red', pseudo FROM public.profiles WHERE id = v_uid;
  ELSE
    SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id=v_game_id;
    IF v_count >= _max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;
    PERFORM public.join_game(v_game_id);
  END IF;
  RETURN v_game_id;
END $function$;

REVOKE ALL ON FUNCTION public.create_game(integer, numeric, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_game(integer, numeric, text) TO authenticated;
REVOKE ALL ON FUNCTION public.create_private_game(integer, numeric, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_private_game(integer, numeric, text, text) TO authenticated;
REVOKE ALL ON FUNCTION public.find_or_create_game(integer, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.find_or_create_game(integer, numeric) TO authenticated;
