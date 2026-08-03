
CREATE OR REPLACE FUNCTION public._finance_tests_cleanup(_ids uuid[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  DELETE FROM public.ludo_participants WHERE user_id = ANY(_ids);
  DELETE FROM public.domino_participants WHERE user_id = ANY(_ids);
  DELETE FROM public.ludo_games WHERE host_id = ANY(_ids);
  DELETE FROM public.chess_games WHERE host_id = ANY(_ids) OR white_id = ANY(_ids) OR black_id = ANY(_ids);
  DELETE FROM public.domino_games WHERE host_id = ANY(_ids);
  DELETE FROM public.transactions WHERE user_id = ANY(_ids);
  DELETE FROM public.deposits WHERE user_id = ANY(_ids);
  DELETE FROM public.withdrawals WHERE user_id = ANY(_ids);
  DELETE FROM public.withdrawal_debts WHERE user_id = ANY(_ids);
  DELETE FROM public.notifications WHERE user_id = ANY(_ids);
  DELETE FROM public.user_roles WHERE user_id = ANY(_ids);
  DELETE FROM public.profiles WHERE id = ANY(_ids);
  DELETE FROM auth.users WHERE id = ANY(_ids);
END
$$;
