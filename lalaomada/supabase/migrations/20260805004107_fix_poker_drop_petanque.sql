-- ============================================
-- Fix poker_create + Drop Pétanque/Billiard
-- ============================================

-- 1. Fix poker_create: set host_id (was missing, causing NOT NULL violation)
CREATE OR REPLACE FUNCTION public.poker_create(
  _stake numeric,
  _max integer DEFAULT 6,
  _private boolean DEFAULT false,
  _commission numeric DEFAULT 10
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_gid uuid;
  v_code text;
  v_name text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _max < 2 OR _max > 9 THEN RAISE EXCEPTION 'Nombre de joueurs invalide (2-9)'; END IF;
  IF _stake > 0 AND (SELECT balance_ar FROM public.profiles WHERE id=v_uid) < _stake THEN
    RAISE EXCEPTION 'Solde insuffisant';
  END IF;
  SELECT pseudo INTO v_name FROM public.profiles WHERE id=v_uid;
  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar=balance_ar-_stake WHERE id=v_uid;
    INSERT INTO public.transactions(user_id,type,amount,note) VALUES(v_uid,'stake',-_stake,'Mise Poker');
  END IF;
  IF _private THEN v_code := upper(substring(md5(random()::text),1,6)); END IF;
  INSERT INTO public.poker_games(host_id,stake,commission_pct,max_players,is_private,room_code,created_by,state)
  VALUES(v_uid,_stake,_commission,_max,_private,v_code,v_uid,'{}')
  RETURNING id INTO v_gid;
  DECLARE
    v_chips numeric := GREATEST(_stake * 100, 10000);
  BEGIN
    INSERT INTO public.poker_players(game_id,user_id,slot,seat,display_name,chips,bet,folded,all_in,is_bot,status,is_ready,bet_round,total_bet,hole_cards)
    VALUES(v_gid,v_uid,0,0,COALESCE(v_name,'Player'),v_chips,0,false,false,false,'waiting',false,0,0,ARRAY[]::integer[]);
  END;
  RETURN v_gid;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.poker_create(numeric, integer, boolean, numeric) TO authenticated, anon;

-- 2. Drop all Pétanque functions
DO $$ DECLARE r record; BEGIN
  FOR r IN SELECT p.oid::regprocedure::text as fqn 
    FROM pg_proc p 
    JOIN pg_namespace n ON p.pronamespace = n.oid 
    WHERE n.nspname = 'public' 
    AND (p.proname LIKE '%petanque%' OR p.proname LIKE '%billiard%')
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || r.fqn || ' CASCADE';
  END LOOP;
END $$;

-- 3. Drop Pétanque/Billiard tables
DROP TABLE IF EXISTS public.petanque_boules CASCADE;
DROP TABLE IF EXISTS public.petanque_participants CASCADE;
DROP TABLE IF EXISTS public.petanque_games CASCADE;
DROP TABLE IF EXISTS public.billiard_participants CASCADE;
DROP TABLE IF EXISTS public.billiard_games CASCADE;
