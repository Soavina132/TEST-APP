-- Mise à jour de create_public_game pour accepter le paramètre _mode (classique/rapide)
-- Cela supprime la restriction qui forçait le mode 'classic' pour les parties publiques Ludo

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

  INSERT INTO public.ludo_participants(game_id, user_id, slot)
    VALUES (v_id, v_uid, 0);

  RETURN v_id;
END $$;

-- Accorder les droits sur la nouvelle signature
GRANT EXECUTE ON FUNCTION public.create_public_game(int, numeric, text) TO authenticated;
