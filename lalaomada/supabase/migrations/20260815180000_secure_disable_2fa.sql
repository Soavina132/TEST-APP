-- Migration: Secure disable_totp — revoke direct access from authenticated users
-- The disable-2fa edge function now handles both verification AND disabling atomically.
-- The RPC disable_totp() is kept for the edge function (service-role) but
-- is no longer callable directly by authenticated users without a code.

-- Revoke EXECUTE from authenticated so it can't be called without code verification
REVOKE ALL ON FUNCTION public.disable_totp(text) FROM authenticated;

-- Keep it callable by service_role only (used by the disable-2fa edge function)
-- service_role already has access via superuser privileges

-- Also revoke the no-arg variant if it still exists
REVOKE ALL ON FUNCTION public.disable_totp() FROM authenticated;
