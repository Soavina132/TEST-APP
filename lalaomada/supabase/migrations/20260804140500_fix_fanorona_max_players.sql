-- Fix: fanorona_create was missing max_players in INSERT, causing NOT NULL violation
-- Also add DEFAULT 2 on the column as a safety net

ALTER TABLE public.fanorona_games ALTER COLUMN max_players SET DEFAULT 2;

CREATE OR REPLACE FUNCTION public.fanorona_create(_stake numeric, _private boolean, _commission numeric DEFAULT 10, _variant text DEFAULT 'tsivy', _mandatory_capture boolean DEFAULT true)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_balance numeric;
  v_code text;
  v_id uuid;
  v_name text;
  v_cols int; v_rows int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'invalid stake'; END IF;

  CASE _variant
    WHEN 'telo'  THEN v_cols := 3; v_rows := 3;
    WHEN 'dimy'  THEN v_cols := 5; v_rows := 5;
    WHEN 'tsivy' THEN v_cols := 9; v_rows := 5;
    ELSE v_cols := 9; v_rows := 5; _variant := 'tsivy';
  END CASE;

  SELECT balance_ar, pseudo INTO v_balance, v_name FROM public.profiles WHERE id = v_uid;
  IF v_balance < _stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;
  IF _private THEN v_code := upper(substring(md5(random()::text||clock_timestamp()::text) from 1 for 6)); END IF;

  INSERT INTO public.fanorona_games(host_id, max_players, stake, pot, commission_pct, is_private, room_code, state, cols, rows, variant, mandatory_capture)
  VALUES (v_uid, 2, _stake, _stake, _commission, _private, v_code,
    jsonb_build_object('phase','waiting','board', public._fanorona_init_board(v_cols, v_rows), 'chain_from', null, 'chain_dirs', '[]'::jsonb),
    v_cols, v_rows, _variant, COALESCE(_mandatory_capture, true))
  RETURNING id INTO v_id;

  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note) VALUES (v_uid, 'fanorona_stake', -_stake, v_id, 'Create fanorona');
  INSERT INTO public.fanorona_participants(game_id, user_id, slot, color, display_name) VALUES (v_id, v_uid, 0, 'white', COALESCE(v_name,'Player'));
  RETURN v_id;
END $function$;
