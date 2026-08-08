-- ═══════════════════════════════════════════════════════════════════════════
-- Enforce minimum stake of 200 Ar for all paid games
-- Free games (stake=0) are still allowed via the "Gratuit" tab
-- ═══════════════════════════════════════════════════════════════════════════

-- Helper function: validate stake (0 = free, >= 200 = paid)
CREATE OR REPLACE FUNCTION public._validate_stake(_stake numeric)
RETURNS void LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  IF _stake < 0 THEN RAISE EXCEPTION 'Mise invalide'; END IF;
  IF _stake > 0 AND _stake < 200 THEN
    RAISE EXCEPTION 'Mise minimum 200 Ar pour une partie payante (ou 0 pour gratuit)';
  END IF;
END;
$$;

-- ── Rami ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rami_create(
  _stake numeric, _max int, _private boolean, _commission int,
  _game_mode text DEFAULT 'bordel',
  _joker_mode text DEFAULT 'classique'
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  _uid uuid := auth.uid(); _id uuid; _code text; _bal numeric; _name text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _max < 2 OR _max > 4 THEN RAISE EXCEPTION 'players 2-4'; END IF;
  PERFORM public._validate_stake(_stake);
  SELECT COALESCE(balance_ar, balance, 0), COALESCE(pseudo, display_name, 'Joueur') INTO _bal, _name
    FROM public.profiles WHERE id = _uid;
  IF _bal IS NULL OR _bal < _stake THEN RAISE EXCEPTION 'solde insuffisant'; END IF;
  _code := public._rami_gen_code();
  INSERT INTO public.rami_games (room_code, is_private, stake, max_players, commission_pct, created_by, pot, game_mode, joker_mode)
    VALUES (_code, COALESCE(_private, true), _stake, _max, COALESCE(_commission,10), _uid, _stake, COALESCE(_game_mode, 'bordel'), COALESCE(_joker_mode, 'classique'))
    RETURNING id INTO _id;
  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) - _stake WHERE id = _uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (_uid, 'rami_stake', -_stake, _id, 'Create rami');
  END IF;
  INSERT INTO public.rami_participants(game_id, user_id, slot, display_name, is_bot)
    VALUES (_id, _uid, 0, _name, false);
  RETURN _id;
