
ALTER FUNCTION public.gen_referral_code() SET search_path = public;

REVOKE EXECUTE ON FUNCTION public.create_game(INT,NUMERIC) FROM anon;
REVOKE EXECUTE ON FUNCTION public.join_game(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_add_bot(UUID,TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.update_game_state(UUID,JSONB,INT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.finish_game(UUID,UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_process_deposit(UUID,BOOLEAN) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_process_withdrawal(UUID,BOOLEAN) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_update_settings(TEXT,TEXT,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_adjust_balance(UUID,NUMERIC,TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_reply_support(UUID,TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_list_users() FROM anon;
REVOKE EXECUTE ON FUNCTION public.gen_referral_code() FROM anon, authenticated;
