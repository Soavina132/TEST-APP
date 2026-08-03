-- Correction : create_public_game insère color et display_name dans ludo_participants
-- Erreur : "null value in column "color" of relation "ludo_participants" violates not-null constraint"

CREATE OR REPLACE FUNCTION public.create_public_game(
  _max_players int,
  _stake numeric,
  _mode text DEFAULT 'classic'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_balance numeric;
  v_id uuid;
  v_mode text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;

  -- Normaliser le mode
  v_mode := CASE WHEN _mode = 'fast' THEN 'fast' ELSE 'classic' END;

  IF _stake > 0 THEN
    SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
    IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
    UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
    INSERT INTO public.transactions(user_id, type, amount, note)
      VALUES (v_uid, 'ludo_stake', -_stake, 'Mise Ludo');
  END IF;

  INSERT INTO public.ludo_games(host_id, max_players, stake, status, is_private, pot, mode)
    VALUES (v_uid, _max_players, _stake, 'open', false, _stake, v_mode)
    RETURNING id INTO v_id;

  -- Slot 0 = rouge (même convention que create_private_game)
  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
    SELECT v_id, v_uid, 0, 'red', pseudo FROM public.profiles WHERE id = v_uid;

  RETURN v_id;
END $$;

GRANT EXECUTE ON FUNCTION public.create_public_game(int, numeric, text) TO authenticated;