END $$;
REVOKE ALL ON FUNCTION public.rami_create(numeric,int,boolean,int,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_create(numeric,int,boolean,int,text,text) TO authenticated;

-- ── Ludo ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ludo_create(
  _max_players int DEFAULT 2, _stake numeric DEFAULT 0,
  _mode text DEFAULT 'classic', _match_type text DEFAULT 'solo'
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid uuid := auth.uid(); _id uuid; _bal numeric; _name text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _max_players < 2 OR _max_players > 4 THEN RAISE EXCEPTION 'players 2-4'; END IF;
  PERFORM public._validate_stake(_stake);
  SELECT COALESCE(balance_ar, balance, 0), COALESCE(pseudo, display_name, 'Joueur') INTO _bal, _name
    FROM public.profiles WHERE id = _uid;
  IF _bal IS NULL OR _bal < _stake THEN RAISE EXCEPTION 'solde insuffisant'; END IF;
  INSERT INTO public.ludo_games (max_players, stake, created_by, pot, mode, match_type)
    VALUES (_max_players, _stake, _uid, _stake, COALESCE(_mode,'classic'), COALESCE(_match_type,'solo'))
    RETURNING id INTO _id;
  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) - _stake WHERE id = _uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (_uid, 'ludo_stake', -_stake, _id, 'Create ludo');
  END IF;
  INSERT INTO public.ludo_participants(game_id, user_id, slot, display_name, is_bot)
    VALUES (_id, _uid, 0, _name, false);
  RETURN _id;
END $$;
REVOKE ALL ON FUNCTION public.ludo_create(int,numeric,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ludo_create(int,numeric,text,text) TO authenticated;

-- ── Domino ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.domino_create(
  _stake numeric, _max int, _private boolean, _commission int,
  _mode text DEFAULT 'classic'
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid uuid := auth.uid(); _id uuid; _bal numeric; _name text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _max < 2 OR _max > 4 THEN RAISE EXCEPTION 'players 2-4'; END IF;
  PERFORM public._validate_stake(_stake);
  SELECT COALESCE(balance_ar, balance, 0), COALESCE(pseudo, display_name, 'Joueur') INTO _bal, _name
    FROM public.profiles WHERE id = _uid;
  IF _bal IS NULL OR _bal < _stake THEN RAISE EXCEPTION 'solde insuffisant'; END IF;
  INSERT INTO public.domino_games (max_players, stake, commission_pct, is_private, created_by, pot, mode)
    VALUES (_max, _stake, COALESCE(_commission,10), COALESCE(_private,true), _uid, _stake, COALESCE(_mode,'classic'))
    RETURNING id INTO _id;
  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) - _stake WHERE id = _uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (_uid, 'domino_stake', -_stake, _id, 'Create domino');
  END IF;
  INSERT INTO public.domino_participants(game_id, user_id, slot, display_name, is_bot)
    VALUES (_id, _uid, 0, _name, false);
  RETURN _id;
END $$;
REVOKE ALL ON FUNCTION public.domino_create(numeric,int,boolean,int,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.domino_create(numeric,int,boolean,int,text) TO authenticated;

-- ── Chess ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.chess_create_stake(
  _stake numeric, _time_min int DEFAULT 10
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid uuid := auth.uid(); _id uuid; _bal numeric; _name text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  PERFORM public._validate_stake(_stake);
  SELECT COALESCE(balance_ar, balance, 0), COALESCE(pseudo, display_name, 'Joueur') INTO _bal, _name
    FROM public.profiles WHERE id = _uid;
  IF _bal IS NULL OR _bal < _stake THEN RAISE EXCEPTION 'solde insuffisant'; END IF;
  INSERT INTO public.chess_games (white_id, stake, time_control_min, pot, status)
    VALUES (_uid, _stake, _time_min, _stake, 'waiting')
    RETURNING id INTO _id;
  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) - _stake WHERE id = _uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (_uid, 'chess_stake', -_stake, _id, 'Create chess');
  END IF;
  RETURN _id;
END $$;
REVOKE ALL ON FUNCTION public.chess_create_stake(numeric,int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.chess_create_stake(numeric,int) TO authenticated;

-- ── Fanorona ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fanorona_create(
  _stake numeric, _private boolean, _commission int,
  _variant text DEFAULT 'tsivy', _mandatory_capture boolean DEFAULT true
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid uuid := auth.uid(); _id uuid; _bal numeric; _name text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  PERFORM public._validate_stake(_stake);
  SELECT COALESCE(balance_ar, balance, 0), COALESCE(pseudo, display_name, 'Joueur') INTO _bal, _name
    FROM public.profiles WHERE id = _uid;
  IF _bal IS NULL OR _bal < _stake THEN RAISE EXCEPTION 'solde insuffisant'; END IF;
  INSERT INTO public.fanorona_games (stake, commission_pct, is_private, created_by, pot, variant, mandatory_capture)
    VALUES (_stake, COALESCE(_commission,10), COALESCE(_private,true), _uid, _stake, COALESCE(_variant,'tsivy'), COALESCE(_mandatory_capture,true))
    RETURNING id INTO _id;
  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) - _stake WHERE id = _uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (_uid, 'fanorona_stake', -_stake, _id, 'Create fanorona');
  END IF;
  INSERT INTO public.fanorona_participants(game_id, user_id, slot, display_name, is_bot)
    VALUES (_id, _uid, 0, _name, false);
  RETURN _id;
END $$;
REVOKE ALL ON FUNCTION public.fanorona_create(numeric,boolean,int,text,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fanorona_create(numeric,boolean,int,text,boolean) TO authenticated;

-- ── Poker ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.poker_create(
  _stake numeric, _max int, _private boolean, _commission int,
  _small_blind int DEFAULT 10, _big_blind int DEFAULT 20, _buy_in int DEFAULT 1000
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid uuid := auth.uid(); _id uuid; _bal numeric; _name text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _max < 2 OR _max > 8 THEN RAISE EXCEPTION 'players 2-8'; END IF;
  PERFORM public._validate_stake(_stake);
  SELECT COALESCE(balance_ar, balance, 0), COALESCE(pseudo, display_name, 'Joueur') INTO _bal, _name
    FROM public.profiles WHERE id = _uid;
  IF _bal IS NULL OR _bal < _stake THEN RAISE EXCEPTION 'solde insuffisant'; END IF;
  INSERT INTO public.poker_games (max_players, stake, commission_pct, is_private, created_by, pot,
    small_blind, big_blind, buy_in)
    VALUES (_max, _stake, COALESCE(_commission,10), COALESCE(_private,true), _uid, _stake,
    _small_blind, _big_blind, _buy_in)
    RETURNING id INTO _id;
  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) - _stake WHERE id = _uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (_uid, 'poker_stake', -_stake, _id, 'Create poker');
  END IF;
  INSERT INTO public.poker_players(game_id, user_id, slot, display_name, is_bot, chips)
    VALUES (_id, _uid, 0, _name, false, _buy_in);
  RETURN _id;
END $$;
REVOKE ALL ON FUNCTION public.poker_create(numeric,int,boolean,int,int,int,int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.poker_create(numeric,int,boolean,int,int,int,int) TO authenticated;
