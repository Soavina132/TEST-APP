-- Drop conflicting old functions before recreating with new return types
DROP FUNCTION IF EXISTS public.tournament_register(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.tournament_unregister(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.tournament_report_result(uuid, uuid, jsonb) CASCADE;
DROP FUNCTION IF EXISTS public.admin_start_tournament(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.admin_advance_tournament_round(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.admin_get_tournament_overview(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.list_tournaments(text, text, int) CASCADE;
DROP FUNCTION IF EXISTS public.admin_create_tournament CASCADE;
DROP FUNCTION IF EXISTS public.admin_cancel_tournament(uuid, text) CASCADE;
DROP FUNCTION IF EXISTS public.admin_disqualify_player(uuid, uuid, text) CASCADE;
DROP FUNCTION IF EXISTS public.admin_resolve_claim(uuid, text, text) CASCADE;
DROP FUNCTION IF EXISTS public.admin_replay_match(uuid, text) CASCADE;
DROP FUNCTION IF EXISTS public.admin_force_match_winner(uuid, uuid, text) CASCADE;
DROP FUNCTION IF EXISTS public.tournament_auto_forfeit_expired() CASCADE;
DROP FUNCTION IF EXISTS public.admin_open_registration(uuid) CASCADE;
DROP FUNCTION IF EXISTS public._notify(uuid, text, text, text, uuid) CASCADE;