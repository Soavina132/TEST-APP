-- ═══════════════════════════════════════════════════════════════════════
-- FIX: find_or_create_game n'acceptait pas _mode ni _match_type
-- Les parties publiques ne recevaient jamais le mode 'fast' (Moderne)
-- ═══════════════════════════════════════════════════════════════════════

-- Also need to update the function signature to accept _match_type
-- Current signature: (_max_players integer, _stake numeric)
-- New signature: (_max_players integer, _stake numeric, _mode text DEFAULT 'classic', _match_type text DEFAULT 'groupe')

CREATE OR REPLACE FUNCTION public.find_or_create_game(
  _max_players integer,
  _stake numeric,
  _mode text DEFAULT 'classic',
  _match_type text DEFAULT 'groupe'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_game_id UUID;
  v_balance NUMERIC;
  v_count INT;
  v_commission NUMERIC;
  v_paused BOOLEAN;
  v_banned BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT paused INTO v_paused FROM public.app_settings WHERE id = 1;
  IF COALESCE(v_paused, FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned INTO v_banned FROM public.profiles WHERE id = v_uid;
  IF COALESCE(v_banned, FALSE) THEN RAISE EXCEPTION 'Compte banni'; END IF;
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  -- Try to find an existing open public game with same params
  SELECT id INTO v_game_id FROM public.ludo_games
    WHERE status = 'open'
      AND is_private = false
      AND max_players = _max_players
      AND stake = _stake
      AND COALESCE(mode, 'classic') = COALESCE(_mode, 'classic')
    ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED;

  IF v_game_id IS NULL THEN
    SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id = 1;
    INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, mode, match_type)
      VALUES (v_uid, _max_players, _stake, _stake, COALESCE(v_commission, 10), COALESCE(_mode, 'classic'), COALESCE(_match_type, 'groupe'))
      RETURNING id INTO v_game_id;
    UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'stake', -_stake, v_game_id, 'Mise création partie');
    INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
      SELECT v_game_id, v_uid, 0, 'red', pseudo FROM public.profiles WHERE id = v_uid;
  ELSE
    SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = v_game_id;
    IF v_count >= _max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;
    PERFORM public.join_game(v_game_id);
  END IF;

  RETURN v_game_id;
END $$;

-- Drop the old 2-arg version if it still exists
DROP FUNCTION IF EXISTS public.find_or_create_game(integer, numeric);
