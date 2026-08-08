CREATE OR REPLACE FUNCTION public.transfer_balance(
  _recipient text,
  _amount numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  _sender uuid := auth.uid();
  _sender_name text;
  _sender_phone text;
  _recipient_id uuid;
  _recipient_name text;
  _sender_bal numeric;
  _final_amount numeric;
  _min_transfer numeric := 100;
  _max_transfer numeric := 500000;
  _fee numeric := 0;
BEGIN
  IF _sender IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;

  IF _amount < _min_transfer THEN
    RAISE EXCEPTION 'Montant minimum: % Ar', _min_transfer;
  END IF;
  IF _amount > _max_transfer THEN
    RAISE EXCEPTION 'Montant maximum: % Ar', _max_transfer;
  END IF;

  SELECT pseudo, phone, balance_ar INTO _sender_name, _sender_phone, _sender_bal
    FROM public.profiles WHERE id = _sender;
  IF _sender_name IS NULL THEN RAISE EXCEPTION 'Profil introuvable'; END IF;

  IF COALESCE((SELECT is_banned FROM public.profiles WHERE id = _sender), false) THEN
    RAISE EXCEPTION 'Compte banni';
  END IF;

  IF _sender_bal < _amount THEN
    RAISE EXCEPTION 'Solde insuffisant. Votre solde: % Ar', _sender_bal;
  END IF;

  SELECT id, pseudo INTO _recipient_id, _recipient_name
    FROM public.profiles
    WHERE phone = _recipient
       OR phone_number = _recipient
       OR pseudo = _recipient
       OR unique_code = _recipient
    LIMIT 1;

  IF _recipient_id IS NULL THEN
    RAISE EXCEPTION 'Destinataire introuvable. Vérifiez le numéro de téléphone ou le pseudo.';
  END IF;

  IF _recipient_id = _sender THEN
    RAISE EXCEPTION 'Vous ne pouvez pas transférer à vous-même';
  END IF;

  IF COALESCE((SELECT is_banned FROM public.profiles WHERE id = _recipient_id), false) THEN
    RAISE EXCEPTION 'Le destinataire est banni';
  END IF;

  _final_amount := _amount - _fee;

  UPDATE public.profiles
    SET balance_ar = balance_ar - _amount
    WHERE id = _sender;

  UPDATE public.profiles
    SET balance_ar = balance_ar + _final_amount
    WHERE id = _recipient_id;

  INSERT INTO public.transactions(user_id, type, amount, ref_id, note, meta)
    VALUES (_sender, 'transfer_sent', -_amount, _recipient_id,
      'Transfert à ' || _recipient_name,
      jsonb_build_object('to', _recipient_id, 'to_name', _recipient_name));

  INSERT INTO public.transactions(user_id, type, amount, ref_id, note, meta)
    VALUES (_recipient_id, 'transfer_received', _final_amount, _sender,
      'Transfert de ' || _sender_name,
      jsonb_build_object('from', _sender, 'from_name', _sender_name));

  RETURN jsonb_build_object(
    'success', true,
    'amount', _amount,
    'recipient', _recipient_name,
    'new_balance', _sender_bal - _amount
  );
END $function$;
