CREATE OR REPLACE FUNCTION public._chess_ephemeral_bot(_pseudo text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role,
    email, encrypted_password, email_confirmed_at,
    raw_user_meta_data,
    created_at, updated_at,
    confirmation_token, recovery_token, email_change, email_change_token_new
  ) VALUES (
    v_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated',
    'chessbot_' || v_id::text || '@bot.lalaomada.internal',
    NULL,
    now(),
    jsonb_build_object('pseudo', _pseudo, 'is_bot', true),
    now(), now(),
    '', '', '', ''
  );

  UPDATE public.profiles
    SET balance_ar = 0,
        pseudo = _pseudo,
        avatar_url = NULL
    WHERE id = v_id;

  DELETE FROM public.transactions WHERE user_id = v_id;
  RETURN v_id;
END $$;

GRANT EXECUTE ON FUNCTION public._chess_ephemeral_bot(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public._chess_ephemeral_bot(text) TO service_role;